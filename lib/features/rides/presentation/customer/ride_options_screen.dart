import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../places/application/popular_places.dart';
import '../../application/booking_controller.dart';
import '../../domain/promo_models.dart';
import '../../domain/ride_formatters.dart';
import '../../domain/ride_models.dart';
import '../widgets/ride_map.dart';
import '../widgets/ride_widgets.dart';
import 'promo_code_sheet.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _blue = Color(0xFF2563EB);
const _line = Color(0xFFE2E8F0);
const _red = Color(0xFFEF4444);

/// Ride types shown before "View more".
const _previewCount = 4;

/// Choose a ride and book it, on one screen: the route on the map, the trip
/// (swap or change either end), every bookable ride type with the
/// server's fare, trip time and how soon a driver could arrive, then
/// "Confirm Ride", which sends the request to nearby drivers.
///
/// Prices here are quotes; the server re-prices when the ride is booked.
class RideOptionsScreen extends ConsumerStatefulWidget {
  const RideOptionsScreen({super.key});

  @override
  ConsumerState<RideOptionsScreen> createState() => _RideOptionsScreenState();
}

class _RideOptionsScreenState extends ConsumerState<RideOptionsScreen> {
  bool _booking = false;
  bool _showAll = false;
  String? _error;
  int _refit = 0;

