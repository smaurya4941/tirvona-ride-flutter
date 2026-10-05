import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../circuit/presentation/widgets/circuit_widgets.dart';
import '../../application/ride_providers.dart';
import '../../data/ride_repository.dart';
import '../../domain/ride_formatters.dart';
import '../../domain/ride_models.dart';
import '../widgets/ride_widgets.dart';

/// An incoming request with Accept / Reject. The driver cannot change the
/// fare, the customer or the assignment — only answer it.
class RideRequestCard extends ConsumerStatefulWidget {
  const RideRequestCard({super.key, required this.ride});

  final Ride ride;

  @override
  ConsumerState<RideRequestCard> createState() => _RideRequestCardState();
}

class _RideRequestCardState extends ConsumerState<RideRequestCard> {
  bool _accepting = false;
  bool _rejecting = false;

  bool get _busy => _accepting || _rejecting;

  void _refreshDriverState() {
    ref
      ..invalidate(driverRequestsProvider)
      ..invalidate(driverDashboardProvider);
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      final ride = await ref
          .read(rideRepositoryProvider)
          .accept(widget.ride.id);
      _refreshDriverState();
      if (mounted) unawaited(context.push(AppRoutes.driverRide(ride.id)));
    } catch (error) {
      // Typically "expired" or "no longer available" — the list resyncs.
      if (mounted) showErrorSnack(context, error);
      _refreshDriverState();
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _rejecting = true);
    try {
      await ref.read(rideRepositoryProvider).reject(widget.ride.id);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      _refreshDriverState();
      if (mounted) setState(() => _rejecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final circuit = ride.circuit;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.bhagwa, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.bhagwaLight,
                  child: Icon(
                    rideTypeIcon(ride.rideType),
                    color: AppColors.bhagwa,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        circuit != null
                            ? 'Circuit request'
                            : 'New ${ride.rideType.label} request',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      if (ride.pickupDistanceMeters != null)
                        Text(
                          '${RideFormat.distance(ride.pickupDistanceMeters!)} '
                          'to pickup',
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  RideFormat.money(ride.fare.estimatedFare),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.midnightBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (circuit != null) ...[
              // A circuit keeps the driver for hours: show the whole job.
              CircuitBadge(circuit: circuit),
              const SizedBox(height: 12),
              CircuitStopsTimeline(
                stops: circuit.stops,
                pickup: ride.pickup.title,
                compact: true,
              ),
              Text(
                'Package ${RideFormat.money(circuit.pricing.basePrice)} · '
                '${circuit.passengers} passenger'
                '${circuit.passengers == 1 ? '' : 's'}'
                '${ride.customer == null ? '' : ' · ${ride.customer!.name}'}',
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              const Text(
                'You stay with the customer for the whole circuit and get no '
                'other requests until it ends.',
                style: TextStyle(fontSize: 12, color: AppColors.bhagwaDark),
              ),
            ] else ...[
              RouteSummary(pickup: ride.pickup, destination: ride.destination),
              const SizedBox(height: 10),
              Text(
                'Trip ${RideFormat.distance(ride.distanceMeters)} · '
                '~${RideFormat.duration(ride.durationSeconds)}'
                '${ride.customer == null ? '' : ' · ${ride.customer!.name}'}',
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
            ],
            if (ride.assignmentExpiresAt != null) ...[
              const SizedBox(height: 14),
              _ResponseCountdown(expiresAt: ride.assignmentExpiresAt!),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _busy ? null : _reject,
                    child: _rejecting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy ? null : _accept,
                    child: _accepting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Visual countdown to the server's acceptance deadline. Uses the device
/// clock, so it is a guide; the server's deadline is what actually counts.
class _ResponseCountdown extends StatefulWidget {
  const _ResponseCountdown({required this.expiresAt});

  final DateTime expiresAt;

  @override
  State<_ResponseCountdown> createState() => _ResponseCountdownState();
}

class _ResponseCountdownState extends State<_ResponseCountdown> {
  late final Timer _timer;
  late final int _initialSeconds;
  late int _remaining;

  int _secondsLeft() => widget.expiresAt
      .difference(DateTime.now())
      .inSeconds
      .clamp(0, 1 << 20)
      .toInt();

  @override
  void initState() {
    super.initState();
    _remaining = _secondsLeft();
    _initialSeconds = _remaining == 0 ? 1 : _remaining;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _remaining = _secondsLeft());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_remaining / _initialSeconds).clamp(0.0, 1.0),
            minHeight: 6,
            color: _remaining <= 10 ? AppColors.error : AppColors.bhagwa,
            backgroundColor: AppColors.surfaceSand,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _remaining > 0
              ? 'Respond within ${_remaining}s'
              : 'Request expiring…',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
