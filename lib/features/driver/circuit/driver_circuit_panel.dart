import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/driver_location_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../../../shared/widgets/loading_filled_button.dart';
import '../../circuit/data/circuit_repository.dart';
import '../../circuit/domain/circuit_models.dart';
import '../../circuit/presentation/widgets/circuit_widgets.dart';
import '../../rides/application/ride_providers.dart';
import '../../rides/domain/ride_formatters.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/presentation/widgets/call_button.dart';
import '../../rides/presentation/widgets/ride_map.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';

/// The driver's screen while a circuit runs. Each button is one command the
/// server validates (arrive / visiting / done / blocked / complete); the
/// screen only shows what the server says the circuit is now, so a retry
/// after a network drop is always safe.
class DriverCircuitPanel extends ConsumerStatefulWidget {
  const DriverCircuitPanel({super.key, required this.ride});

  final Ride ride;

  @override
  ConsumerState<DriverCircuitPanel> createState() => _DriverCircuitPanelState();
}

class _DriverCircuitPanelState extends ConsumerState<DriverCircuitPanel> {
  bool _working = false;
  String? _error;

  Future<void> _run(
    Future<Ride> Function(CircuitRepository repo) command,
  ) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await command(ref.read(circuitRepositoryProvider));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      // Reconcile with the server whatever happened.
      ref
        ..invalidate(rideProvider(widget.ride.id))
        ..invalidate(driverDashboardProvider);
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reportBlocked(CircuitRideStop stop) async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Can't reach ${stop.name}?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tirvona support will decide whether to continue or skip this '
              'stop. You will not be able to move on until they do.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'What is the problem?',
                hintText: 'Road closed, temple shut…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (confirmed == true) {
      await _run(
        (repo) =>
            repo.reportStopBlocked(widget.ride.id, stop.order, note: text),
      );
    }
  }

  Future<void> _complete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete the circuit?'),
        content: const Text(
          'Confirm every stop is done and the customer has been dropped. The '
          'fare is then calculated from the time and distance used.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run((repo) => repo.completeCircuit(widget.ride.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final circuit = ride.circuit!;
    final stop = circuit.currentStop;
    final next = circuit.nextStop;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: AppColors.midnightBlue,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CIRCUIT IN PROGRESS',
                  style: TextStyle(
                    color: AppColors.sacredGold,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                CircuitBadge(circuit: circuit, dark: true),
                const SizedBox(height: 16),
                CircuitUsagePanel(circuit: circuit, running: true, dark: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (circuit.hasException)
          const _SupportBanner()
        else if (stop != null)
          _CurrentStopCard(ride: ride, stop: stop),
        if (circuit.readyToComplete)
          const Card(
            child: ListTile(
              leading: Icon(Icons.flag, color: AppColors.success),
              title: Text(
                'All stops done',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Drop the customer, then complete the circuit.'),
            ),
          ),
        const SizedBox(height: 12),
        ErrorBanner(message: _error),
        ..._actions(circuit, stop, next),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stops',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 12),
                CircuitStopsTimeline(
                  stops: circuit.stops,
                  pickup: ride.pickup.title,
                  currentOrder: circuit.currentStopOrder,
                  blockedOrder: circuit.exceptionStopOrder,
                  compact: true,
                ),
              ],
            ),
          ),
        ),
        if (ride.customer case final customer?)
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.bhagwaLight,
                child: Icon(Icons.person, color: AppColors.bhagwa),
              ),
              title: Text(customer.name),
              subtitle: Text(
                '${circuit.passengers} passenger${circuit.passengers == 1 ? '' : 's'}',
              ),
              trailing: customer.phone == null
                  ? null
                  : CallIconButton(phone: customer.phone!, name: customer.name),
            ),
          ),
      ],
    );
  }

  List<Widget> _actions(
    CircuitInfo circuit,
    CircuitRideStop? stop,
    CircuitRideStop? next,
  ) {
    if (circuit.hasException) return const [];
    if (circuit.readyToComplete) {
      return [
        LoadingFilledButton(
          label: 'Complete circuit',
          icon: Icons.flag,
          isLoading: _working,
          onPressed: _complete,
        ),
      ];
    }
    if (stop == null) return const [];
    final id = widget.ride.id;
    final doneLabel = next == null
        ? 'Done at ${stop.name}'
        : 'Continue to ${next.name}';
    return switch (stop.status) {
      CircuitStopStatus.arriving => [
        LoadingFilledButton(
          label: 'Arrived at ${stop.name}',
          icon: Icons.where_to_vote,
          isLoading: _working,
          onPressed: () => _run((repo) => repo.arriveAtStop(id, stop.order)),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _working ? null : () => _reportBlocked(stop),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          icon: const Icon(Icons.block),
          label: const Text("Can't reach this stop"),
        ),
      ],
      CircuitStopStatus.arrived => [
        LoadingFilledButton(
          label: doneLabel,
          icon: Icons.arrow_forward,
          isLoading: _working,
          onPressed: () => _run((repo) => repo.completeStop(id, stop.order)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _working
              ? null
              : () => _run((repo) => repo.waitAtStop(id, stop.order)),
          icon: const Icon(Icons.hourglass_top),
          label: const Text('Customer is visiting — I am waiting'),
        ),
      ],
      CircuitStopStatus.waiting => [
        LoadingFilledButton(
          label: doneLabel,
          icon: Icons.arrow_forward,
          isLoading: _working,
          onPressed: () => _run((repo) => repo.completeStop(id, stop.order)),
        ),
      ],
      _ => const [],
    };
  }
}

