import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/config/app_config.dart';
import 'package:tirvona_ride/core/config/app_config_provider.dart';
import 'package:tirvona_ride/core/notifications/push_notifications.dart';
import 'package:tirvona_ride/core/realtime/realtime_client.dart';
import 'package:tirvona_ride/core/realtime/realtime_models.dart';
import 'package:tirvona_ride/core/realtime/realtime_providers.dart';
import 'package:tirvona_ride/features/auth/data/auth_repository.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/notifications/state/notification_providers.dart';

class _FakeAuth extends AuthRepository {
  _FakeAuth() : super(Dio());
  @override
  Future<AppUser> me() async => const AppUser(
    id: 'u1',
    phone: '+919812345678',
    role: UserRole.customer,
    status: UserStatus.active,
    firstName: 'Test',
    isPhoneVerified: true,
  );
  @override
  Future<void> logout(String refreshToken) async {}
}

class _FakeRealtime implements RealtimeClient {
  @override
  RealtimeStatus get status => RealtimeStatus.idle;
  @override
  Stream<RealtimeStatus> get statusChanges => const Stream.empty();
  @override
  Stream<RealtimeEvent> get events => const Stream.empty();
  @override
  Stream<RealtimeSession> get sessions => const Stream.empty();
  @override
  Stream<RealtimeNotice> get notices => const Stream.empty();
  @override
  void connect() {}
  @override
  void disconnect() {}
  @override
  Future<RealtimeAck> joinRide(String rideId) async =>
      const RealtimeAck(ok: true);
  @override
  Future<void> leaveRide(String rideId) async {}
  @override
  Future<RealtimeAck> sendDriverLocation(Map<String, dynamic> fix) async =>
      const RealtimeAck(ok: true);
}

/// Regression: Phase 5 made logout() read the push controller, which itself
/// listens to the session — a Riverpod dependency cycle that threw inside
/// the (unawaited) Sign out tap, so the button silently did nothing.
void main() {
  test(
    'sign out ends the session with push and the unread badge alive',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth.accessToken': 'a',
        'auth.refreshToken': 'r',
      });
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              environment: AppEnvironment.development,
              apiOrigin: 'http://127.0.0.1:1',
            ),
          ),
          authRepositoryProvider.overrideWithValue(_FakeAuth()),
          realtimeClientProvider.overrideWithValue(_FakeRealtime()),
        ],
      );
      addTearDown(container.dispose);
      // What the app root keeps alive.
      container
        ..listen(pushNotificationsProvider, (_, _) {})
        ..listen(unreadCountProvider, (_, _) {})
        ..listen(sessionControllerProvider, (_, _) {});
      for (
        var i = 0;
        i < 20 && !container.read(sessionControllerProvider).isAuthenticated;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);

      await container.read(sessionControllerProvider.notifier).logout();
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.unauthenticated,
      );
      expect(container.read(unreadCountProvider), 0);
    },
  );
}
