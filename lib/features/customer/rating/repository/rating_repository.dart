import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../models/rating_models.dart';

/// Customer → driver ratings. The app sends only the stars and an optional
/// comment; which driver is rated comes from the ride on the server.
class RatingRepository {
  const RatingRepository(this._dio);

  final Dio _dio;

  Future<RideRatingStatus> status(String rideId) => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.rideRating(rideId),
    );
    return RideRatingStatus.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    );
  });

  Future<RideRating> rate(
    String rideId, {
    required int rating,
    String? comment,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.rideRating(rideId),
      data: {
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
    );
    return RideRating.fromJson(response.data!['data'] as Map<String, dynamic>);
  });

  static Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final ratingRepositoryProvider = Provider<RatingRepository>(
  (ref) => RatingRepository(ref.watch(dioProvider)),
);

final rideRatingProvider = FutureProvider.autoDispose
    .family<RideRatingStatus, String>(
      (ref, rideId) => ref.watch(ratingRepositoryProvider).status(rideId),
    );