  @override
  void initState() {
    super.initState();
    // Arrived without quotes (e.g. after a swap elsewhere): fetch them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final booking = ref.read(bookingControllerProvider);
      final estimates = booking.estimates;
      if (booking.hasTrip &&
          !estimates.isLoading &&
          !estimates.hasError &&
          (estimates.value?.isEmpty ?? true)) {
        unawaited(ref.read(bookingControllerProvider.notifier).loadEstimates());
      }
    });
  }

  /// Back to "Where to?" for [field]; it returns here once both ends are set.
  void _change(PlaceField field) =>
      context.pushReplacement(AppRoutes.customerPlaceSearchFor(field.name));

  void _swap() {
    final controller = ref.read(bookingControllerProvider.notifier)..swap();
    setState(() => _error = null);
    unawaited(controller.loadEstimates());
  }

  Future<void> _confirm() async {
    setState(() {
      _booking = true;
      _error = null;
    });
    final controller = ref.read(bookingControllerProvider.notifier);
    try {
      final ride = await controller.book();
      controller.reset();
      if (mounted) context.go(AppRoutes.customerRide(ride.id));
    } on ApiException catch (error) {
      if (!mounted) return;
      // Double tap / second device: open the ride that already exists.
      final data = error.data;
      if (error.code == 'RIDE_ALREADY_ACTIVE' &&
          data is Map<String, dynamic> &&
          data['rideId'] is String) {
        context.go(AppRoutes.customerRide(data['rideId'] as String));
        return;
      }
      // The promo stopped applying since it was checked (expired, used
      // up…): drop it so the rider can book at the normal fare.
      if (error.code?.startsWith('PROMO_') ?? false) controller.removePromo();
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingControllerProvider);
    final controller = ref.read(bookingControllerProvider.notifier);
    final pickup = booking.pickup;
    final destination = booking.destination;

    if (pickup == null || destination == null || !booking.hasTrip) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choose a ride')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose a pickup and destination first.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _change(PlaceField.destination),
                child: const Text('Where to?'),
              ),
            ],
          ),
        ),
      );
    }

    final estimates = booking.estimates.value ?? const <FareEstimate>[];
    final selected = booking.selectedEstimate;
    // Every ride type shares one route; any quote carries it.
    final trip = selected ?? (estimates.isEmpty ? null : estimates.first);
    final media = MediaQuery.of(context);
    final mapHeight = media.size.height * 0.36;
    final canBook =
        selected != null && !booking.estimates.isLoading && !_booking;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: mapHeight,
            child: RideMap(
              pickup: pickup,
              destination: destination,
              stage: RideMapStage.overview,
              routePolyline: trip?.routePolyline,
              pickupStyle: const RideMapPin(_blue, Icons.my_location),
              destinationStyle: const RideMapPin(_red, Icons.location_on),
              refitSignal: _refit,
              padding: EdgeInsets.fromLTRB(56, media.padding.top + 56, 56, 44),
            ),
          ),
          Positioned(
            top: media.padding.top + 8,
            left: 16,
            child: _MapButton(
              tooltip: 'Back',
              icon: Icons.arrow_back,
              onPressed: () => context.pop(),
            ),
          ),
          Positioned(
            top: mapHeight - 68,
            right: 16,
            child: _MapButton(
              tooltip: 'Show the whole route',
              icon: Icons.gps_fixed_rounded,
              onPressed: () => setState(() => _refit++),
            ),
          ),
          Positioned.fill(
            top: mapHeight - 20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: RefreshIndicator(
                onRefresh: controller.loadEstimates,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TripSummary(
                      pickup: pickup,
                      destination: destination,
                      estimate: trip,
                      loading: booking.estimates.isLoading,
                      onPickup: () => _change(PlaceField.pickup),
                      onDestination: () => _change(PlaceField.destination),
                      onChange: () => _change(PlaceField.destination),
                      onSwap: _booking ? null : _swap,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Choose a ride',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ),
                        if (estimates.length > _previewCount)
                          TextButton(
                            onPressed: () =>
                                setState(() => _showAll = !_showAll),
                            style: TextButton.styleFrom(
                              foregroundColor: _blue,
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: Text(_showAll ? 'View less' : 'View more'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...booking.estimates.when(
                      skipLoadingOnRefresh: false,
                      loading: () => [
                        for (var i = 0; i < 3; i++) const _RideTileSkeleton(),
                      ],
                      error: (error, _) => [
                        LoadErrorView(
                          error: error,
                          onRetry: controller.loadEstimates,
                        ),
                      ],
                      data: (list) {
                        if (list.isEmpty) {
                          return const [
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No rides are available for this trip right '
                                'now. Pull down to try again.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _muted),
                              ),
                            ),
                          ];
                        }
                        // The chosen ride always stays visible.
                        final visible = _showAll
                            ? list
                            : [
                                ...list.take(_previewCount),
                                if (selected != null &&
                                    list.indexOf(selected) >= _previewCount)
                                  selected,
                              ];
                        return [
                          for (final estimate in visible)
                            _RideTile(
                              estimate: estimate,
                              selected:
                                  estimate.rideType == booking.selectedType,
                              promo: estimate.rideType == booking.selectedType
                                  ? booking.promo
                                  : null,
                              enabled: !_booking,
                              onTap: () {
                                setState(() => _error = null);
                                controller.select(estimate.rideType);
                              },
                              onInfo: () => _showFare(context, estimate),
                            ),
                        ];
                      },
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 4),
                      _PromoRow(
                        promo: booking.promo,
                        saved: booking.savedPromo,
                        problem: booking.savedPromoProblem,
                        enabled: !_booking,
                        onApply: () => showPromoCodeSheet(
                          context,
                          code: booking.savedPromo?.code,
                        ),
                        onRemove: controller.removePromo,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _line)),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                _ErrorNote(message: _error!),
                const SizedBox(height: 8),
              ],
              const _Assurances(),
              const SizedBox(height: 10),
              _ConfirmButton(
                label: selected == null
                    ? 'Choose a ride'
                    : 'Confirm ${selected.displayName}',
                busy: _booking,
                onPressed: canBook ? _confirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFare(BuildContext context, FareEstimate estimate) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  estimate.displayName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (estimate.description != null)
                  Text(
                    estimate.description!,
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Up to ${estimate.seatCapacity} '
                  '${estimate.seatCapacity == 1 ? 'passenger' : 'passengers'}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FareBreakdownCard(
                  fare: estimate.fare,
                  distanceMeters: estimate.distanceMeters,
                  durationSeconds: estimate.durationSeconds,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Distance and time are estimates. The fare is confirmed '
                  'when you book and settled on the actual trip.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trip summary: both ends, swap, distance and time
// ─────────────────────────────────────────────────────────────────────────────

class _TripSummary extends StatelessWidget {
  const _TripSummary({
    required this.pickup,
    required this.destination,
    required this.estimate,
    required this.loading,
    required this.onPickup,
    required this.onDestination,
    required this.onChange,
    required this.onSwap,
  });

  final Place pickup;
  final Place destination;
  final FareEstimate? estimate;
  final bool loading;
  final VoidCallback onPickup;
  final VoidCallback onDestination;
  final VoidCallback onChange;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    final trip = estimate;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _EndRow(
                      marker: const Icon(Icons.circle, color: _blue, size: 11),
                      text: pickup.title,
                      semanticLabel: 'Pickup: ${pickup.title}. Change pickup',
                      onTap: onPickup,
                    ),
                    _EndRow(
                      marker: const Icon(
                        Icons.location_on,
                        color: _red,
                        size: 16,
                      ),
                      text: destination.title,
                      semanticLabel:
                          'Destination: ${destination.title}. Change destination',
                      onTap: onDestination,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  tooltip: 'Swap pickup and destination',
                  onPressed: onSwap,
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                  ),
                  icon: const Icon(
                    Icons.swap_vert_rounded,
                    color: _ink,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, color: _muted, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    trip == null
                        ? (loading ? 'Finding the best route…' : '—')
                        : '${RideFormat.distance(trip.distanceMeters)} • '
                              '${RideFormat.duration(trip.durationSeconds)}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: _ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onChange,
                  style: TextButton.styleFrom(
                    foregroundColor: _blue,
                    backgroundColor: const Color(0xFFEFF4FF),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EndRow extends StatelessWidget {
  const _EndRow({
    required this.marker,
    required this.text,
    required this.semanticLabel,
    required this.onTap,
  });

  final Widget marker;
  final String text;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              SizedBox(width: 36, child: Center(child: marker)),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ride type rows
// ─────────────────────────────────────────────────────────────────────────────

/// Tint and glyph per ride type, for the vehicle badge.
({Color tint, Color color}) _vehicleColors(FareEstimate estimate) {
  final key = '${estimate.icon} ${estimate.rideType.wireName}'.toUpperCase();
  if (key.contains('BIKE')) {
    return (tint: const Color(0xFFE7F6EC), color: const Color(0xFF15803D));
  }
  if (key.contains('AUTO') || key.contains('RICKSHAW')) {
    return (tint: const Color(0xFFFEF6D8), color: const Color(0xFFB45309));
  }
  return (tint: const Color(0xFFEFF2F7), color: _ink);
}

class _RideTile extends StatelessWidget {
  const _RideTile({
    required this.estimate,
    required this.selected,
    required this.promo,
    required this.enabled,
    required this.onTap,
    required this.onInfo,
  });

  final FareEstimate estimate;
  final bool selected;
  final PromoQuote? promo;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onInfo;

  String get _supply {
    final eta = estimate.pickupEtaSeconds;
    if (eta == null) return 'No drivers nearby right now';
    final minutes = (eta / 60).round().clamp(1, 999);
    return '$minutes min away';
  }

  @override
  Widget build(BuildContext context) {
    final colors = _vehicleColors(estimate);
    final fare = estimate.fare.estimatedFare;
    final promo = this.promo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        button: true,
        label:
            '${estimate.displayName}, ${RideFormat.money(promo?.payableFare ?? fare)}, $_supply',
        child: Material(
          color: selected ? const Color(0xFFF3F7FF) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? _blue : _line,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.tint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      rideTypeIcon(estimate.rideType, iconKey: estimate.icon),
                      color: colors.color,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                estimate.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: _ink,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 28,
                              height: 24,
                              child: IconButton(
                                tooltip:
                                    'Fare details for ${estimate.displayName}',
                                onPressed: onInfo,
                                padding: EdgeInsets.zero,
                                iconSize: 16,
                                icon: const Icon(
                                  Icons.info_outline_rounded,
                                  color: _muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _supply,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: estimate.pickupEtaSeconds == null
                                ? const Color(0xFFB45309)
                                : const Color(0xFF475569),
                          ),
                        ),
                        Text(
                          '~ ${RideFormat.duration(estimate.durationSeconds)} • '
                          '${RideFormat.distance(estimate.distanceMeters)}',
                          maxLines: 1,
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        RideFormat.money(promo?.payableFare ?? fare),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      if (promo != null)
                        Text(
                          RideFormat.money(fare),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _muted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  _Radio(selected: selected),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? _blue : const Color(0xFFCBD5E1),
          width: selected ? 6 : 1.5,
        ),
      ),
    );
  }
}

class _RideTileSkeleton extends StatelessWidget {
  const _RideTileSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
        ),
        child: Row(
          children: [
            bar(56, 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(110, 12),
                  const SizedBox(height: 6),
                  bar(80, 10),
                  const SizedBox(height: 6),
                  bar(120, 10),
                ],
              ),
            ),
            bar(48, 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Promo, assurances, confirm
// ─────────────────────────────────────────────────────────────────────────────

class _PromoRow extends StatelessWidget {
  const _PromoRow({
    required this.promo,
    required this.saved,
    required this.problem,
    required this.enabled,
    required this.onApply,
    required this.onRemove,
  });

  final PromoQuote? promo;

  /// The rider's saved code (Offers tab), applied automatically when it fits.
  final PromoOffer? saved;

  /// Why the saved code does not apply to this ride.
  final String? problem;
  final bool enabled;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final promo = this.promo;
    final saved = this.saved;
    const green = Color(0xFF15803D);
    final String title;
    if (promo != null) {
      title = '${promo.code} applied · you save ${RideFormat.money(promo.discount)}';
    } else if (saved != null) {
      title = problem == null ? 'Applying ${saved.code}…' : '${saved.code} saved';
    } else {
      title = 'Apply a promo code';
    }
    final removable = promo != null || saved != null;
    return Material(
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _line),
      ),
      child: InkWell(
        onTap: enabled && promo == null ? onApply : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(
                Icons.local_offer_outlined,
                size: 18,
                color: promo == null ? _muted : green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: promo == null ? _ink : green,
                      ),
                    ),
                    if (promo == null && problem != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          problem!,
                          style: const TextStyle(fontSize: 12, color: _red),
                        ),
                      ),
                  ],
                ),
              ),
              if (removable)
                IconButton(
                  tooltip: 'Remove promo',
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.close_rounded, size: 18),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.chevron_right_rounded, color: _muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Assurances extends StatelessWidget {
  const _Assurances();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String title, String subtitle) => Expanded(
      child: Row(
        children: [
          Icon(icon, size: 20, color: _ink),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Row(
      children: [
        item(Icons.sell_outlined, 'Best Price', 'Affordable rides'),
        item(Icons.verified_user_outlined, 'Safe & Secure', 'Verified drivers'),
        item(Icons.schedule_rounded, 'Reliable', 'On-time pickup'),
      ],
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _blue,
          disabledBackgroundColor: busy
              ? _blue.withValues(alpha: 0.85)
              : const Color(0xFFCBD5E1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: busy
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Requesting your ride…',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              )
            : Row(
                children: [
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: _ink, size: 22),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
