import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../circuit/application/circuit_providers.dart';
import '../../circuit/data/circuit_repository.dart';
import '../../circuit/domain/circuit_models.dart';
import '../../circuit/presentation/widgets/circuit_widgets.dart';
import '../../rides/application/booking_controller.dart';
import '../../rides/application/ride_providers.dart';
import '../../rides/domain/ride_formatters.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/presentation/widgets/ride_map.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';

/// Pickup → vehicle → passengers → server estimate → "Confirm & Book".
/// The final consent screen: everything the customer agrees to is on it,
/// and every number comes from `POST /circuit-rides/estimate`.
class CircuitBookingScreen extends ConsumerWidget {
  const CircuitBookingScreen({super.key, required this.packageId});

  final String packageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(circuitPackageProvider(packageId));
    return switch (async) {
      AsyncData(:final value) => _BookingBody(package: value),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(title: const Text('Book circuit')),
        body: LoadErrorView(
          error: error,
          onRetry: () => ref.invalidate(circuitPackageProvider(packageId)),
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(title: const Text('Book circuit')),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _BookingBody extends ConsumerStatefulWidget {
  const _BookingBody({required this.package});

  final CircuitPackage package;

  @override
  ConsumerState<_BookingBody> createState() => _BookingBodyState();
}

class _BookingBodyState extends ConsumerState<_BookingBody> {
  Place? _pickup;
  late CircuitVehicleOption _vehicle = widget.package.vehicles.first;
  int _passengers = 1;
  CircuitEstimate? _estimate;
  Object? _estimateError;
  bool _estimating = false;
  bool _booking = false;
  String? _bookError;

  /// One key per booking attempt: kept while the inputs stay the same, so a
  /// retry after a timeout can never book twice.
  String _bookingKey = newIdempotencyKey();
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    // Start from the pickup the home screen already knows (usually GPS).
    _pickup = ref.read(bookingControllerProvider).pickup;
    if (_pickup != null) unawaited(_refreshEstimate());
  }

  Future<void> _refreshEstimate() async {
    final pickup = _pickup;
    if (pickup == null) return;
    final generation = ++_generation;
    setState(() {
      _estimating = true;
      _estimateError = null;
      _bookError = null;
      _bookingKey = newIdempotencyKey();
    });
    try {
      final estimate = await ref
          .read(circuitRepositoryProvider)
          .estimate(
            packageId: widget.package.id,
            rideType: _vehicle.rideType,
            pickup: pickup,
            passengers: _passengers,
          );
      if (mounted && generation == _generation) {
        setState(() => _estimate = estimate);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _estimate = null;
          _estimateError = error;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _estimating = false);
      }
    }
  }

  Future<void> _choosePickup() async {
    final place = await context.push<Place>(AppRoutes.customerPickPickup);
    if (place == null || !mounted) return;
    setState(() => _pickup = place);
    await _refreshEstimate();
  }

  void _selectVehicle(CircuitVehicleOption vehicle) {
    setState(() {
      _vehicle = vehicle;
      if (_passengers > vehicle.maxPassengers) {
        _passengers = vehicle.maxPassengers;
      }
    });
    unawaited(_refreshEstimate());
  }

  void _setPassengers(int value) {
    setState(() => _passengers = value);
    unawaited(_refreshEstimate());
  }

  Future<void> _book() async {
    final pickup = _pickup;
    if (pickup == null || _estimate == null) return;
    setState(() {
      _booking = true;
      _bookError = null;
    });
    try {
      final ride = await ref
          .read(circuitRepositoryProvider)
          .book(
            packageId: widget.package.id,
            rideType: _vehicle.rideType,
            pickup: pickup,
            passengers: _passengers,
            idempotencyKey: _bookingKey,
          );
      ref.invalidate(activeRideProvider);
      if (mounted) context.go(AppRoutes.customerRide(ride.id));
    } on ApiException catch (error) {
      if (!mounted) return;
      // Already riding: show that ride instead of a dead end.
      final activeId = error.code == 'RIDE_ALREADY_ACTIVE'
          ? (error.data is Map
                ? (error.data as Map)['rideId'] as String?
                : null)
          : null;
      if (activeId != null) {
        context.go(AppRoutes.customerRide(activeId));
        return;
      }
      setState(() => _bookError = error.message);
    } catch (error) {
      if (mounted) setState(() => _bookError = errorMessage(error));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pkg = widget.package;
    final estimate = _estimate;
    final pickup = _pickup;
    final lastStop = pkg.stops.last;

    return Scaffold(
      backgroundColor: AppColors.templeIvory,
      appBar: AppBar(title: Text(pkg.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (pickup != null)
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 200,
                child: RideMap(
                  pickup: pickup,
                  destination: estimate?.stops.last.place ?? lastStop.place,
                  stage: RideMapStage.overview,
                  routePolyline: estimate?.routePolyline,
                  padding: const EdgeInsets.all(32),
                  destinationStyle: const RideMapPin(
                    AppColors.bhagwa,
                    Icons.temple_hindu,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          _Step(
            number: 1,
            title: 'Pickup',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.person_pin_circle,
                color: AppColors.success,
              ),
              title: Text(
                pickup?.title ?? 'Choose where to pick you up',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text(
                'The circuit starts here. It is not one of the stops.',
              ),
              trailing: TextButton(
                onPressed: _choosePickup,
                child: Text(pickup == null ? 'Choose' : 'Change'),
              ),
              onTap: _choosePickup,
            ),
          ),
          _Step(
            number: 2,
            title: 'Vehicle',
            child: Column(
              children: [
                for (final vehicle in pkg.vehicles)
                  _VehicleTile(
                    vehicle: vehicle,
                    selected: vehicle.rideType == _vehicle.rideType,
                    onTap: () => _selectVehicle(vehicle),
                  ),
              ],
            ),
          ),
          _Step(
            number: 3,
            title: 'Passengers',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Up to ${_vehicle.maxPassengers} in a ${_vehicle.displayName}',
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Fewer passengers',
                  onPressed: _passengers > 1
                      ? () => _setPassengers(_passengers - 1)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$_passengers',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'More passengers',
                  onPressed: _passengers < _vehicle.maxPassengers
                      ? () => _setPassengers(_passengers + 1)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          _Step(
            number: 4,
            title: 'Review',
            child: pickup == null
                ? const Text('Choose a pickup to see your circuit price.')
                : _estimating && estimate == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _estimateError != null
                ? _EstimateError(
                    error: _estimateError!,
                    onRetry: _refreshEstimate,
                  )
                : estimate == null
                ? const SizedBox.shrink()
                : AnimatedOpacity(
                    opacity: _estimating ? 0.5 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: _Review(estimate: estimate, package: pkg),
                  ),
          ),
          if (_bookError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _bookError!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: estimate != null && !_estimating && !_booking
              ? _book
              : null,
          child: _booking
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  estimate == null
                      ? 'Confirm & Book'
                      : 'Confirm & Book · ${RideFormat.money(estimate.packagePrice)}',
                ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.child});

  final int number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.midnightBlue,
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.midnightBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({
    required this.vehicle,
    required this.selected,
    required this.onTap,
  });

  final CircuitVehicleOption vehicle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.bhagwaLight : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AppColors.bhagwa : AppColors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  rideTypeIcon(vehicle.rideType, iconKey: vehicle.icon),
                  color: AppColors.midnightBlue,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Up to ${vehicle.maxPassengers} passengers',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? AppColors.bhagwa : AppColors.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.estimate, required this.package});

  final CircuitEstimate estimate;
  final CircuitPackage package;

  @override
  Widget build(BuildContext context) {
    final extra =
        estimate.expectedExtraDistanceCharge +
        estimate.expectedExtraDurationCharge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircuitStopsTimeline.planned(
          stops: estimate.stops,
          pickup: estimate.pickup.title,
          compact: true,
        ),
        Text(
          'Planned route ${CircuitFormat.km(estimate.routeDistanceMeters)} · '
          'about ${RideFormat.duration(estimate.routeDurationSeconds)} of driving',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        if (estimate.pickupEtaSeconds != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Nearest ${estimate.rideTypeName.toLowerCase()} about '
              '${RideFormat.duration(estimate.pickupEtaSeconds!)} away',
              style: const TextStyle(fontSize: 12, color: AppColors.success),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'No driver nearby right now — we keep looking after you book.',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ),
        for (final notice in estimate.notices)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(notice, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        const Divider(height: 28),
        CircuitFareRules(pricing: estimate.pricing),
        const Divider(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Package fare',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              RideFormat.money(estimate.packagePrice),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Expanded(child: Text('Estimated with expected extras')),
                Text(
                  RideFormat.money(estimate.estimatedTotal),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        const Text(
          'This is not the final fare. It is calculated when the circuit ends, '
          'from the time and distance actually used.',
          style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
        if (estimate.cancellationPolicy case final policy?
            when policy.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Cancellation: $policy',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _EstimateError extends StatelessWidget {
  const _EstimateError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          errorMessage(error),
          style: const TextStyle(color: AppColors.error),
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}
