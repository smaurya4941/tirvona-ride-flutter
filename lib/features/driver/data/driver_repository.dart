import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../domain/driver_models.dart';

class DriverRepository {
  const DriverRepository(this._dio);

  final Dio _dio;

  Future<DriverProfile> getProfile() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.driversMe,
    );
    return DriverProfile.fromJson(_data(response));
  });

  Future<DriverProfile> updateProfile({
    required String licenseNumber,
    required DateTime licenseExpiry,
    DateTime? dateOfBirth,
    String? address,
  }) => _guard(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.driversMe,
      data: {
        'licenseNumber': licenseNumber,
        'licenseExpiry': _isoDate(licenseExpiry),
        if (dateOfBirth != null) 'dateOfBirth': _isoDate(dateOfBirth),
        if (address != null && address.isNotEmpty) 'address': address,
      },
    );
    return DriverProfile.fromJson(_data(response));
  });

  Future<List<KycDocument>> listDocuments() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.driversMeDocuments,
    );
    return (response.data!['data'] as List<dynamic>)
        .map((item) => KycDocument.fromJson(item as Map<String, dynamic>))
        .toList();
  });

  Future<KycDocument> uploadDocument({
    required KycDocumentType type,
    required String filePath,
    String? documentNumber,
  }) => _guard(() async {
    final form = FormData.fromMap({
      'documentType': type.wireName,
      if (documentNumber != null && documentNumber.isNotEmpty)
        'documentNumber': documentNumber,
      'file': await MultipartFile.fromFile(filePath),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.driversMeDocuments,
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
        // Uploads of a phone camera photo can take a while on 3G/4G.
        sendTimeout: const Duration(minutes: 2),
      ),
    );
    return KycDocument.fromJson(_data(response));
  });

  Future<void> deleteDocument(String id) => _guard(() async {
    await _dio.delete<void>(ApiEndpoints.driversMeDocument(id));
  });

  Future<DriverProfile> submitKyc() => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.driversMeSubmitKyc,
    );
    return DriverProfile.fromJson(_data(response));
  });

  static Map<String, dynamic> _data(Response<Map<String, dynamic>> response) =>
      response.data!['data'] as Map<String, dynamic>;

  static String _isoDate(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).toIso8601String();

  static Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final driverRepositoryProvider = Provider<DriverRepository>(
  (ref) => DriverRepository(ref.watch(dioProvider)),
);

final driverProfileProvider = FutureProvider.autoDispose<DriverProfile>(
  (ref) => ref.watch(driverRepositoryProvider).getProfile(),
);

final driverDocumentsProvider = FutureProvider.autoDispose<List<KycDocument>>(
  (ref) => ref.watch(driverRepositoryProvider).listDocuments(),
);
