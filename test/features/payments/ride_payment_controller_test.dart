import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/network/api_exception.dart';
import 'package:tirvona_ride/features/customer/payments/models/payment_models.dart';
import 'package:tirvona_ride/features/customer/payments/repository/payment_repository.dart';
import 'package:tirvona_ride/features/customer/payments/state/checkout_launcher.dart';
import 'package:tirvona_ride/features/customer/payments/state/ride_payment_controller.dart';
import 'package:tirvona_ride/features/rides/application/ride_updates_source.dart';
import 'package:tirvona_ride/features/rides/domain/live_tracking.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

Map<String, dynamic> _paymentJson({
  String status = 'CREATED',
  String ridePaymentStatus = 'ORDER_CREATED',
  String? razorpayPaymentId,
  String? failureReason,
}) => {
  'id': 'pmt1',
  'rideId': 'ride1',
  'rideCode': 'TR7K2M9QXA',
  'gateway': 'RAZORPAY',
  'amount': 195,
  'currency': 'INR',
  'status': status,
  'ridePaymentStatus': ridePaymentStatus,
  'method': razorpayPaymentId == null ? null : 'upi',
  'razorpayPaymentId': razorpayPaymentId,
  'failureReason': failureReason,
  'createdAt': '2026-09-24T10:00:00.000Z',
};

PaymentRecord _payment({
  String status = 'CREATED',
  String ridePaymentStatus = 'ORDER_CREATED',
  String? razorpayPaymentId,
  String? failureReason,
}) => PaymentRecord.fromJson(
  _paymentJson(
    status: status,
    ridePaymentStatus: ridePaymentStatus,
    razorpayPaymentId: razorpayPaymentId,
    failureReason: failureReason,
  ),
);

class _FakeRepository extends PaymentRepository {
  _FakeRepository() : super(Dio());

  Object? createError;
  Object? verifyError;
  Object? cashError;
  final cashRides = <String>[];
  PaymentRecord verifyResult = _payment(
    status: 'CAPTURED',
    ridePaymentStatus: 'SUCCESS',
    razorpayPaymentId: 'pay_ABC12345',
  );
  PaymentRecord receiptPayment = _payment(
    status: 'CAPTURED',
    ridePaymentStatus: 'SUCCESS',
    razorpayPaymentId: 'pay_ABC12345',
  );
  final verified = <String>[];
  final failures = <String?>[];

  @override
  Future<PaymentCheckout> create(String rideId) async {
    if (createError != null) throw createError!;
    return PaymentCheckout.fromJson({
      'payment': _paymentJson(),
      'checkout': {
        'key': 'rzp_test_KEY',
        'orderId': 'order_ABC12345',
        'amount': 19500,
        'currency': 'INR',
        'name': 'Tirvona Rides',
        'description': 'Ride TR7K2M9QXA',
        'prefill': {'contact': '+919800000000'},
        'notes': {'rideId': 'ride1'},
      },
    });
  }

  @override
  Future<PaymentRecord> payCash(String rideId) async {
    cashRides.add(rideId);
    if (cashError != null) throw cashError!;
    return PaymentRecord.fromJson({
      ..._paymentJson(status: 'CAPTURED', ridePaymentStatus: 'SUCCESS'),
      'gateway': 'CASH',
      'method': 'cash',
    });
  }

  @override
  Future<PaymentRecord> verify({
    required String paymentId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    verified.add(razorpayPaymentId);
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }

  @override
  Future<PaymentRecord> reportFailure(
    String paymentId, {
    String? razorpayOrderId,
    String? razorpayPaymentId,
    String? code,
    String? description,
    bool cancelled = false,
  }) async {
    failures.add(description);
    return _payment(status: 'FAILED', ridePaymentStatus: 'FAILED');
  }

  @override
  Future<PaymentReceipt> receipt(String paymentId) async => PaymentReceipt(
    payment: receiptPayment,
    rideCode: 'TR7K2M9QXA',
    rideType: RideTypeCode.auto,
    pickup: const Place(address: 'A', latitude: 0, longitude: 0),
    destination: const Place(address: 'B', latitude: 0, longitude: 0),
    distanceMeters: 3000,
    durationSeconds: 600,
    fare: FareBreakdown.fromJson(const {'finalFare': 195}),
    customerName: 'Asha',
  );
}

class _FakeLauncher implements CheckoutLauncher {
  _FakeLauncher(this.result);

  CheckoutResult result;
  CheckoutOptions? opened;

