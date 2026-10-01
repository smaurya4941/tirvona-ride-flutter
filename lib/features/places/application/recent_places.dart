import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/driver_fix.dart' show distanceMeters;
import '../../../core/storage/secure_storage.dart';
import '../../auth/presentation/session_controller.dart';
import '../../rides/data/ride_repository.dart';
import '../../rides/domain/ride_models.dart';

/// How many recent places are kept per rider.
const maxRecentPlaces = 8;

/// Two places closer than this are the same recent entry.
const _sameRecentMeters = 50.0;

/// The rider's recently used pickups and destinations on this device, newest
/// first. Stored encrypted, per signed-in user. Screens show
/// [recentDestinationsProvider], which adds the rider's ride history.
class RecentPlacesController extends AsyncNotifier<List<Place>> {
  String? get _key {
    final userId = ref.read(sessionControllerProvider).user?.id;
    return userId == null ? null : 'places.recent.$userId';
  }

  @override
  Future<List<Place>> build() async {
    // Re-read when the signed-in user changes.
    ref.watch(sessionControllerProvider.select((session) => session.user?.id));
    final key = _key;
    if (key == null) return const [];
    try {
      final raw = await ref.read(secureStorageProvider).read(key);
      return raw == null ? const [] : decodeRecentPlaces(raw);
    } on Object {
      // Corrupt or unreadable entry: start over rather than break booking.
      return const [];
    }
  }

  /// Updates run one after another, so two quick calls (e.g. "book again"
  /// setting both ends) never overwrite each other.
  Future<void> _queue = Future.value();

  /// Moves [place] to the top, replacing an entry for the same spot.
  Future<void> remember(Place place) {
    ref.read(hiddenRecentPlacesProvider.notifier).unhide(place).ignore();
    return _update((current) => addRecentPlace(current, place));
  }

  /// Removes [place] here and hides it in the ride-history list too.
  Future<void> forget(Place place) {
    ref.read(hiddenRecentPlacesProvider.notifier).hide(place).ignore();
    return _update(
      (current) => [
        for (final existing in current)
          if (!_isSameRecent(existing, place)) existing,
      ],
    );
  }

  Future<void> _update(List<Place> Function(List<Place> current) change) {
    final run = _queue.then((_) async {
      final key = _key;
      if (key == null) return;
      final current = state.value ?? await future;
      final next = change(current);
      state = AsyncData(next);
      try {
        await ref
            .read(secureStorageProvider)
            .write(key, encodeRecentPlaces(next));
      } on Object {
        // Best effort: the list still works for this session.
      }
    });
    _queue = run.catchError((Object _) {});
    return run;
  }
}

final recentPlacesProvider =
    AsyncNotifierProvider<RecentPlacesController, List<Place>>(
      RecentPlacesController.new,
    );

/// Past-ride destinations the rider removed from "Recent destinations". The
/// rides themselves stay in the history; this device just stops offering
/// them. Stored like the recents (encrypted, per user).
class HiddenRecentPlacesController extends AsyncNotifier<List<Place>> {
  static const _maxHidden = 50;

  String? get _key {
    final userId = ref.read(sessionControllerProvider).user?.id;
    return userId == null ? null : 'places.recent.hidden.$userId';
  }

  @override
  Future<List<Place>> build() async {
    ref.watch(sessionControllerProvider.select((session) => session.user?.id));
    final key = _key;
    if (key == null) return const [];
    try {
      final raw = await ref.read(secureStorageProvider).read(key);
      return raw == null ? const [] : decodeRecentPlaces(raw, max: _maxHidden);
    } on Object {
      return const [];
    }
  }

  Future<void> hide(Place place) => _write(
    (current) => [
      place,
      for (final existing in current)
        if (!_isSameRecent(existing, place)) existing,
    ].take(_maxHidden).toList(growable: false),
  );

  Future<void> unhide(Place place) async {
    final current = state.value ?? await future;
    if (!current.any((existing) => _isSameRecent(existing, place))) return;
    await _write(
      (current) => [
        for (final existing in current)
          if (!_isSameRecent(existing, place)) existing,
      ],
    );
  }

  Future<void> _write(List<Place> Function(List<Place> current) change) async {
    final key = _key;
    if (key == null) return;
    final next = change(state.value ?? await future);
    state = AsyncData(next);
    try {
      await ref
          .read(secureStorageProvider)
          .write(key, encodeRecentPlaces(next));
    } on Object {
      // Best effort: hidden for this session at least.
    }
  }
}

final hiddenRecentPlacesProvider =
    AsyncNotifierProvider<HiddenRecentPlacesController, List<Place>>(
      HiddenRecentPlacesController.new,
    );

/// Destinations of the rider's past bookings (`GET /rides/recent-destinations`).
final rideHistoryDestinationsProvider = FutureProvider<List<Place>>((ref) {
  ref.watch(sessionControllerProvider.select((session) => session.user?.id));
  return ref
      .read(rideRepositoryProvider)
      .recentDestinations(limit: maxRecentPlaces);
});

/// "Recent destinations": what the rider picked on this device, then where
/// their past rides went (so a new phone is not empty), minus hidden ones.
/// A ride-history outage only shrinks the list; it never fails it.
final recentDestinationsProvider = FutureProvider<List<Place>>((ref) async {
  final local = await ref.watch(recentPlacesProvider.future);
  final hidden = await ref.watch(hiddenRecentPlacesProvider.future);
  List<Place> history;
  try {
    history = await ref.watch(rideHistoryDestinationsProvider.future);
  } on Object {
    history = const [];
  }
  return mergeRecentPlaces(local, history, hidden: hidden);
});

/// [local] first, then [history] entries for spots not already listed,
/// skipping anything [hidden]; capped at [max].
List<Place> mergeRecentPlaces(
  List<Place> local,
  List<Place> history, {
  List<Place> hidden = const [],
  int max = maxRecentPlaces,
}) {
  final merged = <Place>[];
  for (final place in [...local, ...history]) {
    if (merged.length >= max) break;
    if (hidden.any((gone) => _isSameRecent(gone, place))) continue;
    if (merged.any((seen) => _isSameRecent(seen, place))) continue;
    merged.add(place);
  }
  return List.unmodifiable(merged);
}

bool _isSameRecent(Place a, Place b) =>
    distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude) <
    _sameRecentMeters;

/// Pure list update, newest first, de-duplicated, capped.
List<Place> addRecentPlace(List<Place> current, Place place) => [
  place,
  for (final existing in current)
    if (!_isSameRecent(existing, place)) existing,
].take(maxRecentPlaces).toList(growable: false);

String encodeRecentPlaces(List<Place> places) => jsonEncode([
  for (final place in places)
    {
      'name': ?place.name,
      'address': place.address,
      'latitude': place.latitude,
      'longitude': place.longitude,
    },
]);

List<Place> decodeRecentPlaces(String raw, {int max = maxRecentPlaces}) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  final places = <Place>[];
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) continue;
    final address = item['address'];
    final latitude = item['latitude'];
    final longitude = item['longitude'];
    if (address is! String || latitude is! num || longitude is! num) continue;
    places.add(
      Place(
        name: item['name'] as String?,
        address: address,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      ),
    );
  }
  return places.take(max).toList(growable: false);
}