class _CurrentStopCard extends ConsumerWidget {
  const _CurrentStopCard({required this.ride, required this.stop});

  final Ride ride;
  final CircuitRideStop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fix = ref.watch(
      driverLocationServiceProvider.select((state) => state.lastFix),
    );
    final circuit = ride.circuit!;
    final atStop = stop.status.isAtStop;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!atStop)
            SizedBox(
              height: 200,
              child: RideMap(
                pickup: ride.pickup,
                destination: stop.stop.place,
                stops: circuitMapStops(circuit),
                stage: RideMapStage.trip,
                driverIcon: rideTypeIcon(ride.rideType),
                padding: const EdgeInsets.all(36),
                liveRoute: watchLiveRoute(ref, ride),
                destinationStyle: const RideMapPin(
                  AppColors.bhagwa,
                  Icons.temple_hindu,
                ),
                driver: fix == null
                    ? null
                    : DriverPosition(
                        latitude: fix.latitude,
                        longitude: fix.longitude,
                        heading: fix.heading,
                        speed: fix.speed,
                        updatedAt: fix.recordedAt,
                      ),
              ),
            ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.bhagwa,
              child: Text(
                '${stop.order}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(
              atStop ? 'At ${stop.name}' : 'Current stop: ${stop.name}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              atStop ? stop.status.label : stop.stop.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: atStop
                ? null
                : FilledButton.tonalIcon(
                    // Compact: the theme's full-width size would crush the title.
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => _navigate(context, stop.stop.place),
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Navigate'),
                  ),
          ),
        ],
      ),
    );
  }

  static Future<void> _navigate(BuildContext context, Place target) async {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${target.latitude},${target.longitude}',
      'travelmode': 'driving',
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showErrorSnack(
        context,
        const UserFacingError('No navigation app is available on this phone.'),
      );
    }
  }
}

class _SupportBanner extends StatelessWidget {
  const _SupportBanner();

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: Color(0xFFFFFBEB),
      child: ListTile(
        leading: Icon(Icons.support_agent, color: AppColors.warning),
        title: Text(
          'Waiting for Tirvona support',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'You reported this stop as unreachable. Support will tell you whether '
          'to continue or skip it — this screen updates by itself.',
        ),
      ),
    );
  }
}

/// Before the start and after the end, a circuit uses the normal ride screen;
/// this replaces its route card with the package and its stops.
class DriverCircuitSummaryCard extends StatelessWidget {
  const DriverCircuitSummaryCard({super.key, required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final circuit = ride.circuit!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircuitBadge(circuit: circuit),
            const SizedBox(height: 14),
            CircuitStopsTimeline(
              stops: circuit.stops,
              pickup: ride.pickup.title,
              compact: true,
            ),
            Text(
              'Package ${RideFormat.money(circuit.pricing.basePrice)} · '
              'timer starts when you start with the customer\'s PIN',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
