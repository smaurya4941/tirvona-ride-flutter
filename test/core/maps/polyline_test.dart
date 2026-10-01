import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/core/maps/polyline.dart';

void main() {
  test("decodes Google's reference polyline", () {
    // Example from Google's "Encoded Polyline Algorithm Format" page.
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points, hasLength(3));
    expect(points[0].latitude, closeTo(38.5, 1e-9));
    expect(points[0].longitude, closeTo(-120.2, 1e-9));
    expect(points[1].latitude, closeTo(40.7, 1e-9));
    expect(points[1].longitude, closeTo(-120.95, 1e-9));
    expect(points[2].latitude, closeTo(43.252, 1e-9));
    expect(points[2].longitude, closeTo(-126.453, 1e-9));
  });

  test('empty or missing input decodes to no points', () {
    expect(decodePolyline(null), isEmpty);
    expect(decodePolyline(''), isEmpty);
  });

  test('a truncated string keeps the points decoded before the break', () {
    const full = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    expect(decodePolyline(full.substring(0, full.length - 2)), hasLength(2));
  });

  test('characters outside the alphabet stop decoding instead of throwing', () {
    expect(decodePolyline('_p~iF~ps|U\n\n'), hasLength(1));
  });
}
