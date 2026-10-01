import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';

/// `GET /drivers/me/ratings`: the aggregate only — individual ratings stay
/// anonymous to the driver.
@immutable
class DriverRatingSummary {
  const DriverRatingSummary({
    required this.ratingAverage,
    required this.ratingCount,
    required this.totalRides,
    required this.distribution,
  });

  factory DriverRatingSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['distribution'] as Map<String, dynamic>? ?? const {};
    return DriverRatingSummary(
      ratingAverage: (json['ratingAverage'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      totalRides: (json['totalRides'] as num?)?.toInt() ?? 0,
      distribution: {
        for (var star = 1; star <= 5; star++)
          star: (raw['$star'] as num?)?.toInt() ?? 0,
      },
    );
  }

  final double ratingAverage;
  final int ratingCount;
  final int totalRides;

  /// Stars (1–5) → number of ratings.
  final Map<int, int> distribution;
}

final driverRatingSummaryProvider =
    FutureProvider.autoDispose<DriverRatingSummary>((ref) async {
      final dio = ref.watch(dioProvider);
      try {
        final response = await dio.get<Map<String, dynamic>>(
          ApiEndpoints.driverRatings,
        );
        return DriverRatingSummary.fromJson(
          response.data!['data'] as Map<String, dynamic>,
        );
      } on DioException catch (error) {
        throw ApiException.fromDio(error);
      }
    });

/// Profile card: "4.7 ★ · Based on 128 ratings" with a star breakdown.
class DriverRatingCard extends ConsumerWidget {
  const DriverRatingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(driverRatingSummaryProvider).value;
    if (summary == null) return const SizedBox.shrink();
    final max = summary.distribution.values.fold<int>(
      0,
      (a, b) => a > b ? a : b,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Column(
              children: [
                Text(
                  summary.ratingCount == 0
                      ? '—'
                      : summary.ratingAverage.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: AppColors.midnightBlue,
                  ),
                ),
                const Icon(Icons.star_rounded, color: AppColors.sacredGold),
                const SizedBox(height: 4),
                Text(
                  summary.ratingCount == 0
                      ? 'No ratings yet'
                      : 'Based on ${summary.ratingCount} '
                            'rating${summary.ratingCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${summary.totalRides} rides',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [
                  for (var star = 5; star >= 1; star--)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            child: Text(
                              '$star',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 8,
                                value: max == 0
                                    ? 0
                                    : summary.distribution[star]! / max,
                                backgroundColor: AppColors.surfaceSand,
                                color: AppColors.sacredGold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${summary.distribution[star]}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
