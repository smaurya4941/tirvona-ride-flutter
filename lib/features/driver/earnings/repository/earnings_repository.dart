import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../models/earning_models.dart';

/// Read-only: every earning is computed and written by the server.
class EarningsRepository {
  const EarningsRepository(this._dio);

  final Dio _dio;

  Future<EarningsPage> list({
    EarningsPeriod period = EarningsPeriod.all,
    int page = 1,
    int limit = 20,
  }) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.earnings,
      queryParameters: {
        'period': period.wireName,
        'page': page,
        'limit': limit,
      },
    );
    return EarningsPage.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    );
  });

  Future<Earning> detail(String id) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.earning(id),
    );
    return Earning.fromJson(response.data!['data'] as Map<String, dynamic>);
  });

  static Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final earningsRepositoryProvider = Provider<EarningsRepository>(
  (ref) => EarningsRepository(ref.watch(dioProvider)),
);
