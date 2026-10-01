import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/session_controller.dart';
import '../config/app_config_provider.dart';
import '../network/token_refresher.dart';
import '../storage/secure_storage.dart';
import 'realtime_client.dart';
import 'realtime_models.dart';

/// Whether the signed-in user has anything to receive in realtime.
bool usesRealtime(AppUser? user) => switch (user?.role) {
  UserRole.customer => user!.isPhoneVerified,
  UserRole.driver =>
    user!.isPhoneVerified && user.driver?.driverStatus == DriverStatus.approved,
  _ => false,
};

/// The single realtime connection, alive for the whole app. It follows the
/// session: connects when a customer / approved driver signs in, disconnects
/// on sign-out, so no screen ever manages the socket.
final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = SocketIoRealtimeClient(
    url: ref.watch(appConfigProvider).realtimeUrl,
    readAccessToken: ref.watch(secureStorageProvider).readAccessToken,
    refreshAccessToken: ref.watch(tokenRefresherProvider).refresh,
    onUnauthorized: () =>
        ref.read(sessionControllerProvider.notifier).handleSessionExpired(),
  );

  void follow(SessionState session) {
    if (session.isAuthenticated && usesRealtime(session.user)) {
      client.connect();
    } else {
      client.disconnect();
    }
  }

  ref
    ..listen(sessionControllerProvider, (_, next) => follow(next))
    ..onDispose(client.disconnect);
  follow(ref.read(sessionControllerProvider));
  return client;
});

/// Live connection status for banners and indicators.
final realtimeStatusProvider = StreamProvider<RealtimeStatus>((ref) async* {
  final client = ref.watch(realtimeClientProvider);
  yield client.status;
  yield* client.statusChanges;
});
