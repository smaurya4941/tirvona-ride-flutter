import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/location/driver_fix.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../circuit/presentation/widgets/circuit_widgets.dart';
import '../../../customer/payments/widgets/payment_widgets.dart';
import '../../../customer/rating/widgets/ride_rating_card.dart';
import '../../../safety/widgets/share_ride_button.dart';
import '../../../safety/widgets/sos_button.dart';
import '../../application/booking_controller.dart';
import '../../application/ride_providers.dart';
import '../../domain/live_tracking.dart';
import '../../domain/ride_formatters.dart';
import '../../domain/ride_models.dart';
import '../widgets/call_button.dart';
import '../widgets/cancel_ride_sheet.dart';
import '../widgets/ride_map.dart';
import '../widgets/ride_widgets.dart';

/// Share of the screen the ride sheet covers when it first opens.
const _sheetInitial = 0.44;

/// The customer's live ride: a map with pickup, destination, route and the
/// driver moving in real time, under a sheet that follows the ride
/// Searching → Assigned → On the way → Arriving → Arrived (OTP) → On trip →
/// Completed. Every state shown comes from the server (pushed over the
/// socket, re-synced over REST after any reconnect).
class RideTrackingScreen extends ConsumerWidget {
  const RideTrackingScreen({super.key, required this.rideId});

  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A tactile nudge when the ride moves on while the phone is in hand.
    ref.listen(rideProvider(rideId), (previous, next) {
      final before = previous?.value?.status;
      final after = next.value?.status;
      if (before != null && after != null && before != after) {
        HapticFeedback.mediumImpact();
      }
      // Ride completed → payment screen (the final fare is now known).
      final ride = next.value;
      if (before != null &&
          before != RideStatus.completed &&
          ride != null &&
          ride.awaitsPayment) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            context.push(AppRoutes.customerRidePayment(ride.id));
          }
        });
      }
    });
    // A payment settled elsewhere (webhook, another device): re-read the ride.
    ref.listen(ridePaymentUpdatesProvider(rideId), (_, next) {
      if (next.hasValue) ref.invalidate(rideProvider(rideId));
    });

    final rideAsync = ref.watch(rideProvider(rideId));
    final ride = rideAsync.value;

    if (ride == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.close),
            onPressed: () => context.go(AppRoutes.customerHome),
          ),
          title: const Text('Your ride'),
        ),
        body: rideAsync.hasError
            ? LoadErrorView(
                error: rideAsync.error!,
                onRetry: () => ref.invalidate(rideProvider(rideId)),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }

    final mapBottomInset = MediaQuery.sizeOf(context).height * _sheetInitial;
    return CircuitNoticeListener(
      ride: ride,
      asDriver: false,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: _TrackingMap(
                ride: ride,
                padding: EdgeInsets.fromLTRB(48, 120, 48, mapBottomInset + 32),
              ),
            ),
            Positioned(top: 0, left: 0, right: 0, child: _TopBar(ride: ride)),
            DraggableScrollableSheet(
              initialChildSize: _sheetInitial,
              minChildSize: 0.26,
              maxChildSize: 0.92,
              snap: true,
              snapSizes: const [_sheetInitial],
              builder: (context, controller) =>
                  _RideSheet(ride: ride, controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

RideMapStage _stageFor(RideStatus status) => switch (status) {
  RideStatus.driverAccepted ||
  RideStatus.driverArrived => RideMapStage.approach,
  RideStatus.rideStarted => RideMapStage.trip,
  _ => RideMapStage.overview,
};

/// From assignment until the trip ends (the server re-checks, and also
/// allows a short grace period after the ride that the screen doesn't need).
bool _sosAvailable(RideStatus status) =>
    status == RideStatus.driverAssigned ||
    status == RideStatus.driverAccepted ||
    status == RideStatus.driverArrived ||
    status == RideStatus.rideStarted;

bool _showsDriverOnMap(RideStatus status) =>
    status == RideStatus.driverAccepted ||
    status == RideStatus.driverArrived ||
    status == RideStatus.rideStarted;

DriverPosition? _driverPosition(WidgetRef ref, Ride ride) {
  if (!_showsDriverOnMap(ride.status)) return null;
  return latestDriverPosition(
    ref.watch(liveDriverPositionProvider(ride.id)).value,
    ride.driver?.location,
  );
}

class _TrackingMap extends ConsumerWidget {
  const _TrackingMap({required this.ride, required this.padding});

  final Ride ride;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circuit = ride.circuit;
    return RideMap(
      pickup: ride.pickup,
      // A circuit is driven stop by stop: the map points at the current stop.
      destination: circuit == null
          ? ride.destination
          : circuitMapTarget(circuit),
      stops: circuit == null ? const [] : circuitMapStops(circuit),
      stage: _stageFor(ride.status),
      driver: _driverPosition(ref, ride),
      driverIcon: rideTypeIcon(ride.rideType),
      padding: padding,
      routePolyline: ride.routePolyline,
      liveRoute: watchLiveRoute(ref, ride),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                IconButton.filled(
                  tooltip: 'Home',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.midnightBlue,
                  ),
                  icon: const Icon(Icons.close),
                  onPressed: () => context.go(AppRoutes.customerHome),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(blurRadius: 6, color: Colors.black12),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Ride ${ride.rideCode}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.midnightBlue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          RideStatusChip(status: ride.status),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Always in reach, never in the way of the ride controls.
                if (_sosAvailable(ride.status))
                  SosButton(rideId: ride.id, compact: true)
                else
                  const SizedBox(width: 40),
              ],
            ),
          ),
          const ReconnectingBanner(),
        ],
      ),
    );
  }
}

