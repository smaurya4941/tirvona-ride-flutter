import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../../app/router/app_routes.dart';
import '../../../../core/config/app_config_provider.dart';
import '../../../../core/location/driver_fix.dart' show distanceMeters;
import '../../../../core/theme/app_colors.dart';
import '../../../account/presentation/widgets/profile_avatar.dart';
import '../../../auth/presentation/session_controller.dart';
import '../../../branding/presentation/brand_logo.dart';
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
import '../../application/ride_providers.dart';
import '../../domain/promo_models.dart';
import '../../domain/ride_models.dart';
import '../widgets/ride_widgets.dart';
import 'home_map.dart';
import 'promo_code_sheet.dart';

/// A pickup this close to the device's last fix is "Your current location".
const _currentLocationMeters = 100.0;

const _ink = AppColors.midnightBlue;
const _muted = Color(0xFF64748B);
const _blue = AppColors.bhagwa;
const _line = Color(0xFFE2E8F0);

/// Rider Home: live map with free cars around the pickup, then a sheet with
/// the greeting, pickup and "Where to?", Home/Work/Recent shortcuts, popular
/// destinations and the offers carousel.
class CustomerHomeTab extends ConsumerStatefulWidget {
  const CustomerHomeTab({super.key, this.onOpenDrawer, this.onSelectTab});

  final VoidCallback? onOpenDrawer;
  final ValueChanged<int>? onSelectTab;

  @override
  ConsumerState<CustomerHomeTab> createState() => _CustomerHomeTabState();
}

class _CustomerHomeTabState extends ConsumerState<CustomerHomeTab> {
  final _map = GlobalKey<HomeMapState>();

  @override
  void initState() {
    super.initState();
    // Like opening Uber: the pickup fills itself from the device location.
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
    } else {
      _map.currentState?.recenter();
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
      // No pickup yet (location off): ask for it next.
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

  /// "Good morning, Radha" (or just "Good morning").
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

    final topInset = MediaQuery.paddingOf(context).top;
    // The compact sheet leaves more of the screen to the map.
    final mapHeight = MediaQuery.sizeOf(context).height * 0.44;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: mapHeight,
            child: HomeMap(
              key: _map,
              pickup: pickup,
              fallbackCenter: lastFix == null
                  ? null
                  : LatLng(lastFix.latitude, lastFix.longitude),
              // A fix means the location permission is granted.
              showMyLocation: lastFix != null,
              padding: EdgeInsets.only(top: topInset + 64, bottom: 28),
            ),
          ),

