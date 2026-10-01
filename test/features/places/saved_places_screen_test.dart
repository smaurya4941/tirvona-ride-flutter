import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/places/data/places_repository.dart';
import 'package:tirvona_ride/features/places/domain/saved_place.dart';
import 'package:tirvona_ride/features/places/presentation/saved_places_screen.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

import 'places_fakes.dart';

const _gym = Place(
  address: 'Cult Fit, Sector 18, Noida',
  latitude: 28.5701,
  longitude: 77.3219,
);

void main() {
  late FakePlacesRepository places;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    places = FakePlacesRepository();
    container = ProviderContainer(
      overrides: [
        placesRepositoryProvider.overrideWithValue(places),
        sessionControllerProvider.overrideWith(FakeSession.new),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.customerSavedPlaces,
      routes: [
        GoRoute(
          path: AppRoutes.customerSavedPlaces,
          builder: (context, state) => const SavedPlacesScreen(),
        ),
        // Stands in for the search screen in pick mode: returns a place.
        GoRoute(
          path: AppRoutes.customerPlaceSearch,
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.pop(
                  state.uri.queryParameters['mode'] == 'pick' ? _gym : null,
                ),
                child: const Text('pick gym'),
              ),
            ),
          ),
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
    await tester.pumpAndSettle();
  }

  testWidgets('lists Home, Work and an empty "Your places"', (tester) async {
    places.saved[SavedPlaceKind.home] = premMandir;
    await pumpScreen(tester);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text(premMandir.address), findsOneWidget);
    expect(find.text('Add work address'), findsOneWidget);
    expect(find.textContaining('Save the places you go often'), findsOneWidget);
  });

  testWidgets('adds a place: pick an address, name it, and it is saved', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Add a place'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pick gym'));
    await tester.pumpAndSettle();

    expect(find.text('Name this place'), findsOneWidget);
    // Reserved and empty labels are refused before any request.
    await tester.enterText(find.byType(TextFormField), 'home');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Use the Home shortcut instead'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Gym'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(places.others.single.label, 'Gym');
    expect(places.others.single.place, _gym);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text(_gym.address), findsOneWidget);
    expect(find.text('19 more allowed'), findsOneWidget);
  });

  testWidgets('renames and removes a place; duplicate names are refused', (
    tester,
  ) async {
    await places.addOtherPlace('Gym', _gym);
    await places.addOtherPlace('Pool', premMandir);
    await pumpScreen(tester);

    await tester.tap(find.text('Pool'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'GYM');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('You already have "GYM"'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Swimming');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(places.others.map((other) => other.label), ['Gym', 'Swimming']);

    await tester.tap(find.byTooltip('Gym options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(find.text('Remove "Gym"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(places.others.map((other) => other.label), ['Swimming']);
  });
}
