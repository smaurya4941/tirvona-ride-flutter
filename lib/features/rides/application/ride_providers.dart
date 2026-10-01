import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ride_repository.dart';
import '../domain/live_tracking.dart';
import '../domain/ride_models.dart';
import 'ride_updates_source.dart';

/// Live view of one ride (REST snapshot + realtime events).
/// `ref.invalidate(rideProvider(id))` forces a fresh snapshot.
final rideProvider = StreamProvider.autoDispose.family<Ride, String>(
  (ref, rideId) => ref.watch(rideUpdatesSourceProvider).watchRide(rideId),
);

/// Requests offered to the signed-in driver; only listened to while online.
final driverRequestsProvider = StreamProvider.autoDispose<List<Ride>>(
  (ref) => ref.watch(rideUpdatesSourceProvider).watchDriverRequests(),
);

/// Live driver positions for a ride (`ride.location_updated`). Screens fall
/// back to `ride.driver.location` (last known) until the first one arrives.
final liveDriverPositionProvider = StreamProvider.autoDispose
    .family<DriverPosition, String>(
      (ref, rideId) =>
          ref.watch(rideUpdatesSourceProvider).watchDriverPosition(rideId),
    );

/// The freshest of the live position and the ride view's last known one.
DriverPosition? latestDriverPosition(
  DriverPosition? live,
  DriverPosition? known,
) {
  if (live == null) return known;
  if (known == null) return live;
  return known.updatedAt.isAfter(live.updatedAt) ? known : live;
}

/// How often screens re-read the live route. Cheap: the server only calls
/// Google when the driver has moved or the route has aged (see
/// ROUTES_LIVE_REFRESH_* on the API), otherwise it answers from cache.
const liveRoutePollInterval = Duration(seconds: 20);

/// The driver's live road route for a ride in [status] (driver → pickup
/// while accepted, driver → destination while started). Keyed on the status
/// too, so a stage change fetches the new leg at once. Polls while watched;
/// a failed poll keeps the last route instead of blanking the map.
final liveRouteProvider = StreamProvider.autoDispose
    .family<LiveRoute?, ({String rideId, RideStatus status})>((
      ref,
      key,
    ) async* {
      final repository = ref.watch(rideRepositoryProvider);
      var disposed = false;
      ref.onDispose(() => disposed = true);
      var hasRoute = false;
      while (!disposed) {
        try {
          final route = await repository.liveRoute(key.rideId);
          hasRoute = route != null;
          if (!disposed) yield route;
        } on Object {
          // Offline or a server hiccup: keep showing the previous route.
          if (!hasRoute && !disposed) yield null;
        }
        await Future<void>.delayed(liveRoutePollInterval);
      }
    });

/// The live route for [ride] while it can have one (accepted or started);
/// otherwise null without polling.
LiveRoute? watchLiveRoute(WidgetRef ref, Ride ride) {
  if (ride.status != RideStatus.driverAccepted &&
      ride.status != RideStatus.rideStarted) {
    return null;
  }
  return ref
      .watch(liveRouteProvider((rideId: ride.id, status: ride.status)))
      .value;
}

/// `ride.driver_arriving` for a ride, once it has happened.
final arrivingNoticeProvider = StreamProvider.autoDispose
    .family<ArrivingNotice, String>(
      (ref, rideId) =>
          ref.watch(rideUpdatesSourceProvider).watchArriving(rideId),
    );

/// `ride.payment_updated` pushes for one ride (customer and driver).
final ridePaymentUpdatesProvider = StreamProvider.autoDispose
    .family<Ride, String>(
      (ref, rideId) =>
          ref.watch(rideUpdatesSourceProvider).watchPaymentUpdates(rideId),
    );

/// The signed-in user's in-flight ride (customer: any active; driver:
/// accepted → started), used to resume after an app restart.
/// Bookable ride types for the home screen strip.
final bookableRideTypesProvider =
    FutureProvider.autoDispose<List<RideTypeInfo>>(
      (ref) => ref.watch(rideRepositoryProvider).rideTypes(),
    );

final activeRideProvider = FutureProvider.autoDispose<Ride?>(
  (ref) => ref.watch(rideRepositoryProvider).getActiveRide(),
);

final driverDashboardProvider = FutureProvider.autoDispose<DriverDashboard>(
  (ref) => ref.watch(rideRepositoryProvider).dashboard(),
);

/// The customer's most recent completed ride that is still unpaid, if any
/// (home screen "Pay now" card).
final unpaidRideProvider = FutureProvider.autoDispose<Ride?>((ref) async {
  final page = await ref.watch(rideRepositoryProvider).history(limit: 10);
  for (final ride in page.items) {
    if (ride.awaitsPayment) return ride;
  }
  return null;
});
