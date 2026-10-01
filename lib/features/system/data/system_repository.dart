import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../domain/backend_health.dart';

class SystemRepository {
  const SystemRepository(this._dio);

  final Dio _dio;

  /// A degraded backend answers 503 with the full report, which is still a
  /// successful health *check* — only transport failures throw.
  Future<BackendHealth> checkHealth() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiEndpoints.health,
      );
      return BackendHealth.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      final body = error.response?.data;
      if (error.response?.statusCode == 503 &&
          body is Map<String, dynamic> &&
          body['data'] is Map<String, dynamic>) {
        return BackendHealth.fromJson(body['data'] as Map<String, dynamic>);
      }
      throw ApiException.fromDio(error);
    }
  }
}

final systemRepositoryProvider = Provider<SystemRepository>(
  (ref) => SystemRepository(ref.watch(dioProvider)),
);