          // Menu, brand, notifications and profile over the map.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _TopBar(
                  onMenu: widget.onOpenDrawer,
                  onProfile: () => widget.onSelectTab?.call(3),
                ),
              ),
            ),
          ),

          Positioned(
            right: 16,
            top: mapHeight - 76,
            child: _RoundButton(
              tooltip: 'Use my current location',
              onPressed: booking.locatingPickup ? null : _locatePickup,
              child: booking.locatingPickup
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.gps_fixed_rounded, color: _ink, size: 26),
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
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _greeting(user?.firstName),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      'Let\'s get you there!',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (activeRide.value case final ride?) ...[
                      _ActiveRideCard(ride: ride),
                      const SizedBox(height: 10),
                    ],
                    if (unpaidRide.value case final ride?) ...[
                      UnpaidRideCard(ride: ride),
                      const SizedBox(height: 10),
                    ],

                    _TripCard(
                      pickupLabel: pickup == null || pickupIsHere
                          ? 'Your current location'
                          : 'Pickup',
                      pickupAddress: booking.locatingPickup
                          ? 'Finding your location…'
                          : pickup?.address ?? 'Set your pickup location',
                      pickupPending: booking.locatingPickup || pickup == null,
                      destination: booking.destination?.title,
                      onPickup: () => _openSearch(PlaceField.pickup),
                      onDestination: () => _openSearch(PlaceField.destination),
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
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        for (final kind in SavedPlaceKind.values) ...[
                          Expanded(
                            child: _ShortcutChip(
                              icon: savedPlaceIcon(kind),
                              title: kind.label,
                              subtitle:
                                  saved.value?[kind]?.title ??
                                  (saved.isLoading ? '…' : 'Add'),
                              subtitleIsAction:
                                  saved.value?[kind] == null &&
                                  !saved.isLoading,
                              onTap: () =>
                                  _openSavedPlace(kind, saved.value?[kind]),
                              onLongPress: saved.value?[kind] == null
                                  ? null
                                  : () => showSavedPlaceOptions(
                                      context,
                                      ref,
                                      kind,
                                    ),
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
                            onTap: () => _openSearch(PlaceField.destination),
                          ),
                        ),
                      ],
                    ),

                    _PopularDestinations(
                      onSelect: _chooseDestination,
                      onSeeAll: () => _openSearch(PlaceField.destination),
                    ),
                    const SizedBox(height: 16),
                    const _OffersCarousel(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onMenu, required this.onProfile});

  final VoidCallback? onMenu;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final unread = ref.watch(unreadCountProvider);

    return Row(
      children: [
        _RoundButton(
          tooltip: 'Menu',
          onPressed: onMenu,
          child: const Icon(Icons.menu_rounded, color: _ink, size: 26),
        ),
        const SizedBox(width: 12),
        const BrandLogo(height: 46),
        const Spacer(),
        IconButton(
          tooltip: unread > 0
              ? '$unread unread notifications'
              : 'Notifications',
          onPressed: () =>
              unawaited(context.push(AppRoutes.customerNotifications)),
          icon: Badge(
            isLabelVisible: unread > 0,
            smallSize: 10,
            backgroundColor: const Color(0xFFEF4444),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: _ink,
              size: 30,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Semantics(
          button: true,
          label: 'Profile',
          child: GestureDetector(
            onTap: onProfile,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: user == null
                  ? const CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.bhagwaLight,
                      child: Text(
                        '?',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.bhagwaDark,
                        ),
                      ),
                    )
                  : ProfileAvatar(user: user, radius: 24),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        padding: const EdgeInsets.all(11),
        icon: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trip card: pickup and destination as two compact rows (Uber style)
// ─────────────────────────────────────────────────────────────────────────────

/// Height of one row of the trip card.
const _tripRowHeight = 52.0;

/// Width of the leading column holding the pickup dot, connector and drop
/// square; row dividers start after it so they line up with the text.
const _tripGutter = 36.0;

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.pickupLabel,
    required this.pickupAddress,
    required this.pickupPending,
    required this.destination,
    required this.onPickup,
    required this.onDestination,
    this.onSwap,
  });

  final String pickupLabel;
  final String pickupAddress;

  /// Locating or not set yet: the address reads as a hint.
  final bool pickupPending;
  final String? destination;
  final VoidCallback onPickup;
  final VoidCallback onDestination;

  /// Shown only once both ends are set.
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _line),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              _TripRow(
                semanticLabel: '$pickupLabel: $pickupAddress',
                marker: const _TripMarker.pickup(),
                onTap: onPickup,
                trailingSpace: onSwap != null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pickupLabel,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _blue,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      pickupAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: pickupPending ? _muted : _ink,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(
                height: 1,
                thickness: 1,
                indent: _tripGutter,
                color: _line,
              ),
              _TripRow(
                semanticLabel: destination == null
                    ? 'Where to?'
                    : 'Destination: $destination',
                marker: const _TripMarker.destination(),
                onTap: onDestination,
                trailingSpace: onSwap != null,
                trailing: onSwap == null
                    ? const Icon(Icons.search_rounded, color: _ink, size: 20)
                    : null,
                child: Text(
                  destination ?? 'Where to?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: destination == null
                        ? FontWeight.w500
                        : FontWeight.w600,
                    color: destination == null ? _muted : _ink,
                  ),
                ),
              ),
            ],
          ),
          // Dotted connector between the pickup dot and the drop square.
          const Positioned(
            left: _tripGutter / 2 - 0.75,
            top: _tripRowHeight / 2 + 7,
            height: _tripRowHeight - 14,
            child: _Connector(),
          ),
          if (onSwap != null)
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  tooltip: 'Swap pickup and destination',
                  onPressed: onSwap,
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    minimumSize: const Size(34, 34),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(
                    Icons.swap_vert_rounded,
                    color: _ink,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({
    required this.semanticLabel,
    required this.marker,
    required this.onTap,
    required this.child,
    required this.trailingSpace,
    this.trailing,
  });

  final String semanticLabel;
  final Widget marker;
  final VoidCallback onTap;
  final Widget child;

  /// Leaves room on the right for the swap button that overlays both rows.
  final bool trailingSpace;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: _tripRowHeight,
          child: Row(
            children: [
              SizedBox(
                width: _tripGutter,
                child: Center(child: marker),
              ),
              Expanded(child: child),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              SizedBox(width: trailingSpace ? 52 : 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripMarker extends StatelessWidget {
  const _TripMarker.pickup() : _pickup = true;
  const _TripMarker.destination() : _pickup = false;

  final bool _pickup;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: _pickup ? _blue : _ink,
        shape: _pickup ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: _pickup ? null : BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: (_pickup ? _blue : _ink).withValues(alpha: 0.18),
            spreadRadius: 3,
          ),
        ],
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dots = (constraints.maxHeight / 5).floor();
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < dots; i++)
              Container(
                width: 1.5,
                height: 2.5,
                color: const Color(0xFFCBD5E1),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home / Work / Recent shortcuts (compact chips)
// ─────────────────────────────────────────────────────────────────────────────

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.subtitleIsAction = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// "Add" / "See all": drawn in the accent colour, like a link.
  final bool subtitleIsAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: Material(
        color: const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _line),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: _ink, size: 16),
                ),
                const SizedBox(width: 7),
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
                          fontWeight: FontWeight.w600,
                          color: _ink,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: subtitleIsAction
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: subtitleIsAction ? _blue : _muted,
                          height: 1.25,
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

// Popular destinations (admin-managed, nearest first)
// ─────────────────────────────────────────────────────────────────────────────

class _PopularDestinations extends ConsumerWidget {
  const _PopularDestinations({required this.onSelect, required this.onSeeAll});

  final ValueChanged<Place> onSelect;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = (ref.watch(popularPlacesProvider).value ?? const [])
        .where((place) => place.hasCoordinates)
        .toList();
    // No places near the rider (or the list failed): leave the space to the
    // offers rather than show an empty row.
    if (places.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
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
                  ),
                ),
              ),
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: _blue,
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
          const SizedBox(height: 2),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: places.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
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
      ),
    );
  }
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
    return SizedBox(
      width: 146,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _line),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  place.secondaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _muted),
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
// Offers carousel: the brand banner, then each live promo code
// ─────────────────────────────────────────────────────────────────────────────

