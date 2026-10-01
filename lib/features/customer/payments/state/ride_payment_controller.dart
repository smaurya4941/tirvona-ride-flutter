import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../rides/application/ride_providers.dart';
import '../models/payment_models.dart';
import '../repository/payment_repository.dart';
import 'checkout_launcher.dart';

enum PaymentPhase {
  /// Nothing started; show the fare and "Pay".
  idle,

  /// Asking the server for a checkout (order).
  preparing,

  /// The Razorpay sheet is open.
  inCheckout,

  /// The sheet reported success; the server is verifying it.
  verifying,

  /// Razorpay may have the money but the server has not confirmed it yet.
  confirming,
  succeeded,
  failed,
}

class RidePaymentState {
  const RidePaymentState({
    this.phase = PaymentPhase.idle,
    this.payment,
    this.message,
    this.cancelled = false,
    this.cash = false,
  });

  final PaymentPhase phase;
  final PaymentRecord? payment;

  /// The attempt in progress is "pay cash" (which button shows a spinner).
  final bool cash;

  /// Failure or progress text for the user.
  final String? message;

  /// The customer closed the sheet (softer copy than a decline).
  final bool cancelled;

  bool get busy =>
      phase == PaymentPhase.preparing ||
      phase == PaymentPhase.inCheckout ||
      phase == PaymentPhase.verifying;
}

/// Customer payment for one completed ride — either
/// create (server prices it) → Razorpay checkout → server verification, or
/// "pay cash", which the server settles at once.
///
/// The ride only counts as paid when the server says so — after /verify,
/// a `ride.payment_updated` push, or a receipt read that finds it CAPTURED.
class RidePaymentController extends Notifier<RidePaymentState> {
  RidePaymentController(this.rideId);

  final String rideId;

  static const _pollInterval = Duration(seconds: 3);
  static const _maxPolls = 20;
  Timer? _poll;
  int _polls = 0;

  PaymentRepository get _repository => ref.read(paymentRepositoryProvider);

  @override
  RidePaymentState build() {
    ref.onDispose(() => _poll?.cancel());
    // The webhook may settle the payment while we wait (or while the app
    // was in the background during a UPI hand-off).
    ref.listen(ridePaymentUpdatesProvider(rideId), (_, next) {
      final ride = next.value;
      if (ride == null) return;
      if (ride.paymentStatus.isPaid && state.phase != PaymentPhase.succeeded) {
        final paymentId = ride.payment?.paymentId;
        if (paymentId != null) unawaited(_loadSettled(paymentId));
      }
    });
    return const RidePaymentState();
  }

  Future<void> pay() async {
    if (state.busy) return;
    _stopPolling();
    state = RidePaymentState(
      phase: PaymentPhase.preparing,
      payment: state.payment,
    );

    final PaymentCheckout checkout;
    try {
      checkout = await _repository.create(rideId);
    } on ApiException catch (error) {
      final paymentId = _paymentIdOf(error);
      if (error.code == 'PAYMENT_ALREADY_COMPLETED' && paymentId != null) {
        await _loadSettled(paymentId);
        return;
      }
      if (error.code == 'PAYMENT_IN_PROGRESS' && paymentId != null) {
        _confirm(paymentId);
        return;
      }
      state = RidePaymentState(
        phase: PaymentPhase.failed,
        message: error.message,
        payment: state.payment,
      );
      return;
    }

    state = RidePaymentState(
      phase: PaymentPhase.inCheckout,
      payment: checkout.payment,
    );
    final result = await ref
        .read(checkoutLauncherProvider)
        .open(checkout.options);
    if (!ref.mounted) return;

    switch (result) {
      case CheckoutSucceeded():
        await _verify(checkout.payment, result);
      case CheckoutFailed():
        unawaited(
          _repository
              .reportFailure(
                checkout.payment.id,
                razorpayOrderId: checkout.options.orderId,
                razorpayPaymentId: result.razorpayPaymentId,
                code: result.code,
                description: result.message,
                cancelled: result.cancelled,
              )
              .then<void>((_) {}, onError: (_) {}),
        );
        state = RidePaymentState(
          phase: PaymentPhase.failed,
          payment: checkout.payment,
          message: result.message,
          cancelled: result.cancelled,
        );
      case CheckoutHandedOff():
        _confirm(checkout.payment.id);
    }
  }

