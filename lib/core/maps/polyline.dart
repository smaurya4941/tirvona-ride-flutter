import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Decodes Google's encoded polyline format (precision 5), as returned by the
/// Routes API and relayed by the Tirvona API (`routePolyline`, `polyline`).
///
/// Returns an empty list for null/empty input. A malformed string (truncated
/// in transit) yields the points decoded before the damage rather than
/// throwing, so a map never crashes on a bad route.
///
/// Format: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
List<LatLng> decodePolyline(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const [];
  final points = <LatLng>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;

  // One zig-zag, 5-bit-chunked signed delta; null when the input ends early.
  int? nextDelta() {
    var result = 0;
    var shift = 0;
    while (index < encoded.length) {
      final chunk = encoded.codeUnitAt(index++) - 63;
      if (chunk < 0 || chunk > 63) return null;
      result |= (chunk & 0x1f) << shift;
      shift += 5;
      if (chunk < 0x20) {
        return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      }
    }
    return null;
  }

  while (index < encoded.length) {
    final dLat = nextDelta();
    final dLng = nextDelta();
    if (dLat == null || dLng == null) break;
    latitude += dLat;
    longitude += dLng;
    points.add(LatLng(latitude / 1e5, longitude / 1e5));
  }
  return points;
}
