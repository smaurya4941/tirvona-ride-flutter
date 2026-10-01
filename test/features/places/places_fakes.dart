import 'dart:async';

import 'package:dio/dio.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/places/application/current_location.dart';
import 'package:tirvona_ride/features/places/application/voice_search.dart';
import 'package:tirvona_ride/features/places/data/places_repository.dart';
import 'package:tirvona_ride/features/places/domain/place_suggestion.dart';
import 'package:tirvona_ride/features/places/domain/saved_place.dart';
import 'package:tirvona_ride/features/rides/data/ride_repository.dart';
import 'package:tirvona_ride/features/rides/domain/nearby_driver.dart';
import 'package:tirvona_ride/features/rides/domain/promo_models.dart';
import 'package:tirvona_ride/features/rides/domain/ride_models.dart';

const premMandir = Place(
  name: 'Prem Mandir',
  address: 'Prem Mandir, Raman Reiti, Vrindavan',
  latitude: 27.5714,
  longitude: 77.6716,
);

const bankeBihari = Place(
  name: 'Banke Bihari Temple',
  address: 'Banke Bihari Temple, Bihari Pura, Vrindavan',
  latitude: 27.5806,
  longitude: 77.7006,
);

const govindDevSuggestion = PlaceSuggestion(
  id: 'google:ChIJ-govind-dev-01',
  name: 'Govind Dev Ji Temple',
  secondaryText: 'Goda Vihar, Vrindavan',
  address: 'Govind Dev Ji Temple, Goda Vihar, Vrindavan',
  distanceMeters: 2300,
);

const bankeBihariSuggestion = PlaceSuggestion(
  id: 'featured:banke-bihari',
  name: 'Banke Bihari Temple',
  secondaryText: 'Bihari Pura, Vrindavan',
  address: 'Banke Bihari Temple, Bihari Pura, Vrindavan',
  latitude: 27.5806,
  longitude: 77.7006,
  featured: true,
);

/// Answers from [results] by query; a query in [held] waits for its
/// completer so tests can control ordering.
class FakePlacesRepository implements PlacesRepository {
  final queries = <String>[];
  final sessionTokens = <String?>[];
  final resolved = <String>[];
  final held = <String, Completer<PlaceSearchResult>>{};
  Map<String, PlaceSearchResult> results = {
    'govind': const PlaceSearchResult(suggestions: [govindDevSuggestion]),
  };
  List<PlaceSuggestion> popularPlaces = const [bankeBihariSuggestion];

  @override
  Future<PlaceSearchResult> autocomplete(
    String query, {
    GeoPoint? near,
    String? sessionToken,
    int limit = 8,
    CancelToken? cancelToken,
  }) {
    queries.add(query);
    sessionTokens.add(sessionToken);
    final gate = held[query];
    if (gate != null) return gate.future;
    return Future.value(
      results[query.toLowerCase()] ?? const PlaceSearchResult(suggestions: []),
    );
  }

  @override
  Future<Place> resolve(
    PlaceSuggestion suggestion, {
    String? sessionToken,
  }) async {
    resolved.add(suggestion.id);
    return Place(
      name: suggestion.name,
      address: suggestion.address,
      latitude: 27.5791,
      longitude: 77.6993,
    );
  }

  @override
  Future<ReverseGeocodedPlace> reverse(GeoPoint point) async =>
      ReverseGeocodedPlace(
        place: Place(
          name: 'Parikrama Marg',
          address: 'Parikrama Marg, Vrindavan',
          latitude: point.latitude,
          longitude: point.longitude,
        ),
        approximate: false,
      );

  @override
  Future<List<PlaceSuggestion>> popular({
    GeoPoint? near,
    int limit = 8,
  }) async => popularPlaces;

  /// Server-side Home/Work, keyed by kind.
  final saved = <SavedPlaceKind, Place>{};
  int savedReads = 0;

  /// Server-side labelled places, oldest first.
  final others = <OtherSavedPlace>[];
  int _nextOtherId = 0;

  SavedPlaces get _saved => SavedPlaces(
    home: saved[SavedPlaceKind.home],
    work: saved[SavedPlaceKind.work],
    others: List.of(others),
    othersRemaining: defaultOtherSavedPlacesLimit - others.length,
  );