  Future<void> payCash() async {
    if (state.busy) return;
    _stopPolling();
    state = RidePaymentState(
      phase: PaymentPhase.preparing,
      payment: state.payment,
      cash: true,
    );
    try {
      final payment = await _repository.payCash(rideId);
      if (!ref.mounted) return;
      state = RidePaymentState(phase: PaymentPhase.succeeded, payment: payment);
    } on ApiException catch (error) {
      if (!ref.mounted) return;
      final paymentId = _paymentIdOf(error);
      if (error.code == 'PAYMENT_ALREADY_COMPLETED' && paymentId != null) {
        await _loadSettled(paymentId);
      } else if (error.code == 'PAYMENT_IN_PROGRESS' && paymentId != null) {
        // An online payment is still being confirmed: follow that instead.
        _confirm(paymentId);
      } else {
        state = RidePaymentState(
          phase: PaymentPhase.failed,
          payment: state.payment,
          message: error.message,
        );
      }
    }
  }

  Future<void> _verify(PaymentRecord payment, CheckoutSucceeded result) async {
    state = RidePaymentState(phase: PaymentPhase.verifying, payment: payment);
    try {
      final verified = await _repository.verify(
        paymentId: payment.id,
        razorpayOrderId: result.razorpayOrderId,
        razorpayPaymentId: result.razorpayPaymentId,
        razorpaySignature: result.razorpaySignature,
      );
      if (!ref.mounted) return;
      if (verified.status.isPaid) {
        state = RidePaymentState(
          phase: PaymentPhase.succeeded,
          payment: verified,
        );
      } else if (verified.status == PaymentStatus.failed) {
        state = RidePaymentState(
          phase: PaymentPhase.failed,
          payment: verified,
          message:
              verified.failureReason ?? 'Your payment could not be completed.',
        );
      } else {
        _confirm(payment.id);
      }
    } on ApiException catch (error) {
      if (!ref.mounted) return;
      if (error.code == 'PAYMENT_ALREADY_COMPLETED') {
        await _loadSettled(_paymentIdOf(error) ?? payment.id);
      } else if (error.kind == ApiErrorKind.network ||
          error.kind == ApiErrorKind.timeout ||
          error.kind == ApiErrorKind.server) {
        // Money may have moved even though we could not hear back: never
        // show "failed" here — keep checking with the server.
        _confirm(payment.id);
      } else {
        state = RidePaymentState(
          phase: PaymentPhase.failed,
          payment: payment,
          message: error.message,
        );
      }
    }
  }

  /// Waits for the server to settle the payment (poll + realtime push).
  void _confirm(String paymentId) {
    state = RidePaymentState(
      phase: PaymentPhase.confirming,
      payment: state.payment,
      message: 'Confirming your payment with the bank…',
    );
    _polls = 0;
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => unawaited(_check(paymentId)));
    unawaited(_check(paymentId));
  }

  Future<void> _check(String paymentId) async {
    _polls += 1;
    try {
      final receipt = await _repository.receipt(paymentId);
      if (!ref.mounted) return;
      final payment = receipt.payment;
      if (payment.status.isPaid) {
        _stopPolling();
        state = RidePaymentState(
          phase: PaymentPhase.succeeded,
          payment: payment,
        );
        return;
      }
      if (payment.status == PaymentStatus.failed) {
        _stopPolling();
        state = RidePaymentState(
          phase: PaymentPhase.failed,
          payment: payment,
          message:
              payment.failureReason ?? 'Your payment could not be completed.',
        );
        return;
      }
    } catch (_) {
      // Keep trying until the budget runs out.
    }
    if (_polls >= _maxPolls && ref.mounted) {
      _stopPolling();
      state = RidePaymentState(
        phase: PaymentPhase.confirming,
        payment: state.payment,
        message:
            'Still confirming. If money left your account it will be '
            'matched to this ride automatically — check back shortly.',
      );
    }
  }

  Future<void> _loadSettled(String paymentId) async {
    _stopPolling();
    try {
      final receipt = await _repository.receipt(paymentId);
      if (!ref.mounted) return;
      state = RidePaymentState(
        phase: receipt.payment.status.isPaid
            ? PaymentPhase.succeeded
            : PaymentPhase.confirming,
        payment: receipt.payment,
      );
    } catch (_) {
      if (ref.mounted) {
        state = const RidePaymentState(phase: PaymentPhase.succeeded);
      }
    }
  }

  /// Re-check now (pull to refresh while confirming).
  void refresh() {
    final paymentId = state.payment?.id;
    if (paymentId != null) _confirm(paymentId);
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  static String? _paymentIdOf(ApiException error) {
    final data = error.data;
    return data is Map<String, dynamic> ? data['paymentId'] as String? : null;
  }
}

final ridePaymentControllerProvider = NotifierProvider.autoDispose
    .family<RidePaymentController, RidePaymentState, String>(
      RidePaymentController.new,
    );
