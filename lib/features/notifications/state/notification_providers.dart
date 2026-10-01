import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_models.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../auth/presentation/session_controller.dart';
import '../repository/notification_repository.dart';

/// Unread notifications for the bell badge. The number always comes from
/// the server: fetched on sign-in, then kept live by the socket's
/// `notification.created` / `notification.unread_count` events (and
/// re-fetched after a foreground push or when the centre marks things read).
class UnreadCountNotifier extends Notifier<int> {
  @override
  int build() {
    final userId = ref.watch(
      sessionControllerProvider.select((session) => session.user?.id),
    );
    if (userId == null) return 0;

    final subscription = ref
        .watch(realtimeClientProvider)
        .notices
        .listen(_onNotice);
    // A reconnect may have missed events: re-sync the count.
    final sessions = ref
        .watch(realtimeClientProvider)
        .sessions
        .listen((_) => unawaited(refresh()));
    ref.onDispose(() {
      unawaited(subscription.cancel());
      unawaited(sessions.cancel());
    });
    Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async {
    try {
      final count = await ref
          .read(notificationRepositoryProvider)
          .unreadCount();
      if (ref.mounted) state = count;
    } catch (_) {
      // Keep the last known count on a transient failure.
    }
  }

  void set(int count) => state = count < 0 ? 0 : count;

  /// Notifications that mean the driver's account status just changed: the
  /// session is re-read so the router moves them (e.g. to the suspended
  /// screen) without waiting for their next action to fail.
  static const _accountStatusTypes = {
    'DRIVER_APPROVED',
    'DRIVER_REJECTED',
    'DRIVER_SUSPENDED',
    'DRIVER_REINSTATED',
  };

  void _onNotice(RealtimeNotice notice) {
    if (notice.event != RealtimeEvents.notificationCreated &&
        notice.event != RealtimeEvents.notificationUnreadCount) {
      return;
    }
    final count = notice.data['unreadCount'];
    if (count is num) state = count.toInt();

    final created = notice.data['notification'];
    if (created is Map && _accountStatusTypes.contains(created['type'])) {
      unawaited(
        ref
            .read(sessionControllerProvider.notifier)
            .refreshUser()
            .catchError((_) {}),
      );
    }
  }
}

final unreadCountProvider = NotifierProvider<UnreadCountNotifier, int>(
  UnreadCountNotifier.new,
);

/// Fires whenever a new notification arrives over the socket, so an open
/// notification centre can show it at the top.
final notificationArrivalsProvider = StreamProvider.autoDispose<RealtimeNotice>(
  (ref) => ref
      .watch(realtimeClientProvider)
      .notices
      .where((notice) => notice.event == RealtimeEvents.notificationCreated),
);
