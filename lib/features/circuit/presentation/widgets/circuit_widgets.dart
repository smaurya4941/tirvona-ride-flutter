import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../rides/domain/ride_formatters.dart';
import '../../../rides/domain/ride_models.dart';
import '../../../rides/presentation/widgets/ride_map.dart';
import '../../application/circuit_providers.dart';
import '../../domain/circuit_models.dart';

/// Pickup → ✓ visited → ● current → ○ upcoming. Shared by the customer and
/// driver screens; the statuses are the server's.
class CircuitStopsTimeline extends StatelessWidget {
  const CircuitStopsTimeline({
    super.key,
    required this.stops,
    this.pickup,
    this.currentOrder,
    this.blockedOrder,
    this.compact = false,
  });

  /// Before booking (package details) the stops have no progress yet.
  CircuitStopsTimeline.planned({
    super.key,
    required List<CircuitStop> stops,
    this.pickup,
    this.compact = false,
  }) : stops = [
         for (final stop in stops)
           CircuitRideStop(stop: stop, status: CircuitStopStatus.upcoming),
       ],
       currentOrder = null,
       blockedOrder = null;

  final List<CircuitRideStop> stops;
  final String? pickup;
  final int? currentOrder;
  final int? blockedOrder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (pickup != null)
        _TimelineRow(
          icon: Icons.person_pin_circle,
          color: AppColors.success,
          title: 'Pickup',
          subtitle: pickup,
          last: stops.isEmpty,
          compact: compact,
        ),
      for (final (index, stop) in stops.indexed)
        _TimelineRow(
          icon: switch (stop.status) {
            CircuitStopStatus.completed => Icons.check_circle,
            CircuitStopStatus.skipped => Icons.remove_circle,
            CircuitStopStatus.upcoming => Icons.radio_button_unchecked,
            _ => Icons.radio_button_checked,
          },
          color: switch (stop.status) {
            CircuitStopStatus.completed => AppColors.success,
            CircuitStopStatus.skipped => AppColors.error,
            CircuitStopStatus.upcoming => AppColors.outlineVariant,
            _ => AppColors.bhagwa,
          },
          title: '${stop.order}. ${stop.name}',
          subtitle: stop.order == blockedOrder
              ? 'Reported unreachable · support is deciding'
              : stop.status == CircuitStopStatus.upcoming
              ? (compact ? null : stop.stop.address)
              : stop.status.label,
          highlighted: stop.order == currentOrder,
          warn: stop.order == blockedOrder,
          last: index == stops.length - 1,
          compact: compact,
        ),
    ];
    return Column(children: rows);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.highlighted = false,
    this.warn = false,
    required this.last,
    required this.compact,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool highlighted;
  final bool warn;
  final bool last;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(icon, size: 22, color: color),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: AppColors.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: compact ? 8 : 14),
              padding: highlighted
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                  : EdgeInsets.zero,
              decoration: highlighted
                  ? BoxDecoration(
                      color: warn
                          ? const Color(0xFFFEF2F2)
                          : AppColors.bhagwaLight,
                      borderRadius: BorderRadius.circular(10),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: highlighted
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: AppColors.midnightBlue,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: warn
                            ? AppColors.error
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Time and distance against the package, ticking every second from the
/// server's own clock (the snapshot's elapsed time + time since it was built),
/// so a wrong phone clock cannot change what the customer sees.
class CircuitUsagePanel extends StatefulWidget {
  const CircuitUsagePanel({
    super.key,
    required this.circuit,
    required this.running,
    this.dark = false,
  });

  final CircuitInfo circuit;

  /// The circuit has started and not finished.
  final bool running;
  final bool dark;

  @override
  State<CircuitUsagePanel> createState() => _CircuitUsagePanelState();
}

class _CircuitUsagePanelState extends State<CircuitUsagePanel> {
  Timer? _ticker;
  late DateTime _receivedAt;

  @override
  void initState() {
    super.initState();
    _receivedAt = DateTime.now();
    _syncTicker();
  }

  @override
  void didUpdateWidget(CircuitUsagePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.circuit, widget.circuit)) {
      _receivedAt = DateTime.now();
    }
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.running && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!widget.running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final circuit = widget.circuit;
    final pricing = circuit.pricing;
    // Count from when this snapshot arrived, not from the phone's own clock.
    final elapsed = widget.running
        ? circuit.elapsedSeconds +
              DateTime.now().difference(_receivedAt).inSeconds
        : circuit.elapsedSeconds;
    final remaining = pricing.includedDurationSeconds - elapsed;
    final ink = widget.dark ? Colors.white : AppColors.midnightBlue;
    final muted = widget.dark
        ? Colors.white.withValues(alpha: 0.75)
        : AppColors.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Gauge(
                label: remaining >= 0 ? 'Time left' : 'Over time',
                value: CircuitFormat.clock(remaining.abs()),
                detail:
                    '${CircuitFormat.clock(elapsed)} of ${CircuitFormat.includedTime(pricing.includedDurationSeconds)}',
                ratio: pricing.includedDurationSeconds == 0
                    ? 0
                    : elapsed / pricing.includedDurationSeconds,
                ink: ink,
                muted: muted,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _Gauge(
                label: 'Distance',
                value: CircuitFormat.km(circuit.distanceMeters),
                detail:
                    'of ${CircuitFormat.includedKm(pricing.includedDistanceMeters)} included',
                ratio: pricing.includedDistanceMeters == 0
                    ? 0
                    : circuit.distanceMeters / pricing.includedDistanceMeters,
                ink: ink,
                muted: muted,
              ),
            ),
          ],
        ),
        if (circuit.projected.hasExtras) ...[
          const SizedBox(height: 10),
          Text(
            'Extras so far: ${RideFormat.money(circuit.projected.extraDistanceCharge + circuit.projected.extraDurationCharge)} '
            '· running total ${RideFormat.money(circuit.projected.total)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.dark ? AppColors.sacredGold : AppColors.bhagwaDark,
            ),
          ),
        ],
        if (!circuit.distanceReliable)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'GPS is patchy — distance updates when the signal returns.',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),
      ],
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.label,
    required this.value,
    required this.detail,
    required this.ratio,
    required this.ink,
    required this.muted,
  });

  final String label;
  final String value;
  final String detail;
  final double ratio;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final color = ratio >= 1
        ? AppColors.error
        : ratio >= 0.8
        ? AppColors.warning
        : AppColors.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1).toDouble(),
            minHeight: 6,
            color: color,
            backgroundColor: color.withValues(alpha: 0.18),
          ),
        ),
        const SizedBox(height: 4),
        Text(detail, style: TextStyle(fontSize: 11, color: muted)),
      ],
    );
  }
}

