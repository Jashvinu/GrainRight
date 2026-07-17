import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kalsubai_farms/utils/polygon_geometry.dart';

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

  test('contains only hotspot points inside or on the marked farm', () {
    const polygon = [
      LatLng(18.0, 73.0),
      LatLng(18.0, 73.01),
      LatLng(18.01, 73.01),
      LatLng(18.01, 73.0),
      LatLng(18.0, 73.0),
    ];

    expect(
      PolygonGeometry.containsPoint(polygon, const LatLng(18.005, 73.005)),
      isTrue,
    );
    expect(
      PolygonGeometry.containsPoint(polygon, const LatLng(18.0, 73.005)),
      isTrue,
    );
    expect(
      PolygonGeometry.containsPoint(polygon, const LatLng(18.02, 73.005)),
      isFalse,
    );
  });

  test('accepts a valid closed or open farm boundary', () {
    const open = [
      LatLng(18.0, 73.0),
      LatLng(18.0, 73.01),
      LatLng(18.01, 73.01),
      LatLng(18.01, 73.0),
    ];
    final closed = [...open, open.first];

    expect(PolygonGeometry.boundaryIssue(open), isNull);
    expect(PolygonGeometry.boundaryIssue(closed), isNull);
  });

  test('rejects a self-crossing farm boundary', () {
    const bowTie = [
      LatLng(18.0, 73.0),
      LatLng(18.01, 73.01),
      LatLng(18.0, 73.01),
      LatLng(18.01, 73.0),
    ];

    expect(
      PolygonGeometry.boundaryIssue(bowTie),
      PolygonBoundaryIssue.selfIntersection,
    );
  });

  test('rejects repeated corners and zero-area boundaries', () {
    const repeated = [
      LatLng(18.0, 73.0),
      LatLng(18.0, 73.01),
      LatLng(18.01, 73.01),
      LatLng(18.0, 73.01),
    ];
    const line = [
      LatLng(18.0, 73.0),
      LatLng(18.01, 73.01),
      LatLng(18.02, 73.02),
    ];

    expect(
      PolygonGeometry.boundaryIssue(repeated),
      PolygonBoundaryIssue.repeatedPoint,
    );
    expect(PolygonGeometry.boundaryIssue(line), PolygonBoundaryIssue.zeroArea);
  });
}
