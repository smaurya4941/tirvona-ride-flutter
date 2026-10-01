import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ride_repository.dart';
import '../domain/nearby_driver.dart';

/// How often the cars on the Home map are refreshed while it is visible.
const nearbyDriversRefresh = Duration(seconds: 30);

/// A ~100 m grid cell: small pickup adjustments reuse the same answer.
typedef NearbyDriversArea = ({double latitude, double longitude});

NearbyDriversArea nearbyDriversArea(double latitude, double longitude) => (
  latitude: double.parse(latitude.toStringAsFixed(3)),
  longitude: double.parse(longitude.toStringAsFixed(3)),
);

/// Free drivers around the rider's pickup (approximate positions, no
/// identities), re-fetched every [nearbyDriversRefresh] while watched. A
/// failed refresh keeps showing no cars rather than an error: the map is
/// decoration, booking never depends on it.
final nearbyDriversProvider = FutureProvider.autoDispose
    .family<List<NearbyDriver>, NearbyDriversArea>((ref, area) async {
      final timer = Timer(nearbyDriversRefresh, ref.invalidateSelf);
      ref.onDispose(timer.cancel);
      try {
        return await ref
            .read(rideRepositoryProvider)
            .nearbyDrivers(latitude: area.latitude, longitude: area.longitude);
      } on Object {
        return const [];
      }
    });
