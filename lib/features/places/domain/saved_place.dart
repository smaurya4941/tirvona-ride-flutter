import 'package:flutter/foundation.dart';

import '../../rides/domain/ride_models.dart';

/// The two address shortcuts a rider can save.
enum SavedPlaceKind {
  home,
  work;

  String get label => switch (this) {
    SavedPlaceKind.home => 'Home',
    SavedPlaceKind.work => 'Work',
  };

  static SavedPlaceKind? tryParse(String? value) {
    for (final kind in SavedPlaceKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

/// One of the rider's own labelled places ("Gym", "Mom's house").
@immutable
class OtherSavedPlace {
  const OtherSavedPlace({
    required this.id,
    required this.label,
    required this.place,
  });

  final String id;
  final String label;
  final Place place;
}

/// The most own places a rider can keep when the server does not say.
const defaultOtherSavedPlacesLimit = 20;

/// The rider's saved places, from `GET /places/saved`: Home and Work
/// (null = not set) and their own labelled places, oldest first.
@immutable
class SavedPlaces {
  const SavedPlaces({
    this.home,
    this.work,
    this.others = const [],
    this.othersRemaining = defaultOtherSavedPlacesLimit,
  });

  factory SavedPlaces.fromJson(Map<String, dynamic> json) => SavedPlaces(
    home: _place(json['home']),
    work: _place(json['work']),
    others: [
      for (final item in (json['others'] as List<dynamic>? ?? const []))
        if (item is Map<String, dynamic> && _place(item) != null)
          OtherSavedPlace(
            id: item['id'] as String,
            label: item['label'] as String? ?? 'Saved place',
            place: _place(item)!,
          ),
    ],
    othersRemaining:
        (json['othersRemaining'] as num?)?.toInt() ??
        defaultOtherSavedPlacesLimit,
  );

  final Place? home;
  final Place? work;
  final List<OtherSavedPlace> others;
  final int othersRemaining;

  bool get canAddOther => othersRemaining > 0;

  Place? operator [](SavedPlaceKind kind) => switch (kind) {
    SavedPlaceKind.home => home,
    SavedPlaceKind.work => work,
  };

  static Place? _place(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return Place(
      name: json['name'] as String?,
      address: json['address'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}
