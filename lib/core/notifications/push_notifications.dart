import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_router.dart';
import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../../features/notifications/repository/notification_repository.dart';
import '../../features/notifications/state/notification_providers.dart';
import '../storage/secure_storage.dart';
import 'alert_sounds.dart';
import 'notification_target.dart';
import 'push_config.dart';

/// Runs on a background isolate when a push arrives while the app is in the
/// background or killed. Notification pushes are shown by the OS itself, so
/// all this has to do is make Firebase usable in that isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = PushConfig.fromEnvironment().optionsFor(
    defaultTargetPlatform,
  );
  if (options != null && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
}

/// Called once from `bootstrap()` before `runApp`. Returns whether push is
/// available in this build; the rest of the app degrades to in-app only.
Future<bool> initializePush(PushConfig config) async {
  final options = config.optionsFor(defaultTargetPlatform);
  if (options == null) {
    developer.log('Push disabled: Firebase is not configured', name: 'push');
    return false;
  }
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // iOS: show native notification banner and play sound even while the app is in the foreground.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
    return true;
  } catch (error, stack) {
    developer.log(
      'Push disabled: Firebase failed to start',
      error: error,
      stackTrace: stack,
      name: 'push',
    );
    return false;
  }
}

/// Overridden in `bootstrap()` with the result of [initializePush].
final pushEnabledProvider = Provider<bool>((ref) => false);

/// Messenger for app-wide banners (foreground pushes), set on MaterialApp.
final rootMessengerKeyProvider = Provider<GlobalKey<ScaffoldMessengerState>>(
  (ref) => GlobalKey<ScaffoldMessengerState>(),
);

enum PushPermission {
  /// Push is not available in this build.
  unavailable,

  /// Not asked yet / not resolved.
  unknown,
  granted,

  /// The user said no; we never ask again (they can enable it in Settings).
  denied,
}

class PushPermissionNotifier extends Notifier<PushPermission> {
  @override
  PushPermission build() => ref.watch(pushEnabledProvider)
      ? PushPermission.unknown
      : PushPermission.unavailable;

  void set(PushPermission value) => state = value;
}

final pushPermissionProvider =
    NotifierProvider<PushPermissionNotifier, PushPermission>(
      PushPermissionNotifier.new,
    );

/// Whether this user should get pushes on this phone at all.
bool _receivesPush(AppUser? user) => switch (user?.role) {
  UserRole.customer => user!.isPhoneVerified,
  // Pending drivers too: "You're approved!" is a push.
  UserRole.driver => user!.isPhoneVerified,
  _ => false,
};

/// Follows the session and owns everything FCM on this device:
///
/// * after sign-in: asks for permission once (never again after a "no"),
///   gets the FCM token and registers it for the signed-in user;
/// * token refresh: re-registers the new token;
/// * sign-out: deactivates the token server-side and deletes it locally, so
///   the next person to sign in on this phone never gets the previous
///   user's notifications;
/// * foreground pushes: an in-app banner + badge refresh (the realtime
///   socket already updates open screens);
/// * taps (tray or banner): opens the screen the notification is about.
class PushNotificationsController {
  PushNotificationsController(this._ref);

  final Ref _ref;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  String? _registeredToken;
  String? _registeredForUser;
  Map<String, String>? _pendingTap;
  OverlayEntry? _currentBanner;
  Timer? _bannerDismissTimer;
  bool _started = false;

  bool get _enabled => _ref.read(pushEnabledProvider);