  @override
  Future<SavedPlaces> savedPlaces() async {
    savedReads++;
    return _saved;
  }

  @override
  Future<SavedPlaces> savePlace(SavedPlaceKind kind, Place place) async {
    saved[kind] = place;
    return _saved;
  }

  @override
  Future<SavedPlaces> clearSavedPlace(SavedPlaceKind kind) async {
    saved.remove(kind);
    return _saved;
  }

  @override
  Future<SavedPlaces> addOtherPlace(String label, Place place) async {
    others.add(
      OtherSavedPlace(id: 'other-${++_nextOtherId}', label: label, place: place),
    );
    return _saved;
  }

  @override
  Future<SavedPlaces> updateOtherPlace(
    String id, {
    String? label,
    Place? place,
  }) async {
    final index = others.indexWhere((other) => other.id == id);
    final current = others[index];
    others[index] = OtherSavedPlace(
      id: id,
      label: label ?? current.label,
      place: place ?? current.place,
    );
    return _saved;
  }

  @override
  Future<SavedPlaces> removeOtherPlace(String id) async {
    others.removeWhere((other) => other.id == id);
    return _saved;
  }
}

class FakeDeviceLocation implements DeviceLocation {
  @override
  GeoPoint? lastPoint;

  @override
  Future<GeoPoint?> approximatePosition() async => lastPoint;

  @override
  Future<GeoPoint> currentPosition({bool prompt = true}) async =>
      lastPoint ?? (throw const LocationFailure(LocationFailureReason.denied));

  @override
  Future<void> openSettings(LocationFailure failure) async {}
}

class FakeLocator implements CurrentPlaceLocator {
  FakeLocator(this.answer);

  /// A [Place] to return, or an error to throw.
  Object answer;
  int calls = 0;
  final prompts = <bool>[];

  @override
  Future<Place> locate({bool prompt = true}) async {
    calls++;
    prompts.add(prompt);
    final value = answer;
    if (value is Place) return value;
    throw value;
  }
}

class FakeSession extends SessionController {
  @override
  SessionState build() => const SessionState.authenticated(
    AppUser(
      id: 'user-1',
      phone: '+919800000001',
      role: UserRole.customer,
      status: UserStatus.active,
      firstName: 'Radha',
    ),
  );
}

class FakeRides extends RideRepository {
  FakeRides() : super(Dio());

  int estimateCalls = 0;

  @override
  Future<List<FareEstimate>> estimateAll({
    required Place pickup,
    required Place destination,
  }) async {
    estimateCalls++;
    return const [];
  }

  /// Destinations of past rides (GET /rides/recent-destinations).
  List<Place> pastDestinations = const [];
  List<NearbyDriver> nearby = const [];
  final nearbyAreas = <({double latitude, double longitude})>[];

  @override
  Future<List<Place>> recentDestinations({int limit = 8}) async =>
      pastDestinations;

  @override
  Future<List<NearbyDriver>> nearbyDrivers({
    required double latitude,
    required double longitude,
  }) async {
    nearbyAreas.add((latitude: latitude, longitude: longitude));
    return nearby;
  }

  @override
  Future<List<PromoOffer>> promoOffers() async => const [];

  @override
  Future<Ride?> getActiveRide() async => null;

  @override
  Future<RidePage> history({
    int page = 1,
    int limit = 20,
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      const RidePage(items: [], page: 1, total: 0, hasMore: false);
}

/// Speech-to-text driven by the test: [say] delivers recognised words.
class FakeVoiceSearch implements VoiceSearch {
  bool unavailable = false;
  bool listening = false;
  void Function(String words, {required bool isFinal})? _onWords;
  void Function()? _onDone;

  @override
  Future<void> listen({
    required void Function(String words, {required bool isFinal}) onWords,
    required void Function() onDone,
  }) async {
    if (unavailable) {
      throw const VoiceSearchUnavailable(
        'Voice search needs microphone access.',
      );
    }
    listening = true;
    _onWords = onWords;
    _onDone = onDone;
  }

  /// Delivers [words]; a final result ends the session like the real one.
  void say(String words, {bool isFinal = false}) {
    _onWords?.call(words, isFinal: isFinal);
    if (isFinal) stop();
  }

  @override
  Future<void> stop() async {
    listening = false;
    final done = _onDone;
    _onDone = null;
    done?.call();
  }
}