  @override
  Future<CheckoutResult> open(CheckoutOptions options) async {
    opened = options;
    return result;
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
  late _FakeRepository repository;
  late _FakeLauncher launcher;
  late ProviderContainer container;

  const success = CheckoutSucceeded(
    razorpayPaymentId: 'pay_ABC12345',
    razorpayOrderId: 'order_ABC12345',
    razorpaySignature: 'sig',
  );

  setUp(() {
    repository = _FakeRepository();
    launcher = _FakeLauncher(success);
    container = ProviderContainer(
      overrides: [
        paymentRepositoryProvider.overrideWithValue(repository),
        checkoutLauncherProvider.overrideWithValue(launcher),
        rideUpdatesSourceProvider.overrideWithValue(_QuietUpdates()),
      ],
    );
    container.listen(ridePaymentControllerProvider('ride1'), (_, _) {});
  });

  tearDown(() => container.dispose());

  RidePaymentState state() =>
      container.read(ridePaymentControllerProvider('ride1'));
  Future<void> pay() =>
      container.read(ridePaymentControllerProvider('ride1').notifier).pay();

  test(
    'opens checkout with the server amount and succeeds only after verify',
    () async {
      await pay();
      expect(launcher.opened?.amountPaise, 19500);
      expect(
        launcher.opened?.toRazorpayOptions()['order_id'],
        'order_ABC12345',
      );
      expect(repository.verified, ['pay_ABC12345']);
      expect(state().phase, PaymentPhase.succeeded);
      expect(state().payment?.razorpayPaymentId, 'pay_ABC12345');
    },
  );

  test(
    'a checkout "success" the server rejects is a failure, not a payment',
    () async {
      repository.verifyError = const ApiException(
        kind: ApiErrorKind.client,
        statusCode: 400,
        code: 'PAYMENT_SIGNATURE_INVALID',
        message: 'Payment verification failed',
      );
      await pay();
      expect(state().phase, PaymentPhase.failed);
      expect(state().message, 'Payment verification failed');
    },
  );

  test('a failed checkout reports the failure and offers a retry', () async {
    launcher.result = const CheckoutFailed(
      message: 'Payment failed due to incorrect UPI PIN',
      code: 'BAD_REQUEST_ERROR',
    );
    await pay();
    await Future<void>.delayed(Duration.zero);
    expect(state().phase, PaymentPhase.failed);
    expect(state().cancelled, isFalse);
    expect(repository.failures, ['Payment failed due to incorrect UPI PIN']);

    launcher.result = success;
    await pay();
    expect(state().phase, PaymentPhase.succeeded);
  });

  test('closing the sheet is a soft failure', () async {
    launcher.result = const CheckoutFailed(
      message: 'You closed the payment page.',
      cancelled: true,
    );
    await pay();
    expect(state().phase, PaymentPhase.failed);
    expect(state().cancelled, isTrue);
  });

  test(
    'a network error during verify never shows "failed": it confirms instead',
    () async {
      repository.verifyError = const ApiException(
        kind: ApiErrorKind.network,
        message: 'Cannot reach Tirvona Rides.',
      );
      await pay();
      // The first status check runs immediately and finds the payment captured.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(state().phase, PaymentPhase.succeeded);
    },
  );

  test('an already-paid ride goes straight to success', () async {
    repository.createError = const ApiException(
      kind: ApiErrorKind.client,
      statusCode: 409,
      code: 'PAYMENT_ALREADY_COMPLETED',
      message: 'This ride is already paid',
      data: {'paymentId': 'pmt1'},
    );
    await pay();
    expect(launcher.opened, isNull);
    expect(state().phase, PaymentPhase.succeeded);
  });

  group('pay cash', () {
    Future<void> payCash() => container
        .read(ridePaymentControllerProvider('ride1').notifier)
        .payCash();

    test('settles at once, without opening Razorpay', () async {
      await payCash();
      expect(repository.cashRides, ['ride1']);
      expect(launcher.opened, isNull);
      expect(state().phase, PaymentPhase.succeeded);
      expect(state().payment?.isCash, isTrue);
      expect(state().payment?.methodLabel, 'Cash to driver');
    });

    test('an already-paid ride shows the existing payment', () async {
      repository.cashError = const ApiException(
        kind: ApiErrorKind.client,
        statusCode: 409,
        code: 'PAYMENT_ALREADY_COMPLETED',
        message: 'This ride is already paid',
        data: {'paymentId': 'pmt1'},
      );
      await payCash();
      expect(state().phase, PaymentPhase.succeeded);
      expect(state().payment?.razorpayPaymentId, 'pay_ABC12345');
    });

    test('while an online payment is confirming, follows that one', () async {
      repository
        ..receiptPayment = _payment(
          status: 'AUTHORIZED',
          ridePaymentStatus: 'PROCESSING',
        )
        ..cashError = const ApiException(
          kind: ApiErrorKind.client,
          statusCode: 409,
          code: 'PAYMENT_IN_PROGRESS',
          message: 'An online payment for this ride is still being confirmed.',
          data: {'paymentId': 'pmt1'},
        );
      await payCash();
      expect(state().phase, PaymentPhase.confirming);
    });

    test('other errors fail with the server message', () async {
      repository.cashError = const ApiException(
        kind: ApiErrorKind.client,
        statusCode: 409,
        code: 'PAYMENT_RIDE_NOT_COMPLETED',
        message: 'Payment opens once the ride is completed',
      );
      await payCash();
      expect(state().phase, PaymentPhase.failed);
      expect(state().message, 'Payment opens once the ride is completed');
      expect(state().cash, isFalse);
    });
  });

  test('ride payment status helpers', () {
    expect(RidePaymentStatus.fromWire('FAILED').isPayable, isTrue);
    expect(RidePaymentStatus.fromWire('SUCCESS').isPaid, isTrue);
    expect(RidePaymentStatus.fromWire(null), RidePaymentStatus.notRequired);
    expect(_payment(status: 'CAPTURED').status.isPaid, isTrue);
  });

  test('checkout errors surface as ApiException messages', () async {
    repository.createError = const ApiException(
      kind: ApiErrorKind.server,
      statusCode: 503,
      code: 'PAYMENT_GATEWAY_NOT_CONFIGURED',
      message: 'Online payments are not available right now',
    );
    await pay();
    expect(state().phase, PaymentPhase.failed);
    expect(state().message, 'Online payments are not available right now');
    unawaited(Future<void>.value());
  });
}
