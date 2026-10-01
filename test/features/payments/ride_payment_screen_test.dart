import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/customer/payments/models/payment_models.dart';
import 'package:tirvona_ride/features/customer/payments/repository/payment_repository.dart';
import 'package:tirvona_ride/features/customer/payments/screens/ride_payment_screen.dart';
import 'package:tirvona_ride/features/rides/application/ride_updates_source.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/live_tracking.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

import '../rides/ride_models_test.dart' show rideJson;

/// A completed, unpaid ride driven by "Rahul Kumar" (final fare ₹73).
final _completed = Ride.fromJson(
  rideJson(
    status: 'COMPLETED',
    extra: {
      'paymentStatus': 'PENDING',
      'completedAt': '2026-09-23T04:20:00.000Z',
      'fare': {
        'currency': 'INR',
        'baseFare': 30,
        'distanceCharge': 30.48,
        'timeCharge': 12.48,
        'subtotal': 72.96,
        'minimumFare': 40,
        'minimumFareApplied': false,
        'estimatedFare': 73,
        'finalFare': 73,
      },
      'driver': {
        'name': 'Rahul Kumar',
        'phone': '+919800000011',
        'ratingAverage': 4.8,
        'ratingCount': 12,
        'totalRides': 40,
      },
    },
  ),
);

class _FakeRides extends RideRepository {
  _FakeRides() : super(Dio());

  @override
  Future<Ride> getRide(String id) async => _completed;
}

class _FakePayments extends PaymentRepository {
  _FakePayments() : super(Dio());

  final cashRides = <String>[];

  @override
  Future<PaymentRecord> payCash(String rideId) async {
    cashRides.add(rideId);
    return PaymentRecord.fromJson({
      'id': 'pmt1',
      'rideId': rideId,
      'rideCode': 'TR7K2M9QXA',
      'gateway': 'CASH',
      'method': 'cash',
      'amount': 73,
      'currency': 'INR',
      'status': 'CAPTURED',
      'ridePaymentStatus': 'SUCCESS',
      'createdAt': '2026-09-23T04:21:00.000Z',
    });
  }
}

class _QuietUpdates implements RideUpdatesSource {
  @override
  Stream<Ride> watchRide(String rideId) => const Stream.empty();
  @override
  Stream<List<Ride>> watchDriverRequests() => const Stream.empty();
  @override
  Stream<DriverPosition> watchDriverPosition(String rideId) =>
      const Stream.empty();
  @override
  Stream<ArrivingNotice> watchArriving(String rideId) => const Stream.empty();
  @override
  Stream<Ride> watchPaymentUpdates(String rideId) => const Stream.empty();
}

void main() {
  late _FakePayments payments;

  Future<void> pumpScreen(WidgetTester tester) async {
    payments = _FakePayments();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rideRepositoryProvider.overrideWithValue(_FakeRides()),
          paymentRepositoryProvider.overrideWithValue(payments),
          rideUpdatesSourceProvider.overrideWithValue(_QuietUpdates()),
        ],
        child: MaterialApp(home: RidePaymentScreen(rideId: _completed.id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cashButton() => find.widgetWithText(OutlinedButton, 'Pay ₹73 in cash');

  testWidgets('offers online and cash payment for the final fare', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('Pay ₹73'), findsOneWidget);
    expect(cashButton(), findsOneWidget);
    expect(find.text('Hand the cash to Rahul at drop-off.'), findsOneWidget);
  });

  testWidgets('cash asks first; cancelling changes nothing', (tester) async {
    await pumpScreen(tester);
    await tester.ensureVisible(cashButton());
    await tester.tap(cashButton());
    await tester.pumpAndSettle();
    expect(find.text('Pay in cash?'), findsOneWidget);
    expect(
      find.textContaining('Please hand ₹73 in cash to Rahul'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(payments.cashRides, isEmpty);
    expect(cashButton(), findsOneWidget);
  });

  testWidgets('confirming marks the ride paid in cash', (tester) async {
    await pumpScreen(tester);
    await tester.ensureVisible(cashButton());
    await tester.tap(cashButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, pay cash'));
    await tester.pumpAndSettle();

    expect(payments.cashRides, [_completed.id]);
    expect(find.text('Paying in cash'), findsOneWidget);
    expect(find.text('₹73'), findsOneWidget);
    expect(
      find.text('Please hand this to Rahul · Ride TR7K2M9QXA'),
      findsOneWidget,
    );
    expect(find.text('Rate Rahul'), findsOneWidget);
  });
}
