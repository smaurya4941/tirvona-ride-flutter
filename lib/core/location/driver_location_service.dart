import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../realtime/realtime_client.dart';
import '../realtime/realtime_models.dart';
import '../realtime/realtime_providers.dart';
import 'driver_fix.dart';
import 'location_tracking_policy.dart';

enum LocationAccess {
  unknown,
  granted,
  denied,

  /// Denied with "don't ask again" — only the system settings can fix it.
  deniedForever,

  /// Location services (GPS) are switched off on the device.
  serviceDisabled,
}

@immutable
class DriverLocationState {
  const DriverLocationState({
    this.mode = LocationTrackingMode.off,
    this.access = LocationAccess.unknown,
    this.streaming = false,
    this.lastFix,
    this.lastSentAt,
    this.rejection,
  });

  final LocationTrackingMode mode;
  final LocationAccess access;

  /// GPS subscription running.
  final bool streaming;
  final DriverFix? lastFix;

  /// Last time the server accepted a fix.
  final DateTime? lastSentAt;

  /// The server's last refusal code (e.g. `LOW_ACCURACY`, `DRIVER_OFFLINE`).
  final String? rejection;

  bool get weakSignal => rejection == 'LOW_ACCURACY';

  DriverLocationState copyWith({
    LocationTrackingMode? mode,
    LocationAccess? access,
    bool? streaming,
    DriverFix? lastFix,
    DateTime? lastSentAt,
    String? rejection,
    bool clearRejection = false,
  }) => DriverLocationState(
    mode: mode ?? this.mode,
    access: access ?? this.access,
    streaming: streaming ?? this.streaming,
    lastFix: lastFix ?? this.lastFix,
    lastSentAt: lastSentAt ?? this.lastSentAt,
    rejection: clearRejection ? null : rejection ?? this.rejection,
  );
}

/// Fallback used when the socket is down: `PATCH /drivers/location`.
typedef RestLocationSender = Future<void> Function(Map<String, dynamic> fix);

/// Driver GPS for the whole app: permission, the GPS subscription, filtering,
/// frequency (from [LocationTrackingPolicy]) and delivery.
///
/// It is independent of any screen: it is started and re-moded by the duty
/// binding from the driver's server state, and keeps running while the app
/// is in the background (Android foreground service with a persistent
/// notification; iOS background location mode) for as long as the driver
/// is online. Sending goes through [RealtimeClient]; this class knows nothing
/// about sockets beyond "send this fix".
class DriverLocationService extends Notifier<DriverLocationState> {
  StreamSubscription<Position>? _positions;
  StreamSubscription<RealtimeSession>? _sessions;
  Timer? _heartbeat;
  final _filter = DriverFixFilter();
  bool _sending = false;
  RestLocationSender? _restFallback;

  RealtimeClient get _realtime => ref.read(realtimeClientProvider);

  @override
  DriverLocationState build() {
    // Back from system Settings (permission granted, GPS switched on) or
    // after a stream error: pick up where the duty state says we should be.
    final lifecycle = AppLifecycleListener(onResume: () => unawaited(retry()));
    ref.onDispose(() {
      lifecycle.dispose();
      _teardown();
    });
    return const DriverLocationState();
  }

  /// Restarts streaming in the current mode if it should be running but is not.
  Future<void> retry() async {
    if (state.mode == LocationTrackingMode.off || state.streaming) {
      await checkAccess();
      return;
    }
    await setMode(state.mode);
  }

  /// Supplied by the rides feature (keeps core free of feature imports).
  // ignore: use_setters_to_change_properties
  void useRestFallback(RestLocationSender sender) => _restFallback = sender;

  /// Current permission state; prompts only when [request] is true.
  Future<LocationAccess> checkAccess({bool request = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return _setAccess(LocationAccess.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && request) {
      permission = await Geolocator.requestPermission();
    }
    return _setAccess(switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    });
  }

