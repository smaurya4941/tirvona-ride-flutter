import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../rides/domain/ride_models.dart';
import '../domain/circuit_models.dart';

/// Every circuit call the apps make. Like rides, nothing priced or ordered is
/// ever sent: the client names a package, a pickup, a vehicle and a passenger
/// count, and the server works out the rest. Driver progress is a set of
/// explicit commands the server validates; there is no "set status".
class CircuitRepository {
  const CircuitRepository(this._dio);

  final Dio _dio;

  // ── Customer ────────────────────────────────────────────────────────

  Future<List<CircuitPackage>> packages({String? city}) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.circuitPackages,
      queryParameters: {'city': ?city},
    );
    return _list(response).map(CircuitPackage.fromJson).toList();
  });

  Future<CircuitPackage> package(String id) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.circuitPackage(id),
    );
    return CircuitPackage.fromJson(_data(response));
  });

  Future<CircuitEstimate> estimate({
    required String packageId,
    required RideTypeCode rideType,
    required Place pickup,
    required int passengers,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.circuitEstimate,
      data: _quote(packageId, rideType, pickup, passengers),
    );
    return CircuitEstimate.fromJson(_data(response));
  });

  /// [idempotencyKey] must be the same for every retry of one booking: a
  /// repeated tap or a retry after a lost response returns the first booking
  /// instead of creating a second circuit.
  Future<Ride> book({
    required String packageId,
    required RideTypeCode rideType,
    required Place pickup,
    required int passengers,
    required String idempotencyKey,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.circuitRides,
      data: _quote(packageId, rideType, pickup, passengers),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return Ride.fromJson(_data(response));
  });

  // ── Driver ──────────────────────────────────────────────────────────

  Future<Ride> arriveAtStop(String rideId, int order) =>
      _command(ApiEndpoints.circuitStopAction(rideId, order, 'arrive'));

  Future<Ride> waitAtStop(String rideId, int order) =>
      _command(ApiEndpoints.circuitStopAction(rideId, order, 'waiting'));

  Future<Ride> completeStop(String rideId, int order) =>
      _command(ApiEndpoints.circuitStopAction(rideId, order, 'complete'));

  Future<Ride> reportStopBlocked(String rideId, int order, {String? note}) =>
      _command(ApiEndpoints.circuitStopAction(rideId, order, 'blocked'), {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  Future<Ride> completeCircuit(String rideId) =>
      _command(ApiEndpoints.circuitAction(rideId, 'complete'));

  // ── Helpers ─────────────────────────────────────────────────────────

  Future<Ride> _command(String path, [Map<String, dynamic>? body]) =>
      _guard(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          path,
          data: body ?? const <String, dynamic>{},
        );
        return Ride.fromJson(_data(response));
      });

  static Map<String, dynamic> _quote(
    String packageId,
    RideTypeCode rideType,
    Place pickup,
    int passengers,
  ) => {
    'packageId': packageId,
    'rideType': rideType.wireName,
    'pickup': pickup.toJson(),
    'passengers': passengers,
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

/// A fresh key per booking attempt (kept across that attempt's retries).
String newIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return 'circuit-${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
}

final circuitRepositoryProvider = Provider<CircuitRepository>(
  (ref) => CircuitRepository(ref.watch(dioProvider)),
);