class _RideSheet extends ConsumerWidget {
  const _RideSheet({required this.ride, required this.controller});

  final Ride ride;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driver = ride.driver;
    final position = _driverPosition(ref, ride);
    final arriving = ride.status == RideStatus.driverAccepted
        ? ref.watch(arrivingNoticeProvider(ride.id)).value
        : null;

    return Material(
      color: AppColors.templeIvory,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          _StatusHero(
            ride: ride,
            driverPosition: position,
            arriving: arriving,
            liveRoute: watchLiveRoute(ref, ride),
          ),
          const SizedBox(height: 16),
          if (ride.otp case final otp?) ...[
            _OtpCard(otp: otp),
            const SizedBox(height: 12),
          ],
          if (driver != null &&
              ride.status != RideStatus.cancelled &&
              ride.status != RideStatus.noDriverAvailable) ...[
            _DriverCard(driver: driver),
            const SizedBox(height: 12),
          ],
          if (ride.isCircuit) ...[
            CircuitProgressCard(ride: ride),
            const SizedBox(height: 12),
          ],
          if (_sosAvailable(ride.status)) ...[
            ShareRideButton(rideId: ride.id),
            const SizedBox(height: 12),
          ],
          // A circuit's route is the stop list in the progress card above.
          if (!ride.isCircuit)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    RouteSummary(
                      pickup: ride.pickup,
                      destination: ride.destination,
                    ),
                    const Divider(height: 28),
                    Row(
                      children: [
                        StatTile(
                          icon: rideTypeIcon(ride.rideType),
                          label: 'Ride',
                          value: ride.rideType.label,
                        ),
                        StatTile(
                          icon: Icons.straighten,
                          label: 'Distance',
                          value: RideFormat.distance(ride.distanceMeters),
                        ),
                        StatTile(
                          icon: Icons.currency_rupee,
                          label: ride.fare.finalFare != null
                              ? 'Fare'
                              : 'Est. fare',
                          value: RideFormat.money(ride.fare.payable),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (ride.status == RideStatus.completed) ...[
            const SizedBox(height: 12),
            RidePaymentCard(ride: ride),
            if (ride.paymentStatus.isPaid) ...[
              const SizedBox(height: 12),
              RideRatingCard(rideId: ride.id),
            ],
            const SizedBox(height: 12),
            if (ride.isCircuit)
              CircuitBillCard(ride: ride)
            else
              FareBreakdownCard(
                title: 'Trip fare',
                fare: ride.fare,
                distanceMeters: ride.distanceMeters,
                durationSeconds: ride.durationSeconds,
              ),
          ],
          _Actions(ride: ride),
        ],
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({
    required this.ride,
    required this.driverPosition,
    required this.arriving,
    this.liveRoute,
  });

  final Ride ride;
  final DriverPosition? driverPosition;
  final ArrivingNotice? arriving;
  final LiveRoute? liveRoute;

  /// "about 6 min · 2.1 km away" along the roads when the server has a road
  /// route for this leg, else "1.2 km away" in a straight line from the
  /// latest driver position.
  String? _liveDistance() {
    final onTrip = ride.status == RideStatus.rideStarted;
    final route = liveRoute;
    final expectedStage = onTrip
        ? LiveRouteStage.trip
        : LiveRouteStage.approach;
    if (route != null && route.followsRoads && route.stage == expectedStage) {
      final eta = RideFormat.duration(route.duration.inSeconds);
      final distance = RideFormat.distance(route.distanceMeters);
      return onTrip
          ? 'about $eta · $distance to go'
          : 'about $eta · $distance away';
    }
    final position = driverPosition;
    if (position == null) return null;
    final circuit = ride.circuit;
    final target = onTrip
        ? (circuit == null ? ride.destination : circuitMapTarget(circuit))
        : ride.pickup;
    final meters = distanceMeters(
      position.latitude,
      position.longitude,
      target.latitude,
      target.longitude,
    ).round();
    return onTrip
        ? '${RideFormat.distance(meters)} to go'
        : '${RideFormat.distance(meters)} away';
  }

  @override
  Widget build(BuildContext context) {
    final driverName = ride.driver?.name ?? 'Your driver';
    final live = _liveDistance();
    final notice = arriving;
    final circuit = ride.circuit;
    final atStop = circuit?.currentStop;
    final (
      IconData icon,
      Color color,
      String title,
      String body,
    ) = switch (ride.status) {
      RideStatus.searching when circuit != null => (
        Icons.radar,
        AppColors.bhagwa,
        'Finding your driver',
        'Looking for a ${ride.rideType.label.toLowerCase()} for '
            '${circuit.name} near ${ride.pickup.title}…',
      ),
      RideStatus.rideStarted when circuit != null && circuit.hasException => (
        Icons.report_problem_outlined,
        AppColors.warning,
        'We are sorting out a stop',
        'Your driver reported a stop as unreachable. Tirvona support will '
            'decide how to continue in a moment.',
      ),
      RideStatus.rideStarted when circuit != null && atStop != null => (
        atStop.status.isAtStop ? Icons.temple_hindu : Icons.route,
        AppColors.bhagwa,
        atStop.status.isAtStop
            ? 'At ${atStop.name}'
            : 'Heading to ${atStop.name}',
        atStop.status.isAtStop
            ? 'Take your time. Your driver waits here; the included time '
                  'keeps running.'
            : 'Stop ${atStop.order} of ${circuit.stops.length}'
                  '${live == null ? '' : ' · $live'}.',
      ),
      RideStatus.rideStarted when circuit != null => (
        Icons.flag,
        AppColors.success,
        'All stops visited',
        'Your driver will now complete the circuit.',
      ),
      RideStatus.completed when circuit != null => (
        Icons.check_circle,
        AppColors.success,
        'Circuit complete',
        ride.paymentStatus.isPaid
            ? 'Paid ${RideFormat.money(ride.fare.payable)}. Thank you for '
                  'travelling with Tirvona.'
            : 'Final fare ${RideFormat.money(ride.fare.payable)}. Please '
                  'complete the payment.',
      ),
      RideStatus.searching => (
        Icons.radar,
        AppColors.bhagwa,
        'Finding your driver',
        'Looking for the nearest ${ride.rideType.label.toLowerCase()} '
            'near ${ride.pickup.title}…',
      ),
      RideStatus.driverAssigned => (
        Icons.person_search,
        AppColors.bhagwa,
        'Driver found',
        'Waiting for $driverName to confirm.',
      ),
      RideStatus.driverAccepted when notice != null => (
        Icons.near_me,
        AppColors.success,
        'Driver is arriving',
        '$driverName is almost at ${ride.pickup.title} — about '
            '${RideFormat.duration(notice.eta.inSeconds)}. Please be ready.',
      ),
      RideStatus.driverAccepted => (
        Icons.near_me,
        AppColors.midnightBlue,
        'Driver is on the way',
        '$driverName is heading to ${ride.pickup.title}'
            '${live == null ? '.' : ' · $live'}',
      ),
      RideStatus.driverArrived => (
        Icons.where_to_vote,
        AppColors.success,
        'Your driver has arrived',
        'Share the OTP below with your driver to start the ride.',
      ),
      RideStatus.rideStarted when ride.otp?.isEnd ?? false => (
        Icons.pin,
        AppColors.success,
        'Your driver is ending the trip',
        'If you have reached ${ride.destination.title}, read the OTP below '
            'to your driver to complete the ride.',
      ),
      RideStatus.rideStarted => (
        Icons.route,
        AppColors.bhagwa,
        'Ride in progress',
        'Heading to ${ride.destination.title}'
            '${live == null ? '' : ' · $live'}. Have a peaceful journey.',
      ),
      RideStatus.completed => (
        Icons.check_circle,
        AppColors.success,
        'You have arrived',
        ride.paymentStatus.isPaid
            ? 'Paid ${RideFormat.money(ride.fare.payable)}. Thank you for '
                  'riding with Tirvona.'
            : 'Trip fare ${RideFormat.money(ride.fare.payable)}. Please complete '
                  'the payment.',
      ),
      RideStatus.cancelled => (
        Icons.cancel,
        AppColors.onSurfaceVariant,
        'Ride cancelled',
        _cancellationText(ride.cancellation),
      ),
      RideStatus.noDriverAvailable => (
        Icons.hourglass_disabled,
        AppColors.error,
        'No drivers available',
        'All nearby drivers are busy right now. Please try again in a '
            'few minutes.',
      ),
    };

    final waiting =
        ride.status == RideStatus.searching ||
        ride.status == RideStatus.driverAssigned;
    return Row(
      children: [
        SizedBox.square(
          dimension: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (waiting)
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: color.withValues(alpha: 0.6),
                  ),
                ),
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, size: 28, color: color),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.midnightBlue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _cancellationText(RideCancellation? cancellation) {
    final who = switch (cancellation?.cancelledBy) {
      'CUSTOMER' => 'You cancelled this ride',
      'DRIVER' => 'Your driver had to cancel this ride',
      'ADMIN' => 'Tirvona support cancelled this ride',
      _ => 'This ride was cancelled',
    };
    final reason = cancellation?.reason;
    final text = reason == null || reason.isEmpty ? '$who.' : '$who: $reason';
    if (cancellation == null || !cancellation.hasFee) return text;
    return '$text\nCancellation fee ${RideFormat.money(cancellation.feeAmount)} '
        '(${cancellation.feeLabel}).';
  }
}

class _OtpCard extends StatelessWidget {
  const _OtpCard({required this.otp});

  final RideOtp otp;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.midnightBlue,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            Text(
              otp.isEnd ? 'Your end-of-trip OTP' : 'Your ride OTP',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final digit in otp.code.split(''))
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: 48,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      digit,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppColors.midnightBlue,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              otp.isEnd
                  ? 'Share this only once you have reached your destination.'
                  : 'Only share this with your driver, in person.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.driver});

  final RideDriverInfo driver;

  @override
  Widget build(BuildContext context) {
    final vehicle = driver.vehicle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.bhagwaLight,
              child: Text(
                driver.name.isEmpty ? '?' : driver.name[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bhagwaDark,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    driver.totalRides == 0
                        ? 'New driver'
                        : '★ ${driver.ratingAverage.toStringAsFixed(1)} · '
                              '${driver.totalRides} rides',
                    style: const TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                  if (vehicle != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSand,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Text(
                        vehicle.registrationNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    if (vehicle.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          vehicle.description,
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (driver.phone.isNotEmpty)
              CallIconButton(phone: driver.phone, name: driver.name),
          ],
        ),
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.ride});

  final Ride ride;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      final cancelled = await showCancelRideSheet(
        context,
        ride: widget.ride,
        asDriver: false,
      );
      if (cancelled == null) return;
      ref
        ..invalidate(rideProvider(widget.ride.id))
        ..invalidate(activeRideProvider);
      final fee = cancelled.cancellation;
      if (mounted && fee != null && fee.hasFee) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ride cancelled. A cancellation fee of '
              '${RideFormat.money(fee.feeAmount)} is due.',
            ),
          ),
        );
      }
    } finally {
      // Whatever happened, show the ride as the server has it now.
      ref.invalidate(rideProvider(widget.ride.id));
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _bookAgain() {
    final circuit = widget.ride.circuit;
    if (circuit != null) {
      ref.invalidate(activeRideProvider);
      context.go(AppRoutes.customerHome);
      context.push(AppRoutes.customerCircuit(circuit.packageId));
      return;
    }
    ref.read(bookingControllerProvider.notifier)
      ..setPickup(widget.ride.pickup)
      ..setDestination(widget.ride.destination)
      ..select(widget.ride.rideType);
    ref.invalidate(activeRideProvider);
    context.go(AppRoutes.customerHome);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.ride.status;
    final Widget child;
    if (status.customerCanCancel) {
      child = OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
        ),
        onPressed: _cancelling ? null : _cancel,
        icon: _cancelling
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.close),
        label: Text(widget.ride.isCircuit ? 'Cancel circuit' : 'Cancel ride'),
      );
    } else if (widget.ride.awaitsPayment) {
      child = FilledButton.icon(
        onPressed: () =>
            context.push(AppRoutes.customerRidePayment(widget.ride.id)),
        icon: const Icon(Icons.payments_outlined),
        label: Text('Pay ${RideFormat.money(widget.ride.fare.payable)}'),
      );
    } else if (status == RideStatus.completed) {
      child = FilledButton(
        onPressed: () {
          ref.invalidate(activeRideProvider);
          context.go(AppRoutes.customerHome);
        },
        child: const Text('Done'),
      );
    } else if (status == RideStatus.cancelled ||
        status == RideStatus.noDriverAvailable) {
      child = FilledButton.icon(
        onPressed: _bookAgain,
        icon: const Icon(Icons.refresh),
        label: const Text('Book again'),
      );
    } else {
      return const SizedBox.shrink();
    }
    final reportable =
        status == RideStatus.completed || status == RideStatus.cancelled;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            child,
            if (reportable)
              TextButton.icon(
                onPressed: () => context.push(
                  AppRoutes.newComplaintFor(false, rideId: widget.ride.id),
                ),
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('Report an issue with this ride'),
              ),
          ],
        ),
      ),
    );
  }
}
