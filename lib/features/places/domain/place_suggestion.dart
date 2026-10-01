import 'package:flutter/foundation.dart';

import '../../rides/domain/ride_models.dart';

/// One row of the "where to?" list from `GET /places/autocomplete` or
/// `GET /places/popular`. Curated and OpenStreetMap results carry
/// coordinates; Google results only an [id], resolved when tapped.
@immutable
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.id,
    required this.name,
    required this.secondaryText,
    required this.address,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.featured = false,
    this.imagePath,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) =>
      PlaceSuggestion(
        id: json['id'] as String,
        name: json['name'] as String,
        secondaryText: json['secondaryText'] as String? ?? '',
        address: json['address'] as String,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        distanceMeters: (json['distanceMeters'] as num?)?.toInt(),
        featured: json['featured'] as bool? ?? false,
        imagePath: json['imagePath'] as String?,
      );

  final String id;
  final String name;
  final String secondaryText;

  /// One-line address the ride is booked with.
  final String address;
  final double? latitude;
  final double? longitude;
  final int? distanceMeters;

  /// A curated place (Braj landmark or an admin-managed popular place).
  final bool featured;

  /// Admin-uploaded photo of a popular place, relative to the API base
  /// (`/places/popular/:id/image?v=…`); null when there is none.
  final String? imagePath;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Only valid when [hasCoordinates]; otherwise resolve [id] first.
  Place toPlace() {
    if (!hasCoordinates) {
      throw StateError('Suggestion $id has no coordinates; resolve it first');
    }
    return Place(
      name: name,
      address: address,
      latitude: latitude!,
      longitude: longitude!,
    );
  }
}

@immutable
class PlaceSearchResult {
  const PlaceSearchResult({required this.suggestions, this.degraded = false});

  factory PlaceSearchResult.fromJson(Map<String, dynamic> json) =>
      PlaceSearchResult(
        suggestions: (json['suggestions'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PlaceSuggestion.fromJson)
            .toList(),
        degraded: json['degraded'] as bool? ?? false,
      );

  final List<PlaceSuggestion> suggestions;

  /// Full search was unavailable; only popular places were searched.
  final bool degraded;
}

/// The place at a coordinate, from `GET /places/reverse`.
@immutable
class ReverseGeocodedPlace {
  const ReverseGeocodedPlace({required this.place, required this.approximate});

  factory ReverseGeocodedPlace.fromJson(Map<String, dynamic> json) =>
      ReverseGeocodedPlace(
        place: Place(
          name: json['name'] as String,
          address: json['address'] as String,
          latitude: (json['latitude'] as num).toDouble(),
          longitude: (json['longitude'] as num).toDouble(),
        ),
        approximate: json['approximate'] as bool? ?? false,
      );

  final Place place;

  /// No street name was found; the address is a coordinate label. The pin
  /// itself is still exact and bookable.
  final bool approximate;
}

/// "350 m" / "4.2 km" / "38 km" for suggestion rows.
String formatDistance(int meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}
