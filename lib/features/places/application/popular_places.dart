import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/places_repository.dart';
import '../domain/place_suggestion.dart';
import 'current_location.dart';

/// Which end of the trip a place is being chosen for.
enum PlaceField {
  pickup,
  destination;

  String get label => switch (this) {
    PlaceField.pickup => 'pickup',
    PlaceField.destination => 'destination',
  };

  static PlaceField parse(String? value) => PlaceField.values.firstWhere(
    (field) => field.name == value,
    orElse: () => PlaceField.destination,
  );
}

/// Curated pilgrimage places, nearest first when the rider's rough position
/// is known. Shared by Home (quick destinations) and the search screen.
final popularPlacesProvider = FutureProvider<List<PlaceSuggestion>>((
  ref,
) async {
  final near = await ref.read(deviceLocationProvider).approximatePosition();
  return ref.read(placesRepositoryProvider).popular(near: near);
});
