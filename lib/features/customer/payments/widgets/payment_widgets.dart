import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../rides/application/ride_providers.dart';
import '../../../rides/domain/ride_formatters.dart';
import '../../../rides/domain/ride_models.dart';

({Color background, Color foreground}) paymentStatusColors(
  RidePaymentStatus status,
) => switch (status) {
  RidePaymentStatus.success => (
    background: const Color(0xFFDCFCE7),
    foreground: const Color(0xFF166534),
  ),
  RidePaymentStatus.failed => (
    background: const Color(0xFFFEE2E2),
    foreground: const Color(0xFF991B1B),
  ),
  RidePaymentStatus.processing => (
    background: const Color(0xFFE0E7FF),
    foreground: const Color(0xFF3730A3),
  ),
  RidePaymentStatus.pending || RidePaymentStatus.orderCreated => (
    background: const Color(0xFFFEF3C7),
    foreground: const Color(0xFF92400E),
  ),
  _ => (
    background: const Color(0xFFE2E8F0),
    foreground: const Color(0xFF334155),
  ),
};

class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip({super.key, required this.status, this.method});

  final RidePaymentStatus status;

  /// Shown for a paid ride: "Paid · Cash", "Paid · UPI".
  final String? method;

  @override
  Widget build(BuildContext context) {
    final colors = paymentStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.isPaid) ...[
            Icon(Icons.check_circle, size: 14, color: colors.foreground),
            const SizedBox(width: 4),
          ],
          Text(
            status == RidePaymentStatus.success && method != null
                ? 'Paid · ${RideFormat.paymentMethod(method)}'
                : status.label,
            style: TextStyle(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Payment block for a completed ride on the ride details screen: "Paid ✓"
/// with the payment id and a receipt link, or "Pending" with "Pay now".
class RidePaymentCard extends StatelessWidget {
  const RidePaymentCard({super.key, required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final status = ride.paymentStatus;
    final payment = ride.payment;
    final fare = ride.fare.payable;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Payment',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                PaymentStatusChip(status: status, method: payment?.method),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Fare'),
                const Spacer(),
                Text(
                  RideFormat.money(fare),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            if (status.isPaid && payment != null && payment.isCash) ...[
              const SizedBox(height: 6),
              const Text(
                'Paid in cash to your driver',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
            ],
            if (status.isPaid && payment?.gatewayPaymentId != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text(
                    'Payment ID',
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                  const Spacer(),
                  SelectableText(
                    payment!.gatewayPaymentId!,
                    style: const TextStyle(fontSize: 12, letterSpacing: 0.3),
                  ),
                ],
              ),
            ],
            if (status == RidePaymentStatus.failed &&
                payment?.failureReason != null) ...[
              const SizedBox(height: 8),
              Text(
                payment!.failureReason!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 14),
            if (status.isPaid && payment != null)
              OutlinedButton.icon(
                onPressed: () =>
                    context.push(AppRoutes.customerPayment(payment.paymentId)),
                icon: const Icon(Icons.receipt_long),
                label: const Text('View receipt'),
              )
            else if (status.isPayable)
              FilledButton.icon(
                onPressed: () =>
                    context.push(AppRoutes.customerRidePayment(ride.id)),
                icon: const Icon(Icons.payments_outlined),
                label: Text(
                  status == RidePaymentStatus.processing
                      ? 'Check payment status'
                      : 'Pay ${RideFormat.money(fare)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A completed ride the customer has not paid for yet.
class UnpaidRideCard extends ConsumerWidget {
  const UnpaidRideCard({super.key, required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Stacked, not a ListTile with a trailing button: the theme's filled
    // buttons are full-width and would squeeze the text to nothing.
    return Card(
      color: AppColors.bhagwaLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.payments_outlined,
                    color: AppColors.bhagwaDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payment pending',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.bhagwaDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ride ${ride.rideCode} to ${ride.destination.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  RideFormat.money(ride.fare.payable),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppColors.midnightBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                await context.push(AppRoutes.customerRidePayment(ride.id));
                ref.invalidate(unpaidRideProvider);
              },
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Pay now'),
            ),
          ],
        ),
      ),
    );
  }
}
