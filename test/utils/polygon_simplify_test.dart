import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:millets_now/utils/polygon_simplify.dart';

void main() {
  test('simplify closes a drawn ring', () {
    final ring = PolygonSimplifier.simplify([
      const LatLng(12.0, 77.0),
      const LatLng(12.0, 77.001),
      const LatLng(12.001, 77.001),
      const LatLng(12.001, 77.0),
    ]);

    expect(ring.length, greaterThanOrEqualTo(4));
    expect(ring.first.latitude, ring.last.latitude);
    expect(ring.first.longitude, ring.last.longitude);
  });

  test('single-point stroke returns empty polygon', () {
    final ring = PolygonSimplifier.simplify([
      const LatLng(12.0, 77.0),
    ]);

    expect(ring, isEmpty);
  });

  test('collinear stroke does not create invalid polygon', () {
    final ring = PolygonSimplifier.simplify([
      const LatLng(12.0, 77.0),
      const LatLng(12.0, 77.001),
      const LatLng(12.0, 77.002),
    ]);

    expect(ring.isEmpty || ring.length >= 4, isTrue);
  });
}
