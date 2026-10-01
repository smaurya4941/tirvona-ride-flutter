import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../data/driver_repository.dart';
import '../../domain/driver_models.dart';
import '../domain/driver_change.dart';

/// Requested vehicle details; only non-null fields are sent (and the server
/// drops the ones equal to the verified values).
class VehicleChange {
  const VehicleChange({
    this.vehicleType,
    this.registrationNumber,
    this.make,
    this.model,
    this.color,
    this.manufactureYear,
  });

  final VehicleType? vehicleType;
  final String? registrationNumber;
  final String? make;
  final String? model;
  final String? color;
  final int? manufactureYear;

  Map<String, dynamic> toJson() => {
    'vehicleType': ?vehicleType?.wireName,
    'registrationNumber': ?registrationNumber
        ?.replaceAll(RegExp(r'\s'), '')
        .toUpperCase(),
    'make': ?make,
    'model': ?model,
    'color': ?color,
    'manufactureYear': ?manufactureYear,
  };
}

/// An approved driver's account: address (self-service), change requests
/// for verified details, vehicle documents, and their individual ratings.
class DriverAccountRepository {
  const DriverAccountRepository(this._dio);

  final Dio _dio;

  Future<DriverChangesOverview> changes() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.driverChangeRequests,
    );
    return DriverChangesOverview.fromJson(_data(response));
  });

  /// The one field an approved driver edits without review.
  Future<DriverProfile> updateAddress(String address) => _guard(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.driversMe,
      data: {'address': address},
    );
    return DriverProfile.fromJson(_data(response));
  });

  Future<DriverChangeRequest> requestProfileChange({
    String? licenseNumber,
    DateTime? licenseExpiry,
    DateTime? dateOfBirth,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.driverChangeProfile,
      data: {
        'licenseNumber': ?licenseNumber,
        if (licenseExpiry != null) 'licenseExpiry': isoDate(licenseExpiry),
        if (dateOfBirth != null) 'dateOfBirth': isoDate(dateOfBirth),
      },
    );
    return DriverChangeRequest.fromJson(_data(response));
  });

  Future<DriverChangeRequest> requestVehicleChange(
    String vehicleId,
    VehicleChange change,
  ) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.driverChangeVehicle,
      data: {'vehicleId': vehicleId, ...change.toJson()},
    );
    return DriverChangeRequest.fromJson(_data(response));
  });

  /// A new or renewed document. Driver documents pass [driverDocument];
  /// vehicle documents pass [vehicleDocument] and [vehicleId].
  Future<DriverChangeRequest> requestDocumentChange({
    KycDocumentType? driverDocument,
    VehicleDocumentType? vehicleDocument,
    String? vehicleId,
    required String filePath,
    String? documentNumber,
    DateTime? expiryDate,
  }) => _guard(() async {
    assert(
      (driverDocument == null) != (vehicleDocument == null),
      'Pass exactly one document type',
    );
    final form = FormData.fromMap({
      'scope': driverDocument != null ? 'DRIVER' : 'VEHICLE',
      'documentType': driverDocument?.wireName ?? vehicleDocument!.wireName,
      'vehicleId': ?vehicleId,
      if (documentNumber != null && documentNumber.isNotEmpty)
        'documentNumber': documentNumber,
      if (expiryDate != null) 'expiryDate': isoDate(expiryDate),
      'file': await MultipartFile.fromFile(filePath),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.driverChangeDocument,
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        // A phone camera photo on a slow mobile connection.
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    return DriverChangeRequest.fromJson(_data(response));
  });

  Future<DriverChangeRequest> withdraw(String id) => _guard(() async {
    final response = await _dio.delete<Map<String, dynamic>>(
      ApiEndpoints.driverChangeRequest(id),
    );
    return DriverChangeRequest.fromJson(_data(response));
  });

  Future<List<VehicleDocumentRecord>> vehicleDocuments(String vehicleId) =>
      _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.vehicleDocuments(vehicleId),
        );
        return [
          for (final item in response.data!['data'] as List<dynamic>)
            ?VehicleDocumentRecord.tryFromJson(item as Map<String, dynamic>),
        ];
      });

  Future<DriverReviewsPage> reviews({
    String? cursor,
    int limit = 20,
    int? stars,
    bool withComment = false,
  }) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.driverReviews,
      queryParameters: {
        'limit': limit,
        'cursor': ?cursor,
        'stars': ?stars,
        if (withComment) 'withComment': 'true',
      },
    );
    return DriverReviewsPage.fromJson(_data(response));
  });

  /// A calendar day as the API expects it ("2027-03-31").
  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

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

final driverAccountRepositoryProvider = Provider<DriverAccountRepository>(
  (ref) => DriverAccountRepository(ref.watch(dioProvider)),
);

/// Pending changes and recent decisions.
final driverChangesProvider = FutureProvider.autoDispose<DriverChangesOverview>(
  (ref) => ref.watch(driverAccountRepositoryProvider).changes(),
);

final vehicleDocumentsProvider = FutureProvider.autoDispose
    .family<List<VehicleDocumentRecord>, String>(
      (ref, vehicleId) => ref
          .watch(driverAccountRepositoryProvider)
          .vehicleDocuments(vehicleId),
    );

/// After a change is submitted or withdrawn, or the address saved: refetch
/// everything the account screens show.
void refreshDriverAccount(WidgetRef ref) {
  ref
    ..invalidate(driverChangesProvider)
    ..invalidate(driverProfileProvider)
    ..invalidate(driverDocumentsProvider);
}