/// What the package includes and exactly how extras are charged — shown
/// before booking so nothing is hidden.
class CircuitFareRules extends StatelessWidget {
  const CircuitFareRules({super.key, required this.pricing});

  final CircuitPricing pricing;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.bhagwa),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return Column(
      children: [
        row(
          Icons.sell_outlined,
          'Package price',
          RideFormat.money(pricing.basePrice),
        ),
        row(
          Icons.schedule,
          'Included time',
          CircuitFormat.includedTime(pricing.includedDurationSeconds),
        ),
        row(
          Icons.straighten,
          'Included distance',
          CircuitFormat.includedKm(pricing.includedDistanceMeters),
        ),
        const Divider(height: 20),
        row(
          Icons.add_road,
          'Extra distance',
          '${RideFormat.money(pricing.extraDistanceRatePerKm)} / km',
        ),
        row(
          Icons.more_time,
          'Extra time',
          '${RideFormat.money(pricing.extraDurationRatePerHour)} / hour',
        ),
        const SizedBox(height: 6),
        const Text(
          'The included time starts when your driver starts the circuit with '
          'your PIN, and counts driving, waiting and your time at each stop. '
          'Extras are charged per started km and per started 15 minutes, and '
          'the final fare is worked out when the circuit ends.',
          style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Cover image (or a branded fallback) for a package card or header.
class CircuitCover extends ConsumerWidget {
  const CircuitCover({
    super.key,
    required this.coverPath,
    this.height = 140,
    this.borderRadius = const BorderRadius.vertical(top: Radius.circular(18)),
  });

  final String? coverPath;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(circuitCoverUrlProvider(coverPath));
    final fallback = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bhagwa, AppColors.bhagwaDark],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.temple_hindu,
        size: height * 0.38,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    );
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: url == null
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : fallback,
              ),
      ),
    );
  }
}

/// "3 stops · 5 hours · 30 km"
String circuitHeadline(CircuitPricing pricing, int stops) =>
    '$stops stop${stops == 1 ? '' : 's'} · '
    '${CircuitFormat.includedTime(pricing.includedDurationSeconds)} · '
    '${CircuitFormat.includedKm(pricing.includedDistanceMeters)}';

/// Package name and the headline, for cards on the ride screens.
class CircuitBadge extends StatelessWidget {
  const CircuitBadge({super.key, required this.circuit, this.dark = false});