class _OffersCarousel extends ConsumerStatefulWidget {
  const _OffersCarousel();

  @override
  ConsumerState<_OffersCarousel> createState() => _OffersCarouselState();
}

class _OffersCarouselState extends ConsumerState<_OffersCarousel> {
  static const _advanceEvery = Duration(seconds: 6);

  final _pages = PageController();
  Timer? _timer;
  int _page = 0;
  int _count = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_advanceEvery, (_) {
      if (!mounted || _count < 2 || !_pages.hasClients) return;
      unawaited(
        _pages.animateToPage(
          (_page + 1) % _count,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offers = ref.watch(promoOffersProvider).value ?? const <PromoOffer>[];
    _count = 1 + offers.length;
    if (_page >= _count) _page = 0;

    return Column(
      children: [
        SizedBox(
          height: 108,
          // Fixed-height slides: cap very large text scales so they fit.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: PageView.builder(
              controller: _pages,
              itemCount: _count,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) => index == 0
                  ? const _BrandBanner()
                  : _OfferBanner(
                      offer: offers[index - 1],
                      onTap: () => showPromoCodeSheet(context),
                    ),
            ),
          ),
        ),
        if (_count > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _count; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _page ? _ink : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BrandBanner extends StatelessWidget {
  const _BrandBanner();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            bottom: -8,
            child: Icon(
              Icons.location_city_rounded,
              size: 120,
              color: Colors.green.shade800.withValues(alpha: 0.16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
            child: Row(
              children: [
                // Shrinks rather than overflows with large accessibility text.
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ride Anywhere\nWith Tirvona',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            height: 1.15,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Safe. Reliable. Affordable.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF166534),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 104,
                  height: 72,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_car_filled_rounded,
                        color: _ink,
                        size: 34,
                      ),
                      SizedBox(height: 2),
                      BrandLogo(height: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferBanner extends StatelessWidget {
  const _OfferBanner({required this.offer, required this.onTap});

  final PromoOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(20),
      color: const Color(0xFFFFF4E5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      offer.title.isEmpty ? offer.summary : offer.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      offer.description ?? '${offer.summary} on your next ride',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.bhagwa, width: 1.2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'USE CODE',
                      style: TextStyle(
                        fontSize: 10,
                        color: _muted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      offer.code,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.bhagwaDark,
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

// ─────────────────────────────────────────────────────────────────────────────
// Ongoing ride and location problems
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
