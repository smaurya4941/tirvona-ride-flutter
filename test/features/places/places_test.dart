import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/places/application/current_location.dart';
import 'package:tirvona_ride/features/places/application/place_search_controller.dart';
import 'package:tirvona_ride/features/places/application/recent_places.dart';
import 'package:tirvona_ride/features/places/data/places_repository.dart';
import 'package:tirvona_ride/features/places/domain/place_suggestion.dart';
import 'package:tirvona_ride/features/rides/application/booking_controller.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

import 'places_fakes.dart';

Future<void> _afterDebounce() =>
    Future<void>.delayed(searchDebounce + const Duration(milliseconds: 80));

void main() {
  group('PlaceSuggestion', () {
    test('parses API rows, with and without coordinates', () {
      final curated = PlaceSuggestion.fromJson({
        'id': 'featured:prem-mandir',
        'name': 'Prem Mandir',
        'secondaryText': 'Raman Reiti, Vrindavan',
        'address': 'Prem Mandir, Raman Reiti, Vrindavan',
        'latitude': 27.5714,
        'longitude': 77.6716,
        'distanceMeters': 420,
        'featured': true,
      });
      expect(curated.hasCoordinates, isTrue);
      expect(curated.toPlace().title, 'Prem Mandir');
      expect(curated.toPlace().address, 'Prem Mandir, Raman Reiti, Vrindavan');

      final google = PlaceSuggestion.fromJson({
        'id': 'google:abc',
        'name': 'Hotel',
        'secondaryText': 'Vrindavan',
        'address': 'Hotel, Vrindavan',
        'featured': false,
      });
      expect(google.hasCoordinates, isFalse);
      expect(google.toPlace, throwsStateError);
    });

    test('formats distances for list rows', () {
      expect(formatDistance(346), '350 m');
      expect(formatDistance(4230), '4.2 km');
      expect(formatDistance(38400), '38 km');
    });

    test('reverse geocoding keeps the approximate flag', () {
      final named = ReverseGeocodedPlace.fromJson({
        'id': 'pin:1,2',
        'name': 'Pinned location',
        'address': 'Pinned location (27.60000, 77.75000)',
        'latitude': 27.6,
        'longitude': 77.75,
        'approximate': true,
      });
      expect(named.approximate, isTrue);
      expect(named.place.latitude, 27.6);
    });
  });

  group('recent places', () {
    test('newest first, same spot replaced, capped', () {
      var list = <Place>[];
      for (var i = 0; i < maxRecentPlaces + 3; i++) {
        list = addRecentPlace(
          list,
          Place(address: 'Place $i', latitude: 27 + i / 100, longitude: 77),
        );
      }
      expect(list, hasLength(maxRecentPlaces));
      expect(list.first.address, 'Place ${maxRecentPlaces + 2}');

      // ~10 m away from the newest entry: replaces it, stays on top.
      final moved = addRecentPlace(
        list,
        Place(
          name: 'Gate 2',
          address: 'Gate 2',
          latitude: list.first.latitude + 0.0001,
          longitude: 77,
        ),
      );
      expect(moved, hasLength(maxRecentPlaces));
      expect(moved.first.title, 'Gate 2');
      expect(
        moved.any((p) => p.address == 'Place ${maxRecentPlaces + 2}'),
        isFalse,
      );
      expect(moved[1].address, 'Place ${maxRecentPlaces + 1}');
    });

    test('round-trips through storage and survives corrupt data', () {
      final encoded = encodeRecentPlaces([premMandir, bankeBihari]);
      final decoded = decodeRecentPlaces(encoded);
      expect(decoded.map((p) => p.title), [
        'Prem Mandir',
        'Banke Bihari Temple',
      ]);
      expect(decoded.first.latitude, premMandir.latitude);
      expect(decodeRecentPlaces('{"not":"a list"}'), isEmpty);
      expect(
        decodeRecentPlaces(
          '[{"address":1},{"address":"ok","latitude":1,"longitude":2}]',
        ).single.address,
        'ok',
      );
    });

    test('are stored per signed-in user', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [sessionControllerProvider.overrideWith(FakeSession.new)],
      );
      addTearDown(container.dispose);
      await container.read(recentPlacesProvider.future);
      await container.read(recentPlacesProvider.notifier).remember(premMandir);
      await container.read(recentPlacesProvider.notifier).remember(bankeBihari);
      expect(container.read(recentPlacesProvider).value!.map((p) => p.title), [
        'Banke Bihari Temple',
        'Prem Mandir',
      ]);

      // A fresh container (app restart) reads them back.
      final restarted = ProviderContainer(
        overrides: [sessionControllerProvider.overrideWith(FakeSession.new)],
      );
      addTearDown(restarted.dispose);
      final restored = await restarted.read(recentPlacesProvider.future);
      expect(restored.map((p) => p.title), [
        'Banke Bihari Temple',
        'Prem Mandir',
      ]);

      await restarted.read(recentPlacesProvider.notifier).forget(premMandir);
      expect(restarted.read(recentPlacesProvider).value, hasLength(1));
    });
  });

  group('PlaceSearchController', () {
    late FakePlacesRepository places;
    late ProviderContainer container;

    setUp(() {
      places = FakePlacesRepository();
      container = ProviderContainer(
        overrides: [
          placesRepositoryProvider.overrideWithValue(places),
          deviceLocationProvider.overrideWithValue(
            FakeDeviceLocation()
              ..lastPoint = (latitude: 27.57, longitude: 77.67),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(placeSearchControllerProvider, (_, _) {});
    });

    PlaceSearchState state() => container.read(placeSearchControllerProvider);
    PlaceSearchController controller() =>
        container.read(placeSearchControllerProvider.notifier);

    test('debounces keystrokes into one request', () async {
      controller()
        ..search('g')
        ..search('go')
        ..search('gov')
        ..search('govind');
      expect(state().loading, isTrue);
      expect(places.queries, isEmpty);
      await _afterDebounce();
      expect(places.queries, ['govind']);
      expect(state().loading, isFalse);
      expect(state().suggestions!.single.name, 'Govind Dev Ji Temple');
    });

    test('short queries show shortcuts instead of searching', () async {
      controller().search(' g ');
      await _afterDebounce();
      expect(places.queries, isEmpty);
      expect(state().isSearching, isFalse);
      expect(state().suggestions, isNull);
    });

    test('drops a late answer for an older query', () async {
      final slow = Completer<PlaceSearchResult>();
      places.held['ban'] = slow;
      controller().search('ban');
      await _afterDebounce();
      controller().search('govind');
      slow.complete(
        const PlaceSearchResult(suggestions: [bankeBihariSuggestion]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(state().query, 'govind');
      expect(state().suggestions, isNull);
      await _afterDebounce();
      expect(state().suggestions!.single.id, govindDevSuggestion.id);
    });

    test('resolves only suggestions without coordinates, in-session', () async {
      controller().search('govind');
      await _afterDebounce();
      final token = places.sessionTokens.single;
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));

      final curated = await controller().choose(bankeBihariSuggestion);
      expect(curated.latitude, bankeBihariSuggestion.latitude);
      expect(places.resolved, isEmpty);

      final resolved = await controller().choose(govindDevSuggestion);
      expect(resolved.title, 'Govind Dev Ji Temple');
      expect(resolved.latitude, 27.5791);
      expect(places.resolved, [govindDevSuggestion.id]);

      // A new session starts after a choice.
      controller().search('govind dev');
      await _afterDebounce();
      expect(places.sessionTokens.last, isNot(token));
    });
  });

  group('BookingController pickup location', () {
    late FakeLocator locator;
    late ProviderContainer container;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      locator = FakeLocator(premMandir);
      container = ProviderContainer(
        overrides: [
          currentPlaceLocatorProvider.overrideWithValue(locator),
          sessionControllerProvider.overrideWith(FakeSession.new),
          rideRepositoryProvider.overrideWithValue(FakeRides()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(bookingControllerProvider, (_, _) {});
    });

    BookingState booking() => container.read(bookingControllerProvider);
    BookingController controller() =>
        container.read(bookingControllerProvider.notifier);

    test('starts without a pickup and fills it from the device once', () async {
      expect(booking().pickup, isNull);
      expect(booking().hasTrip, isFalse);
      final pending = controller().ensurePickup();
      expect(booking().locatingPickup, isTrue);
      await pending;
      expect(booking().pickup, premMandir);
      expect(booking().locatingPickup, isFalse);

      await controller().ensurePickup();
      expect(locator.calls, 1);
    });

    test('reports a location failure without inventing a pickup', () async {
      locator.answer = const LocationFailure(
        LocationFailureReason.deniedForever,
      );
      final error = await controller().useCurrentLocationForPickup();
      expect(error, isA<LocationFailure>());
      expect((error! as LocationFailure).needsSettings, isTrue);
      expect(booking().pickup, isNull);
      expect(booking().pickupLocationError, same(error));

      controller().setPickup(bankeBihari);
      expect(booking().pickupLocationError, isNull);
    });

    test('a pickup chosen while locating wins over the late fix', () async {
      final pending = controller().useCurrentLocationForPickup();
      controller().setPickup(bankeBihari);
      await pending;
      expect(booking().pickup, bankeBihari);
      expect(booking().locatingPickup, isFalse);
    });

    test('needs both ends to be a trip; swap exchanges them', () async {
      controller().setDestination(bankeBihari);
      expect(booking().hasTrip, isFalse);
      controller().setPickup(premMandir);
      expect(booking().hasTrip, isTrue);
      controller().swap();
      expect(booking().pickup, bankeBihari);
      expect(booking().destination, premMandir);

      // Chosen places land in recents; the current location does not.
      await Future<void>.delayed(Duration.zero);
      final recents = await container.read(recentPlacesProvider.future);
      expect(recents.map((p) => p.title), contains('Banke Bihari Temple'));
    });
  });
}
