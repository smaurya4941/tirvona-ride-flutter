import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/profile_tab.dart';
import '../../account/presentation/widgets/profile_avatar.dart';
import '../../auth/presentation/session_controller.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../rides/application/booking_controller.dart';
import '../../rides/application/ride_providers.dart';
import '../../rides/application/ride_resume.dart';
import '../../rides/domain/promo_models.dart';
import '../../rides/domain/ride_formatters.dart';
import '../../rides/presentation/customer/customer_home_tab.dart';
import '../../rides/presentation/customer/promo_code_sheet.dart';
import '../../rides/presentation/ride_history_tab.dart';
import '../../rides/presentation/widgets/ride_widgets.dart';
import '../payments/screens/payment_history_tab.dart';

/// Customer shell: Home (booking), Rides (history), Offers & Payments, Profile.
class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({super.key});

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_resumeActiveRide());
  }

  /// App restart during a ride: go straight back to the live map. The
  /// tracking screen then joins the ride room and re-syncs from REST.
  Future<void> _resumeActiveRide() async {
    try {
      final ride = await ref.read(activeRideProvider.future);
      if (ride == null || !mounted) return;
      if (!ref.read(rideResumeGateProvider).shouldResume(ride.id)) return;
      unawaited(context.push(AppRoutes.customerRide(ride.id)));
    } catch (_) {
      // Home shows the active-ride card and a retry; nothing to do here.
    }
  }

  static const _titles = ['Tirvona Rides', 'Your rides', 'Offers & Promos', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).user;

    return Scaffold(
      key: _scaffoldKey,
      // Home tab renders its own full-bleed map header with hamburger and branding.
      appBar: _index == 0
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF1F5F9),
                ),
              ),
              title: Text(
                _titles[_index],
                style: const TextStyle(
                  color: AppColors.midnightBlue,
                  fontWeight: FontWeight.w800,
                  fontSize: 18.5,
                  letterSpacing: -0.3,
                ),
              ),
              actions: const [
                NotificationBell(isDriver: false),
                SizedBox(width: 8),
              ],
            ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                color: AppColors.midnightBlue,
              ),
              currentAccountPicture: user == null
                  ? null
                  : ProfileAvatar(user: user, radius: 36),
              accountName: Text(
                user?.displayName ?? 'Rider',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              accountEmail: Text(
                user?.phone ?? '',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_rounded, color: Color(0xFF2563EB)),
              title: const Text('Home'),
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _index = 0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.access_time_rounded, color: Color(0xFF2563EB)),
              title: const Text('Your Rides'),
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _index = 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_offer_outlined, color: Color(0xFF2563EB)),
              title: const Text('Offers & Discounts'),
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _index = 2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.credit_card_rounded, color: Color(0xFF2563EB)),
              title: const Text('Payments & History'),
              onTap: () {
                Navigator.of(context).pop();
                setState(() => _index = 2);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.shield_outlined, color: AppColors.bhagwa),
              title: const Text('Safety & Emergency Contacts'),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(context.push(AppRoutes.customerEmergencyContacts));
              },
            ),
            ListTile(
              leading: const Icon(Icons.headset_mic_outlined, color: AppColors.bhagwa),
              title: const Text('Help & Support'),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(context.push(AppRoutes.customerSupport));
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border_rounded, color: Color(0xFF2563EB)),
              title: const Text('Saved places'),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(context.push(AppRoutes.customerSavedPlaces));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(context.push(AppRoutes.customerSettings));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('Log out', style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.of(context).pop();
                ref.read(sessionControllerProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          CustomerHomeTab(
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            onSelectTab: (index) => setState(() => _index = index),
          ),
          if (_index == 1)
            const RideHistoryTab(rideRoute: AppRoutes.customerRide)
          else
            const SizedBox.shrink(),
          if (_index == 2)
            const _OffersAndPaymentsTab()
          else
            const SizedBox.shrink(),
          const ProfileTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFF1F5F9), width: 1),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.white,
          elevation: 0,
          height: 64,
          indicatorColor: AppColors.bhagwaLight,
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: AppColors.bhagwa),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.access_time_rounded),
              selectedIcon:
                  Icon(Icons.access_time_filled_rounded, color: AppColors.bhagwa),
              label: 'Rides',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_offer_outlined),
              selectedIcon:
                  Icon(Icons.local_offer_rounded, color: AppColors.bhagwa),
              label: 'Offers',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded, color: AppColors.bhagwa),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Offers tab: enter a code or pick a live offer (saved now, applied
/// automatically on "Choose a ride"), then the payment history.
class _OffersAndPaymentsTab extends ConsumerStatefulWidget {
  const _OffersAndPaymentsTab();

  @override
  ConsumerState<_OffersAndPaymentsTab> createState() =>
      _OffersAndPaymentsTabState();
}

class _OffersAndPaymentsTabState extends ConsumerState<_OffersAndPaymentsTab> {
  /// The offer code being checked by its "Use" button.
  String? _using;

  void _confirm(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSheet() async =>
      _confirm(await showPromoCodeSheet(context));

  Future<void> _use(PromoOffer offer) async {
    setState(() => _using = offer.code);
    try {
      _confirm(await usePromoCode(ref, offer.code));
    } on ApiException catch (error) {
      _confirm(error.message);
    } catch (error) {
      _confirm(errorMessage(error));
    } finally {
      if (mounted) setState(() => _using = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offers = ref.watch(promoOffersProvider);
    final saved = ref.watch(
      bookingControllerProvider.select((booking) => booking.savedPromo),
    );
    final applied = ref.watch(
      bookingControllerProvider.select((booking) => booking.promo),
    );
    final activeCode = applied?.code ?? saved?.code;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(promoOffersProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: AppColors.bhagwaLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.bhagwa.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: AppColors.bhagwa,
                    child: Icon(Icons.discount_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Have a Promo Code?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.midnightBlue,
                          ),
                        ),
                        Text(
                          'Apply to get instant discounts on your next ride',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.bhagwaDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _openSheet,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.midnightBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, 36), // Override the global double.infinity width
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ),
          if (activeCode != null) ...[
            const SizedBox(height: 12),
            _SavedPromoBanner(
              code: activeCode,
              line: applied != null
                  ? 'Applied to the ride you are booking · you save '
                        '${RideFormat.money(applied.discount)}'
                  : 'Saved · applied automatically when you choose a ride',
              onRemove: ref.read(bookingControllerProvider.notifier).removePromo,
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Active Offers',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          offers.when(
            data: (list) {
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No offers right now. Check back soon!\n'
                      'Got a code? Tap Apply above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final offer in list)
                    PromoOfferCard(
                      offer: offer,
                      saved: activeCode == offer.code,
                      onUse: _using != null ? null : () => _use(offer),
                    ),
                ],
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => Center(
              child: Column(
                children: [
                  const Text('Unable to load offers right now.'),
                  TextButton(
                    onPressed: () => ref.invalidate(promoOffersProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 10),
          const Text(
            'Payment History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const SizedBox(
            height: 350,
            child: PaymentHistoryTab(),
          ),
        ],
      ),
    );
  }
}

/// The rider's saved or applied code, with a way to drop it.
class _SavedPromoBanner extends StatelessWidget {
  const _SavedPromoBanner({
    required this.code,
    required this.line,
    required this.onRemove,
  });

  final String code;
  final String line;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF15803D);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: green.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: green,
                  ),
                ),
                Text(line, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove promo',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
