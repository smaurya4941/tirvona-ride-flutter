import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/core/notifications/notification_target.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/driver/domain/driver_models.dart';
import 'package:tirvona_ride/features/rides/application/booking_controller.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/cancellation_models.dart';
import 'package:tirvona_ride/features/rides/domain/promo_models.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';
import 'package:tirvona_ride/features/rides/presentation/widgets/cancel_ride_sheet.dart';

import '../rides/ride_models_test.dart' show rideJson;

const _pickup = Place(
  address: 'Prem Mandir',
  latitude: 27.5714,
  longitude: 77.6716,
);
const _destination = Place(
  address: 'Banke Bihari Temple',
  latitude: 27.5806,
  longitude: 77.7006,
);

Map<String, dynamic> _previewJson({bool feeApplies = false}) => {
  'cancellable': true,
  'currency': 'INR',
  'fee': {
    'amount': feeApplies ? 25 : 0,
    'applies': feeApplies,
    'explanation': feeApplies
        ? 'A cancellation fee of ₹25 applies because your driver is already on the way'
        : 'Free cancellation',
  },
  'reasons': [
    {'code': 'CHANGED_MIND', 'label': 'Changed my mind', 'requiresNote': false},
    {'code': 'OTHER', 'label': 'Other', 'requiresNote': true},
  ],
};

class _FakeRides extends RideRepository {
  _FakeRides({this.feeApplies = false}) : super(Dio());

  final bool feeApplies;
  final cancels = <({String id, String? reasonCode, String? note})>[];
  final validated = <String>[];
  String? bookedPromo;

  @override
  Future<CancellationPreview> cancellationPreview(String id) async =>
      CancellationPreview.fromJson(_previewJson(feeApplies: feeApplies));

  @override
  Future<Ride> cancel(String id, {String? reasonCode, String? note}) async {
    cancels.add((id: id, reasonCode: reasonCode, note: note));
    return Ride.fromJson(
      rideJson(
        status: 'CANCELLED',
        extra: {
          'cancellation': {
            'cancelledBy': 'CUSTOMER',
            'reasonCode': reasonCode,
            'feeAmount': feeApplies ? 25 : 0,
            'feeStatus': feeApplies ? 'DUE' : 'NOT_APPLICABLE',
          },
        },
      ),
    );
  }

  @override
  Future<PromoQuote> validatePromo({
    required String code,
    required RideTypeCode rideType,
    required Place pickup,
    required Place destination,
  }) async {
    validated.add(code);
    if (code != 'BRAJ20') {
      throw const ApiException(
        kind: ApiErrorKind.client,
        message: 'This promo code is not valid',
        statusCode: 404,
        code: 'PROMO_INVALID',
      );
    }
    return PromoQuote.fromJson({
      'code': 'BRAJ20',
      'title': '₹20 off',
      'rideType': rideType.wireName,
      'fare': 73,
      'discount': 20,
      'payableFare': 53,
    });
  }

  @override
  Future<Ride> book({
    required RideTypeCode rideType,
    required Place pickup,
    required Place destination,
    String? promoCode,
  }) async {
    bookedPromo = promoCode;
    return Ride.fromJson(rideJson(status: 'SEARCHING'));
  }
}

