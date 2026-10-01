import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../models/safety_models.dart';

/// Emergency contacts, SOS and share-ride. The server decides whether an
/// SOS is allowed and generates share tokens; the app never builds either.
class SafetyRepository {
  const SafetyRepository(this._dio);

  final Dio _dio;

  // ── Emergency contacts ────────────────────────────────────────────────

  Future<List<EmergencyContact>> contacts() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.emergencyContacts,
    );
    return (response.data!['data'] as List<dynamic>)
        .map((item) => EmergencyContact.fromJson(item as Map<String, dynamic>))
        .toList();
  });

  Future<EmergencyContact> addContact({
    required String name,
    required String phone,
    String? relationship,
    bool isPrimary = false,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.emergencyContacts,
      data: {
        'name': name,
        'phone': phone,
        if (relationship != null && relationship.isNotEmpty)
          'relationship': relationship,
        if (isPrimary) 'isPrimary': true,
      },
    );
    return EmergencyContact.fromJson(_data(response));
  });

  Future<EmergencyContact> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    bool? makePrimary,
  }) => _guard(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.emergencyContact(id),
      data: {
        'name': ?name,
        'phone': ?phone,
        'relationship': ?relationship,
        if (makePrimary == true) 'isPrimary': true,
      },
    );
    return EmergencyContact.fromJson(_data(response));
  });

  Future<void> deleteContact(String id) => _guard(() async {
    await _dio.delete<Map<String, dynamic>>(ApiEndpoints.emergencyContact(id));
  });

  // ── SOS ───────────────────────────────────────────────────────────────

  Future<SosAlert> triggerSos(
    String rideId, {
    SosFix? fix,
    String? message,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.rideSos(rideId),
      data: {
        if (fix != null) ...{
          'latitude': fix.latitude,
          'longitude': fix.longitude,
          if (fix.accuracyMeters != null) 'accuracyMeters': fix.accuracyMeters,
        },
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      },
    );
    return SosAlert.fromJson(_data(response)['sos'] as Map<String, dynamic>);
  });

  Future<List<SosAlert>> sosForRide(String rideId) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.rideSos(rideId),
    );
    return (response.data!['data'] as List<dynamic>)
        .map((item) => SosAlert.fromJson(item as Map<String, dynamic>))
        .toList();
  });

  // ── Share ride ────────────────────────────────────────────────────────

  Future<ShareLink> createShareLink(String rideId) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.rideShare(rideId),
    );
    return ShareLink.fromJson(_data(response));
  });

  Future<int> activeShareLinks(String rideId) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.rideShare(rideId),
    );
    return (_data(response)['active'] as num).toInt();
  });

  Future<void> stopSharing(String rideId) => _guard(() async {
    await _dio.delete<Map<String, dynamic>>(ApiEndpoints.rideShare(rideId));
  });

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

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SafetyRepository(ref.watch(dioProvider)),
);

final emergencyContactsProvider =
    FutureProvider.autoDispose<List<EmergencyContact>>(
      (ref) => ref.watch(safetyRepositoryProvider).contacts(),
    );

/// The caller's SOS alerts on a ride (status shown after an alert).
final rideSosProvider = FutureProvider.autoDispose
    .family<List<SosAlert>, String>(
      (ref, rideId) => ref.watch(safetyRepositoryProvider).sosForRide(rideId),
    );

final activeShareLinksProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, rideId) => ref.watch(safetyRepositoryProvider).activeShareLinks(rideId),
);
