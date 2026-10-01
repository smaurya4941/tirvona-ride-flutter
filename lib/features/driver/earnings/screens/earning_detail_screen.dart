import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../rides/domain/ride_formatters.dart';
import '../models/earning_models.dart';
import '../state/earnings_providers.dart';
import '../widgets/earning_widgets.dart';

/// One earning: gross fare − Tirvona commission = your earnings.
class EarningDetailScreen extends ConsumerWidget {
  const EarningDetailScreen({super.key, required this.earningId});

  final String earningId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningAsync = ref.watch(earningDetailProvider(earningId));
    return Scaffold(
      appBar: AppBar(title: const Text('Earning')),
      body: earningAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LoadErrorView(
          error: error,
          onRetry: () => ref.invalidate(earningDetailProvider(earningId)),
        ),
        data: (earning) => _Body(earning: earning),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.earning});

  final Earning earning;

  @override
  Widget build(BuildContext context) {
    Widget line(
      String label,
      String value, {
      bool strong = false,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                fontSize: strong ? 16 : 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              fontSize: strong ? 18 : 14,
              color: color,
            ),
          ),
        ],
      ),
    );

    final rate =
        earning.commissionRate == earning.commissionRate.roundToDouble()
        ? earning.commissionRate.round().toString()
        : earning.commissionRate.toString();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ride ${earning.rideCode}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            EarningStatusChip(status: earning.status),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          RideFormat.date(earning.rideCompletedAt),
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                line(
                  'Paid by customer',
                  earning.paymentMode == PaymentMode.cash
                      ? 'Cash (to you)'
                      : 'Online · ${RideFormat.paymentMethod(earning.paymentMethod)}',
                ),
                line('Gross fare', RideFormat.money(earning.grossFare)),
                line(
                  'Tirvona commission ($rate%)',
                  '−${RideFormat.money(earning.commissionAmount)}',
                ),
                const Divider(height: 24),
                line(
                  'Your earnings',
                  RideFormat.money(earning.netEarning),
                  strong: true,
                  color: AppColors.success,
                ),
              ],
            ),
          ),
        ),
        if (earning.adjustments.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Customer refunds',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Your share is worked out at this ride's $rate% commission.",
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  for (final adjustment in earning.adjustments)
                    AdjustmentTile(adjustment: adjustment),
                  const Divider(height: 16),
                  line(
                    'You keep',
                    RideFormat.money(earning.netEarning - earning.deducted),
                    strong: true,
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payout',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(switch (earning.status) {
                  EarningStatus.pending =>
                    'In the settlement window. Available from '
                        '${RideFormat.dateTime(earning.availableAt)}.',
                  EarningStatus.available =>
                    'Available — included in your next payout from Tirvona.',
                  EarningStatus.paid =>
                    'Paid${earning.paidAt == null ? '' : ' on ${RideFormat.date(earning.paidAt!)}'}.',
                  EarningStatus.collected =>
                    'You collected ${RideFormat.money(earning.grossFare)} in cash, so '
                        "there is nothing to pay out. Tirvona's commission of "
                        '${RideFormat.money(earning.commissionAmount)} is added to your dues.',
                }),
                if (earning.payoutReference != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    'Reference: ${earning.payoutReference}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
                if (earning.payoutNote != null)
                  Text(
                    earning.payoutNote!,
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        if (earning.destinationAddress != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.route, color: AppColors.bhagwa),
              title: Text(earning.pickupAddress ?? ''),
              subtitle: Text('→ ${earning.destinationAddress}'),
            ),
          ),
        ],
      ],
    );
  }
}
