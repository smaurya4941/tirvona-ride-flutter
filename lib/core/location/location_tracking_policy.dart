import 'package:flutter/foundation.dart';

/// What the driver is doing, which decides how often GPS is sampled.
enum LocationTrackingMode {
  /// Offline: no streaming at all.
  off,

  /// Online, waiting for a request: position only needs to be good enough
  /// for matching (and fresh within the server's stale window).
  waiting,

  /// Accepted a ride, heading to (or waiting at) the pickup.
  toPickup,

  /// Trip in progress.
  onTrip,
}

/// Sampling rules for one [LocationTrackingMode].
@immutable
class LocationTrackingProfile {
  const LocationTrackingProfile({
    required this.distanceFilterMeters,
    required this.interval,
    required this.heartbeat,
    required this.highAccuracy,
  });

  /// Minimum movement before the OS reports a new fix.
  final int distanceFilterMeters;

  /// Desired fix interval (Android; iOS is distance-driven).
  final Duration interval;

  /// Re-send the position at least this often even when standing still, so
  /// the server never considers an online driver stale. Must stay well below
  /// the backend's DRIVER_LOCATION_STALE_SECONDS (default 60 s).
  final Duration heartbeat;

  final bool highAccuracy;
}

/// The single place location frequency is decided — never inside screens.
abstract final class LocationTrackingPolicy {
  static const _waiting = LocationTrackingProfile(
    distanceFilterMeters: 25,
    interval: Duration(seconds: 10),
    heartbeat: Duration(seconds: 20),
    highAccuracy: false,
  );
  static const _toPickup = LocationTrackingProfile(
    distanceFilterMeters: 10,
    interval: Duration(seconds: 4),
    heartbeat: Duration(seconds: 10),
    highAccuracy: true,
  );
  static const _onTrip = LocationTrackingProfile(
    distanceFilterMeters: 10,
    interval: Duration(seconds: 3),
    heartbeat: Duration(seconds: 10),
    highAccuracy: true,
  );

  static LocationTrackingProfile? profileFor(LocationTrackingMode mode) =>
      switch (mode) {
        LocationTrackingMode.off => null,
        LocationTrackingMode.waiting => _waiting,
        LocationTrackingMode.toPickup => _toPickup,
        LocationTrackingMode.onTrip => _onTrip,
      };

  /// Fixes less accurate than this are not sent (server limit is 150 m).
  static const maxAccuracyMeters = 100.0;

  /// Fixes older than this are not sent (server limit is 30 s).
  static const maxFixAge = Duration(seconds: 20);

  /// Never send faster than this (server floor is 1 s).
  static const minSendInterval = Duration(milliseconds: 1500);

  /// Faster than ~250 km/h between two fixes is a GPS jump, not driving.
  static const maxPlausibleSpeedMps = 70.0;
}
