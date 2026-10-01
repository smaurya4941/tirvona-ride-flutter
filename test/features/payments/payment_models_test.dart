import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/customer/payments/models/payment_models.dart';
import 'package:tirvona_ride/features/driver/earnings/models/earning_models.dart';
import 'package:tirvona_ride/features/rides/domain/ride_formatters.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

void main() {
  test('PaymentRecord parses the server view, method from the gateway', () {
    final payment = PaymentRecord.fromJson(const {
      'id': 'p1',
      'rideId': 'r1',
      'rideCode': 'TRABC',
      'amount': 195.5,
      'currency': 'INR',
      'status': 'CAPTURED',
      'ridePaymentStatus': 'SUCCESS',
      'method': 'card',
      'methodDetails': {'cardNetwork': 'Visa', 'cardLast4': '1111'},
      'razorpayPaymentId': 'pay_X1',
      'paidAt': '2026-09-24T10:00:00.000Z',
      'createdAt': '2026-09-24T09:59:00.000Z',
    });
    expect(payment.status, PaymentStatus.captured);
    expect(payment.ridePaymentStatus, RidePaymentStatus.success);
    expect(payment.amount, 195.5);
    expect(payment.methodLabel, 'Card (Visa · •••• 1111)');
  });

  test('CheckoutOptions become Razorpay Standard Checkout options', () {
    final options = CheckoutOptions.fromJson(const {
      'key': 'rzp_test_K',
      'orderId': 'order_1',
      'amount': 19550,
      'currency': 'INR',
      'name': 'Tirvona Rides',
      'description': 'Ride TRABC',
      'prefill': {'name': 'Asha', 'contact': '+919800000000'},
      'notes': {'rideId': 'r1'},
    }).toRazorpayOptions();
    expect(options['key'], 'rzp_test_K');
    expect(options['order_id'], 'order_1');
    expect(options['amount'], 19550);
    expect(options['prefill'], {'name': 'Asha', 'contact': '+919800000000'});
  });

  test('a completed ride with PENDING payment awaits payment', () {
    final json = {
      'id': 'r1',
      'rideCode': 'TRABC',
      'status': 'COMPLETED',
      'rideType': 'AUTO',
      'pickup': {'address': 'A', 'latitude': 0, 'longitude': 0},
      'destination': {'address': 'B', 'latitude': 0, 'longitude': 0},
      'distanceMeters': 1000,
      'durationSeconds': 300,
      'fare': {'estimatedFare': 80, 'finalFare': 85},
      'requestedAt': '2026-09-24T09:00:00.000Z',
      'paymentStatus': 'PENDING',
    };
    expect(Ride.fromJson(json).awaitsPayment, isTrue);
    final paid = Ride.fromJson({
      ...json,
      'paymentStatus': 'SUCCESS',
      'payment': {'paymentId': 'p1', 'gatewayPaymentId': 'pay_1', 'amount': 85},
    });
    expect(paid.awaitsPayment, isFalse);
    expect(paid.payment?.gatewayPaymentId, 'pay_1');
    // Pre-Phase-4 payloads without the field still parse.
    expect(
      Ride.fromJson({...json}..remove('paymentStatus')).paymentStatus,
      RidePaymentStatus.notRequired,
    );
  });

  test('EarningsPage parses summary, balances and ledger lines', () {
    final page = EarningsPage.fromJson(const {
      'period': 'today',
      'periodTotals': {'net': 160, 'gross': 200, 'commission': 40, 'rides': 1},
      'summary': {
        'today': {'net': 160, 'gross': 200, 'commission': 40, 'rides': 1},
        'week': {'net': 160, 'gross': 200, 'commission': 40, 'rides': 1},
        'month': {'net': 160, 'gross': 200, 'commission': 40, 'rides': 1},
        'total': {'net': 900, 'gross': 1125, 'commission': 225, 'rides': 6},
        'balances': {'pending': 0, 'available': 160, 'paid': 740},
      },
      'items': [
        {
          'id': 'e1',
          'rideId': 'r1',
          'rideCode': 'TRABC',
          'rideType': 'AUTO',
          'rideCompletedAt': '2026-09-24T09:00:00.000Z',
          'grossFare': 200,
          'commissionRate': 20,
          'commissionAmount': 40,
          'netEarning': 160,
          'status': 'AVAILABLE',
          'availableAt': '2026-09-24T09:00:00.000Z',
        },
      ],
      'page': 1,
      'hasMore': false,
    });
    expect(page.summary.today.net, 160);
    expect(page.summary.available, 160);
    expect(page.summary.paid, 740);
    expect(page.items.single.status, EarningStatus.available);
    expect(page.items.single.commissionRate, 20);
    // Lines written before cash existed are online.
    expect(page.items.single.paymentMode, PaymentMode.online);
    expect(page.summary.collected, 0);
  });

  test('a cash earning is collected, with the commission due', () {
    final summary = EarningsSummary.fromJson(const {
      'balances': {
        'pending': 0,
        'available': 0,
        'paid': 0,
        'collected': 160,
        'commissionDue': 40,
      },
    });
    expect(summary.collected, 160);
    expect(summary.commissionDue, 40);
    final line = Earning.fromJson(const {
      'id': 'e2',
      'rideId': 'r2',
      'grossFare': 200,
      'commissionAmount': 40,
      'netEarning': 160,
      'status': 'COLLECTED',
      'paymentMode': 'CASH',
      'paymentMethod': 'cash',
    });
    expect(line.status, EarningStatus.collected);
    expect(line.paymentMode, PaymentMode.cash);
    expect(RideFormat.paymentMethod(line.paymentMethod), 'Cash');
    expect(RideFormat.paymentMethod('upi'), 'UPI');
  });
}
