import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_target.dart';
import '../../../core/notifications/push_notifications.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../auth/presentation/session_controller.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../models/app_notification.dart';
import '../repository/notification_repository.dart';
import '../state/notification_providers.dart';

/// The notification centre (customer and driver): newest first, grouped by
/// day, paged 20 at a time. Tapping a notification marks it read and opens
/// what it is about.
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  final List<AppNotification> _items = [];
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await ref
          .read(notificationRepositoryProvider)
          .list(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _page = 1;
        _hasMore = page.hasMore;
      });
      ref.read(unreadCountProvider.notifier).set(page.unreadCount);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _maybeLoadMore() {
    if (!_hasMore || _loadingMore) return;
    if (_scroll.position.extentAfter < 400) unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(notificationRepositoryProvider)
          .list(page: _page + 1, limit: _pageSize);
      if (!mounted) return;
      final known = _items.map((item) => item.id).toSet();
      setState(() {
        _items.addAll(page.items.where((item) => !known.contains(item.id)));
        _page = page.page;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.isRead) {
      final index = _items.indexWhere((item) => item.id == notification.id);
      if (index >= 0) setState(() => _items[index] = notification.markedRead());
      final unread = ref.read(unreadCountProvider);
      ref.read(unreadCountProvider.notifier).set(unread - 1);
      unawaited(
        ref
            .read(notificationRepositoryProvider)
            .markRead(notification.id)
            .then((_) {}, onError: (Object _) {}),
      );
    }
    final user = ref.read(sessionControllerProvider).user;
    if (user == null) return;
    final target = NotificationTarget.resolve(
      role: user.role,
      type: notification.type,
      rideId: notification.rideId,
      data: notification.data,
    );
    if (target != null && mounted) unawaited(context.push(target.location));
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          if (!_items[i].isRead) _items[i] = _items[i].markedRead();
        }
      });
      ref.read(unreadCountProvider.notifier).set(0);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A new notification over the socket: show it at the top.
    ref.listen(notificationArrivalsProvider, (_, next) {
      if (next.hasValue) unawaited(_reload());
    });
    final unread = ref.watch(unreadCountProvider);
    final permission = ref.watch(pushPermissionProvider);

    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _items.isEmpty) {
      body = LoadErrorView(error: _error!, onRetry: _reload);
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (permission == PushPermission.denied) const _PushOffCard(),
                  const _EmptyState(),
                ],
              )
            : ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                itemCount:
                    _items.length +
                    (permission == PushPermission.denied ? 1 : 0) +
                    (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (permission == PushPermission.denied) {
                    if (index == 0) return const _PushOffCard();
                    index -= 1;
                  }
                  if (index >= _items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final item = _items[index];
                  final header = notificationDayLabel(item.createdAt);
                  final showHeader =
                      index == 0 ||
                      notificationDayLabel(_items[index - 1].createdAt) !=
                          header;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                          child: Text(
                            header,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      _NotificationTile(
                        notification: item,
                        onTap: () => _open(item),
                      ),
                    ],
                  );
                },
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: body,
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = notification.visual;
    final time = TimeOfDay.fromDateTime(notification.createdAt).format(context);
    return Material(
      color: notification.isRead ? Colors.transparent : AppColors.bhagwaLight,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: visual.color.withValues(alpha: 0.12),
                child: Icon(visual.icon, color: visual.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: notification.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                              color: AppColors.midnightBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.message,
                      style: const TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (!notification.isRead)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 8, top: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.bhagwa,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 96, 32, 32),
      child: Column(
        children: [
          Icon(
            Icons.notifications_none,
            size: 56,
            color: AppColors.outlineVariant,
          ),
          SizedBox(height: 12),
          Text(
            'No notifications yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Ride updates, payments and support replies will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Shown when the user declined push permission — we don't ask again.
class _PushOffCard extends StatelessWidget {
  const _PushOffCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: ListTile(
        leading: Icon(
          Icons.notifications_off_outlined,
          color: AppColors.warning,
        ),
        title: Text('Push notifications are off'),
        subtitle: Text(
          'You will still see updates here. To get alerts when the app is '
          'closed, allow notifications for Tirvona Rides in your phone '
          'settings.',
        ),
      ),
    );
  }
}
