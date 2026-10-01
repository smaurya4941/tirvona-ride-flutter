import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/driver_location_service.dart';
import '../../../core/location/location_tracking_policy.dart';
import '../../../core/realtime/realtime_models.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/session_controller.dart';
import '../data/ride_repository.dart';
import '../domain/ride_models.dart';
import 'ride_providers.dart';

/// How often to sample GPS, from what the server says the driver is doing.
LocationTrackingMode trackingModeFor(DriverDashboard dashboard) {
  if (!dashboard.isOnline) return LocationTrackingMode.off;
  return switch (dashboard.currentRide?.status) {
    RideStatus.driverAccepted ||
    RideStatus.driverArrived => LocationTrackingMode.toPickup,
    RideStatus.rideStarted => LocationTrackingMode.onTrip,
    _ => LocationTrackingMode.waiting,
  };
}

/// Ride events after which the driver's duty state (busy/available, current
/// ride) changed on the server.
const _dutyEvents = {
  RealtimeEvents.driverAccepted,
  RealtimeEvents.driverArrived,
  RealtimeEvents.started,
  RealtimeEvents.completed,
  RealtimeEvents.cancelled,
};

/// App-level wiring for an approved driver, mounted at the app root so it
/// survives every navigation (a ride screen, a backgrounded app):
///
/// * keeps the dashboard in sync with realtime ride events and reconnects;
/// * drives [DriverLocationService]'s mode from the dashboard — streaming
///   starts when the server says "online" (including after an app restart)
///   and stops when it says "offline";
/// * stops location entirely when the session is not an approved driver.
final driverDutyBindingProvider = Provider<void>((ref) {
  final user = ref.watch(sessionControllerProvider.select((s) => s.user));
  final location = ref.read(driverLocationServiceProvider.notifier);
  final isApprovedDriver =
      user?.role == UserRole.driver &&
      user?.driver?.driverStatus == DriverStatus.approved;
  if (!isApprovedDriver) {
    unawaited(location.stop());
    return;
  }

  final repository = ref.watch(rideRepositoryProvider);
  location.useRestFallback(repository.updateLocation);

  final realtime = ref.watch(realtimeClientProvider);
  final events = realtime.events
      .where((event) => _dutyEvents.contains(event.event))
      .listen((_) => ref.invalidate(driverDashboardProvider));
  final sessions = realtime.sessions.listen(
    (_) => ref.invalidate(driverDashboardProvider),
  );

  ref
    ..listen(driverDashboardProvider, (_, next) {
      final dashboard = next.value;
      if (dashboard != null) {
        unawaited(location.setMode(trackingModeFor(dashboard)));
      }
    }, fireImmediately: true)
    // The server stopped accepting fixes because it has us offline.
    ..listen(driverLocationServiceProvider.select((state) => state.rejection), (
      _,
      rejection,
    ) {
      if (rejection == 'DRIVER_OFFLINE') {
        ref.invalidate(driverDashboardProvider);
      }
    })
    ..onDispose(() {
      unawaited(events.cancel());
      unawaited(sessions.cancel());
    });
});
