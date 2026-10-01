import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/realtime_models.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../data/ride_repository.dart';
import '../domain/live_tracking.dart';
import '../domain/ride_models.dart';

/// How ride state reaches the UI. Screens only consume these streams and
/// never know about sockets, rooms or re-syncs.
abstract interface class RideUpdatesSource {
  /// Emits the ride now, then on every change; completes once it is terminal.
  Stream<Ride> watchRide(String rideId);

  /// Emits the requests currently offered to the signed-in driver.
  Stream<List<Ride>> watchDriverRequests();

  /// Live driver positions for a ride the caller is part of.
  Stream<DriverPosition> watchDriverPosition(String rideId);

  /// `ride.driver_arriving` for a ride (fires at most once per ride).
  Stream<ArrivingNotice> watchArriving(String rideId);

  /// The ride as pushed with every `ride.payment_updated` (Phase 4). Lives
  /// on after the ride is completed, unlike [watchRide].
  Stream<Ride> watchPaymentUpdates(String rideId);
}

/// Phase 3 transport: **REST for state, WebSocket for change**.
///
/// * On listen: join the ride room, then fetch the authoritative snapshot
///   over REST.
/// * Every status event carries the recipient's full ride view, applied
///   directly — no round trip.
/// * After every (re)connect (`session.ready`) and every return to the
///   foreground, the snapshot is fetched again, so an event missed while
///   offline can never leave the UI stale.
/// * Snapshots are ordered by `stateVersion`; an older one (a slow REST
///   response racing a newer event) is dropped.
/// * 404/403 is final: the ride is not visible to this user any more.
class RealtimeRideUpdatesSource implements RideUpdatesSource {
  RealtimeRideUpdatesSource(
    this._repository,
    this._realtime, {
    this.pollWhileDisconnected = const Duration(seconds: 5),
    this.offerPollWhileConnected = const Duration(seconds: 20),
    this.ridePollWhileConnected = const Duration(seconds: 30),
  });

  final RideRepository _repository;
  final RealtimeClient _realtime;

  /// REST safety net under the socket (see [FallbackPoll]). Offers live for
  /// ~30 s, so they are re-checked more often than an ongoing ride.
  final Duration pollWhileDisconnected;
  final Duration offerPollWhileConnected;
  final Duration ridePollWhileConnected;

  static const _offerEvents = {
    RealtimeEvents.requested,
    RealtimeEvents.offerWithdrawn,
    RealtimeEvents.cancelled,
    RealtimeEvents.driverAccepted,
  };

