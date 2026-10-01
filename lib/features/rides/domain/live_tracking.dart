import 'package:flutter/foundation.dart';

import '../../../core/realtime/realtime_models.dart';
import 'ride_models.dart';

/// `ride.driver_arriving`: the accepted driver is close to the pickup.
@immutable
class ArrivingNotice {
  const ArrivingNotice({required this.distanceMeters, required this.eta});

  factory ArrivingNotice.fromEvent(RealtimeEvent event) => ArrivingNotice(
    distanceMeters: (event.data['distanceMeters'] as num?)?.round() ?? 0,
    eta: Duration(seconds: (event.data['etaSeconds'] as num?)?.round() ?? 0),
  );

  final int distanceMeters;
  final Duration eta;
}

/// Which leg a [LiveRoute] covers.
enum LiveRouteStage {
  /// Driver → pickup.
  approach,

  /// Driver → destination.
  trip;

  static LiveRouteStage? fromWire(String? value) => switch (value) {
    'APPROACH' => approach,
    'TRIP' => trip,
    _ => null,
  };
}

/// `GET /rides/:id/route`: the driver's current road route, computed by the
/// server (Google Routes, straight-line fallback) and refreshed as they move.
@immutable
class LiveRoute {
  const LiveRoute({
    required this.stage,
    required this.distanceMeters,
    required this.duration,
    required this.computedAt,
    this.polyline,
  });

  static LiveRoute? fromJson(Map<String, dynamic> json) {
    final stage = LiveRouteStage.fromWire(json['stage'] as String?);
    if (stage == null) return null;
    return LiveRoute(
      stage: stage,
      distanceMeters: (json['distanceMeters'] as num?)?.round() ?? 0,
      duration: Duration(
        seconds: (json['durationSeconds'] as num?)?.round() ?? 0,
      ),
      computedAt:
          DateTime.tryParse(json['computedAt'] as String? ?? '') ??
          DateTime.now(),
      polyline: json['polyline'] as String?,
    );
  }

  final LiveRouteStage stage;
  final int distanceMeters;

  /// Drive time from where the driver was at [computedAt].
  final Duration duration;
  final DateTime computedAt;

  /// Road path (Google encoded polyline); null for a straight-line fallback.
  final String? polyline;

  bool get followsRoads => polyline != null && polyline!.isNotEmpty;
}

/// Parses `ride.location_updated` into a [DriverPosition].
DriverPosition? driverPositionFromEvent(RealtimeEvent event) {
  final latitude = event.data['latitude'];
  final longitude = event.data['longitude'];
  if (latitude is! num || longitude is! num) return null;
  return DriverPosition.fromJson({
    ...event.data,
    'updatedAt': event.data['recordedAt'] ?? event.timestamp.toIso8601String(),
  });
}
