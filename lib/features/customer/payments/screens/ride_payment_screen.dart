import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../../shared/widgets/loading_filled_button.dart';
import '../../../rides/application/ride_providers.dart';
import '../../../rides/data/ride_repository.dart';
import '../../../rides/domain/ride_formatters.dart';
import '../../../rides/domain/ride_models.dart';
import '../../../rides/presentation/widgets/ride_widgets.dart';
import '../state/ride_payment_controller.dart';

/// The ride being paid for, as the server sees it (final fare included).
final _payableRideProvider = FutureProvider.autoDispose.family<Ride, String>(
  (ref, rideId) => ref.watch(rideRepositoryProvider).getRide(rideId),
);

/// Ride Completed → Payment: the final, server-calculated fare, "Pay"
/// online or "Pay in cash", then success / failure / confirming states.
class RidePaymentScreen extends ConsumerWidget {
  const RidePaymentScreen({super.key, required this.rideId});

  final String rideId;

  void _finish(BuildContext context, WidgetRef ref) {
    ref
      ..invalidate(rideProvider(rideId))
      ..invalidate(activeRideProvider);
    context.go(AppRoutes.customerHome);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(ridePaymentControllerProvider(rideId), (previous, next) {
      if (previous?.phase != next.phase &&
          (next.phase == PaymentPhase.succeeded ||
              next.phase == PaymentPhase.failed)) {
        HapticFeedback.mediumImpact();
        ref.invalidate(rideProvider(rideId));
      }
    });

    final rideAsync = ref.watch(_payableRideProvider(rideId));
    final payment = ref.watch(ridePaymentControllerProvider(rideId));
    final ride = rideAsync.value;

    final Widget body;
    if (ride == null) {
      body = rideAsync.hasError
          ? LoadErrorView(
              error: rideAsync.error!,
              onRetry: () => ref.invalidate(_payableRideProvider(rideId)),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (payment.phase == PaymentPhase.succeeded ||
        (payment.phase == PaymentPhase.idle && ride.paymentStatus.isPaid)) {
      body = _SuccessView(
        ride: ride,
        amount:
            payment.payment?.amount ??
            ride.payment?.amount ??
            ride.fare.payable,
        paymentId: payment.payment?.id ?? ride.payment?.paymentId,
        cash: payment.payment?.isCash ?? ride.payment?.isCash ?? false,
        gatewayPaymentId:
            payment.payment?.razorpayPaymentId ??
            ride.payment?.gatewayPaymentId,
        onDone: () => _finish(context, ref),
        // Payment Success → Rating (optional: "Done" skips it).
        onRate: () {
          ref
            ..invalidate(rideProvider(rideId))
            ..invalidate(activeRideProvider);
          context.pushReplacement(AppRoutes.customerRideRating(rideId));
        },
      );
    } else if (payment.phase == PaymentPhase.verifying ||
        payment.phase == PaymentPhase.confirming) {
      body = _ConfirmingView(
        message: payment.phase == PaymentPhase.verifying
            ? 'Verifying your payment…'
            : payment.message ?? 'Confirming your payment…',
        onRefresh: payment.phase == PaymentPhase.confirming
            ? ref.read(ridePaymentControllerProvider(rideId).notifier).refresh
            : null,
      );
    } else if (ride.status != RideStatus.completed) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Payment opens once your ride is completed.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = _PayView(ride: ride, state: payment, rideId: rideId);
    }

    return PopScope(
      // Don't let a back gesture interrupt verification.
      canPop: !payment.busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ride == null ? 'Payment' : 'Pay for ${ride.rideCode}'),
          automaticallyImplyLeading: !payment.busy,
        ),
        body: SafeArea(child: body),
      ),
    );
  }
}

class _PayView extends ConsumerWidget {
  const _PayView({
    required this.ride,
    required this.state,
    required this.rideId,
  });

