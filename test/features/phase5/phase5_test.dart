import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/app/router/app_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/core/notifications/notification_target.dart';
import 'package:tirvona_ride/core/notifications/push_config.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/complaints/models/complaint_models.dart';
import 'package:tirvona_ride/features/customer/rating/models/rating_models.dart';
import 'package:tirvona_ride/features/notifications/models/app_notification.dart';
import 'package:tirvona_ride/features/safety/models/safety_models.dart';

AppUser _user(UserRole role, {DriverStatus? driverStatus}) => AppUser(
  id: 'u1',
  phone: '+919812345678',
  role: role,
  status: UserStatus.active,
  firstName: 'Test',
  isPhoneVerified: true,
  driver: driverStatus == null
      ? null
      : DriverStatusInfo(driverStatus: driverStatus),
);

void main() {
  group('NotificationTarget (tap routing)', () {
    String? customer(
      String type, {
      String? rideId,
      Map<String, String> data = const {},
    }) => NotificationTarget.resolve(
      role: UserRole.customer,
      type: type,
      rideId: rideId,
      data: data,
    )?.location;

    String? driver(
      String type, {
      String? rideId,
      Map<String, String> data = const {},
    }) => NotificationTarget.resolve(
      role: UserRole.driver,
      type: type,
      rideId: rideId,
      data: data,
    )?.location;

    test('customer ride events open the ride', () {
      for (final type in [
        'RIDE_DRIVER_ASSIGNED',
        'RIDE_DRIVER_ARRIVED',
        'RIDE_COMPLETED',
        'PAYMENT_FAILED',
        'SOS_UPDATED',
      ]) {
        expect(customer(type, rideId: 'r1'), AppRoutes.customerRide('r1'));
      }
    });

    test('payment success opens the rating screen', () {
      expect(
        customer('PAYMENT_SUCCESS', data: const {'rideId': 'r1'}),
        AppRoutes.customerRideRating('r1'),
      );
    });

    test('complaints open the ticket, or support without one', () {
      expect(
        customer('COMPLAINT_UPDATED', data: const {'complaintId': 'c1'}),
        AppRoutes.customerComplaint('c1'),
      );
      expect(driver('COMPLAINT_CREATED'), AppRoutes.driverSupport);
    });

    test('driver events open the driver ride; approval opens home', () {
      expect(driver('RIDE_REQUEST', rideId: 'r2'), AppRoutes.driverRide('r2'));
      expect(
        driver('PAYMENT_RECEIVED', rideId: 'r2'),
        AppRoutes.driverRide('r2'),
      );
      expect(driver('DRIVER_APPROVED'), AppRoutes.driverHome);
    });

    test('anything else falls back to the notification centre', () {
      expect(customer('GENERAL'), AppRoutes.customerNotifications);
      expect(driver('GENERAL'), AppRoutes.driverNotifications);
      expect(
        NotificationTarget.resolve(role: UserRole.admin, type: 'SOS_CREATED'),
        isNull,
      );
    });
  });

  group('router access to Phase 5 screens', () {
    test('customers and approved drivers reach their own screens only', () {
      final customer = SessionState.authenticated(_user(UserRole.customer));
      for (final location in [
        AppRoutes.customerNotifications,
        AppRoutes.customerEmergencyContacts,
        AppRoutes.customerSupport,
        AppRoutes.newComplaintFor(false, rideId: 'r1'),
        AppRoutes.customerComplaint('c1'),
        AppRoutes.customerRideRating('r1'),
      ]) {
        expect(resolveRedirect(customer, location), isNull, reason: location);
      }
      expect(
        resolveRedirect(customer, AppRoutes.driverNotifications),
        AppRoutes.customerHome,
      );

      final driver = SessionState.authenticated(
        _user(UserRole.driver, driverStatus: DriverStatus.approved),
      );
      for (final location in [
        AppRoutes.driverNotifications,
        AppRoutes.driverEmergencyContacts,
        AppRoutes.driverSupport,
        AppRoutes.driverSupportNew,
        AppRoutes.driverComplaint('c1'),
      ]) {
        expect(resolveRedirect(driver, location), isNull, reason: location);
      }
      expect(
        resolveRedirect(driver, AppRoutes.customerSupport),
        AppRoutes.driverHome,
      );
    });

    test('a driver still under review cannot open the approved screens', () {
      final pending = SessionState.authenticated(
        _user(UserRole.driver, driverStatus: DriverStatus.underReview),
      );
      expect(
        resolveRedirect(pending, AppRoutes.driverNotifications),
        AppRoutes.driverPendingApproval,
      );
    });
  });

  group('models', () {
    test('notification parses and flattens data to strings', () {
      final notification = AppNotification.fromJson({
        'id': 'n1',
        'type': 'RIDE_DRIVER_ARRIVED',
        'title': 'Your driver has arrived',
        'message': 'Rahul is at the pickup point.',
        'rideId': 'r1',
        'data': {'rideId': 'r1', 'attempt': 2},
        'isRead': false,
        'createdAt': '2026-09-25T04:30:00.000Z',
      });
      expect(notification.data, {'rideId': 'r1', 'attempt': '2'});
      expect(notification.markedRead().isRead, isTrue);
      expect(
        NotificationPage.fromJson({
          'items': <dynamic>[],
          'page': 1,
          'hasMore': false,
          'unreadCount': 3,
        }).unreadCount,
        3,
      );
    });

    test('day labels', () {
      final now = DateTime(2026, 9, 25, 12);
      expect(notificationDayLabel(DateTime(2026, 9, 25, 8), now: now), 'Today');
      expect(
        notificationDayLabel(DateTime(2026, 9, 24, 23), now: now),
        'Yesterday',
      );
      expect(notificationDayLabel(DateTime(2026, 9, 12), now: now), '12 Sep');
      expect(
        notificationDayLabel(DateTime(2025, 12, 31), now: now),
        '31 Dec 2025',
      );
    });

    test('rating status: rateable, rated, and blocked', () {
      final open = RideRatingStatus.fromJson({
        'rideId': 'r1',
        'canRate': true,
        'rating': null,
        'driver': {
          'name': 'Rahul Driver',
          'ratingAverage': 4.5,
          'ratingCount': 2,
          'vehicle': {
            'vehicleType': 'AUTO',
            'registrationNumber': 'UP85CC0001',
            'color': 'Green',
            'make': 'Bajaj',
          },
        },
      });
      expect(open.canRate, isTrue);
      expect(open.driver!.vehicleDescription, 'Green Bajaj');

      final rated = RideRatingStatus.fromJson({
        'rideId': 'r1',
        'canRate': false,
        'rating': {
          'id': 'x',
          'rating': 5,
          'comment': 'Very polite',
          'createdAt': '2026-09-25T04:30:00Z',
        },
      });
      expect(rated.rating!.rating, 5);

      final unpaid = RideRatingStatus.fromJson({
        'rideId': 'r1',
        'canRate': false,
        'reason': 'PAYMENT_NOT_VERIFIED',
      });
      expect(unpaid.reason, RatingBlocker.paymentNotVerified);
      expect(ratingSuggestions(5), contains('Polite driver'));
      expect(ratingSuggestions(2), contains('Unsafe driving'));
    });

    test('complaint categories follow the server rules', () {
      expect(
        ComplaintCategory.driverBehaviour.availableTo(isDriver: false),
        isTrue,
      );
      expect(
        ComplaintCategory.driverBehaviour.availableTo(isDriver: true),
        isFalse,
      );
      expect(
        ComplaintCategory.customerBehaviour.availableTo(isDriver: true),
        isTrue,
      );
      expect(ComplaintCategory.fare.needsRide, isTrue);
      expect(ComplaintCategory.technical.needsRide, isFalse);
      final complaint = Complaint.fromJson({
        'id': 'c1',
        'ticketCode': 'TKT-4HX8QW',
        'category': 'FARE',
        'subject': 'Overcharged',
        'description': 'The fare was higher than shown.',
        'status': 'IN_REVIEW',
        'createdAt': '2026-09-25T04:30:00Z',
        'timeline': [
          {'status': 'OPEN', 'at': '2026-09-25T04:30:00Z'},
          {'status': 'IN_REVIEW', 'at': '2026-09-25T05:30:00Z'},
        ],
      });
      expect(complaint.status, ComplaintStatus.inReview);
      expect(complaint.timeline.map((step) => step.status), [
        ComplaintStatus.open,
        ComplaintStatus.inReview,
      ]);
    });

    test('SOS status labels and openness', () {
      final alert = SosAlert.fromJson({
        'id': 's1',
        'sosCode': 'SOS-7K2M9Q',
        'rideId': 'r1',
        'status': 'ACKNOWLEDGED',
        'triggeredAt': '2026-09-25T04:30:00Z',
        'location': {'latitude': 27.5, 'longitude': 77.6, 'source': 'DEVICE'},
      });
      expect(alert.status.isOpen, isTrue);
      expect(SosStatus.resolved.isOpen, isFalse);
      expect(alert.locationSource, 'DEVICE');
    });
  });

  group('PushConfig', () {
    test('push stays off unless the platform has complete keys', () {
      const empty = PushConfig(
        apiKey: '',
        projectId: '',
        messagingSenderId: '',
        androidAppId: '',
        iosAppId: '',
        iosBundleId: 'com.tirvona.ride',
      );
      expect(empty.optionsFor(TargetPlatform.android, isWeb: false), isNull);

      const android = PushConfig(
        apiKey: 'key',
        projectId: 'tirvona',
        messagingSenderId: '123',
        androidAppId: '1:123:android:abc',
        iosAppId: '',
        iosBundleId: 'com.tirvona.ride',
      );
      expect(
        android.optionsFor(TargetPlatform.android, isWeb: false)?.appId,
        '1:123:android:abc',
      );
      expect(android.optionsFor(TargetPlatform.iOS, isWeb: false), isNull);
      expect(android.optionsFor(TargetPlatform.android, isWeb: true), isNull);
    });
  });
}
