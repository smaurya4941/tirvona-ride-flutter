import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// One entry of the notification centre (`GET /notifications`). The server
/// generates every notification; the app only shows them and marks them read.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.rideId,
    this.referenceId,
    this.data = const {},
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'GENERAL',
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        isRead: json['isRead'] as bool? ?? false,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        readAt: DateTime.tryParse(json['readAt'] as String? ?? '')?.toLocal(),
        rideId: json['rideId'] as String?,
        referenceId: json['referenceId'] as String?,
        data: (json['data'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, '$value'),
        ),
      );

  final String id;

  /// Backend `NotificationType` (RIDE_DRIVER_ARRIVED, PAYMENT_SUCCESS, …).
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? rideId;
  final String? referenceId;
  final Map<String, String> data;

  AppNotification markedRead() => AppNotification(
    id: id,
    type: type,
    title: title,
    message: message,
    isRead: true,
    createdAt: createdAt,
    readAt: DateTime.now(),
    rideId: rideId,
    referenceId: referenceId,
    data: data,
  );

  /// Icon and accent per family of notification.
  ({IconData icon, Color color}) get visual => switch (type) {
    'RIDE_REQUEST' => (
      icon: Icons.notifications_active,
      color: AppColors.bhagwa,
    ),
    'RIDE_DRIVER_ASSIGNED' ||
    'RIDE_DRIVER_ACCEPTED' ||
    'RIDE_DRIVER_ARRIVING' => (icon: Icons.local_taxi, color: AppColors.bhagwa),
    'RIDE_DRIVER_ARRIVED' => (
      icon: Icons.where_to_vote,
      color: AppColors.success,
    ),
    'RIDE_STARTED' => (icon: Icons.route, color: AppColors.midnightBlue),
    'RIDE_END_OTP' => (icon: Icons.pin, color: AppColors.success),
    'RIDE_COMPLETED' => (icon: Icons.flag, color: AppColors.success),
    'RIDE_CANCELLED' || 'RIDE_NO_DRIVER' => (
      icon: Icons.cancel_outlined,
      color: AppColors.onSurfaceVariant,
    ),
    'PAYMENT_SUCCESS' ||
    'PAYMENT_RECEIVED' => (icon: Icons.check_circle, color: AppColors.success),
    'PAYMENT_FAILED' => (icon: Icons.error_outline, color: AppColors.error),
    'REFUND_INITIATED' || 'REFUND_PROCESSED' => (
      icon: Icons.currency_rupee,
      color: AppColors.success,
    ),
    'EARNING_ADJUSTED' => (icon: Icons.undo_rounded, color: AppColors.warning),
    'SOS_CREATED' || 'SOS_UPDATED' => (icon: Icons.sos, color: AppColors.error),
    'DRIVER_APPROVED' => (icon: Icons.verified, color: AppColors.success),
    'DRIVER_REJECTED' => (
      icon: Icons.report_outlined,
      color: AppColors.warning,
    ),
    'DRIVER_SUSPENDED' => (icon: Icons.block, color: AppColors.error),
    'DRIVER_REINSTATED' => (
      icon: Icons.verified_user,
      color: AppColors.success,
    ),
    'DRIVER_UPDATE_APPROVED' => (
      icon: Icons.task_alt_rounded,
      color: AppColors.success,
    ),
    'DRIVER_UPDATE_REJECTED' => (
      icon: Icons.assignment_late_outlined,
      color: AppColors.warning,
    ),
    'ANNOUNCEMENT' => (icon: Icons.campaign, color: AppColors.bhagwa),
    'COMPLAINT_CREATED' || 'COMPLAINT_UPDATED' => (
      icon: Icons.support_agent,
      color: AppColors.midnightBlue,
    ),
    _ => (icon: Icons.notifications_none, color: AppColors.midnightBlue),
  };
}

@immutable
class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.page,
    required this.hasMore,
    required this.unreadCount,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> json) =>
      NotificationPage(
        items: (json['items'] as List<dynamic>)
            .map(
              (item) => AppNotification.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        page: (json['page'] as num?)?.toInt() ?? 1,
        hasMore: json['hasMore'] as bool? ?? false,
        unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      );

  final List<AppNotification> items;
  final int page;
  final bool hasMore;
  final int unreadCount;
}

/// "Today" / "Yesterday" / "12 Sep" section headers for the centre.
String notificationDayLabel(DateTime at, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(at);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final label = '${day.day} ${months[day.month - 1]}';
  return day.year == today.year ? label : '$label ${day.year}';
}