  final Ride ride;
  final RidePaymentState state;
  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fare = ride.fare.payable;
    final failed = state.phase == PaymentPhase.failed;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 22,
              backgroundColor: Color(0xFFDCFCE7),
              child: Icon(Icons.check, color: AppColors.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ride completed',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  Text(
                    ride.completedAt == null
                        ? ride.rideCode
                        : '${ride.rideCode} · ${RideFormat.dateTime(ride.completedAt!)}',
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              const Text(
                'Trip fare',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                RideFormat.money(fare),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.midnightBlue,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (failed) ...[
          _FailureBanner(state: state),
          const SizedBox(height: 16),
        ],
        // Only the components the pricing engine actually charges — no
        // invented taxes or fees.
        FareBreakdownCard(
          title: 'Fare breakdown',
          fare: ride.fare,
          distanceMeters: ride.distanceMeters,
          durationSeconds: ride.durationSeconds,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: RouteSummary(
              pickup: ride.pickup,
              destination: ride.destination,
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: LoadingFilledButton(
            label: failed
                ? 'Try again · ${RideFormat.money(fare)}'
                : 'Pay ${RideFormat.money(fare)}',
            icon: failed ? Icons.refresh : Icons.lock_outline,
            isLoading: state.busy && !state.cash,
            onPressed: state.busy
                ? null
                : () => ref
                      .read(ridePaymentControllerProvider(rideId).notifier)
                      .pay(),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 14,
              color: AppColors.onSurfaceVariant,
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Secured by Razorpay · UPI, cards, net banking, wallets',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _OrDivider(),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: state.busy ? null : () => _confirmCash(context, ref),
            icon: state.busy && state.cash
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payments_outlined),
            label: Text('Pay ${RideFormat.money(fare)} in cash'),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Hand the cash to ${_driverName(ride)} at drop-off.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Cash cannot be undone (the ride can no longer be paid online), so ask.
  Future<void> _confirmCash(BuildContext context, WidgetRef ref) async {
    final fare = RideFormat.money(ride.fare.payable);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.payments_outlined),
        title: const Text('Pay in cash?'),
        content: Text(
          'Please hand $fare in cash to ${_driverName(ride)}. The ride will '
          'be marked as paid in cash, so it cannot be paid online afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, pay cash'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(ridePaymentControllerProvider(rideId).notifier).payCash();
    }
  }
}

/// "Rahul" from "Rahul Driver"; "your driver" when unknown.
String _driverName(Ride ride) {
  final name = ride.driver?.name.trim() ?? '';
  return name.isEmpty ? 'your driver' : name.split(' ').first;
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ),
        Expanded(child: Divider()),
      ],
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.state});

  final RidePaymentState state;

  @override
  Widget build(BuildContext context) {
    final color = state.cancelled ? AppColors.warning : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            state.cancelled ? Icons.info_outline : Icons.error_outline,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.cancelled ? 'Payment not completed' : 'Payment failed',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(state.message ?? 'Your payment could not be completed.'),
                const SizedBox(height: 4),
                const Text(
                  'You have not been charged for this attempt. Try again when ready.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmingView extends StatelessWidget {
  const _ConfirmingView({required this.message, this.onRefresh});

  final String message;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 56,
              child: CircularProgressIndicator(strokeWidth: 4),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please keep the app open. Do not pay again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
            if (onRefresh != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.ride,
    required this.amount,
    required this.paymentId,
    required this.gatewayPaymentId,
    required this.cash,
    required this.onDone,
    required this.onRate,
  });

  final Ride ride;
  final double amount;
  final String? paymentId;
  final String? gatewayPaymentId;

  /// Settled as "pay cash": the money still has to change hands.
  final bool cash;
  final VoidCallback onDone;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        Center(
          child: CircleAvatar(
            radius: 44,
            backgroundColor: const Color(0xFFDCFCE7),
            child: Icon(
              cash ? Icons.payments_rounded : Icons.check_rounded,
              size: cash ? 48 : 56,
              color: AppColors.success,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          cash ? 'Paying in cash' : 'Payment successful',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          RideFormat.money(amount),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.midnightBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          cash
              ? 'Please hand this to ${_driverName(ride)} · Ride ${ride.rideCode}'
              : 'Ride ${ride.rideCode}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
        if (!cash && gatewayPaymentId != null) ...[
          const SizedBox(height: 4),
          SelectableText(
            gatewayPaymentId!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 40),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: onRate,
          icon: const Icon(Icons.star_rounded),
          label: Text(
            'Rate ${ride.driver?.name.split(' ').first ?? 'your driver'}',
          ),
        ),
        const SizedBox(height: 12),
        if (paymentId != null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () =>
                context.push(AppRoutes.customerPayment(paymentId!)),
            icon: const Icon(Icons.receipt_long),
            label: const Text('View receipt'),
          ),
        const SizedBox(height: 4),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: onDone,
          child: const Text('Done'),
        ),
      ],
    );
  }
}
