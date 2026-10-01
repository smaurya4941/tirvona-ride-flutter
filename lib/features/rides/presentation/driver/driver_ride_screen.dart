import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/location/driver_location_service.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/error_banner.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../../shared/widgets/loading_filled_button.dart';
import '../../../safety/widgets/sos_button.dart';
import '../../application/ride_providers.dart';
import '../../data/ride_repository.dart';
import '../../domain/ride_formatters.dart';
import '../../domain/ride_models.dart';
import '../widgets/cancel_ride_sheet.dart';
import '../widgets/ride_map.dart';
import '../widgets/ride_widgets.dart';
import 'ride_request_card.dart';

/// The driver's side of one ride. Each button asks the server to move the
/// ride on; the screen only ever shows what the server says the status is.
class DriverRideScreen extends ConsumerWidget {
  const DriverRideScreen({super.key, required this.rideId});

  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rideAsync = ref.watch(rideProvider(rideId));
    final ride = rideAsync.value;

    void leave() {
      ref.invalidate(driverDashboardProvider);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.driverHome);
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: leave,
        ),
        title: Text(ride == null ? 'Ride' : 'Ride ${ride.rideCode}'),
        actions: [
          // Once the driver is committed to the ride, until it ends.
          if (ride != null &&
              (ride.status == RideStatus.driverAccepted ||
                  ride.status == RideStatus.driverArrived ||
                  ride.status == RideStatus.rideStarted))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SosButton(rideId: ride.id, compact: true),
            ),
        ],
      ),
      body: ride != null
          ? Column(
              children: [
                if (rideAsync.hasError) const ReconnectingBanner(),
                Expanded(
                  child: _DriverRideBody(ride: ride, onLeave: leave),
                ),
              ],
            )
          : rideAsync.hasError
          ? LoadErrorView(
              error: rideAsync.error!,
              onRetry: () => ref.invalidate(rideProvider(rideId)),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class _DriverRideBody extends ConsumerStatefulWidget {
  const _DriverRideBody({required this.ride, required this.onLeave});

  final Ride ride;
  final VoidCallback onLeave;

  @override
  ConsumerState<_DriverRideBody> createState() => _DriverRideBodyState();
}

class _DriverRideBodyState extends ConsumerState<_DriverRideBody> {
  final _otpController = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(RideRepository repository) action,
  ) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action(ref.read(rideRepositoryProvider));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      // Resync with the server whatever happened.
      ref
        ..invalidate(rideProvider(widget.ride.id))
        ..invalidate(driverDashboardProvider);
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _complete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete this ride?'),
        content: Text(
          'Confirm the customer has reached ${widget.ride.destination.title}.',
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
    if (confirmed == true) await _run((repo) => repo.complete(widget.ride.id));
  }

  Future<void> _cancel() async {
    final cancelled = await showCancelRideSheet(
      context,
      ride: widget.ride,
      asDriver: true,
    );
    if (cancelled == null) return;
    ref
      ..invalidate(rideProvider(widget.ride.id))
      ..invalidate(driverDashboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;

    if (ride.status == RideStatus.driverAssigned) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [RideRequestCard(ride: ride)],
      );
    }

    final (
      IconData icon,
      String title,
      String subtitle,
    ) = switch (ride.status) {
      RideStatus.driverAccepted => (
        Icons.near_me,
        'Head to pickup',
        'Pick up ${ride.customer?.name ?? 'the customer'} at ${ride.pickup.title}.',
      ),
      RideStatus.driverArrived => (
        Icons.pin,
        'Ask for the OTP',
        'The customer sees a 4-digit code in their app. Enter it to start.',
      ),
      RideStatus.rideStarted => (
        Icons.route,
        'Trip in progress',
        'Drop the customer at ${ride.destination.title}.',
      ),
      RideStatus.completed => (
        Icons.check_circle,
        'Ride completed',
        ride.fare.hasDiscount
            ? 'Trip fare ${RideFormat.money(ride.fare.fare)}. The customer pays '
                  '${RideFormat.money(ride.fare.payable)} after a Tirvona promo; '
                  'you still earn on the full fare.'
            : 'Fare for this trip: ${RideFormat.money(ride.fare.payable)}.',
      ),
      RideStatus.cancelled => (
        Icons.cancel,
        'Ride cancelled',
        switch (ride.cancellation?.cancelledBy) {
          'CUSTOMER' => 'The customer cancelled this ride.',
          'DRIVER' => 'You cancelled this ride.',
          _ => 'This ride was cancelled.',
        },
      ),
      _ => (
        Icons.info_outline,
        'Ride no longer assigned',
        'This ride is not assigned to you any more.',
      ),
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (!ride.status.isTerminal) ...[
          _DriverRideMap(ride: ride),
          const SizedBox(height: 12),
        ],
        Card(
          color: ride.status.isTerminal ? Colors.white : AppColors.midnightBlue,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 36,
                  color: ride.status.isTerminal
                      ? AppColors.bhagwa
                      : Colors.white,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: ride.status.isTerminal
                              ? AppColors.midnightBlue
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: ride.status.isTerminal
                              ? AppColors.onSurfaceVariant
                              : Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (ride.customer case final customer? when !ride.status.isTerminal)
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.bhagwaLight,
                child: Icon(Icons.person, color: AppColors.bhagwa),
              ),
              title: Text(
                customer.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: customer.phone == null ? null : Text(customer.phone!),
              trailing: customer.phone == null
                  ? null
                  : IconButton(
                      tooltip: 'Copy phone number',
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: customer.phone!),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied ${customer.phone}')),
                        );
                      },
                    ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
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
                      label: 'Trip',
                      value: RideFormat.distance(ride.distanceMeters),
                    ),
                    StatTile(
                      icon: Icons.currency_rupee,
                      label: ride.fare.hasDiscount
                          ? 'Collect'
                          : ride.fare.finalFare != null
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
          _CustomerPaymentCard(ride: ride),
          const SizedBox(height: 12),
          FareBreakdownCard(
            title: 'Fare',
            fare: ride.fare,
            distanceMeters: ride.distanceMeters,
            durationSeconds: ride.durationSeconds,
          ),
        ],
        const SizedBox(height: 20),
        ErrorBanner(message: _error),
        ..._actions(ride),
      ],
    );
  }

  List<Widget> _actions(Ride ride) {
    final cancelButton = TextButton(
      onPressed: _working ? null : _cancel,
      style: TextButton.styleFrom(foregroundColor: AppColors.error),
      child: const Text('Cancel ride'),
    );

    switch (ride.status) {
      case RideStatus.driverAccepted:
        return [
          LoadingFilledButton(
            label: "I've arrived at pickup",
            icon: Icons.where_to_vote,
            isLoading: _working,
            onPressed: () => _run((repo) => repo.markArrived(ride.id)),
          ),
          const SizedBox(height: 8),
          cancelButton,
        ];
      case RideStatus.driverArrived:
        return [
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: 16,
            ),
            decoration: InputDecoration(
              hintText: '• • • •',
              counterText: '',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          LoadingFilledButton(
            label: 'Start ride',
            icon: Icons.play_arrow,
            isLoading: _working,
            onPressed: _otpController.text.length == 4
                ? () => _run((repo) async {
                    await repo.start(ride.id, otp: _otpController.text);
                    _otpController.clear();
                  })
                : null,
          ),
          const SizedBox(height: 8),
          cancelButton,
        ];
      case RideStatus.rideStarted:
        return [
          LoadingFilledButton(
            label: 'Complete ride',
            icon: Icons.flag,
            isLoading: _working,
            onPressed: _complete,
          ),
        ];
      case RideStatus.completed ||
          RideStatus.cancelled ||
          RideStatus.noDriverAvailable ||
          RideStatus.searching ||
          RideStatus.driverAssigned:
        return [
          FilledButton(
            onPressed: widget.onLeave,
            child: const Text('Back to dashboard'),
          ),
          if (ride.status == RideStatus.completed ||
              ride.status == RideStatus.cancelled)
            TextButton.icon(
              onPressed: () => context.push(
                AppRoutes.newComplaintFor(true, rideId: ride.id),
              ),
              icon: const Icon(Icons.support_agent_outlined),
              label: const Text('Report an issue with this ride'),
            ),
        ];
    }
  }
}

