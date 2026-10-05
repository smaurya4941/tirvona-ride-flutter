import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../core/location/driver_fix.dart' show distanceMeters;
import '../../../../core/theme/app_colors.dart';
import '../../../account/presentation/widgets/profile_avatar.dart';
import '../../../auth/presentation/session_controller.dart';
import '../../../customer/payments/widgets/payment_widgets.dart';
import '../../../notifications/state/notification_providers.dart';
import '../../../places/application/current_location.dart';
import '../../../places/application/popular_places.dart';
import '../../../places/application/recent_places.dart';
import '../../../places/application/saved_places.dart';
import '../../../places/domain/place_suggestion.dart';
import '../../../places/domain/saved_place.dart';
import '../../../places/presentation/location_feedback.dart';
import '../../../places/presentation/saved_place_actions.dart';
import '../../application/booking_controller.dart';
import '../../application/nearby_drivers.dart';
import '../../application/ride_providers.dart';
import '../../domain/nearby_driver.dart';
import '../../domain/promo_models.dart';
import '../../domain/ride_models.dart';
import '../widgets/ride_widgets.dart';
import 'promo_code_sheet.dart';

/// A pickup this close to the device's last fix is "Your current location".
const _currentLocationMeters = 100.0;

const _ink = AppColors.midnightBlue;
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);

/// Rider Home: a map-free, vertically scrollable content-first dashboard.
///
/// Layout hierarchy:
/// 1. Compact Header (Tirvona logo, locality context, notifications & profile)
/// 2. Greeting & live nearby drivers indicator
/// 3. Active / Unpaid ride alert cards (if ongoing)
/// 4. Primary Booking Card (Current location + "Where to?" CTA + Swap)
/// 5. Saved Places (Home, Work, Recent)
/// 6. Popular Destinations (horizontal cards with photos)
/// 7. Ride Types / Quick Booking (Bike, Auto, Cab)
/// 8. Offers & Promotions (dynamic promo cards)
/// 9. Promotional Brand Banner
class CustomerHomeTab extends ConsumerStatefulWidget {
  const CustomerHomeTab({super.key, this.onOpenDrawer, this.onSelectTab});

  final VoidCallback? onOpenDrawer;
  final ValueChanged<int>? onSelectTab;

  @override
  ConsumerState<CustomerHomeTab> createState() => _CustomerHomeTabState();
}

