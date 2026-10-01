import 'package:flutter/foundation.dart';

import '../../app/router/app_routes.dart';
import '../../features/auth/domain/app_user.dart';

/// Where tapping a notification takes the user. Built from the push `data`
/// map (or an in-app notification's `type`/`rideId`/`data`), so a push
/// tapped from the tray and a row tapped in the notification centre land on
/// the same screen. Pure, so the whole table is unit-tested.
@immutable
class NotificationTarget {
  const NotificationTarget._(this.location);

  final String location;

  static NotificationTarget? resolve({
    required UserRole role,
    required String? type,
    String? rideId,
    Map<String, String> data = const {},
  }) {
    final ride = (rideId?.isNotEmpty ?? false) ? rideId : data['rideId'];
    final complaintId = data['complaintId'];
    final paymentId = data['paymentId'];
    String? location;

    // Admin broadcasts (Phase 7) carry an allow-listed deep link; anything
    // unknown falls back to the notification centre.
    if (type == 'ANNOUNCEMENT') {
      final customer = role == UserRole.customer;
      location = switch (data['deepLink']) {
        'HOME' ||
        'RIDES' ||
        'OFFERS' => customer ? AppRoutes.customerHome : AppRoutes.driverHome,
        'SUPPORT' =>
          customer ? AppRoutes.customerSupport : AppRoutes.driverSupport,
        _ =>
          customer
              ? AppRoutes.customerNotifications
              : AppRoutes.driverNotifications,
      };
      return role == UserRole.admin ? null : NotificationTarget._(location);
    }

    switch (role) {
      case UserRole.customer:
        location = switch (type) {
          // "Tap to rate your driver"; the screen shows an existing rating.
          'PAYMENT_SUCCESS' when ride != null => AppRoutes.customerRideRating(
            ride,
          ),
          // Refund updates open the receipt, which lists every refund.
          'REFUND_INITIATED' || 'REFUND_PROCESSED' when paymentId != null =>
            AppRoutes.customerPayment(paymentId),
          // The tracking screen opens Pay itself when the fare is due.
          _ when type != null && type.startsWith('COMPLAINT_') =>
            complaintId == null
                ? AppRoutes.customerSupport
                : AppRoutes.customerComplaint(complaintId),
          _ when ride != null => AppRoutes.customerRide(ride),
          _ => AppRoutes.customerNotifications,
        };
      case UserRole.driver:
        location = switch (type) {
          'DRIVER_APPROVED' ||
          'DRIVER_REJECTED' ||
          'DRIVER_SUSPENDED' ||
          'DRIVER_REINSTATED' => AppRoutes.driverHome,
          // The deduction shows on the Earnings tab (home shell).
          'EARNING_ADJUSTED' => AppRoutes.driverHome,
          // A reviewed change to licence, vehicle or documents.
          'DRIVER_UPDATE_APPROVED' ||
          'DRIVER_UPDATE_REJECTED' => AppRoutes.driverDocuments,
          _ when type != null && type.startsWith('COMPLAINT_') =>
            complaintId == null
                ? AppRoutes.driverSupport
                : AppRoutes.driverComplaint(complaintId),
          _ when ride != null => AppRoutes.driverRide(ride),
          _ => AppRoutes.driverNotifications,
        };
      case UserRole.admin:
        location = null;
    }
    return location == null ? null : NotificationTarget._(location);
  }
}