  void start() {
    if (_started || !_enabled) return;
    _started = true;
    unawaited(_initLocalNotifications());
    final messaging = FirebaseMessaging.instance;
    _subscriptions
      ..add(FirebaseMessaging.onMessage.listen(_onForegroundMessage))
      ..add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          (message) => _openFromData(message.data),
        ),
      )
      ..add(messaging.onTokenRefresh.listen(_onTokenRefresh));
    // App launched by tapping a notification while it was killed.
    unawaited(
      messaging.getInitialMessage().then((message) {
        if (message != null) _openFromData(message.data);
      }, onError: (Object _) {}),
    );
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('ic_stat_tirvona');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            _openFromData(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      },
    );

    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      for (final sound in AlertSound.values) {
        await androidImpl.createNotificationChannel(sound.channel);
      }
    }

    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) {
            _openFromData(Map<String, dynamic>.from(decoded));
          }
        } catch (_) {}
      }
    }
  }

  /// Session changed (login, logout, OTP verified, driver approved…).
  Future<void> onSession(SessionState session) async {
    if (!_enabled) return;
    final user = session.user;
    if (!session.isAuthenticated || !_receivesPush(user)) {
      _registeredForUser = null;
      return;
    }
    if (_registeredForUser != user!.id) await _register(user);
    _flushPendingTap();
  }

  /// Before the session is cleared on sign-out. Never throws, never blocks
  /// sign-out for long.
  Future<void> unregister() async {
    if (!_enabled) return;
    final token = _registeredToken;
    _registeredToken = null;
    _registeredForUser = null;
    try {
      if (token != null) {
        await _ref
            .read(notificationRepositoryProvider)
            .deactivateDeviceToken(token)
            .timeout(const Duration(seconds: 4));
      }
    } catch (_) {
      // The server also retires this device's tokens on /auth/logout.
    }
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 4),
      );
    } catch (_) {}
  }

  void dispose() {
    _bannerDismissTimer?.cancel();
    _currentBanner?.remove();
    _currentBanner = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  Future<void> _register(AppUser user) async {
    final permission = await _ensurePermission();
    _ref.read(pushPermissionProvider.notifier).set(permission);
    if (permission != PushPermission.granted) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _send(token);
      _registeredForUser = user.id;
    } catch (error) {
      // No network / APNs not ready yet: retried on the next session change
      // or token refresh; the in-app centre works regardless.
      developer.log(
        'FCM token registration failed',
        error: error,
        name: 'push',
      );
    }
  }

  Future<PushPermission> _ensurePermission() async {
    final messaging = FirebaseMessaging.instance;
    var settings = await messaging.getNotificationSettings();
    // Ask exactly once; a "no" is respected (and remembered by the OS).
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      settings = await messaging.requestPermission();
    }
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => PushPermission.granted,
      AuthorizationStatus.denied ||
      AuthorizationStatus.deniedPermanently => PushPermission.denied,
      AuthorizationStatus.notDetermined => PushPermission.unknown,
    };
  }

  Future<void> _onTokenRefresh(String token) async {
    if (_registeredForUser == null) return;
    try {
      await _send(token);
    } catch (error) {
      developer.log('FCM token refresh failed', error: error, name: 'push');
    }
  }

  Future<void> _send(String token) async {
    final deviceId = await _ref
        .read(secureStorageProvider)
        .readOrCreateDeviceId();
    await _ref
        .read(notificationRepositoryProvider)
        .registerDeviceToken(
          token: token,
          platform: defaultTargetPlatform == TargetPlatform.iOS
              ? 'IOS'
              : 'ANDROID',
          deviceId: deviceId,
        );
    _registeredToken = token;
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    unawaited(_ref.read(unreadCountProvider.notifier).refresh());
    final notification = message.notification;
    if (notification == null) return;
    final sos = '${message.data['type'] ?? ''}'.startsWith('SOS');

    // 1. Show elegant in-app heads-up notification sliding down from the TOP
    _showTopBanner(
      title: notification.title ?? 'Tirvona Rides',
      body: notification.body,
      data: message.data,
      isSos: sos,
    );

    // 2. Also post to the system tray, so the alert sound plays. The OS only
    //    plays a push's sound when the app is closed or in the background.
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final alert = AlertSound.fromPush(message.data);
        final androidDetails = AndroidNotificationDetails(
          alert.channelId,
          alert.channelName,
          channelDescription: alert.channelDescription,
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_stat_tirvona',
          color: sos ? const Color(0xFFB91C1C) : const Color(0xFF0F172A),
          ticker: notification.title,
          playSound: true,
          sound: alert.androidSound,
          enableVibration: true,
          styleInformation: notification.body != null
              ? BigTextStyleInformation(
                  notification.body!,
                  contentTitle: notification.title,
                )
              : null,
        );

        final notificationDetails = NotificationDetails(
          android: androidDetails,
          iOS: DarwinNotificationDetails(
            presentAlert: false, // the in-app banner already shows it
            presentSound: true,
            sound: '${alert.sound}.wav',
          ),
        );
        await _localNotifications.show(
          id: message.messageId?.hashCode ??
              DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title: notification.title,
          body: notification.body,
          notificationDetails: notificationDetails,
          payload: jsonEncode(message.data),
        );
      } catch (error) {
        developer.log(
          'Failed to post local notification',
          error: error,
          name: 'push',
        );
      }
    }
  }

  void _showTopBanner({
    required String title,
    required String? body,
    required Map<String, dynamic> data,
    bool isSos = false,
  }) {
    final overlayState = rootNavigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    _bannerDismissTimer?.cancel();
    _currentBanner?.remove();
    _currentBanner = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return _TopNotificationBanner(
          title: title,
          body: body,
          isSos: isSos,
          onTap: () {
            _bannerDismissTimer?.cancel();
            entry.remove();
            if (_currentBanner == entry) _currentBanner = null;
            _openFromData(data);
          },
          onDismiss: () {
            _bannerDismissTimer?.cancel();
            entry.remove();
            if (_currentBanner == entry) _currentBanner = null;
          },
        );
      },
    );

    _currentBanner = entry;
    overlayState.insert(entry);

    _bannerDismissTimer = Timer(const Duration(seconds: 5), () {
      if (_currentBanner == entry) {
        entry.remove();
        _currentBanner = null;
      }
    });
  }

  void _openFromData(Map<String, dynamic> raw) {
    _pendingTap = raw.map((key, value) => MapEntry(key, '$value'));
    _flushPendingTap();
  }

  /// Navigates once there is a signed-in user to route for (a cold start
  /// from a tap arrives before the session has been restored).
  void _flushPendingTap() {
    final data = _pendingTap;
    final session = _ref.read(sessionControllerProvider);
    if (data == null || !session.isAuthenticated) return;
    _pendingTap = null;
    final notificationId = data['notificationId'];
    if (notificationId != null) {
      unawaited(
        _ref
            .read(notificationRepositoryProvider)
            .markRead(notificationId)
            .then((_) => _ref.read(unreadCountProvider.notifier).refresh())
            .catchError((Object _) {}),
      );
    }
    final target = NotificationTarget.resolve(
      role: session.user!.role,
      type: data['type'],
      rideId: data['rideId'],
      data: data,
    );
    if (target == null) return;
    // After the current frame, so the shell has built under the router.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ref.read(appRouterProvider).push(target.location));
    });
  }
}

