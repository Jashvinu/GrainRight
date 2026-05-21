import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:millets_now/utils/polygon_geometry.dart';

void main() {
  test('area is within one percent for a roughly 100m square', () {
    const origin = LatLng(12.0, 77.0);
    final square = [
      origin,
      const LatLng(12.0, 77.000921),
      const LatLng(12.000898, 77.000921),
      const LatLng(12.000898, 77.0),
      origin,
    ];

    final hectares = PolygonGeometry.areaHectares(square);
    expect(hectares, closeTo(1.0, 0.01));
  });
}
