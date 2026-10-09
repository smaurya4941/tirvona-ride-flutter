import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../domain/cancellation_models.dart';
import '../domain/live_tracking.dart';
import '../domain/nearby_driver.dart';
import '../domain/promo_models.dart';
import '../domain/ride_models.dart';

/// Every ride call the customer and driver apps make. Fares are never sent:
/// the server prices each estimate and each booking itself.
class RideRepository {
  const RideRepository(this._dio);

  final Dio _dio;

  // ── Customer ────────────────────────────────────────────────────────

  /// Ride types customers can book right now (admins switch them on/off).
  Future<List<RideTypeInfo>> rideTypes() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.rideTypes,
    );
    return _list(response).map(RideTypeInfo.fromJson).toList();
  });

  Future<List<FareEstimate>> estimateAll({
    required Place pickup,
    required Place destination,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.ridesEstimateAll,
      data: {'pickup': pickup.toJson(), 'destination': destination.toJson()},
    );
    return _list(response).map(FareEstimate.fromJson).toList();
  });

  Future<FareEstimate> estimate({
    required RideTypeCode rideType,
    required Place pickup,
    required Place destination,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.ridesEstimate,
      data: _trip(rideType, pickup, destination),
    );
    return FareEstimate.fromJson(_data(response));
  });

  /// [promoCode] is validated and reserved by the server for this ride.
  Future<Ride> book({
    required RideTypeCode rideType,
    required Place pickup,
    required Place destination,
    String? promoCode,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.rides,
      data: {
        ..._trip(rideType, pickup, destination),
        if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
      },
    );
    return Ride.fromJson(_data(response));
  });

  /// Server-priced promo check for a trip. Throws ApiException with a
  /// PROMO_* code (invalid, expired, not eligible…) when it does not apply.
  Future<PromoQuote> validatePromo({
    required String code,
    required RideTypeCode rideType,
    required Place pickup,
    required Place destination,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.promotionsValidate,
      data: {..._trip(rideType, pickup, destination), 'code': code},
    );
    return PromoQuote.fromJson(_data(response));
  });

  /// Trip-free check of a code (Offers screen): active, in date, uses
  /// left. Ride type and minimum fare are checked later by [validatePromo].
  Future<PromoOffer> checkPromo(String code) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.promotionsCheck,
      data: {'code': code},
    );
    return PromoOffer.fromJson(_data(response));
  });

  /// Live offers listed in the app.
  Future<List<PromoOffer>> promoOffers() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.promotions,
    );
    return _list(response).map(PromoOffer.fromJson).toList();
  });

  /// Free drivers around [latitude]/[longitude] for the Home map.
  Future<List<NearbyDriver>> nearbyDrivers({
    required double latitude,
    required double longitude,
  }) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.ridesNearbyDrivers,
      queryParameters: {
        'latitude': latitude.toStringAsFixed(6),
        'longitude': longitude.toStringAsFixed(6),
      },
    );
    return (_data(response)['drivers'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(NearbyDriver.fromJson)
        .toList();
  });

  /// Distinct destinations of the rider's past bookings, newest first.
  Future<List<Place>> recentDestinations({int limit = 8}) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.ridesRecentDestinations,
      queryParameters: {'limit': limit},
    );
    return _list(response).map((json) {
      final place = Place.fromJson(json);
      // "DLF Mall of India, Sector 18, Noida": the first part is the title.
      final comma = place.address.indexOf(',');
      return comma <= 0
          ? place
          : Place(
              name: place.address.substring(0, comma).trim(),
              address: place.address,
              latitude: place.latitude,
              longitude: place.longitude,
            );
    }).toList();
  });

  // ── Shared ──────────────────────────────────────────────────────────

  Future<Ride> getRide(String id) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.ride(id),
    );
    return Ride.fromJson(_data(response));
  });

  Future<Ride?> getActiveRide() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.ridesActive,
    );
    final data = response.data!['data'];
    return data == null ? null : Ride.fromJson(data as Map<String, dynamic>);
  });

  /// The driver's live road route for an accepted or started ride; null when
  /// there is none (searching, waiting at the pickup, finished) or the
  /// driver's position is not known yet.
  Future<LiveRoute?> liveRoute(String id) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.rideRoute(id),
    );
    final data = response.data!['data'];
    return data == null
        ? null
        : LiveRoute.fromJson(data as Map<String, dynamic>);
  });

  /// The caller's rides, newest first. [startDate] is inclusive and
  /// [endDate] exclusive; both are sent as UTC instants so local-midnight
  /// boundaries survive the trip to the server.
  Future<RidePage> history({
    int page = 1,
    int limit = 20,
    DateTime? startDate,
    DateTime? endDate,
  }) => _guard(() async {
    final queryParameters = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (startDate != null) 'startDate': startDate.toUtc().toIso8601String(),
      if (endDate != null) 'endDate': endDate.toUtc().toIso8601String(),
    };
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.rides,
      queryParameters: queryParameters,
    );
    return RidePage.fromJson(_data(response));
  });

  /// Allowed reasons and any fee, before the user confirms a cancellation.
  Future<CancellationPreview> cancellationPreview(String id) =>
      _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.rideCancellation(id),
        );
        return CancellationPreview.fromJson(_data(response));
      });

  /// [reasonCode] from [cancellationPreview]; [note] for reasons that need one.
  Future<Ride> cancel(String id, {String? reasonCode, String? note}) =>
      _guard(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.rideAction(id, 'cancel'),
          data: {
            'reasonCode': ?reasonCode,
            if (note != null && note.trim().isNotEmpty) 'reason': note.trim(),
          },
        );
        return Ride.fromJson(_data(response));
      });

  // ── Driver ──────────────────────────────────────────────────────────

  /// Offers currently assigned to this driver (recovery after reconnect;
  /// new offers arrive live as `ride.requested`).
  Future<List<Ride>> driverRequests() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.ridesRequests,
    );
    return _list(response).map(Ride.fromJson).toList();
  });

  Future<Ride> accept(String id) => _action(id, 'accept');

  Future<void> reject(String id, {String? reason}) => _guard(() async {
    await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.rideAction(id, 'reject'),
      data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
  });

  Future<Ride> markArrived(String id) => _action(id, 'arrived');

  Future<Ride> start(String id, {required String otp}) =>
      _action(id, 'start', {'otp': otp});

  /// Asks to end the trip: the fare is frozen to now and the rider's app
  /// shows the end-of-trip code. The ride stays "in progress" until
  /// [complete] is called with that code.
  Future<Ride> requestEnd(String id) => _action(id, 'request-end');

  /// Takes the end request back; the trip continues.
  Future<Ride> cancelEnd(String id) => _action(id, 'cancel-end');

  /// Completes the trip with the rider's end-of-trip [otp].
  Future<Ride> complete(String id, {required String otp}) =>
      _action(id, 'complete', {'otp': otp});

  /// "Rider not responding": allowed by the server only after the wait that
  /// [RideEndOtp.overrideAvailableAt] shows (or while an SOS is open). The
  /// trip is flagged for review with [reason].
  Future<Ride> completeWithoutOtp(String id, {required String reason}) =>
      _action(id, 'complete-without-otp', {'reason': reason});

  Future<DriverDashboard> dashboard() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.driversDashboard,
    );
    return DriverDashboard.fromJson(_data(response));
  });

  Future<void> setAvailability({required bool online, Place? location}) =>
      _guard(() async {
        await _dio.patch<Map<String, dynamic>>(
          ApiEndpoints.driversAvailability,
          data: {
            'isOnline': online,
            if (location != null) 'latitude': location.latitude,
            if (location != null) 'longitude': location.longitude,
          },
        );
      });

  /// REST fallback for the `driver.location` socket message.
  Future<void> updateLocation(Map<String, dynamic> fix) => _guard(() async {
    await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.driversLocation,
      data: fix,
    );
  });

  // ── Helpers ─────────────────────────────────────────────────────────

  Future<Ride> _action(
    String id,
    String action, [
    Map<String, dynamic>? body,
  ]) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.rideAction(id, action),
      data: body ?? const <String, dynamic>{},
    );
    return Ride.fromJson(_data(response));
  });

  static Map<String, dynamic> _trip(
    RideTypeCode rideType,
    Place pickup,
    Place destination,
  ) => {
    'rideType': rideType.wireName,
    'pickup': pickup.toJson(),
    'destination': destination.toJson(),
  };

  static Map<String, dynamic> _data(Response<Map<String, dynamic>> response) =>
      response.data!['data'] as Map<String, dynamic>;

  static Iterable<Map<String, dynamic>> _list(
    Response<Map<String, dynamic>> response,
  ) => (response.data!['data'] as List<dynamic>).cast<Map<String, dynamic>>();

  static Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final rideRepositoryProvider = Provider<RideRepository>(
  (ref) => RideRepository(ref.watch(dioProvider)),
);