/// App-lifetime controller (watched by the root widget).
final pushNotificationsProvider = Provider<PushNotificationsController>((ref) {
  final controller = PushNotificationsController(ref)..start();
  // Sign-out calls back into us (the session must not depend on push).
  final session = ref.read(sessionControllerProvider.notifier)
    ..addBeforeLogoutHook(controller.unregister);
  ref
    ..onDispose(() => session.removeBeforeLogoutHook(controller.unregister))
    ..listen(
      sessionControllerProvider,
      (_, next) => unawaited(controller.onSession(next)),
    )
    ..onDispose(controller.dispose);
  unawaited(controller.onSession(ref.read(sessionControllerProvider)));
  return controller;
});

class _TopNotificationBanner extends StatefulWidget {
  const _TopNotificationBanner({
    required this.title,
    required this.body,
    required this.isSos,
    required this.onTap,
    required this.onDismiss,
  });

  final String title;
  final String? body;
  final bool isSos;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_TopNotificationBanner> createState() => _TopNotificationBannerState();
}

class _TopNotificationBannerState extends State<_TopNotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 10,
      left: 14,
      right: 14,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Dismissible(
          key: UniqueKey(),
          direction: DismissDirection.up,
          onDismissed: (_) => widget.onDismiss(),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.isSos
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Color(0x26FFFFFF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isSos
                            ? Icons.warning_amber_rounded
                            : Icons.notifications_active_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (widget.body != null &&
                              widget.body!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              widget.body!,
                              style: const TextStyle(
                                color: Color(0xFFE2E8F0),
                                fontSize: 13,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'View',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

