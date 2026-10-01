import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../rides/domain/ride_models.dart';
import '../data/places_repository.dart';

enum LocationFailureReason {
  /// Location (GPS) is switched off on the device.
  serviceDisabled,
  denied,

  /// Denied with "don't ask again": only system settings can fix it.
  deniedForever,

  /// Permission is fine but no fix arrived in time (indoors, airplane mode).
  noFix,
}

/// Why the rider's location could not be used, written for the rider.
class LocationFailure implements Exception {
  const LocationFailure(this.reason);

  final LocationFailureReason reason;

  /// The fix is in system settings rather than in the app.
  bool get needsSettings =>
      reason == LocationFailureReason.serviceDisabled ||
      reason == LocationFailureReason.deniedForever;

  String get message => switch (reason) {
    LocationFailureReason.serviceDisabled =>
      'Turn on location services to use your current location.',
    LocationFailureReason.denied => 'Allow location access to use your current location, or search for your pickup.',
    LocationFailureReason.deniedForever => 'Location access is off for Tirvona Rides. Enable it in Settings, or search for your pickup.',
    LocationFailureReason.noFix => "We couldn't find your location. Move to an open area or search for your pickup.",
  };

  @override
  String toString() => message;
}

/// A position no older than this is good enough for a pickup.
const _freshFixAge = Duration(minutes: 2);

/// A fix less accurate than this (metres) is not used as a pickup.
const _maxPickupAccuracyMeters = 250.0;

/// The rider's device position: permission handling, one-shot fixes, and the
/// last known point (to rank search results near the rider).
class DeviceLocation {
  GeoPoint? _lastPoint;

  /// Last position this session obtained, without prompting or waiting.
  GeoPoint? get lastPoint => _lastPoint;

  /// Current position. Prompts for permission when [prompt] is true and it
  /// has not been decided yet. Throws [LocationFailure].
  Future<GeoPoint> currentPosition({bool prompt = true}) async {
    await _ensureAccess(prompt: prompt);
    final recent = await _recentKnownPosition();
    if (recent != null) return _remember(recent);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return _remember(position);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && last.accuracy <= _maxPickupAccuracyMeters * 2) {
        return _remember(last);
      }
      throw const LocationFailure(LocationFailureReason.noFix);
    } on LocationServiceDisabledException {
      throw const LocationFailure(LocationFailureReason.serviceDisabled);
    } on PermissionDeniedException {
      throw const LocationFailure(LocationFailureReason.denied);
    }
  }

  /// A rough position for ranking results; never prompts, never waits long.
  Future<GeoPoint?> approximatePosition() async {
    if (_lastPoint != null) return _lastPoint;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : _remember(last);
    } on Exception {
      return null;
    }
  }

  Future<void> openSettings(LocationFailure failure) async {
    if (failure.reason == LocationFailureReason.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _ensureAccess({required bool prompt}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(LocationFailureReason.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && prompt) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.always || LocationPermission.whileInUse:
        return;
      case LocationPermission.deniedForever:
        throw const LocationFailure(LocationFailureReason.deniedForever);
      case LocationPermission.denied || LocationPermission.unableToDetermine:
        throw const LocationFailure(LocationFailureReason.denied);
    }
  }

  Future<Position?> _recentKnownPosition() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return null;
      final fresh = DateTime.now().difference(last.timestamp) <= _freshFixAge;
      return fresh && last.accuracy <= _maxPickupAccuracyMeters ? last : null;
    } on Exception {
      return null;
    }
  }

  GeoPoint _remember(Position position) =>
      _lastPoint = (latitude: position.latitude, longitude: position.longitude);
}

final deviceLocationProvider = Provider<DeviceLocation>(
  (ref) => DeviceLocation(),
);

/// "Use current location": the device position, named by the server.
class CurrentPlaceLocator {
  const CurrentPlaceLocator(this._device, this._places);

  final DeviceLocation _device;
  final PlacesRepository _places;

  /// Throws [LocationFailure] or `ApiException`.
  Future<Place> locate({bool prompt = true}) async {
    final point = await _device.currentPosition(prompt: prompt);
    final named = await _places.reverse(point);
    return Place(
      // "Your current location" reads better than a coordinate label.
      name: named.approximate ? 'Your current location' : named.place.name,
      address: named.place.address,
      latitude: point.latitude,
      longitude: point.longitude,
    );
  }
}

final currentPlaceLocatorProvider = Provider<CurrentPlaceLocator>(
  (ref) => CurrentPlaceLocator(
    ref.watch(deviceLocationProvider),
    ref.watch(placesRepositoryProvider),
  ),
);
