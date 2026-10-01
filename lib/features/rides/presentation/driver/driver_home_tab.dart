import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/location/driver_location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/load_error_view.dart';
import '../../../auth/presentation/session_controller.dart';
import '../../application/ride_providers.dart';
import '../../data/ride_repository.dart';
import '../../domain/ride_formatters.dart';
import '../../domain/ride_models.dart';
import '../widgets/ride_widgets.dart';
import 'location_status_card.dart';
import 'ride_request_card.dart';

/// Driver dashboard: duty toggle, live GPS status, today's numbers, the
/// current ride, and — while online and free — incoming requests pushed in
/// real time.
class DriverHomeTab extends ConsumerStatefulWidget {
  const DriverHomeTab({super.key});

  @override
  ConsumerState<DriverHomeTab> createState() => _DriverHomeTabState();
}

class _DriverHomeTabState extends ConsumerState<DriverHomeTab> {
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    // A new request arriving is worth a buzz.
    ref.listenManual(driverRequestsProvider, (previous, next) {
      final before = previous?.value?.length ?? 0;
      final after = next.value?.length ?? 0;
      if (after > before) HapticFeedback.heavyImpact();
    });
  }

  /// Going online needs a real GPS position: without one the server would
  /// have the driver online but never matchable. The backend decides whether
  /// the driver may go online; this only gathers what it needs.
  Future<void> _setOnline(bool online) async {
    setState(() => _toggling = true);
    try {
      Place? position;
      if (online) {
        position = await _acquirePosition();
        if (position == null) return;
      }
      await ref
          .read(rideRepositoryProvider)
          .setAvailability(online: online, location: position);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      // The duty binding re-modes location streaming from the new dashboard.
      ref.invalidate(driverDashboardProvider);
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<Place?> _acquirePosition() async {
    final location = ref.read(driverLocationServiceProvider.notifier);
    final access = await location.checkAccess(request: true);
    if (access != LocationAccess.granted) {
      if (mounted) await showLocationAccessDialog(context, ref, access);
      return null;
    }
    final fix = await location.currentFix();
    if (fix == null) {
      if (mounted) {
        showErrorSnack(
          context,
          const UserFacingError(
            'We could not get your location. Move to open sky and try again.',
          ),
        );
      }
      return null;
    }
    return Place(
      address: 'Current location',
      latitude: fix.latitude,
      longitude: fix.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;
    final dashboardAsync = ref.watch(driverDashboardProvider);
    final dashboard = dashboardAsync.value;

    if (dashboard == null) {
      return dashboardAsync.hasError
          ? LoadErrorView(
              error: dashboardAsync.error!,
              onRetry: () => ref.invalidate(driverDashboardProvider),
            )
          : const Center(child: CircularProgressIndicator());
    }

    final currentRide = dashboard.currentRide;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(driverDashboardProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Namaste, ${user?.firstName ?? 'Driver'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.midnightBlue,
            ),
          ),
          const SizedBox(height: 16),
          _DutyCard(
            dashboard: dashboard,
            toggling: _toggling,
            onChanged: _setOnline,
          ),
          const SizedBox(height: 12),
          LocationStatusCard(dashboard: dashboard),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  StatTile(
                    icon: Icons.local_taxi_outlined,
                    label: "Today's rides",
                    value: '${dashboard.todayRides}',
                  ),
                  // Net of commission, paid rides only (earnings ledger).
                  StatTile(
                    icon: Icons.account_balance_wallet_outlined,
                    label: "Today's earnings",
                    value: RideFormat.money(dashboard.todayEarnings),
                  ),
                  StatTile(
                    icon: Icons.star_outline,
                    label: 'Rating',
                    value: dashboard.totalRides == 0
                        ? 'New'
                        : dashboard.ratingAverage.toStringAsFixed(1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (currentRide != null)
            _CurrentRideCard(ride: currentRide)
          else if (dashboard.isOnline)
            const _IncomingRequests()
          else
            const _OfflineHint(),
        ],
      ),
    );
  }
}

class _DutyCard extends StatelessWidget {
  const _DutyCard({
    required this.dashboard,
    required this.toggling,
    required this.onChanged,
  });

  final DriverDashboard dashboard;
  final bool toggling;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final online = dashboard.isOnline;
    final vehicle = dashboard.vehicle;
    final status = !online
        ? "You're offline"
        : dashboard.isAvailable
        ? "You're online — waiting for rides"
        : "You're online — on a ride";
    return Card(
      color: online ? AppColors.midnightBlue : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: online ? Colors.white : AppColors.midnightBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vehicle == null
                        ? 'Your active vehicle is used when you go online'
                        : '${vehicle.vehicleType} · ${vehicle.registrationNumber}',
                    style: TextStyle(
                      color: online
                          ? Colors.white.withValues(alpha: 0.75)
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (toggling)
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Transform.scale(
                scale: 1.2,
                child: Switch(
                  value: online,
                  activeThumbColor: AppColors.bhagwa,
                  onChanged: onChanged,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IncomingRequests extends ConsumerWidget {
  const _IncomingRequests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(driverRequestsProvider);
    final list = requests.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ride requests',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        // Offers are pushed live; while the socket is down the list is
        // re-checked over REST every few seconds, so say so.
        const ReconnectingBanner(
          message: 'Reconnecting… still checking for requests',
        ),
        if (list == null && requests.hasError)
          Text(
            errorMessage(requests.error!),
            style: const TextStyle(color: AppColors.error),
          )
        else if (list == null || list.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Looking for rides near you…',
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        else
          for (final ride in list)
            RideRequestCard(key: ValueKey(ride.id), ride: ride),
      ],
    );
  }
}

class _CurrentRideCard extends StatelessWidget {
  const _CurrentRideCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(AppRoutes.driverRide(ride.id)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Current ride',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push(AppRoutes.driverRide(ride.id)),
                child: const Text('Open ride'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineHint extends StatelessWidget {
  const _OfflineHint();

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: AppColors.bhagwaLight,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.power_settings_new, color: AppColors.bhagwaDark),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Go online to start receiving ride requests near you.',
                style: TextStyle(color: AppColors.bhagwaDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
