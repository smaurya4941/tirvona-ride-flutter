import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../shared/widgets/profile_tab.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../rides/application/ride_providers.dart';
import '../../rides/application/ride_resume.dart';
import '../../rides/presentation/driver/driver_home_tab.dart';
import '../../rides/presentation/ride_history_tab.dart';
import '../account/data/driver_account_repository.dart';
import '../data/driver_repository.dart';
import '../earnings/screens/earnings_tab.dart';
import '../ratings/driver_ratings.dart';

/// Approved-driver shell: dashboard, ride history, earnings, profile. Only reachable once `driverStatus == APPROVED`.
class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key});

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_resumeCurrentRide());
  }

  /// App restart mid-ride: reopen the ride. Location streaming resumes on
  /// its own (the duty binding follows the dashboard's online state).
  Future<void> _resumeCurrentRide() async {
    try {
      final ride = (await ref.read(driverDashboardProvider.future)).currentRide;
      if (ride == null || !mounted) return;
      if (!ref.read(rideResumeGateProvider).shouldResume(ride.id)) return;
      unawaited(context.push(AppRoutes.driverRide(ride.id)));
    } catch (_) {
      // The dashboard shows its own error and retry.
    }
  }

  static const _titles = ['Home', 'Your rides', 'Earnings', 'Profile'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: const [NotificationBell(isDriver: true)],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const DriverHomeTab(),
          if (_index == 1)
            const RideHistoryTab(rideRoute: AppRoutes.driverRide)
          else
            const SizedBox.shrink(),
          // Mounted only while visible, so totals are fresh each time.
          if (_index == 2) const EarningsTab() else const SizedBox.shrink(),
          const _DriverProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Rides',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Earnings',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _DriverProfileTab extends ConsumerWidget {
  const _DriverProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(driverProfileProvider).value;
    final pendingUpdates =
        ref.watch(driverChangesProvider).value?.pending.length ?? 0;
    return ProfileTab(
      header: [
        Semantics(
          button: true,
          label: 'See all ratings and reviews',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push(AppRoutes.driverReviews),
            child: const DriverRatingCard(),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Driver details'),
                subtitle: Text(
                  profile == null
                      ? 'Licence and address'
                      : 'Code ${profile.driverCode} · licence and address',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.driverDetails),
              ),
              ListTile(
                leading: const Icon(Icons.local_taxi_outlined),
                title: const Text('Vehicle'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.driverVehicleDetails),
              ),
              ListTile(
                leading: const Icon(Icons.folder_copy_outlined),
                title: const Text('Documents'),
                subtitle: pendingUpdates == 0
                    ? const Text('Licence, ID, RC, insurance, permit')
                    : Text(
                        '$pendingUpdates update${pendingUpdates == 1 ? '' : 's'} '
                        'under review',
                      ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.driverDocuments),
              ),
              ListTile(
                leading: const Icon(Icons.reviews_outlined),
                title: const Text('Ratings & reviews'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.driverReviews),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
