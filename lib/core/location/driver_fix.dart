import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'location_tracking_policy.dart';

/// One device GPS fix, as the driver app sends it.
@immutable
class DriverFix {
  const DriverFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.recordedAt,
    this.heading,
    this.speed,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy radius, metres.
  final double accuracy;
  final DateTime recordedAt;

  /// Degrees clockwise from north; only meaningful while moving.
  final double? heading;

  /// Metres per second.
  final double? speed;

  DriverFix restamped(DateTime at) => DriverFix(
    latitude: latitude,
    longitude: longitude,
    accuracy: accuracy,
    recordedAt: at,
    heading: heading,
    speed: speed,
  );

  /// Payload of the `driver.location` socket message / REST fallback.
  Map<String, dynamic> toPayload({String? rideId}) => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': double.parse(accuracy.toStringAsFixed(1)),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    if (heading != null) 'heading': double.parse(heading!.toStringAsFixed(1)),
    if (speed != null) 'speed': double.parse(speed!.toStringAsFixed(2)),
    'rideId': ?rideId,
  };
}

const _earthRadiusMeters = 6371008.8;

double _radians(double degrees) => degrees * math.pi / 180;

/// Great-circle distance in metres.
double distanceMeters(
  double fromLatitude,
  double fromLongitude,
  double toLatitude,
  double toLongitude,
) {
  final dLat = _radians(toLatitude - fromLatitude);
  final dLng = _radians(toLongitude - fromLongitude);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radians(fromLatitude)) *
          math.cos(_radians(toLatitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
}

enum FixVerdict { accept, inaccurate, stale, tooSoon, implausibleJump }

/// Client-side hygiene before a fix is sent: drops inaccurate, old, too
/// frequent and physically impossible fixes. The server applies the same
/// rules again — this just avoids wasting uplink on them.
class DriverFixFilter {
  DriverFix? _lastAccepted;

  DriverFix? get lastAccepted => _lastAccepted;

  FixVerdict check(DriverFix fix, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    if (fix.accuracy > LocationTrackingPolicy.maxAccuracyMeters) {
      return FixVerdict.inaccurate;
    }
    if (clock.difference(fix.recordedAt) > LocationTrackingPolicy.maxFixAge) {
      return FixVerdict.stale;
    }
    final last = _lastAccepted;
    if (last != null) {
      final elapsed = fix.recordedAt.difference(last.recordedAt);
      if (elapsed < LocationTrackingPolicy.minSendInterval) {
        return FixVerdict.tooSoon;
      }
      final meters = distanceMeters(
        last.latitude,
        last.longitude,
        fix.latitude,
        fix.longitude,
      );
      final seconds = elapsed.inMilliseconds / 1000;
      // Only judge short gaps; after a long gap any distance is possible.
      if (seconds < 60 &&
          meters / seconds > LocationTrackingPolicy.maxPlausibleSpeedMps) {
        return FixVerdict.implausibleJump;
      }
    }
    _lastAccepted = fix;
    return FixVerdict.accept;
  }

  void reset() => _lastAccepted = null;
}
