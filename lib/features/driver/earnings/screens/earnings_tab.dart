import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../rides/domain/ride_formatters.dart';
import '../../../rides/presentation/widgets/ride_widgets.dart';
import '../models/earning_models.dart';
import '../repository/earnings_repository.dart';
import '../state/earnings_providers.dart';
import '../widgets/earning_widgets.dart';

/// Driver Earnings: today / week / total, payout balances, and the ledger.
class EarningsTab extends ConsumerStatefulWidget {
  const EarningsTab({super.key});

  @override
  ConsumerState<EarningsTab> createState() => _EarningsTabState();
}

class _EarningsTabState extends ConsumerState<EarningsTab> {
  // Pages after the first, for the selected period.
  final _more = <Earning>[];
  int _page = 1;
  bool? _hasMore;
  bool _loadingMore = false;

  void _resetPaging() {
    _more.clear();
    _page = 1;
    _hasMore = null;
  }

  Future<void> _refresh(EarningsPeriod period) async {
    setState(_resetPaging);
    ref.invalidate(earningsFirstPageProvider(period));
    await ref.read(earningsFirstPageProvider(period).future);
  }

  Future<void> _loadMore(EarningsPeriod period) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await ref
          .read(earningsRepositoryProvider)
          .list(period: period, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _more.addAll(next.items);
        _page = next.page;
        _hasMore = next.hasMore;
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(earningsPeriodProvider);
    final pageAsync = ref.watch(earningsFirstPageProvider(period));
    final first = pageAsync.value;

    if (first == null) {
      return pageAsync.hasError
          ? LoadErrorView(
              error: pageAsync.error!,
              onRetry: () => ref.invalidate(earningsFirstPageProvider(period)),
            )
          : const Center(child: CircularProgressIndicator());
    }

    final summary = first.summary;
    final items = [...first.items, ..._more];
    final hasMore = _hasMore ?? first.hasMore;

    return RefreshIndicator(
      onRefresh: () => _refresh(period),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: AppColors.midnightBlue,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EarningsFigure(
                    amount: summary.today.net,
                    label: "Today's earnings · ${summary.today.rides} rides",
                    large: true,
                    inverse: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: EarningsFigure(
                          amount: summary.week.net,
                          label: 'This week',
                          inverse: true,
                        ),
                      ),
                      Expanded(
                        child: EarningsFigure(
                          amount: summary.total.net,
                          label: 'Total earnings',
                          inverse: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Row(
                children: [
                  _Balance(
                    label: 'Available',
                    amount: summary.available,
                    color: const Color(0xFF075985),
                  ),
                  _Balance(
                    label: 'Pending',
                    amount: summary.pending,
                    color: const Color(0xFF92400E),
                  ),
                  _Balance(
                    label: 'Paid',
                    amount: summary.paid,
                    color: const Color(0xFF166534),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Available earnings are paid out by Tirvona to your bank '
              'account; paid ones show the transfer reference.',
              style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ),
          if (summary.deductions > 0 || first.adjustments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.undo_rounded, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Refund deductions',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (summary.deductions > 0)
                          Text(
                            '−${RideFormat.money(summary.deductions)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF92400E),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.deductions > 0
                          ? 'When a customer is refunded, your share of the '
                                'refund comes off your next payout.'
                          : 'Past deductions for customer refunds.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    for (final adjustment in first.adjustments.take(5))
                      AdjustmentTile(
                        adjustment: adjustment,
                        onTap: () => context.push(
                          AppRoutes.driverEarning(adjustment.earningId),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (summary.collected > 0 || summary.commissionDue > 0) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 8,
                ),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 12),
                      child: Row(
                        children: [
                          Icon(Icons.payments_outlined, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Cash rides',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        _Balance(
                          label: 'Your share (in hand)',
                          amount: summary.collected,
                          color: AppColors.success,
                        ),
                        _Balance(
                          label: 'Commission due',
                          amount: summary.commissionDue,
                          color: AppColors.bhagwaDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                "Cash fares stay with you and are never paid out. Tirvona's "
                'commission on them is owed to Tirvona.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in EarningsPeriod.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(option.label),
                      selected: option == period,
                      onSelected: (_) {
                        setState(_resetPaging);
                        ref
                            .read(earningsPeriodProvider.notifier)
                            .select(option);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${period.label} · ${first.periodTotals.rides} rides',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                RideFormat.money(first.periodTotals.net),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 44,
                    color: AppColors.onSurfaceVariant,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No earnings in this period yet. Earnings appear once '
                    'the customer has paid for a ride.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            for (final earning in items) ...[
              EarningTile(
                earning: earning,
                onTap: () => context.push(AppRoutes.driverEarning(earning.id)),
              ),
              const SizedBox(height: 10),
            ],
          if (hasMore)
            Center(
              child: _loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    )
                  : TextButton(
                      onPressed: () => _loadMore(period),
                      child: const Text('Load more'),
                    ),
            ),
        ],
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            RideFormat.money(amount),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