  /// One accurate fix, e.g. to send with "go online".
  Future<DriverFix?> currentFix() async {
    if (await checkAccess() != LocationAccess.granted) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return _toFix(position);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : _toFix(last);
    }
  }

  Future<void> openSettings() async {
    if (state.access == LocationAccess.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  /// Starts, re-tunes or stops streaming. Idempotent.
  Future<void> setMode(LocationTrackingMode mode) async {
    if (mode == LocationTrackingMode.off) return stop();
    if (mode == state.mode && state.streaming) return;

    state = state.copyWith(mode: mode);
    if (await checkAccess() != LocationAccess.granted) {
      // The UI shows why; the driver grants access and we are re-moded.
      await _stopStream();
      return;
    }
    // A mode switch may happen while the permission check was pending.
    if (state.mode != mode) return;

    final profile = LocationTrackingPolicy.profileFor(mode)!;
    await _stopStream();
    _positions = Geolocator.getPositionStream(
      locationSettings: _settingsFor(profile),
    ).listen(_onPosition, onError: _onStreamError);
    _sessions ??= _realtime.sessions.listen((_) => unawaited(_resendLatest()));
    _heartbeat = Timer.periodic(profile.heartbeat, (_) => unawaited(_beat()));
    state = state.copyWith(streaming: true);
    developer.log('Location streaming in ${mode.name} mode', name: 'location');
  }

  Future<void> stop() async {
    await _stopStream();
    await _sessions?.cancel();
    _sessions = null;
    _filter.reset();
    state = state.copyWith(
      mode: LocationTrackingMode.off,
      streaming: false,
      clearRejection: true,
    );
  }

  // ── Internals ──────────────────────────────────────────────────────────

  void _onPosition(Position position) {
    final fix = _toFix(position);
    if (_filter.check(fix) != FixVerdict.accept) return;
    state = state.copyWith(lastFix: fix);
    unawaited(_send(fix));
  }

  void _onStreamError(Object error) {
    developer.log('GPS stream error', error: error, name: 'location');
    // Typically permission revoked or GPS switched off mid-shift.
    unawaited(checkAccess());
    state = state.copyWith(streaming: false);
  }

  Future<void> _send(DriverFix fix) async {
    if (_sending) return; // the next fix supersedes this one
    _sending = true;
    try {
      if (_realtime.status == RealtimeStatus.connected) {
        final ack = await _realtime.sendDriverLocation(fix.toPayload());
        if (ack.ok) {
          state = state.copyWith(
            lastSentAt: DateTime.now(),
            clearRejection: true,
          );
        } else if (ack.code != 'RATE_LIMITED' && ack.code != 'NOT_CONNECTED') {
          state = state.copyWith(rejection: ack.code);
        }
      }
    } finally {
      _sending = false;
    }
  }

  /// Keeps a stationary online driver fresh on the server, and uses the
  /// REST fallback when the socket has been unavailable.
  Future<void> _beat() async {
    final profile = LocationTrackingPolicy.profileFor(state.mode);
    if (profile == null) return;
    final lastSent = state.lastSentAt;
    if (lastSent != null &&
        DateTime.now().difference(lastSent) < profile.heartbeat) {
      return;
    }

    var fix = state.lastFix;
    if (fix == null ||
        DateTime.now().difference(fix.recordedAt) >
            LocationTrackingPolicy.maxFixAge) {
      fix = await currentFix();
      if (fix == null) return;
      state = state.copyWith(lastFix: fix);
    } else {
      // Standing still: the OS suppressed updates, the position is current.
      fix = fix.restamped(DateTime.now());
    }

    if (_realtime.status == RealtimeStatus.connected) {
      await _send(fix);
    } else if (_restFallback != null) {
      try {
        await _restFallback!(fix.toPayload());
        state = state.copyWith(
          lastSentAt: DateTime.now(),
          clearRejection: true,
        );
      } catch (_) {
        // Offline entirely; the next beat tries again.
      }
    }
  }

  Future<void> _resendLatest() async {
    final fix = state.lastFix;
    if (fix == null || state.mode == LocationTrackingMode.off) return;
    await _send(fix.restamped(DateTime.now()));
  }

  Future<void> _stopStream() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _positions?.cancel();
    _positions = null;
  }

  void _teardown() {
    _heartbeat?.cancel();
    unawaited(_positions?.cancel());
    unawaited(_sessions?.cancel());
  }

  LocationAccess _setAccess(LocationAccess access) {
    if (state.access != access) state = state.copyWith(access: access);
    return access;
  }

  static DriverFix _toFix(Position position) {
    final moving = position.speed > 1;
    return DriverFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      // Device time; clamped by the server if the clock runs ahead.
      recordedAt: position.timestamp,
      heading: moving && position.heading >= 0 ? position.heading : null,
      speed: position.speed >= 0 ? position.speed : null,
    );
  }

  static LocationSettings _settingsFor(LocationTrackingProfile profile) {
    final accuracy = profile.highAccuracy
        ? LocationAccuracy.bestForNavigation
        : LocationAccuracy.high;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: accuracy,
          distanceFilter: profile.distanceFilterMeters,
          intervalDuration: profile.interval,
          // Keeps GPS (and this isolate) alive while the app is backgrounded.
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'You are online on Tirvona Rides',
            notificationText:
                'Sharing your location with riders while you are on duty.',
            notificationChannelName: 'Driver location',
            enableWakeLock: true,
            setOngoing: true,
            notificationIcon: AndroidResource(
              name: 'ic_stat_tirvona',
              defType: 'drawable',
            ),
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: accuracy,
          distanceFilter: profile.distanceFilterMeters,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      default:
        return LocationSettings(
          accuracy: accuracy,
          distanceFilter: profile.distanceFilterMeters,
        );
    }
  }
}

final driverLocationServiceProvider =
    NotifierProvider<DriverLocationService, DriverLocationState>(
      DriverLocationService.new,
    );