  @override
  Stream<Ride> watchRide(String rideId) {
    late final StreamController<Ride> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    AppLifecycleListener? lifecycle;
    Ride? latest;

    FallbackPoll? poll;

    Future<void> close() async {
      poll?.cancel();
      poll = null;
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
      lifecycle?.dispose();
      lifecycle = null;
      if (!controller.isClosed) await controller.close();
    }

    void accept(Ride ride) {
      if (controller.isClosed) return;
      final current = latest;
      if (current != null && ride.stateVersion < current.stateVersion) return;
      latest = ride;
      controller.add(ride);
      if (ride.status.isTerminal) unawaited(close());
    }

    Future<void> resync() async {
      try {
        accept(await _repository.getRide(rideId));
      } on ApiException catch (error, stackTrace) {
        if (controller.isClosed) return;
        controller.addError(error, stackTrace);
        if (error.statusCode == 404 || error.statusCode == 403) {
          await close();
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<Ride>(
      onListen: () {
        subscriptions
          ..add(
            _realtime.events
                .where((event) => event.rideId == rideId && event.ride != null)
                .listen((event) {
                  try {
                    accept(Ride.fromJson(event.ride!));
                  } catch (_) {
                    // A malformed push is recovered by the next snapshot.
                    unawaited(resync());
                  }
                }),
          )
          ..add(_realtime.sessions.listen((_) => unawaited(resync())));
        lifecycle = AppLifecycleListener(onResume: () => unawaited(resync()));
        poll = FallbackPoll(
          _realtime,
          whileDisconnected: pollWhileDisconnected,
          whileConnected: ridePollWhileConnected,
          onTick: () => unawaited(resync()),
        );
        unawaited(_realtime.joinRide(rideId));
        unawaited(resync());
      },
      onCancel: close,
    );
    return controller.stream;
  }

  @override
  Stream<Ride> watchPaymentUpdates(String rideId) => _realtime.events
      .where(
        (event) =>
            event.rideId == rideId &&
            event.event == RealtimeEvents.paymentUpdated &&
            event.ride != null,
      )
      .map((event) => Ride.fromJson(event.ride!));

  @override
  Stream<List<Ride>> watchDriverRequests() {
    late final StreamController<List<Ride>> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    final offers = <String, Ride>{};
    AppLifecycleListener? lifecycle;
    Timer? pruneTimer;
    FallbackPoll? poll;

    void publish() {
      if (controller.isClosed) return;
      final list = offers.values.toList()
        ..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
      controller.add(List.unmodifiable(list));
    }

    Future<void> resync() async {
      try {
        final current = await _repository.driverRequests();
        offers
          ..clear()
          ..addEntries(current.map((ride) => MapEntry(ride.id, ride)));
        publish();
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    void onEvent(RealtimeEvent event) {
      final json = event.ride;
      Ride? ride;
      try {
        ride = json == null ? null : Ride.fromJson(json);
      } catch (_) {
        // A malformed push is recovered from the authoritative list.
        unawaited(resync());
        return;
      }
      if (event.event == RealtimeEvents.requested &&
          ride?.status == RideStatus.driverAssigned) {
        offers[event.rideId] = ride!;
      } else {
        offers.remove(event.rideId);
      }
      publish();
    }

    // Safety net: the server withdraws lapsed offers itself; this only
    // tidies a card whose deadline passed while the socket was down.
    void prune() {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 3));
      final before = offers.length;
      offers.removeWhere(
        (_, ride) =>
            ride.assignmentExpiresAt != null &&
            ride.assignmentExpiresAt!.isBefore(cutoff),
      );
      if (offers.length != before) publish();
    }

    Future<void> close() async {
      pruneTimer?.cancel();
      poll?.cancel();
      poll = null;
      lifecycle?.dispose();
      lifecycle = null;
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
      if (!controller.isClosed) await controller.close();
    }

    controller = StreamController<List<Ride>>(
      onListen: () {
        subscriptions
          ..add(
            _realtime.events
                .where((event) => _offerEvents.contains(event.event))
                .listen(onEvent),
          )
          ..add(_realtime.sessions.listen((_) => unawaited(resync())));
        lifecycle = AppLifecycleListener(onResume: () => unawaited(resync()));
        pruneTimer = Timer.periodic(const Duration(seconds: 2), (_) => prune());
        // Offers live for ~30 s: a missed push must not cost the driver one.
        poll = FallbackPoll(
          _realtime,
          whileDisconnected: pollWhileDisconnected,
          whileConnected: offerPollWhileConnected,
          onTick: () => unawaited(resync()),
        );
        unawaited(resync());
      },
      onCancel: close,
    );
    return controller.stream;
  }

  @override
  Stream<DriverPosition> watchDriverPosition(String rideId) => _realtime.events
      .where(
        (event) =>
            event.rideId == rideId &&
            event.event == RealtimeEvents.locationUpdated,
      )
      .map(driverPositionFromEvent)
      .where((position) => position != null)
      .cast<DriverPosition>();

  @override
  Stream<ArrivingNotice> watchArriving(String rideId) => _realtime.events
      .where(
        (event) =>
            event.rideId == rideId &&
            event.event == RealtimeEvents.driverArriving,
      )
      .map(ArrivingNotice.fromEvent);
}

/// Re-fetches over REST on a timer, as a safety net under the socket: every
/// [whileDisconnected] while the socket is down or still connecting, and
/// every [whileConnected] while it is up (a push can still be missed — the
/// app was suspended, a proxy dropped a frame). Re-armed on every status
/// change. Nothing polls once the session is gone (`unauthorized`).
///
/// The reconnect itself needs no tick here: `session.ready` already
/// triggers a re-sync.
@visibleForTesting
class FallbackPoll {
  FallbackPoll(
    this._realtime, {
    required this.whileDisconnected,
    required this.whileConnected,
    required this.onTick,
  }) {
    _statusSubscription = _realtime.statusChanges.listen((_) => _arm());
    _arm();
  }

  final RealtimeClient _realtime;
  final Duration whileDisconnected;
  final Duration whileConnected;
  final VoidCallback onTick;
  StreamSubscription<RealtimeStatus>? _statusSubscription;
  Timer? _timer;

  void _arm() {
    _timer?.cancel();
    _timer = switch (_realtime.status) {
      RealtimeStatus.unauthorized => null,
      RealtimeStatus.connected => Timer.periodic(
        whileConnected,
        (_) => onTick(),
      ),
      _ => Timer.periodic(whileDisconnected, (_) => onTick()),
    };
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    unawaited(_statusSubscription?.cancel());
    _statusSubscription = null;
  }
}

final rideUpdatesSourceProvider = Provider<RideUpdatesSource>(
  (ref) => RealtimeRideUpdatesSource(
    ref.watch(rideRepositoryProvider),
    ref.watch(realtimeClientProvider),
  ),
);
