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

const _ink = AppColors.midnightBlue;
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);

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
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          _FilterBar(
            filter: _filter,
            total: _page == 0 ? null : _total,
            shown: _rides.length,
            onSelected: _selectPeriod,
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_rides.isEmpty) {
      if (_error != null) {
        return LoadErrorView(error: _error!, onRetry: _refresh);
      }
      if (_loading || _hasMore) {
        return const Center(
          child: CircularProgressIndicator(color: AppColors.bhagwa),
        );
      }
      return RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.bhagwa,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          children: [
            const SizedBox(height: 56),
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.bhagwaLight.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.bhagwa.withValues(alpha: 0.25),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.route_rounded,
                  size: 40,
                  color: AppColors.bhagwaDark,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _filter.emptyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Your past trips, fare receipts, and ride summaries will be catalogued here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _muted,
                  height: 1.4,
                ),
              ),
            ),
            if (_filter.period != RideHistoryPeriod.all) ...[
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () => _selectPeriod(RideHistoryPeriod.all),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Show all rides'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.bhagwa,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _rides.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton.icon(
            onPressed: _loadMore,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Could not load more — tap to retry'),
            style: TextButton.styleFrom(foregroundColor: AppColors.bhagwa),
          ),
        ),
      );
    }
    if (_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.bhagwa,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _line),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 14,
                color: _muted,
              ),
              SizedBox(width: 6),
              Text(
                "That's all your rides for this period",
                style: TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.bhagwaLight,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.bhagwa.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: AppColors.bhagwa,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Filter by:',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<RideHistoryPeriod>(
                        key: const ValueKey('ride-history-filter'),
                        value: filter.period,
                        isExpanded: true,
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _ink,
                          size: 20,
                        ),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
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
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.bhagwa,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      shown < total
                          ? 'Showing $shown of $total rides'
                          : total == 1
                              ? '1 ride'
                              : '$total rides',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

(Color bg, Color fg) _vehicleBadgeColors(RideTypeCode type) {
  final code = type.wireName;
  if (code.contains('BIKE')) {
    return (const Color(0xFFFFFBEB), const Color(0xFFD97706));
  }
  if (code.contains('AUTO') || code.contains('RICKSHAW')) {
    return (const Color(0xFFECFDF5), const Color(0xFF059669));
  }
  if (code.contains('PREMIUM') || code.contains('XL')) {
    return (const Color(0xFFFAF5FF), const Color(0xFF7C3AED));
  }
  return (const Color(0xFFEFF6FF), const Color(0xFF2563EB));
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.ride, required this.onTap});

  final Ride ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (vehicleBg, vehicleFg) = _vehicleBadgeColors(ride.rideType);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Vehicle Icon Badge + Ride Type & Date + Status Chip
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: vehicleBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: vehicleFg.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(
                        rideTypeIcon(ride.rideType),
                        color: vehicleFg,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            // A circuit is known by its package.
                            ride.circuit == null
                                ? ride.rideType.label
                                : '${ride.circuit!.name} · ${ride.rideType.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            RideFormat.dateTime(ride.requestedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    RideStatusChip(status: ride.status),
                  ],
                ),
                const SizedBox(height: 14),

                // Middle: Route Visualizer
                _RideRouteTrail(
                  pickupTitle: ride.pickup.title,
                  destinationTitle: ride.circuit == null
                      ? ride.destination.title
                      : '${ride.circuit!.stops.length} stops · '
                            '${ride.circuit!.stops.map((stop) => stop.name).join(' → ')}',
                ),
                const SizedBox(height: 12),

                // Hairline Divider
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF1F5F9),
                ),
                const SizedBox(height: 12),

                // Bottom Row: Ride Code Pill + Payment Chip + Price + Chevron
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _line),
                      ),
                      child: Text(
                        ride.rideCode,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF475569),
                          letterSpacing: 0.5,
                        ),
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
                    if (ride.status != RideStatus.noDriverAvailable) ...[
                      Text(
                        RideFormat.money(ride.fare.payable),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16.5,
                          color: _ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF94A3B8),
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RideRouteTrail extends StatelessWidget {
  const _RideRouteTrail({
    required this.pickupTitle,
    required this.destinationTitle,
  });

  final String pickupTitle;
  final String destinationTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Pickup row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                pickupTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),

        // Vertical Connector
        Row(
          children: [
            const SizedBox(width: 4),
            Container(
              width: 2,
              height: 14,
              color: const Color(0xFFE2E8F0),
            ),
            const SizedBox(width: 18),
            const Expanded(
              child: SizedBox(height: 14),
            ),
          ],
        ),

        // Destination row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.bhagwa,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                destinationTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
