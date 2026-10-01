import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../models/complaint_models.dart';

class ComplaintRepository {
  const ComplaintRepository(this._dio);

  final Dio _dio;

  Future<Complaint> create({
    required ComplaintCategory category,
    required String subject,
    required String description,
    String? rideId,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.complaints,
      data: {
        'category': category.wireName,
        'subject': subject,
        'description': description,
        'rideId': ?rideId,
      },
    );
    return Complaint.fromJson(response.data!['data'] as Map<String, dynamic>);
  });

  Future<ComplaintPage> list({int page = 1, int limit = 20}) =>
      _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.complaints,
          queryParameters: {'page': page, 'limit': limit},
        );
        return ComplaintPage.fromJson(
          response.data!['data'] as Map<String, dynamic>,
        );
      });

  Future<Complaint> get(String id) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.complaint(id),
    );
    return Complaint.fromJson(response.data!['data'] as Map<String, dynamic>);
  });

  static Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final complaintRepositoryProvider = Provider<ComplaintRepository>(
  (ref) => ComplaintRepository(ref.watch(dioProvider)),
);

final complaintsProvider = FutureProvider.autoDispose<ComplaintPage>(
  (ref) => ref.watch(complaintRepositoryProvider).list(limit: 50),
);

final complaintProvider = FutureProvider.autoDispose.family<Complaint, String>(
  (ref, id) => ref.watch(complaintRepositoryProvider).get(id),
);
