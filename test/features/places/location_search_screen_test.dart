import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/places/application/current_location.dart';
import 'package:tirvona_ride/features/places/application/place_search_controller.dart';
import 'package:tirvona_ride/features/places/application/popular_places.dart';
import 'package:tirvona_ride/features/places/application/recent_places.dart';
import 'package:tirvona_ride/features/places/application/voice_search.dart';
import 'package:tirvona_ride/features/places/data/places_repository.dart';
import 'package:tirvona_ride/features/places/domain/place_suggestion.dart';
import 'package:tirvona_ride/features/places/domain/saved_place.dart';
import 'package:tirvona_ride/features/places/presentation/location_search_screen.dart';
import 'package:tirvona_ride/features/rides/application/booking_controller.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

import 'places_fakes.dart';

void main() {
  late FakePlacesRepository places;
  late FakeLocator locator;
  late FakeRides rides;
  late FakeVoiceSearch voice;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    places = FakePlacesRepository();
    locator = FakeLocator(premMandir);
    rides = FakeRides();
    voice = FakeVoiceSearch();
    container = ProviderContainer(
      overrides: [
        placesRepositoryProvider.overrideWithValue(places),
        deviceLocationProvider.overrideWithValue(FakeDeviceLocation()),
        currentPlaceLocatorProvider.overrideWithValue(locator),
        sessionControllerProvider.overrideWith(FakeSession.new),
        rideRepositoryProvider.overrideWithValue(rides),
        voiceSearchProvider.overrideWithValue(voice),
      ],
    );
    addTearDown(container.dispose);
  });

  /// What the search screen returned when it closed (pick mode).
  Object? popped;

  Future<void> pumpSearch(
    WidgetTester tester,
    PlaceField field, {
    String? location,
  }) async {
    // A tall phone, so every section of the list is laid out.
    tester.view
      ..physicalSize = const Size(1080, 3000)
      ..devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => popped = await context.push<Object>(
                  location ?? AppRoutes.customerPlaceSearchFor(field.name),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.customerPlaceSearch,
          builder: (context, state) => LocationSearchScreen(
            initialField: PlaceField.parse(state.uri.queryParameters['field']),
            saveAs: SavedPlaceKind.tryParse(
              state.uri.queryParameters['saveAs'],
            ),
            pickOnly: state.uri.queryParameters['mode'] == 'pick',
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
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  BookingState booking() => container.read(bookingControllerProvider);

  testWidgets('typing a destination and tapping a result opens ride options', (
    tester,
  ) async {
    container
        .read(bookingControllerProvider.notifier)
        .setPickup(premMandir, remember: false);
    await pumpSearch(tester, PlaceField.destination);

    // Before typing: the design's sections, all from the server.
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Choose on map'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Add address'), findsNWidgets(2));
    expect(find.text('Popular destinations'), findsOneWidget);
    expect(find.text('Banke Bihari Temple'), findsOneWidget);
    // No rides and nothing picked yet: no (invented) recent list.
    expect(find.text('Recent destinations'), findsNothing);
    // Standing still is a pickup, not a destination.
    expect(find.text('Use current location'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'govind');
    await tester.pump(searchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(places.queries, ['govind']);
    expect(find.text('Govind Dev Ji Temple'), findsOneWidget);
    expect(find.text('2.3 km'), findsOneWidget);

    await tester.tap(find.text('Govind Dev Ji Temple'));
    await tester.pumpAndSettle();

    expect(places.resolved, [govindDevSuggestion.id]);
    expect(booking().destination?.title, 'Govind Dev Ji Temple');
    expect(booking().destination?.latitude, 27.5791);
    expect(booking().hasTrip, isTrue);
    expect(rides.estimateCalls, 1);
    expect(find.text('RIDE OPTIONS'), findsOneWidget);
  });

  testWidgets(
    'current location fills the pickup and moves on to the destination',
    (tester) async {
      await pumpSearch(tester, PlaceField.pickup);

      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();

      expect(locator.calls, 1);
      expect(booking().pickup, premMandir);
      // Still planning: the destination field is next.
      expect(find.text('Where to?'), findsOneWidget);
      expect(find.text('RIDE OPTIONS'), findsNothing);
      final destination = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(destination.focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets('refuses a destination equal to the pickup', (tester) async {
    container
        .read(bookingControllerProvider.notifier)
        .setPickup(bankeBihari, remember: false);
    places.popularPlaces = const [bankeBihariSuggestion];
    await pumpSearch(tester, PlaceField.destination);

    // The pickup itself is hidden from the popular destinations…
    expect(find.text('Banke Bihari Temple'), findsNothing);
    // …so search for it instead.
    places.results['banke'] = const PlaceSearchResult(
      suggestions: [bankeBihariSuggestion],
    );
    await tester.enterText(find.byType(TextField).first, 'banke');
    await tester.pump(searchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banke Bihari Temple').last);
    await tester.pumpAndSettle();

    expect(
      find.text("Pickup and destination can't be the same place."),
      findsOneWidget,
    );
    expect(booking().destination, isNull);
    expect(find.text('RIDE OPTIONS'), findsNothing);
  });

  testWidgets('shows a notice when search is degraded or empty', (
    tester,
  ) async {
    await pumpSearch(tester, PlaceField.destination);
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump(searchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('No places match "zzz".'), findsOneWidget);
    expect(find.text("Can't find it? Drop a pin instead"), findsOneWidget);

    places.results['mathura'] = const PlaceSearchResult(
      suggestions: [],
      degraded: true,
    );
    await tester.enterText(find.byType(TextField).first, 'mathura');
    await tester.pump(searchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.textContaining('Full search is unavailable'), findsOneWidget);

    // Retry asks again, and full results replace the notice.
    places.results['mathura'] = const PlaceSearchResult(
      suggestions: [],
      degraded: false,
    );
    final asked = places.queries.length;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(places.queries.length, asked + 1);
    expect(places.queries.last, 'mathura');
    expect(find.textContaining('Full search is unavailable'), findsNothing);
    expect(find.text('No places match "mathura".'), findsOneWidget);
  });

  testWidgets(
    'recent destinations come from ride history: four, then "See all", and '
    'a removed one stays hidden',
    (tester) async {
      rides.pastDestinations = [
        for (var i = 1; i <= 5; i++)
          Place(
            name: 'Past stop $i',
            address: 'Past stop $i, Sector $i, Noida',
            latitude: 28.5 + i / 100,
            longitude: 77.3,
          ),
      ];
      container
          .read(bookingControllerProvider.notifier)
          .setPickup(premMandir, remember: false);
      await pumpSearch(tester, PlaceField.destination);

      expect(find.text('Recent destinations'), findsOneWidget);
      expect(find.text('Past stop 1'), findsOneWidget);
      expect(find.text('Sector 1, Noida'), findsOneWidget);
      expect(find.text('Past stop 5'), findsNothing);
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.text('Past stop 5'), findsOneWidget);

      await tester.longPress(find.text('Past stop 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Past stop 2'), findsNothing);
      // Still hidden after the history is fetched again.
      container.invalidate(rideHistoryDestinationsProvider);
      await tester.pumpAndSettle();
      expect(find.text('Past stop 2'), findsNothing);
      expect(find.text('Past stop 3'), findsOneWidget);
    },
  );

  testWidgets(
    'Home: "Add address" searches and saves it on the server; then one tap '
    'books it',
    (tester) async {
      container
          .read(bookingControllerProvider.notifier)
          .setPickup(premMandir, remember: false);
      await pumpSearch(tester, PlaceField.destination);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Set home address'), findsOneWidget);
      // Saving an address: no Home/Work cards, but "use where I am" is offered.
      expect(find.text('Use current location'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'govind');
      await tester.pump(searchDebounce + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Govind Dev Ji Temple'));
      await tester.pumpAndSettle();

      expect(places.saved[SavedPlaceKind.home]?.title, 'Govind Dev Ji Temple');
      // Saving never touches the trip being planned.
      expect(booking().destination, isNull);
      expect(find.text('Where to?'), findsOneWidget);
      expect(find.text('Govind Dev Ji Temple'), findsOneWidget); // Home card

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(booking().destination?.title, 'Govind Dev Ji Temple');
      expect(find.text('RIDE OPTIONS'), findsOneWidget);
    },
  );

  testWidgets(
    'Home saved on the device by an older build moves to the server',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'places.saved.user-1':
            '{"home":{"name":"Old home","address":"Old home, Vrindavan",'
            '"latitude":27.58,"longitude":77.69}}',
      });
      await pumpSearch(tester, PlaceField.destination);

      expect(places.saved[SavedPlaceKind.home]?.title, 'Old home');
      expect(find.text('Old home'), findsOneWidget);
      expect(
        await const FlutterSecureStorage().read(key: 'places.saved.user-1'),
        isNull,
      );
    },
  );

  testWidgets('the mic fills the box with what the rider says and searches', (
    tester,
  ) async {
    await pumpSearch(tester, PlaceField.destination);

    await tester.tap(find.byTooltip('Search by voice'));
    await tester.pump();
    expect(voice.listening, isTrue);
    expect(find.byTooltip('Stop listening'), findsOneWidget);

    voice.say('govind', isFinal: true);
    await tester.pump(searchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(places.queries, ['govind']);
    expect(find.text('Govind Dev Ji Temple'), findsOneWidget);
    expect(find.byTooltip('Search by voice'), findsOneWidget);
  });

  testWidgets('explains when voice search is unavailable', (tester) async {
    voice.unavailable = true;
    await pumpSearch(tester, PlaceField.destination);
    await tester.tap(find.byTooltip('Search by voice'));
    await tester.pumpAndSettle();
    expect(find.textContaining('microphone'), findsOneWidget);
  });

  testWidgets('fits a small phone with large system text', (tester) async {
    rides.pastDestinations = const [bankeBihari];
    places.saved[SavedPlaceKind.work] = premMandir;
    await pumpSearch(tester, PlaceField.pickup);
    // 360 × 740 dp at 130% text.
    tester.view
      ..physicalSize = const Size(1080, 2220)
      ..devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Pickup location'), findsOneWidget);
    expect(find.text('Choose on map'), findsOneWidget);
  });

  testWidgets('the rider''s own places are offered on "Where to?"', (
    tester,
  ) async {
    container
        .read(bookingControllerProvider.notifier)
        .setPickup(premMandir, remember: false);
    await places.addOtherPlace('Gym', bankeBihari);
    await pumpSearch(tester, PlaceField.destination);

    expect(find.text('Your places'), findsOneWidget);
    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();
    expect(booking().destination, bankeBihari);
    expect(find.text('RIDE OPTIONS'), findsOneWidget);
  });

  testWidgets('pick mode returns the chosen place and leaves the trip alone', (
    tester,
  ) async {
    await places.addOtherPlace('Gym', bankeBihari);
    await pumpSearch(
      tester,
      PlaceField.destination,
      location: AppRoutes.customerPickAddress,
    );
    expect(find.text('Choose an address'), findsOneWidget);
    // Choosing an address for a saved place, not for the trip.
    expect(find.text('Your places'), findsNothing);
    expect(find.text('Add address'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'govind');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text(govindDevSuggestion.name).first);
    await tester.pumpAndSettle();

    expect(popped, isA<Place>());
    expect((popped! as Place).address, govindDevSuggestion.address);
    expect(booking().destination, isNull);
  });

  test('BookingState needs a pickup for a trip', () {
    const state = BookingState(destination: bankeBihari);
    expect(state.hasTrip, isFalse);
    expect(
      const BookingState(pickup: premMandir, destination: premMandir).hasTrip,
      isFalse,
    );
    expect(
      const BookingState(pickup: premMandir, destination: bankeBihari).hasTrip,
      isTrue,
    );
  });

  test('field names round-trip through the route', () {
    expect(PlaceField.parse('pickup'), PlaceField.pickup);
    expect(PlaceField.parse(null), PlaceField.destination);
    expect(
      AppRoutes.customerPlaceSearchFor(PlaceField.pickup.name),
      '/customer/book/where?field=pickup',
    );
    expect(const Place(address: 'x', latitude: 1, longitude: 2).title, 'x');
  });
}