class _CustomerHomeTabState extends ConsumerState<CustomerHomeTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(bookingControllerProvider.notifier).ensurePickup());
      }
    });
  }

  void _openSearch(PlaceField field) =>
      unawaited(context.push(AppRoutes.customerPlaceSearchFor(field.name)));

  Future<void> _locatePickup() async {
    final error = await ref
        .read(bookingControllerProvider.notifier)
        .useCurrentLocationForPickup();
    if (!mounted) return;
    if (error != null) {
      showLocationError(context, ref, error);
    }
  }

  void _chooseDestination(Place place) {
    final pickup = ref.read(bookingControllerProvider).pickup;
    if (pickup != null &&
        distanceMeters(
              pickup.latitude,
              pickup.longitude,
              place.latitude,
              place.longitude,
            ) <
            50) {
      showErrorSnack(
        context,
        const UserFacingError(
          'Pickup and destination can\'t be the same place.',
        ),
      );
      return;
    }
    ref.read(bookingControllerProvider.notifier).setDestination(place);
    if (ref.read(bookingControllerProvider).hasTrip) {
      unawaited(ref.read(bookingControllerProvider.notifier).loadEstimates());
      unawaited(context.push(AppRoutes.customerRideOptions));
    } else {
      _openSearch(PlaceField.pickup);
    }
  }

  void _openSavedPlace(SavedPlaceKind kind, Place? saved) {
    if (saved != null) {
      _chooseDestination(saved);
    } else {
      unawaited(context.push(AppRoutes.customerSavePlace(kind.name)));
    }
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(unpaidRideProvider)
      ..invalidate(activeRideProvider)
      ..invalidate(popularPlacesProvider)
      ..invalidate(savedPlacesProvider)
      ..invalidate(rideHistoryDestinationsProvider)
      ..invalidate(promoOffersProvider);
    await ref.read(activeRideProvider.future);
  }

  static String _greeting(String? firstName) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final name = firstName?.trim() ?? '';
    return name.isEmpty ? part : '$part, $name';
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingControllerProvider);
    final activeRide = ref.watch(activeRideProvider);
    final unpaidRide = ref.watch(unpaidRideProvider);
    final saved = ref.watch(savedPlacesProvider);
    final user = ref.watch(sessionControllerProvider).user;
    final pickup = booking.pickup;
    final pickupError = booking.pickupLocationError;

    final lastFix = ref.read(deviceLocationProvider).lastPoint;
    final pickupIsHere =
        pickup != null &&
        lastFix != null &&
        distanceMeters(
              lastFix.latitude,
              lastFix.longitude,
              pickup.latitude,
              pickup.longitude,
            ) <
            _currentLocationMeters;

    final nearbyDrivers = pickup == null
        ? const <NearbyDriver>[]
        : ref
                  .watch(
                    nearbyDriversProvider(
                      nearbyDriversArea(pickup.latitude, pickup.longitude),
                    ),
                  )
                  .value ??
              const <NearbyDriver>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.bhagwa,
          child: Stack(
            children: [
              // Ambient top aura backdrop
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 260,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.bhagwaLight.withValues(alpha: 0.45),
                          const Color(0xFFF8FAFC).withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // 1. Compact Header
                  SliverToBoxAdapter(
                    child: CustomerHomeHeader(
                      onMenu: widget.onOpenDrawer,
                      onProfile: () => widget.onSelectTab?.call(3),
                      localityText: pickup?.title,
                    ),
                  ),

                  // Main Vertically Scrollable Content
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate.fixed([
                        // 2. Greeting Section
                        CustomerHomeGreeting(
                          greeting: _greeting(user?.firstName),
                          nearbyCount: nearbyDrivers.length,
                        ),
                        const SizedBox(height: 16),

                        // Active or Unpaid ongoing rides (if any)
                        if (activeRide.value case final ride?) ...[
                          _ActiveRideCard(ride: ride),
                          const SizedBox(height: 14),
                        ],
                        if (unpaidRide.value case final ride?) ...[
                          UnpaidRideCard(ride: ride),
                          const SizedBox(height: 14),
                        ],

                        // 3. Primary Booking Card
                        PrimaryBookingCard(
                          pickupLabel: pickup == null || pickupIsHere
                              ? 'Your current location'
                              : 'Pickup',
                          pickupAddress: booking.locatingPickup
                              ? 'Finding your location…'
                              : (pickup?.address ?? 'Set your pickup location'),
                          pickupPending: booking.locatingPickup || pickup == null,
                          destination: booking.destination?.title,
                          locatingPickup: booking.locatingPickup,
                          onLocatePickup: _locatePickup,
                          onPickupTap: () => _openSearch(PlaceField.pickup),
                          onDestinationTap: () =>
                              _openSearch(PlaceField.destination),
                          onSwap: pickup != null && booking.destination != null
                              ? ref.read(bookingControllerProvider.notifier).swap
                              : null,
                        ),
                        if (pickupError != null && pickup == null)
                          _PickupLocationHint(
                            error: pickupError,
                            onRetry: _locatePickup,
                            onSearch: () => _openSearch(PlaceField.pickup),
                          ),
                        const SizedBox(height: 16),

                        // Tirvona Circuit: multi-stop packages.
                        RideCircuitEntryCard(
                          onTap: () => context.push(AppRoutes.customerCircuits),
                        ),
                        const SizedBox(height: 22),

                        // 4. Saved Places
                        SavedPlacesSection(
                          savedPlaces: saved.value,
                          isLoading: saved.isLoading,
                          onOpenSavedPlace: _openSavedPlace,
                          onRecentTap: () => _openSearch(PlaceField.destination),
                        ),
                        const SizedBox(height: 24),

                        // 5. Popular Destinations
                        PopularDestinationsSection(
                          onSelect: _chooseDestination,
                          onSeeAll: () => _openSearch(PlaceField.destination),
                        ),
                        const SizedBox(height: 24),

                        // 6. Offers & Promotions Banner
                        OffersSection(
                          onApplyOffer: (offer) => showPromoCodeSheet(context),
                        ),
                        const SizedBox(height: 20),

                        // 7. Trust & Assurance Bar
                        const TirvonaTrustBar(),
                        const SizedBox(height: 16),
                      ]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry point to Tirvona Circuit, next to the normal booking card.
class RideCircuitEntryCard extends StatelessWidget {
  const RideCircuitEntryCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.midnightBlue, Color(0xFF1E3A5F)],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.bhagwa,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.temple_hindu, color: Colors.white),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ride Circuit',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Explore multiple temples in one booking',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Compact Header (56-60px)
// ─────────────────────────────────────────────────────────────────────────────

class CustomerHomeHeader extends ConsumerWidget {
  const CustomerHomeHeader({
    super.key,
    required this.onMenu,
    required this.onProfile,
    this.localityText,
  });

  final VoidCallback? onMenu;
  final VoidCallback onProfile;
  final String? localityText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final unread = ref.watch(unreadCountProvider);

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular Framed Hamburger Menu Button
          Material(
            color: const Color(0xFFF8FAFC),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: IconButton(
              tooltip: 'Menu',
              onPressed: onMenu,
              icon: const Icon(
                Icons.menu_rounded,
                color: _ink,
                size: 22,
              ),
              splashRadius: 20,
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              padding: EdgeInsets.zero,
            ),
          ),

          // Locality Pill
          if (localityText != null && localityText!.trim().isNotEmpty) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 14,
                      color: AppColors.bhagwa,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        localityText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const Spacer(),

          // Notification Bell
          Material(
            color: const Color(0xFFF8FAFC),
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: IconButton(
              tooltip: unread > 0
                  ? '$unread unread notifications'
                  : 'Notifications',
              onPressed: () =>
                  unawaited(context.push(AppRoutes.customerNotifications)),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
              padding: EdgeInsets.zero,
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(
                  unread > 9 ? '9+' : '$unread',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                backgroundColor: const Color(0xFFEF4444),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: _ink,
                  size: 21,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Circular Profile Avatar with Brand Ring
          Semantics(
            button: true,
            label: 'Profile',
            child: GestureDetector(
              onTap: onProfile,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.bhagwa.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: user == null
                    ? const CircleAvatar(
                        radius: 17,
                        backgroundColor: AppColors.bhagwaLight,
                        child: Text(
                          '?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.bhagwaDark,
                          ),
                        ),
                      )
                    : ProfileAvatar(user: user, radius: 17),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Greeting Section
// ─────────────────────────────────────────────────────────────────────────────

class CustomerHomeGreeting extends StatelessWidget {
  const CustomerHomeGreeting({
    super.key,
    required this.greeting,
    this.nearbyCount = 0,
  });

  final String greeting;
  final int nearbyCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                greeting,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (nearbyCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dual-ring live radar pulsing dot
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Color(0xFF059669),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$nearbyCount rides nearby',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          "Let's get you there!",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: -0.6,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Primary Booking Card
// ─────────────────────────────────────────────────────────────────────────────

class PrimaryBookingCard extends StatelessWidget {
  const PrimaryBookingCard({
    super.key,
    required this.pickupLabel,
    required this.pickupAddress,
    required this.pickupPending,
    required this.destination,
    required this.locatingPickup,
    required this.onLocatePickup,
    required this.onPickupTap,
    required this.onDestinationTap,
    this.onSwap,
  });

  final String pickupLabel;
  final String pickupAddress;
  final bool pickupPending;
  final String? destination;
  final bool locatingPickup;
  final VoidCallback onLocatePickup;
  final VoidCallback onPickupTap;
  final VoidCallback onDestinationTap;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // Row 1: Pickup Location
          InkWell(
            onTap: onPickupTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.bhagwaLight,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.bhagwa.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: AppColors.bhagwa,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pickupLabel,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.bhagwa,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pickupAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: pickupPending ? _muted : _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (locatingPickup)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.bhagwa,
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Use my current location',
                      icon: const Icon(
                        Icons.gps_fixed_rounded,
                        size: 20,
                        color: _muted,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: onLocatePickup,
                    ),
                ],
              ),
            ),
          ),

          // Route Connector & Divider
          Row(
            children: [
              const SizedBox(width: 30),
              Container(
                width: 2,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 26),
              const Expanded(
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF1F5F9),
                ),
              ),
            ],
          ),

          // Row 2: Destination CTA ("Where to?")
          InkWell(
            onTap: onDestinationTap,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Icon(
                      Icons.search_rounded,
                      color: _ink,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination ?? 'Where to?',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: destination == null
                            ? FontWeight.w500
                            : FontWeight.w700,
                        color: destination == null ? _muted : _ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (onSwap != null)
                    IconButton(
                      tooltip: 'Swap pickup and destination',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF1F5F9),
                        minimumSize: const Size(34, 34),
                      ),
                      icon: const Icon(
                        Icons.swap_vert_rounded,
                        color: _ink,
                        size: 19,
                      ),
                      onPressed: onSwap,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bhagwa,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.bhagwa.withValues(alpha: 0.28),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Go',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ],
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

// ─────────────────────────────────────────────────────────────────────────────
// 4. Saved Places Section
// ─────────────────────────────────────────────────────────────────────────────

class SavedPlacesSection extends ConsumerWidget {
  const SavedPlacesSection({
    super.key,
    required this.savedPlaces,
    required this.isLoading,
    required this.onOpenSavedPlace,
    required this.onRecentTap,
  });

  final SavedPlaces? savedPlaces;
  final bool isLoading;
  final void Function(SavedPlaceKind kind, Place? saved) onOpenSavedPlace;
  final VoidCallback onRecentTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Saved places',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  unawaited(context.push(AppRoutes.customerSavedPlaces)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.bhagwa,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final kind in SavedPlaceKind.values) ...[
              Expanded(
                child: _ShortcutChip(
                  icon: savedPlaceIcon(kind),
                  title: kind.label,
                  subtitle:
                      savedPlaces?[kind]?.title ?? (isLoading ? '…' : 'Add'),
                  subtitleIsAction: savedPlaces?[kind] == null && !isLoading,
                  iconBgColor: kind == SavedPlaceKind.home
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFFFFBEB),
                  iconColor: kind == SavedPlaceKind.home
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFD97706),
                  iconBorderColor: kind == SavedPlaceKind.home
                      ? const Color(0xFFDBEAFE)
                      : const Color(0xFFFEF3C7),
                  onTap: () => onOpenSavedPlace(kind, savedPlaces?[kind]),
                  onLongPress: savedPlaces?[kind] == null
                      ? null
                      : () => showSavedPlaceOptions(context, ref, kind),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _ShortcutChip(
                icon: Icons.schedule_rounded,
                title: 'Recent',
                subtitle: 'See all',
                subtitleIsAction: true,
                iconBgColor: const Color(0xFFFAF5FF),
                iconColor: const Color(0xFF7C3AED),
                iconBorderColor: const Color(0xFFF3E8FF),
                onTap: onRecentTap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.subtitleIsAction = false,
    this.iconBgColor = const Color(0xFFF8FAFC),
    this.iconColor = _ink,
    this.iconBorderColor = const Color(0xFFE2E8F0),
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool subtitleIsAction;
  final Color iconBgColor;
  final Color iconColor;
  final Color iconBorderColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: iconBorderColor),
                  ),
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: subtitleIsAction
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: subtitleIsAction ? AppColors.bhagwa : _muted,
                        ),
                      ),
                    ],
                  ),
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
// 5. Popular Destinations Section (Max 4, in one row, name & location only)
// ─────────────────────────────────────────────────────────────────────────────

class PopularDestinationsSection extends ConsumerWidget {
  const PopularDestinationsSection({
    super.key,
    required this.onSelect,
    required this.onSeeAll,
  });

  final ValueChanged<Place> onSelect;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = (ref.watch(popularPlacesProvider).value ?? const [])
        .where((place) => place.hasCoordinates)
        .take(4)
        .toList();
    if (places.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Popular destinations',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.bhagwa,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: places.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final place = places[index];
              return _DestinationCard(
                place: place,
                onTap: () => onSelect(place.toPlace()),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DestinationBadgeTheme {
  const _DestinationBadgeTheme({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.borderColor,
  });

  final IconData icon;
  final Color color;
  final Color bgColor;
  final Color borderColor;
}

_DestinationBadgeTheme _categoryForPlace(String name, String secondary) {
  final text = '${name.toLowerCase()} ${secondary.toLowerCase()}';
  if (text.contains('mandir') ||
      text.contains('temple') ||
      text.contains('ashram') ||
      text.contains('ghat') ||
      text.contains('dham')) {
    return const _DestinationBadgeTheme(
      icon: Icons.temple_hindu_rounded,
      color: Color(0xFFEA580C),
      bgColor: Color(0xFFFFF7ED),
      borderColor: Color(0xFFFFEDD5),
    );
  }
  if (text.contains('hospital') ||
      text.contains('clinic') ||
      text.contains('med') ||
      text.contains('health')) {
    return const _DestinationBadgeTheme(
      icon: Icons.local_hospital_rounded,
      color: Color(0xFF059669),
      bgColor: Color(0xFFECFDF5),
      borderColor: Color(0xFFA7F3D0),
    );
  }
  if (text.contains('metro') ||
      text.contains('station') ||
      text.contains('railway') ||
      text.contains('junction')) {
    return const _DestinationBadgeTheme(
      icon: Icons.subway_rounded,
      color: Color(0xFF2563EB),
      bgColor: Color(0xFFEFF6FF),
      borderColor: Color(0xFFDBEAFE),
    );
  }
  if (text.contains('airport') || text.contains('aerodrome')) {
    return const _DestinationBadgeTheme(
      icon: Icons.flight_takeoff_rounded,
      color: Color(0xFF0284C7),
      bgColor: Color(0xFFF0F9FF),
      borderColor: Color(0xFFBAE6FD),
    );
  }
  if (text.contains('mall') ||
      text.contains('centre') ||
      text.contains('center') ||
      text.contains('plaza') ||
      text.contains('market') ||
      text.contains('sector')) {
    return const _DestinationBadgeTheme(
      icon: Icons.domain_rounded,
      color: Color(0xFF4F46E5),
      bgColor: Color(0xFFEEF2FF),
      borderColor: Color(0xFFE0E7FF),
    );
  }
  return const _DestinationBadgeTheme(
    icon: Icons.place_rounded,
    color: AppColors.bhagwa,
    bgColor: AppColors.bhagwaLight,
    borderColor: Color(0xFFFFEDD5),
  );
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.place,
    required this.onTap,
  });

  final PlaceSuggestion place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locationText = place.secondaryText.isNotEmpty
        ? place.secondaryText
        : place.address;
    final badge = _categoryForPlace(place.name, locationText);

    return SizedBox(
      width: 175,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: badge.bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: badge.borderColor),
                  ),
                  child: Icon(badge.icon, color: badge.color, size: 18),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locationText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
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
// 6. Offers & Promotions Banner
// ─────────────────────────────────────────────────────────────────────────────

class OffersSection extends ConsumerStatefulWidget {
  const OffersSection({
    super.key,
    required this.onApplyOffer,
  });

  final ValueChanged<PromoOffer> onApplyOffer;

  @override
  ConsumerState<OffersSection> createState() => _OffersSectionState();
}

class _OffersSectionState extends ConsumerState<OffersSection> {
  int _activePage = 0;

  static final _defaultOffer = PromoOffer(
    code: 'RIDE50',
    title: 'Ride More. Save More.',
    discountType: 'FLAT',
    discountValue: 50,
    description: 'Get ₹50 OFF on your next ride',
    endsAt: DateTime.now().add(const Duration(days: 30)),
  );

  @override
  Widget build(BuildContext context) {
    final offersAsync = ref.watch(promoOffersProvider);

    return offersAsync.when(
      loading: () => const _OfferBannerSkeleton(),
      error: (_, _) => _OfferBannerCard(
        offer: _defaultOffer,
        onTap: () => widget.onApplyOffer(_defaultOffer),
      ),
      data: (offers) {
        final list = offers.isNotEmpty ? offers : [_defaultOffer];

        if (list.length == 1) {
          return _OfferBannerCard(
            offer: list.first,
            index: 0,
            onTap: () => widget.onApplyOffer(list.first),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 114,
              child: PageView.builder(
                itemCount: list.length,
                onPageChanged: (index) => setState(() => _activePage = index),
                itemBuilder: (context, index) {
                  return _OfferBannerCard(
                    offer: list[index],
                    index: index,
                    onTap: () => widget.onApplyOffer(list[index]),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < list.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: _activePage == i ? 16 : 6,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _activePage == i
                          ? _OfferBannerCard
                              .themes[i % _OfferBannerCard.themes.length]
                              .codeColor
                          : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _OfferBannerTheme {
  const _OfferBannerTheme({
    required this.gradient,
    required this.shadowColor,
    required this.codeColor,
    required this.watermarkIcon,
    required this.boltColor,
  });

  final LinearGradient gradient;
  final Color shadowColor;
  final Color codeColor;
  final IconData watermarkIcon;
  final Color boltColor;
}

class _OfferBannerCard extends StatelessWidget {
  const _OfferBannerCard({
    required this.offer,
    required this.onTap,
    this.index = 0,
  });

  final PromoOffer offer;
  final VoidCallback onTap;
  final int index;

  static const List<_OfferBannerTheme> themes = [
    // Theme 0: Signature Tirvona Sunset Saffron
    _OfferBannerTheme(
      gradient: LinearGradient(
        colors: [Color(0xFF7C2D12), Color(0xFFC2410C), Color(0xFFEA580C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shadowColor: Color(0xFFEA580C),
      codeColor: Color(0xFFC2410C),
      watermarkIcon: Icons.local_offer_rounded,
      boltColor: AppColors.sacredGold,
    ),
    // Theme 1: Midnight Sapphire Blue
    _OfferBannerTheme(
      gradient: LinearGradient(
        colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF2563EB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shadowColor: Color(0xFF2563EB),
      codeColor: Color(0xFF1D4ED8),
      watermarkIcon: Icons.stars_rounded,
      boltColor: Color(0xFF93C5FD),
    ),
    // Theme 2: Deep Emerald Green
    _OfferBannerTheme(
      gradient: LinearGradient(
        colors: [Color(0xFF064E3B), Color(0xFF065F46), Color(0xFF059669)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shadowColor: Color(0xFF059669),
      codeColor: Color(0xFF047857),
      watermarkIcon: Icons.redeem_rounded,
      boltColor: Color(0xFF6EE7B7),
    ),
    // Theme 3: Regal Mulberry / Plum
    _OfferBannerTheme(
      gradient: LinearGradient(
        colors: [Color(0xFF4A044E), Color(0xFF701A75), Color(0xFF9D174D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shadowColor: Color(0xFF9D174D),
      codeColor: Color(0xFF831843),
      watermarkIcon: Icons.card_giftcard_rounded,
      boltColor: Color(0xFFF472B6),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = themes[index % themes.length];
    final title = offer.title.isEmpty ? offer.summary : offer.title;
    final description =
        offer.description ?? '${offer.summary} on your next ride';
    final summaryText =
        offer.summary.isNotEmpty ? offer.summary : 'SPECIAL OFFER';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: theme.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned(
                right: -10,
                bottom: -15,
                child: Icon(
                  theme.watermarkIcon,
                  size: 115,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.bolt_rounded,
                                  size: 12,
                                  color: theme.boltColor,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    summaryText.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'USE CODE',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            offer.code,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: theme.codeColor,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferBannerSkeleton extends StatelessWidget {
  const _OfferBannerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 104,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 70,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 150,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 110,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 76,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Trust & Assurance Bar
// ─────────────────────────────────────────────────────────────────────────────

class TirvonaTrustBar extends StatelessWidget {
  const TirvonaTrustBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _TrustBadge(
            icon: Icons.verified_user_rounded,
            color: Color(0xFF059669),
            label: 'Verified Drivers',
          ),
          _TrustDivider(),
          _TrustBadge(
            icon: Icons.payments_rounded,
            color: Color(0xFFD97706),
            label: 'Fair Fares',
          ),
          _TrustDivider(),
          _TrustBadge(
            icon: Icons.support_agent_rounded,
            color: Color(0xFF2563EB),
            label: '24/7 Support',
          ),
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustDivider extends StatelessWidget {
  const _TrustDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFE2E8F0),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active Ride and Location Error Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.midnightBlue,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go(AppRoutes.customerRide(ride.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                child: Icon(rideTypeIcon(ride.rideType), color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.status.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'To ${ride.destination.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickupLocationHint extends ConsumerWidget {
  const _PickupLocationHint({
    required this.error,
    required this.onRetry,
    required this.onSearch,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = error is LocationFailure ? error as LocationFailure : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.location_off_outlined,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failure?.message ?? errorMessage(error),
                  style: const TextStyle(color: AppColors.onSurfaceVariant),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    if (failure != null && failure.needsSettings)
                      TextButton(
                        onPressed: () => unawaited(
                          ref
                              .read(deviceLocationProvider)
                              .openSettings(failure),
                        ),
                        child: const Text('Open settings'),
                      )
                    else
                      TextButton(
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                    TextButton(
                      onPressed: onSearch,
                      child: const Text('Search pickup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
