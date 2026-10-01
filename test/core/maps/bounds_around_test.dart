import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:tirvona_ride/core/maps/tirvona_map.dart';

void main() {
  test('spans the given points when they are far apart', () {
    final bounds = boundsAround(const [
      LatLng(27.50, 77.60),
      LatLng(27.60, 77.70),
    ]);
    expect(bounds.southwest, const LatLng(27.50, 77.60));
    expect(bounds.northeast, const LatLng(27.60, 77.70));
  });

  test('widens a single point to a street-level box around it', () {
    final bounds = boundsAround(const [LatLng(28.6, 77.3)]);
    expect(bounds.southwest.latitude, closeTo(28.596, 1e-9));
    expect(bounds.northeast.latitude, closeTo(28.604, 1e-9));
    expect(bounds.southwest.longitude, closeTo(77.296, 1e-9));
    expect(bounds.northeast.longitude, closeTo(77.304, 1e-9));
    expect(bounds.contains(const LatLng(28.6, 77.3)), isTrue);
  });

  test('widens only the narrow axis', () {
    final bounds = boundsAround(const [LatLng(27.5, 77.6), LatLng(27.6, 77.6)]);
    expect(bounds.southwest.latitude, 27.5);
    expect(bounds.northeast.latitude, 27.6);
    expect(
      bounds.northeast.longitude - bounds.southwest.longitude,
      closeTo(0.008, 1e-9),
    );
  });
}