  final CircuitInfo circuit;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: 0.12)
                : AppColors.bhagwaLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.temple_hindu,
            color: dark ? Colors.white : AppColors.bhagwa,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                circuit.name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: dark ? Colors.white : AppColors.midnightBlue,
                ),
              ),
              Text(
                circuitHeadline(circuit.pricing, circuit.stops.length),
                style: TextStyle(
                  fontSize: 12,
                  color: dark
                      ? Colors.white.withValues(alpha: 0.75)
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows circuit notices (warnings, next stop) as snackbars while [child] is
/// on screen.
class CircuitNoticeListener extends ConsumerWidget {
  const CircuitNoticeListener({
    super.key,
    required this.ride,
    required this.asDriver,
    required this.child,
  });

  final Ride ride;
  final bool asDriver;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ride.isCircuit) {
      ref.listen(
        circuitNoticesProvider((rideId: ride.id, asDriver: asDriver)),
        (_, next) {
          final notice = next.value;
          if (notice == null) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(notice.message),
                backgroundColor: notice.isWarning
                    ? AppColors.bhagwaDark
                    : AppColors.midnightBlue,
                duration: Duration(seconds: notice.isWarning ? 8 : 4),
              ),
            );
        },
      );
    }
    return child;
  }
}

/// Circuit stops as map markers.
List<RideMapStop> circuitMapStops(CircuitInfo circuit) => [
  for (final stop in circuit.stops)
    RideMapStop(
      place: stop.stop.place,
      label: '${stop.order}. ${stop.name}',
      done: stop.status.isDone,
    ),
];

/// Where a circuit's map points: the stop being driven to while it runs,
/// else the last stop.
Place circuitMapTarget(CircuitInfo circuit) =>
    (circuit.currentStop ?? circuit.stops.last).stop.place;

/// Package, stops and (once started) live usage — the heart of the active
/// circuit screen for the customer.
class CircuitProgressCard extends StatelessWidget {
  const CircuitProgressCard({super.key, required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final circuit = ride.circuit!;
    final started = ride.startedAt != null;
    final running = ride.status == RideStatus.rideStarted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircuitBadge(circuit: circuit),
            if (started) ...[
              const SizedBox(height: 16),
              CircuitUsagePanel(circuit: circuit, running: running),
            ] else ...[
              const SizedBox(height: 10),
              Text(
                'Your ${CircuitFormat.includedTime(circuit.pricing.includedDurationSeconds)} '
                'start when your driver starts the circuit with your PIN.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
            const Divider(height: 28),
            CircuitStopsTimeline(
              stops: circuit.stops,
              pickup: ride.pickup.title,
              currentOrder: running ? circuit.currentStopOrder : null,
              blockedOrder: circuit.exceptionStopOrder,
            ),
            if (circuit.endedEarlyReason case final reason?)
              Text(
                'Ended early by Tirvona support: $reason',
                style: const TextStyle(color: AppColors.bhagwaDark),
              ),
          ],
        ),
      ),
    );
  }
}

/// The circuit bill: package + extras. Final once the circuit is completed,
/// otherwise the running projection.
class CircuitBillCard extends StatelessWidget {
  const CircuitBillCard({super.key, required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final circuit = ride.circuit!;
    final bill = ride.fare.finalBill;
    final pricing = circuit.pricing;
    final distanceCharge =
        bill?.distanceCharge ?? circuit.projected.extraDistanceCharge;
    final timeCharge =
        bill?.timeCharge ?? circuit.projected.extraDurationCharge;
    final extraKm = circuit.settledExtraKm ?? circuit.projected.extraKm;
    final blocks = circuit.settledExtraBlocks ?? circuit.projected.extraBlocks;
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              fontSize: strong ? 18 : 14,
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bill == null ? 'Bill so far' : 'Final fare',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            row(
              'Package',
              RideFormat.money(bill?.baseFare ?? pricing.basePrice),
            ),
            row(
              'Extra distance${extraKm > 0 ? ' ($extraKm km × ${RideFormat.money(pricing.extraDistanceRatePerKm)})' : ''}',
              RideFormat.money(distanceCharge),
            ),
            row(
              'Extra time${blocks > 0 ? ' (${CircuitFormat.clock(blocks * 15 * 60)})' : ''}',
              RideFormat.money(timeCharge),
            ),
            const Divider(height: 20),
            row(
              'Total',
              RideFormat.money(ride.fare.finalFare ?? circuit.projected.total),
              strong: true,
            ),
            if (bill != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Used ${CircuitFormat.clock(bill.durationSeconds)} and '
                  '${CircuitFormat.km(bill.distanceMeters)}'
                  '${bill.distanceMeasured ? '' : ' (planned route — GPS was unavailable)'}.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
