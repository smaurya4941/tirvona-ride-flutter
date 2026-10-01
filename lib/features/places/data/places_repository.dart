import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../rides/domain/ride_models.dart';
import '../domain/place_suggestion.dart';
import '../domain/saved_place.dart';

typedef GeoPoint = ({double latitude, double longitude});

/// Place search through the Tirvona API, which proxies and caches the maps
/// provider — the app holds no maps key of its own.
class PlacesRepository {
  const PlacesRepository(this._dio);

  final Dio _dio;

  /// Search as the rider types. Pass a [cancelToken] so a newer keystroke
  /// can abandon this request.
  Future<PlaceSearchResult> autocomplete(
    String query, {
    GeoPoint? near,
    String? sessionToken,
    int limit = 8,
    CancelToken? cancelToken,
  }) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.placesAutocomplete,
      queryParameters: {
        'q': query,
        'limit': limit,
        ..._near(near),
        'sessionToken': ?sessionToken,
      },
      cancelToken: cancelToken,
    );
    return PlaceSearchResult.fromJson(_data(response));
  });

  /// Coordinates for a suggestion that came without them.
  Future<Place> resolve(PlaceSuggestion suggestion, {String? sessionToken}) =>
      _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.placesResolve,
          queryParameters: {'id': suggestion.id, 'sessionToken': ?sessionToken},
        );
        final data = _data(response);
        return Place(
          // Keep the short label the rider tapped.
          name: suggestion.name,
          address: data['address'] as String,
          latitude: (data['latitude'] as num).toDouble(),
          longitude: (data['longitude'] as num).toDouble(),
        );
      });

  /// Names the place at [point]. The server always answers, falling back to
  /// a coordinate label when no street name is known.
  Future<ReverseGeocodedPlace> reverse(GeoPoint point) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.placesReverse,
      queryParameters: _near(point),
    );
    return ReverseGeocodedPlace.fromJson(_data(response));
  });

  Future<List<PlaceSuggestion>> popular({GeoPoint? near, int limit = 8}) =>
      _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.placesPopular,
          queryParameters: {'limit': limit, ..._near(near)},
        );
        return (response.data!['data'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(PlaceSuggestion.fromJson)
            .toList();
      });

  /// The rider's saved Home and Work (kept on the server, per account).
  Future<SavedPlaces> savedPlaces() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.placesSaved,
    );
    return SavedPlaces.fromJson(_data(response));
  });

  Future<SavedPlaces> savePlace(SavedPlaceKind kind, Place place) =>
      _guard(() async {
        final response = await _dio.put<Map<String, dynamic>>(
          ApiEndpoints.placesSavedKind(kind.name),
          data: {
            // The address already reads as the place when there is no
            // separate short name.
            if (place.name != null && place.name != place.address)
              'name': place.name,
            ...place.toJson(),
          },
        );
        return SavedPlaces.fromJson(_data(response));
      });

  Future<SavedPlaces> clearSavedPlace(SavedPlaceKind kind) => _guard(() async {
    final response = await _dio.delete<Map<String, dynamic>>(
      ApiEndpoints.placesSavedKind(kind.name),
    );
    return SavedPlaces.fromJson(_data(response));
  });

  /// Saves one of the rider's own labelled places.
  Future<SavedPlaces> addOtherPlace(String label, Place place) =>
      _guard(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.placesSavedOthers,
          data: {'label': label, ..._savedPlaceBody(place)},
        );
        return SavedPlaces.fromJson(_data(response));
      });

  /// Renames ([label]) and/or moves ([place]) one of the rider's places.
  Future<SavedPlaces> updateOtherPlace(
    String id, {
    String? label,
    Place? place,
  }) => _guard(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.placesSavedOther(id),
      data: {
        'label': ?label,
        // Moving replaces the short name too (empty clears it).
        if (place != null) ...{
          'name': place.name != null && place.name != place.address
              ? place.name
              : '',
          ...place.toJson(),
        },
      },
    );
    return SavedPlaces.fromJson(_data(response));
  });

  Future<SavedPlaces> removeOtherPlace(String id) => _guard(() async {
    final response = await _dio.delete<Map<String, dynamic>>(
      ApiEndpoints.placesSavedOther(id),
    );
    return SavedPlaces.fromJson(_data(response));
  });

  static Map<String, dynamic> _savedPlaceBody(Place place) => {
    // The address already reads as the place when there is no separate
    // short name.
    if (place.name != null && place.name != place.address) 'name': place.name,
    ...place.toJson(),
  };

  static Map<String, dynamic> _near(GeoPoint? point) => point == null
      ? const {}
      : {
          'latitude': point.latitude.toStringAsFixed(6),
          'longitude': point.longitude.toStringAsFixed(6),
        };

  static Map<String, dynamic> _data(Response<Map<String, dynamic>> response) =>
      response.data!['data'] as Map<String, dynamic>;

  static Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final placesRepositoryProvider = Provider<PlacesRepository>(
  (ref) => PlacesRepository(ref.watch(dioProvider)),
);