/// The driver's own view of the ride: their live GPS position against the
/// pickup (before the trip) or the destination (during it), plus a hand-off
/// to the phone's navigation app for turn-by-turn directions.
class _DriverRideMap extends ConsumerWidget {
  const _DriverRideMap({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fix = ref.watch(
      driverLocationServiceProvider.select((state) => state.lastFix),
    );
    final onTrip = ride.status == RideStatus.rideStarted;
    final target = onTrip ? ride.destination : ride.pickup;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: RideMap(
              pickup: ride.pickup,
              destination: ride.destination,
              stage: onTrip ? RideMapStage.trip : RideMapStage.approach,
              driverIcon: rideTypeIcon(ride.rideType),
              padding: const EdgeInsets.all(36),
              routePolyline: ride.routePolyline,
              liveRoute: watchLiveRoute(ref, ride),
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
            leading: Icon(
              onTrip ? Icons.flag : Icons.person_pin_circle,
              color: onTrip ? AppColors.bhagwa : AppColors.success,
            ),
            title: Text(
              onTrip ? 'Drop at ${target.title}' : 'Pick up at ${target.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: FilledButton.tonalIcon(
              // Compact: the theme's full-width size would crush the title.
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () => _navigate(context, target),
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

/// Whether the customer has paid for a completed ride, and how. Updates
/// live from `ride.payment_updated`; the earning appears once it is paid.
class _CustomerPaymentCard extends ConsumerWidget {
  const _CustomerPaymentCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(ridePaymentUpdatesProvider(ride.id)).value ?? ride;
    final status = latest.paymentStatus;
    final paid = status.isPaid;
    final cash = paid && (latest.payment?.isCash ?? false);
    final amount = RideFormat.money(
      latest.payment?.amount ?? ride.fare.payable,
    );

    if (cash) {
      return Card(
        color: AppColors.bhagwaLight,
        child: ListTile(
          leading: const Icon(Icons.payments, color: AppColors.bhagwaDark),
          title: Text(
            'Collect $amount in cash',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'The customer is paying you in cash. Your earning is in the '
            "Earnings tab; Tirvona's commission on it is added to your dues.",
          ),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: Icon(
          paid ? Icons.check_circle : Icons.hourglass_top,
          color: paid ? AppColors.success : AppColors.warning,
        ),
        title: Text(
          paid
              ? 'Paid online · ${RideFormat.paymentMethod(latest.payment?.method)}'
              : status.label,
        ),
        subtitle: Text(
          paid
              ? 'Your earning for this ride is in the Earnings tab.'
              : 'The customer pays online or in cash. Your earning is added '
                    'once they have paid.',
        ),
      ),
    );
  }
}
