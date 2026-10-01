import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/core/config/app_config.dart';
import 'package:tirvona_ride/core/config/app_config_provider.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/notifications/state/notification_providers.dart';
import 'package:tirvona_ride/features/places/application/current_location.dart';
import 'package:tirvona_ride/features/places/data/places_repository.dart';
import 'package:tirvona_ride/features/places/domain/place_suggestion.dart';
import 'package:tirvona_ride/features/places/domain/saved_place.dart';
import 'package:tirvona_ride/features/rides/application/booking_controller.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/nearby_driver.dart';
import 'package:tirvona_ride/features/rides/presentation/customer/customer_home_tab.dart';

import '../places/places_fakes.dart';

class _FixedUnread extends UnreadCountNotifier {
  _FixedUnread(this.count);

  final int count;

  @override
  int build() => count;
}

const _noidaCentre = PlaceSuggestion(
  id: 'popular:64f000000000000000000001',
  name: 'Noida City Centre',
  secondaryText: 'Sector 32, Noida',
  address: 'Noida City Centre, Sector 32, Noida',
  latitude: 28.5753,
  longitude: 77.3561,
  featured: true,
  imagePath: '/places/popular/64f000000000000000000001/image?v=abc',
);

void main() {
  late FakePlacesRepository places;
  late FakeRides rides;
  late FakeDeviceLocation device;
  ProviderContainer? container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    places = FakePlacesRepository()..popularPlaces = const [_noidaCentre];
    rides = FakeRides();
    device = FakeDeviceLocation()
      ..lastPoint = (
        latitude: premMandir.latitude,
        longitude: premMandir.longitude,
      );
  });

  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    int unread = 0,
  }) async {
    // Placeholder instead of the native Google map in widget tests.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view
      ..physicalSize = const Size(1080, 3200)
      ..devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final created = container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: AppEnvironment.development,
            apiOrigin: 'http://127.0.0.1:1',
          ),
        ),
        placesRepositoryProvider.overrideWithValue(places),
        deviceLocationProvider.overrideWithValue(device),
        currentPlaceLocatorProvider.overrideWithValue(FakeLocator(premMandir)),
        sessionControllerProvider.overrideWith(FakeSession.new),
        rideRepositoryProvider.overrideWithValue(rides),
        unreadCountProvider.overrideWith(() => _FixedUnread(unread)),
      ],
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const CustomerHomeTab(),
        ),
        GoRoute(
          path: AppRoutes.customerPlaceSearch,
          builder: (context, state) => Scaffold(
            body: Text(
              'SEARCH ${state.uri.queryParameters['field']} '
              '${state.uri.queryParameters['saveAs'] ?? ''}'.trim(),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.customerRideOptions,
          builder: (context, state) =>
              const Scaffold(body: Text('RIDE OPTIONS')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: created,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return created;
  }

  /// Unmounts Home so its auto-refresh timer is cancelled before the test ends.
  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Also cancels the nearby-cars refresh timer.
    container?.dispose();
    container = null;
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('shows the redesigned Home, filled from the server', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.text("Let's get you there!"), findsOneWidget);
    // The pickup fills itself from the device location.
    expect(find.text('Your current location'), findsOneWidget);
    expect(find.text(premMandir.address), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Add'), findsNWidgets(2));
    expect(find.text('Recent'), findsOneWidget);
    // Popular destinations come from the API (with the admin's photo).
    expect(find.text('Popular destinations'), findsOneWidget);
    expect(find.text('Noida City Centre'), findsOneWidget);
    final photo = tester.widget<Image>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Noida City Centre'),
          matching: find.byType(InkWell),
        ),
        matching: find.byType(Image),
      ),
    );
    expect(
      (photo.image as NetworkImage).url,
      'http://127.0.0.1:1/api/v1${_noidaCentre.imagePath}',
    );
    expect(find.text('Ride Anywhere\nWith Tirvona'), findsOneWidget);
    // No unread notifications: no badge (the old screen always showed "1").
    expect(find.byTooltip('Notifications'), findsOneWidget);
    // Cars around the pickup are asked for on a ~100 m grid.
    expect(rides.nearbyAreas, [(latitude: 27.571, longitude: 77.672)]);

    await done(tester);
  });

  testWidgets('compact trip card: greeting by name, swap only with both ends', (
    tester,
  ) async {
    final container = await pumpHome(tester);
    expect(find.textContaining(', Radha'), findsOneWidget);
    expect(find.byTooltip('Swap pickup and destination'), findsNothing);

    container
        .read(bookingControllerProvider.notifier)
        .setDestination(bankeBihari, remember: false);
    await tester.pumpAndSettle();
    // The destination replaces "Where to?" in the second row.
    expect(find.text('Where to?'), findsNothing);
    expect(find.text('Banke Bihari Temple'), findsOneWidget);

    await tester.tap(find.byTooltip('Swap pickup and destination'));
    await tester.pumpAndSettle();
    expect(container.read(bookingControllerProvider).pickup, bankeBihari);
    expect(container.read(bookingControllerProvider).destination, premMandir);
    await done(tester);
  });

  testWidgets('fits a small phone with large system text', (tester) async {
    await pumpHome(tester);
    // 360 × 740 dp (a common budget Android) at 130% text.
    tester.view
      ..physicalSize = const Size(1080, 2220)
      ..devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Where to?'), findsOneWidget);
    await done(tester);
  });

  testWidgets('badges unread notifications', (tester) async {
    await pumpHome(tester, unread: 3);
    expect(find.byTooltip('3 unread notifications'), findsOneWidget);
    await done(tester);
  });

  testWidgets('an unset Home opens "Set home address"', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('SEARCH destination home'), findsOneWidget);
    await done(tester);
  });

  testWidgets('a saved Home books in one tap', (tester) async {
    places.saved[SavedPlaceKind.home] = bankeBihari;
    final booked = await pumpHome(tester);
    expect(find.text('Banke Bihari Temple'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(
      booked.read(bookingControllerProvider).destination,
      bankeBihari,
    );
    expect(rides.estimateCalls, 1);
    expect(find.text('RIDE OPTIONS'), findsOneWidget);
    await done(tester);
  });

  testWidgets('hides Popular destinations when none are near the rider', (
    tester,
  ) async {
    places.popularPlaces = const [];
    rides.nearby = const [NearbyDriver(latitude: 27.57, longitude: 77.67)];
    await pumpHome(tester);
    expect(find.text('Popular destinations'), findsNothing);
    expect(find.text('Where to?'), findsOneWidget);
    await done(tester);
  });
}