void main() {
  group('Phase 7 models', () {
    test(
      'ride types are data: known codes compare equal, unknown ones survive',
      () {
        expect(RideTypeCode.fromWire('E_RICKSHAW'), RideTypeCode.eRickshaw);
        expect(RideTypeCode.fromWire('AUTO'), same(RideTypeCode.auto));
        final xl = RideTypeCode.fromWire('CAB_XL');
        expect(xl.wireName, 'CAB_XL');
        expect(xl.label, 'Cab Xl');
        expect(xl, RideTypeCode.fromWire('CAB_XL'));
        expect(xl == RideTypeCode.cab, isFalse);
      },
    );

    test('a promo ride shows the discount and what the customer pays', () {
      final ride = Ride.fromJson(
        rideJson(
          status: 'COMPLETED',
          extra: {
            'fare': {
              'currency': 'INR',
              'baseFare': 30,
              'perKmRate': 10,
              'perMinuteRate': 1.5,
              'minimumFare': 40,
              'distanceCharge': 30.48,
              'timeCharge': 12.48,
              'subtotal': 72.96,
              'minimumFareApplied': false,
              'estimatedFare': 73,
              'finalFare': 73,
              'discount': 20,
              'payableFare': 53,
            },
            'promo': {'code': 'BRAJ20', 'title': '₹20 off', 'discount': 20},
            'zone': {'id': 'z1', 'name': 'Vrindavan'},
          },
        ),
      );
      expect(ride.fare.fare, 73);
      expect(ride.fare.payable, 53);
      expect(ride.fare.hasDiscount, isTrue);
      expect(ride.promo?.code, 'BRAJ20');
      expect(ride.zoneName, 'Vrindavan');
    });

    test('without a promo the payable fare is the fare', () {
      final ride = Ride.fromJson(rideJson());
      expect(ride.fare.payable, 73);
      expect(ride.fare.hasDiscount, isFalse);
      expect(ride.promo, isNull);
    });

    test('a cancellation carries its reason code and fee', () {
      final ride = Ride.fromJson(
        rideJson(
          status: 'CANCELLED',
          extra: {
            'cancellation': {
              'cancelledBy': 'CUSTOMER',
              'reason': 'Driver is taking too long',
              'reasonCode': 'DRIVER_TOO_LONG',
              'feeAmount': 25,
              'feeStatus': 'WAIVED',
            },
          },
        ),
      );
      final cancellation = ride.cancellation!;
      expect(cancellation.reasonCode, 'DRIVER_TOO_LONG');
      expect(cancellation.hasFee, isTrue);
      expect(cancellation.feeLabel, 'waived');
    });

    test('cancellation preview and promo offers parse', () {
      final preview = CancellationPreview.fromJson(
        _previewJson(feeApplies: true),
      );
      expect(preview.fee.applies, isTrue);
      expect(preview.fee.amount, 25);
      expect(preview.reasons.last.requiresNote, isTrue);

      final offer = PromoOffer.fromJson({
        'code': 'FIRST50',
        'title': 'First ride',
        'discountType': 'PERCENTAGE',
        'discountValue': 50,
        'maxDiscount': 60,
        'endsAt': '2026-10-01T00:00:00.000Z',
      });
      expect(offer.summary, '50% off (up to ₹60)');
    });

    test(
      'drivers can register an e-rickshaw; unknown vehicle types do not crash',
      () {
        expect(VehicleType.fromWire('E_RICKSHAW'), VehicleType.eRickshaw);
        expect(VehicleType.fromWire('HOVERCRAFT'), VehicleType.cab);
      },
    );
  });

  group('Notification deep links', () {
    NotificationTarget? target(
      UserRole role,
      String type, [
      Map<String, String> data = const {},
    ]) => NotificationTarget.resolve(role: role, type: type, data: data);

    test('announcements follow their allow-listed deep link', () {
      expect(
        target(UserRole.customer, 'ANNOUNCEMENT', {
          'deepLink': 'HOME',
        })?.location,
        AppRoutes.customerHome,
      );
      expect(
        target(UserRole.driver, 'ANNOUNCEMENT', {
          'deepLink': 'SUPPORT',
        })?.location,
        AppRoutes.driverSupport,
      );
      expect(
        target(UserRole.customer, 'ANNOUNCEMENT', {
          'deepLink': 'javascript:alert(1)',
        })?.location,
        AppRoutes.customerNotifications,
      );
      expect(target(UserRole.admin, 'ANNOUNCEMENT'), isNull);
    });

    test(
      'suspension notices open the driver home (which shows the account state)',
      () {
        expect(
          target(UserRole.driver, 'DRIVER_SUSPENDED')?.location,
          AppRoutes.driverHome,
        );
        expect(
          target(UserRole.driver, 'DRIVER_REINSTATED')?.location,
          AppRoutes.driverHome,
        );
      },
    );
  });

  group('Cancel sheet', () {
    Future<(_FakeRides, List<Ride?>)> open(
      WidgetTester tester, {
      bool feeApplies = false,
    }) async {
      final rides = _FakeRides(feeApplies: feeApplies);
      final results = <Ride?>[];
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rideRepositoryProvider.overrideWithValue(rides)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async => results.add(
                      await showCancelRideSheet(
                        context,
                        ride: Ride.fromJson(
                          rideJson(status: 'DRIVER_ACCEPTED'),
                        ),
                        asDriver: false,
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (rides, results);
    }

    testWidgets('lists the server reasons and needs one before cancelling', (
      tester,
    ) async {
      final (rides, results) = await open(tester);
      expect(find.text('Changed my mind'), findsOneWidget);
      expect(find.text('Free cancellation'), findsOneWidget);
      final cancel = find.widgetWithText(FilledButton, 'Cancel ride');
      expect(tester.widget<FilledButton>(cancel).onPressed, isNull);

      await tester.tap(find.text('Changed my mind'));
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(rides.cancels.single.reasonCode, 'CHANGED_MIND');
      expect(results.single?.status, RideStatus.cancelled);
    });

    testWidgets('warns about the fee and asks for a note on "Other"', (
      tester,
    ) async {
      final (rides, _) = await open(tester, feeApplies: true);
      expect(find.textContaining('₹25 applies'), findsOneWidget);

      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      final cancel = find.widgetWithText(
        FilledButton,
        'Cancel and pay ₹25 fee',
      );
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(
        find.text('Please tell us briefly why you are cancelling.'),
        findsOneWidget,
      );
      expect(rides.cancels, isEmpty);

      await tester.enterText(find.byType(TextField), 'Temple closed');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(rides.cancels.single, (
        id: '66f0c0ffee0000000000abcd',
        reasonCode: 'OTHER',
        note: 'Temple closed',
      ));
    });
  });

  group('Promo in booking', () {
    ProviderContainer container(_FakeRides rides) {
      final container = ProviderContainer(
        overrides: [rideRepositoryProvider.overrideWithValue(rides)],
      );
      addTearDown(container.dispose);
      final controller = container.read(bookingControllerProvider.notifier)
        ..setPickup(_pickup, remember: false)
        ..setDestination(_destination, remember: false)
        ..select(RideTypeCode.auto);
      expect(controller, isNotNull);
      return container;
    }

    test('an accepted promo is sent with the booking', () async {
      final rides = _FakeRides();
      final c = container(rides);
      final quote = await c
          .read(bookingControllerProvider.notifier)
          .applyPromo(' braj20 ');
      expect(rides.validated.single, 'BRAJ20');
      expect(quote.payableFare, 53);
      expect(c.read(bookingControllerProvider).promo?.code, 'BRAJ20');

      await c.read(bookingControllerProvider.notifier).book();
      expect(rides.bookedPromo, 'BRAJ20');
    });

    test('a rejected code is not applied', () async {
      final rides = _FakeRides();
      final c = container(rides);
      await expectLater(
        c.read(bookingControllerProvider.notifier).applyPromo('NOPE'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'PROMO_INVALID',
          ),
        ),
      );
      expect(c.read(bookingControllerProvider).promo, isNull);
    });

    test('changing the trip or the ride type drops the promo', () async {
      final rides = _FakeRides();
      final c = container(rides);
      final controller = c.read(bookingControllerProvider.notifier);
      await controller.applyPromo('BRAJ20');
      controller.select(RideTypeCode.cab);
      expect(c.read(bookingControllerProvider).promo, isNull);

      controller.select(RideTypeCode.auto);
      await controller.applyPromo('BRAJ20');
      controller.setDestination(
        _pickup.copyWithAddress('Elsewhere'),
        remember: false,
      );
      expect(c.read(bookingControllerProvider).promo, isNull);
    });
  });
}

extension on Place {
  Place copyWithAddress(String address) =>
      Place(address: address, latitude: latitude + 0.01, longitude: longitude);
}
