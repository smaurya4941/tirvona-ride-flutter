import 'package:flutter/foundation.dart';

/// Why a ride cannot be rated (server `RatingBlocker`).
enum RatingBlocker {
  rideNotCompleted('RIDE_NOT_COMPLETED'),
  paymentNotVerified('PAYMENT_NOT_VERIFIED'),
  noDriver('NO_DRIVER'),
  windowClosed('WINDOW_CLOSED'),
  alreadyRated('ALREADY_RATED'),
  unknown('');

  const RatingBlocker(this.wireName);

  final String wireName;

  static RatingBlocker? fromWire(String? value) => value == null
      ? null
      : values.firstWhere(
          (blocker) => blocker.wireName == value,
          orElse: () => RatingBlocker.unknown,
        );
}

@immutable
class RideRating {
  const RideRating({
    required this.id,
    required this.rating,
    required this.createdAt,
    this.comment,
  });

  factory RideRating.fromJson(Map<String, dynamic> json) => RideRating(
    id: json['id'] as String,
    rating: (json['rating'] as num).toInt(),
    comment: json['comment'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );

  final String id;
  final int rating;
  final String? comment;
  final DateTime createdAt;
}

@immutable
class RatedDriver {
  const RatedDriver({
    required this.name,
    required this.ratingAverage,
    required this.ratingCount,
    this.vehicleType,
    this.registrationNumber,
    this.vehicleDescription,
  });

  factory RatedDriver.fromJson(Map<String, dynamic> json) {
    final vehicle = json['vehicle'] as Map<String, dynamic>?;
    return RatedDriver(
      name: json['name'] as String? ?? 'Your driver',
      ratingAverage: (json['ratingAverage'] as num?)?.toDouble() ?? 0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
      vehicleType: vehicle?['vehicleType'] as String?,
      registrationNumber: vehicle?['registrationNumber'] as String?,
      vehicleDescription: vehicle == null
          ? null
          : [
              vehicle['color'],
              vehicle['make'],
              vehicle['model'],
            ].whereType<String>().where((part) => part.isNotEmpty).join(' '),
    );
  }

  final String name;
  final double ratingAverage;
  final int ratingCount;
  final String? vehicleType;
  final String? registrationNumber;
  final String? vehicleDescription;
}

/// `GET /rides/:id/rating`: the caller's rating, or whether they may rate.
@immutable
class RideRatingStatus {
  const RideRatingStatus({
    required this.rideId,
    required this.canRate,
    this.reason,
    this.rating,
    this.driver,
  });

  factory RideRatingStatus.fromJson(Map<String, dynamic> json) =>
      RideRatingStatus(
        rideId: json['rideId'] as String,
        canRate: json['canRate'] as bool? ?? false,
        reason: RatingBlocker.fromWire(json['reason'] as String?),
        rating: json['rating'] == null
            ? null
            : RideRating.fromJson(json['rating'] as Map<String, dynamic>),
        driver: json['driver'] == null
            ? null
            : RatedDriver.fromJson(json['driver'] as Map<String, dynamic>),
      );

  final String rideId;
  final bool canRate;
  final RatingBlocker? reason;
  final RideRating? rating;
  final RatedDriver? driver;
}

/// Quick compliments / issues that pre-fill the comment.
List<String> ratingSuggestions(int stars) => stars >= 4
    ? const ['Polite driver', 'Safe driving', 'Clean vehicle', 'On time']
    : const [
        'Rude behaviour',
        'Unsafe driving',
        'Took a longer route',
        'Late pickup',
      ];

String ratingLabel(int stars) => switch (stars) {
  1 => 'Terrible',
  2 => 'Bad',
  3 => 'Okay',
  4 => 'Good',
  5 => 'Excellent',
  _ => 'Tap a star to rate',
};
