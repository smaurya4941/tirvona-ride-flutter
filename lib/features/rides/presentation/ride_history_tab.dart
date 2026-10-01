import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../customer/payments/widgets/payment_widgets.dart';
import '../data/ride_repository.dart';
import '../domain/ride_formatters.dart';
import '../domain/ride_history_filter.dart';
import '../domain/ride_models.dart';
import 'widgets/ride_widgets.dart';

/// Paginated ride history for customers and drivers (`GET /rides` returns
/// the right set for the caller's role), filtered by date. Pages load as the
/// list nears its end. [rideRoute] maps a ride to the screen that shows it.
class RideHistoryTab extends ConsumerStatefulWidget {
  const RideHistoryTab({super.key, required this.rideRoute});

  final String Function(String rideId) rideRoute;

  @override
  ConsumerState<RideHistoryTab> createState() => _RideHistoryTabState();
}

class _RideHistoryTabState extends ConsumerState<RideHistoryTab> {
  static const _pageSize = 10;

  /// Load the next page once fewer than this many pixels are left below.
  static const _loadAheadPx = 300.0;

  final _scroll = ScrollController();
  final _rides = <Ride>[];
  RideHistoryFilter _filter = RideHistoryFilter.all;
  int _page = 0;
  int _total = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  /// Bumped whenever the list restarts (filter change, refresh), so a page
  /// still in flight for the old filter is dropped instead of appended.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < _loadAheadPx) {
      _loadMore();
    }
  }

  Future<void> _refresh() {
    setState(() {
      _generation++;
      _rides.clear();
      _page = 0;
      _total = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    return _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    final window = _filter.window(DateTime.now());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(rideRepositoryProvider)
          .history(
            page: _page + 1,
            limit: _pageSize,
            startDate: window.start,
            endDate: window.end,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        // A ride requested between two page loads shifts the server's
        // offsets by one; skip anything already shown.
        final seen = {for (final ride in _rides) ride.id};
        _rides.addAll(page.items.where((ride) => !seen.contains(ride.id)));
        _page = page.page;
        _total = page.total;
        _hasMore = page.hasMore;
      });
      // A short first page may not fill the screen, so no scroll event
      // would ever ask for the next one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) _onScroll();
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectPeriod(RideHistoryPeriod period) async {
    RideHistoryFilter next;
    if (period == RideHistoryPeriod.custom) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: today,
        initialDateRange: _filter.period == RideHistoryPeriod.custom
            ? DateTimeRange(start: _filter.customFrom!, end: _filter.customTo!)
            : DateTimeRange(
                start: DateTime(today.year, today.month, today.day - 6),
                end: today,
              ),
        helpText: 'Show rides between',
        saveText: 'Apply',
      );
      // Cancelled: the picker keeps showing the current filter.
      if (range == null || !mounted) return;
      next = RideHistoryFilter.custom(from: range.start, to: range.end);
    } else {
      next = RideHistoryFilter(period);
    }
    if (next == _filter) return;
    _filter = next;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FilterBar(
          filter: _filter,
          total: _page == 0 ? null : _total,
          shown: _rides.length,
          onSelected: _selectPeriod,
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_rides.isEmpty) {
      if (_error != null) {
        return LoadErrorView(error: _error!, onRetry: _refresh);
      }
      if (_loading || _hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            const Icon(
              Icons.history,
              size: 48,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(_filter.emptyMessage, textAlign: TextAlign.center),
            if (_filter.period != RideHistoryPeriod.all) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => _selectPeriod(RideHistoryPeriod.all),
                  child: const Text('Show all rides'),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _rides.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _rides.length) return _buildFooter();
          final ride = _rides[index];
          return _HistoryCard(
            ride: ride,
            onTap: () async {
              await context.push(widget.rideRoute(ride.id));
              if (mounted && ride.status.isActive) await _refresh();
            },
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_error != null) {
      return TextButton(
        onPressed: _loadMore,
        child: const Text('Could not load more — tap to retry'),
      );
    }
    if (_hasMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Text(
        "That's all your rides for this period",
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
      ),
    );
  }
}

/// "Filter by" picker plus how many of the matching rides are loaded.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.total,
    required this.shown,
    required this.onSelected,
  });

  final RideHistoryFilter filter;

  /// Null until the first page of this filter has arrived.
  final int? total;
  final int shown;
  final ValueChanged<RideHistoryPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final total = this.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Filter by:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(),
                  ),
                  // A plain DropdownButton shows exactly [filter.period];
                  // a cancelled date picker therefore leaves it unchanged.
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<RideHistoryPeriod>(
                      key: const ValueKey('ride-history-filter'),
                      value: filter.period,
                      isExpanded: true,
                      items: [
                        for (final period in RideHistoryPeriod.values)
                          DropdownMenuItem(
                            value: period,
                            child: Text(period.label),
                          ),
                      ],
                      selectedItemBuilder: (context) => [
                        for (final period in RideHistoryPeriod.values)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              period == filter.period
                                  ? filter.label
                                  : period.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (period) {
                        if (period != null) onSelected(period);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (total != null && total > 0) ...[
            const SizedBox(height: 8),
            Text(
              shown < total
                  ? 'Showing $shown of $total rides'
                  : total == 1
                  ? '1 ride'
                  : '$total rides',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.ride, required this.onTap});

  final Ride ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(rideTypeIcon(ride.rideType), color: AppColors.bhagwa),
                  const SizedBox(width: 8),
                  Text(
                    RideFormat.dateTime(ride.requestedAt),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  RideStatusChip(status: ride.status),
                ],
              ),
              const SizedBox(height: 12),
              RouteSummary(
                pickup: ride.pickup,
                destination: ride.destination,
                dense: true,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    ride.rideCode,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (ride.status == RideStatus.completed) ...[
                    PaymentStatusChip(
                      status: ride.paymentStatus,
                      method: ride.payment?.method,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (ride.status != RideStatus.noDriverAvailable)
                    Text(
                      RideFormat.money(ride.fare.payable),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
