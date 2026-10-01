import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../rides/domain/ride_formatters.dart';
import '../models/payment_models.dart';
import '../repository/payment_repository.dart';
import '../widgets/payment_widgets.dart';

/// Customer "Payments" tab: every payment, newest first, paginated.
class PaymentHistoryTab extends ConsumerStatefulWidget {
  const PaymentHistoryTab({super.key});

  @override
  ConsumerState<PaymentHistoryTab> createState() => _PaymentHistoryTabState();
}

class _PaymentHistoryTabState extends ConsumerState<PaymentHistoryTab> {
  static const _pageSize = 20;

  final _payments = <PaymentRecord>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _refresh() async {
    setState(() {
      _payments.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(paymentRepositoryProvider)
          .history(page: _page + 1, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _payments.addAll(page.items);
        _page = page.page;
        _hasMore = page.hasMore;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_payments.isEmpty) {
      if (_error != null) {
        return LoadErrorView(error: _error!, onRetry: _refresh);
      }
      if (_loading) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Icon(
              Icons.payments_outlined,
              size: 48,
              color: AppColors.onSurfaceVariant,
            ),
            SizedBox(height: 12),
            Text('No payments yet.', textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 300) _loadMore();
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _payments.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == _payments.length) {
              if (_error != null) {
                return TextButton(
                  onPressed: _loadMore,
                  child: const Text('Could not load more — tap to retry'),
                );
              }
              return _hasMore
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox(height: 24);
            }
            final payment = _payments[index];
            return _PaymentTile(
              payment: payment,
              onTap: () async {
                final route = payment.ridePaymentStatus.isPayable
                    ? AppRoutes.customerRidePayment(payment.rideId)
                    : AppRoutes.customerPayment(payment.id);
                await context.push(route);
                if (mounted) await _refresh();
              },
            );
          },
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment, required this.onTap});

  final PaymentRecord payment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = payment.paidAt ?? payment.createdAt;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    '${date.day}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    RideFormat.date(date).split(' ')[1],
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ride ${payment.rideCode}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (payment.destinationAddress != null)
                      Text(
                        '→ ${payment.destinationAddress}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 6),
                    PaymentStatusChip(status: payment.ridePaymentStatus),
                  ],
                ),
              ),
              Text(
                RideFormat.money(payment.amount),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
