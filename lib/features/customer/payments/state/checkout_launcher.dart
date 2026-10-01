import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../models/payment_models.dart';

/// What the checkout sheet reported. Only a hint: the server decides
/// whether the ride is paid.
sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutSucceeded extends CheckoutResult {
  const CheckoutSucceeded({
    required this.razorpayPaymentId,
    required this.razorpayOrderId,
    required this.razorpaySignature,
  });

  final String razorpayPaymentId;
  final String razorpayOrderId;
  final String razorpaySignature;
}

class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed({
    required this.message,
    this.cancelled = false,
    this.code,
    this.razorpayPaymentId,
  });

  final String message;

  /// The customer closed the sheet.
  final bool cancelled;
  final String? code;
  final String? razorpayPaymentId;
}

/// The customer chose an external wallet; the outcome arrives server-side.
class CheckoutHandedOff extends CheckoutResult {
  const CheckoutHandedOff(this.walletName);

  final String? walletName;
}

/// Opens a payment sheet. An interface so the payment flow is testable
/// without the native Razorpay SDK.
abstract interface class CheckoutLauncher {
  Future<CheckoutResult> open(CheckoutOptions options);
}

/// Razorpay Standard Checkout (native Android/iOS SDK).
class RazorpayCheckoutLauncher implements CheckoutLauncher {
  @override
  Future<CheckoutResult> open(CheckoutOptions options) {
    final razorpay = Razorpay();
    final completer = Completer<CheckoutResult>();

    void finish(CheckoutResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    razorpay
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
        final paymentId = response.paymentId;
        final signature = response.signature;
        if (paymentId == null || signature == null) {
          finish(
            const CheckoutFailed(
              message:
                  'The payment response was incomplete. Please check '
                  'your payment status before trying again.',
            ),
          );
          return;
        }
        finish(
          CheckoutSucceeded(
            razorpayPaymentId: paymentId,
            razorpayOrderId: response.orderId ?? options.orderId,
            razorpaySignature: signature,
          ),
        );
      })
      ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
        finish(_failure(response));
      })
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
        finish(CheckoutHandedOff(response.walletName));
      });

    try {
      razorpay.open(options.toRazorpayOptions());
    } catch (error) {
      finish(const CheckoutFailed(message: 'Could not open the payment page.'));
    }
    return completer.future.whenComplete(razorpay.clear);
  }

  static CheckoutFailed _failure(PaymentFailureResponse response) {
    // responseBody: { error: { code, description, metadata: { payment_id } } }
    final body = response.error;
    final error = body?['error'];
    final metadata = error is Map ? error['metadata'] : null;
    final description = error is Map ? error['description'] as String? : null;
    final cancelled = response.code == Razorpay.PAYMENT_CANCELLED;
    return CheckoutFailed(
      cancelled: cancelled,
      code: error is Map ? error['code'] as String? : null,
      razorpayPaymentId: metadata is Map
          ? metadata['payment_id'] as String?
          : null,
      message: cancelled
          ? 'You closed the payment page.'
          : response.code == Razorpay.NETWORK_ERROR
          ? 'Network problem during payment. Please check your connection.'
          : (description ?? response.message ?? 'Payment failed.'),
    );
  }
}

final checkoutLauncherProvider = Provider<CheckoutLauncher>(
  (ref) => RazorpayCheckoutLauncher(),
);
