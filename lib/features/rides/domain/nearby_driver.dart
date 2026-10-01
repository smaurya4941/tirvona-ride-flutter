import 'package:flutter/foundation.dart';

/// A free driver near the rider, from `GET /rides/nearby-drivers`. The
/// server rounds the position to ~100 m and sends no identity.
@immutable
class NearbyDriver {
  const NearbyDriver({
    required this.latitude,
    required this.longitude,
    this.vehicleType,
  });

  factory NearbyDriver.fromJson(Map<String, dynamic> json) => NearbyDriver(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    vehicleType: json['vehicleType'] as String?,
  );

  final double latitude;
  final double longitude;

  /// BIKE, AUTO, E_RICKSHAW or CAB.
  final String? vehicleType;
}
