import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../branding/presentation/brand_logo.dart';
import '../../../rides/domain/ride_formatters.dart';
import '../../../rides/presentation/widgets/ride_widgets.dart';
import '../models/payment_models.dart';
import '../repository/payment_repository.dart';

final paymentReceiptProvider = FutureProvider.autoDispose
    .family<PaymentReceipt, String>(
      (ref, paymentId) =>
          ref.watch(paymentRepositoryProvider).receipt(paymentId),
    );

/// In-app receipt (V1 has no PDF): ride, people, route, fare, payment.
class PaymentReceiptScreen extends ConsumerWidget {
  const PaymentReceiptScreen({super.key, required this.paymentId});

  final String paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptAsync = ref.watch(paymentReceiptProvider(paymentId));
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: receiptAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LoadErrorView(
          error: error,
          onRetry: () => ref.invalidate(paymentReceiptProvider(paymentId)),
        ),
        data: (receipt) => RefreshIndicator(
          onRefresh: () =>
              ref.refresh(paymentReceiptProvider(paymentId).future),
          child: _ReceiptBody(receipt: receipt),
        ),
      ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.receipt});

  final PaymentReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final payment = receipt.payment;
    final vehicle = receipt.vehicle;
    final fare = receipt.fare;
    final date = payment.paidAt ?? receipt.completedAt ?? payment.createdAt;

    Widget line(
      String label,
      String value, {
      bool strong = false,
      bool copy = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: copy
                ? GestureDetector(
                    onLongPress: () =>
                        Clipboard.setData(ClipboardData(text: value)),
                    child: SelectableText(value, textAlign: TextAlign.right),
                  )
                : Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                      fontSize: strong ? 18 : 14,
                    ),
                  ),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const BrandLogo(height: 72),
                const SizedBox(height: 8),
                Text(
                  RideFormat.money(payment.amount),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.midnightBlue,
                  ),
                ),
                const SizedBox(height: 6),
                _StatusPill(status: payment.status),
                const Divider(height: 28),
                line('Ride ID', receipt.rideCode),
                if (payment.razorpayPaymentId != null)
                  line('Payment ID', payment.razorpayPaymentId!, copy: true),
                line(
                  'Date',
                  '${RideFormat.date(date)}, ${RideFormat.time(date)}',
                ),
                line('Customer', receipt.customerName),
                if (receipt.driverName != null)
                  line('Driver', receipt.driverName!),
                if (vehicle != null)
                  line(
                    'Vehicle',
                    [
                      vehicle.registrationNumber,
                      vehicle.description,
                    ].where((part) => part.isNotEmpty).join(' · '),
                  ),
                line('Payment method', payment.methodLabel),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: RouteSummary(
              pickup: receipt.pickup,
              destination: receipt.destination,
            ),
          ),
        ),
        const SizedBox(height: 12),
        FareBreakdownCard(
          title: 'Fare',
          fare: fare,
          distanceMeters: receipt.distanceMeters,
          durationSeconds: receipt.durationSeconds,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Discounts arrive with promo codes; none exist in V1.
                line(
                  'Final amount',
                  RideFormat.money(payment.amount),
                  strong: true,
                ),
                if (payment.hasRefund) ...[
                  if ((payment.refundAmount ?? 0) > 0)
                    line('Refunded', '− ${RideFormat.money(payment.refundAmount!)}'),
                  if (payment.refundPending > 0)
                    line('Refund processing', RideFormat.money(payment.refundPending)),
                  line(
                    'Net paid',
                    RideFormat.money(
                      payment.amount - (payment.refundAmount ?? 0),
                    ),
                    strong: true,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (receipt.refunds.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RefundsCard(refunds: receipt.refunds, method: payment.methodLabel),
        ],
      ],
    );
  }
}

/// Each refund with where it stands and the bank reference to quote.
class _RefundsCard extends StatelessWidget {
  const _RefundsCard({required this.refunds, required this.method});

  final List<CustomerRefund> refunds;
  final String method;

  @override
  Widget build(BuildContext context) {
    final processing = refunds.any(
      (refund) => refund.state == RefundState.processing,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Refunds', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              processing
                  ? 'Refunds go back to $method. Banks usually show them '
                        'within 5–7 working days after processing.'
                  : 'Refunded to $method.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            for (final refund in refunds) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    refund.state == RefundState.refunded
                        ? Icons.check_circle
                        : Icons.schedule,
                    size: 20,
                    color: refund.state == RefundState.refunded
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          refund.reason,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          refund.state == RefundState.refunded &&
                                  refund.processedAt != null
                              ? 'Refunded ${RideFormat.date(refund.processedAt!)}'
                              : 'Started ${RideFormat.date(refund.createdAt)} · processing',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        if (refund.reference != null)
                          GestureDetector(
                            onLongPress: () => Clipboard.setData(
                              ClipboardData(text: refund.reference!),
                            ),
                            child: Text(
                              'Bank reference ${refund.reference}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    RideFormat.money(refund.amount),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final paid = status.isPaid;
    final color = status == PaymentStatus.refunded ||
            status == PaymentStatus.partiallyRefunded
        ? AppColors.midnightBlue
        : paid
        ? AppColors.success
        : status == PaymentStatus.failed
        ? AppColors.error
        : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            paid ? Icons.check_circle : Icons.schedule,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
