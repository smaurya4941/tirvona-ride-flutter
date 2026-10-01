import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../domain/branding.dart';

/// Reads the public branding endpoints. Uses its own Dio without the auth
/// interceptor: branding is needed before sign-in and must never trigger a
/// token refresh or a session-expired sign-out.
class BrandingRepository {
  BrandingRepository(this._dio);

  final Dio _dio;

  Future<RemoteBranding> fetch() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiEndpoints.branding,
      );
      return RemoteBranding.fromJson(
        response.data!['data'] as Map<String, dynamic>,
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<int>> download(RemoteBrandAsset asset) async {
    try {
      final response = await _dio.get<List<int>>(
        asset.path,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('Empty branding image');
      }
      return bytes;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final brandingRepositoryProvider = Provider<BrandingRepository>((ref) {
  final dio = createDio(ref.watch(appConfigProvider));
  ref.onDispose(dio.close);
  return BrandingRepository(dio);
});
