import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

enum PolygonBoundaryIssue {
  tooFewDistinctPoints,
  repeatedPoint,
  selfIntersection,
  zeroArea,
}

class PolygonGeometry {
  static const double _earthRadiusM = 6371008.8;
  static const double _coordinateTolerance = 1e-12;

  static PolygonBoundaryIssue? boundaryIssue(List<LatLng> ring) {
    final points = _open(ring);
    if (points.length < 3) {
      return PolygonBoundaryIssue.tooFewDistinctPoints;
    }

    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        if (_samePoint(points[i], points[j])) {
          return PolygonBoundaryIssue.repeatedPoint;
        }
      }
    }

    final hasEnclosedTurn = List.generate(points.length, (index) => index).any(
      (index) =>
          _orientation(
            points[index],
            points[(index + 1) % points.length],
            points[(index + 2) % points.length],
          ) !=
          0,
    );
    if (!hasEnclosedTurn) return PolygonBoundaryIssue.zeroArea;

    for (var i = 0; i < points.length; i++) {
      final nextI = (i + 1) % points.length;
      for (var j = i + 1; j < points.length; j++) {
        final nextJ = (j + 1) % points.length;
        final adjacent = i == j || nextI == j || nextJ == i;
        if (adjacent) continue;
        if (_segmentsIntersect(
          points[i],
          points[nextI],
          points[j],
          points[nextJ],
        )) {
          return PolygonBoundaryIssue.selfIntersection;
        }
      }
    }

    if (areaHectares(points) <= 0) {
      return PolygonBoundaryIssue.zeroArea;
    }
    return null;
  }

  static bool isValidBoundary(List<LatLng> ring) => boundaryIssue(ring) == null;

  static double areaHectares(List<LatLng> ring) {
    if (ring.length < 3) return 0;
    final pts = _closed(ring);
    var total = 0.0;

    for (var i = 0; i < pts.length - 1; i++) {
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final lon1 = _rad(p1.longitude);
      final lon2 = _rad(p2.longitude);
      final lat1 = _rad(p1.latitude);
      final lat2 = _rad(p2.latitude);
      total += (lon2 - lon1) * (2 + math.sin(lat1) + math.sin(lat2));
    }

    return (total * _earthRadiusM * _earthRadiusM / 2).abs() / 10000;
  }

  static List<LatLng> fromGeoJsonRing(List<List<double>> coords) {
    return coords.map((pt) => LatLng(pt[1], pt[0])).toList();
  }

  static List<List<double>> toGeoJsonRing(List<LatLng> ring) {
    return _closed(ring).map((pt) => [pt.longitude, pt.latitude]).toList();
  }

  static Map<String, dynamic> bounds(List<LatLng> ring) {
    if (ring.isEmpty) return {};
    var minLat = ring.first.latitude;
    var maxLat = ring.first.latitude;
    var minLng = ring.first.longitude;
    var maxLng = ring.first.longitude;
    for (final point in ring) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    return {'south': minLat, 'west': minLng, 'north': maxLat, 'east': maxLng};
  }

  static bool containsPoint(List<LatLng> ring, LatLng point) {
    if (ring.length < 3) return true;
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final current = ring[i];
      final previous = ring[j];
      if (_pointOnSegment(point, previous, current)) return true;
      final crossesLatitude =
          (current.latitude > point.latitude) !=
          (previous.latitude > point.latitude);
      if (!crossesLatitude) continue;
      final longitudeAtLatitude =
          (previous.longitude - current.longitude) *
              (point.latitude - current.latitude) /
              (previous.latitude - current.latitude) +
          current.longitude;
      if (point.longitude < longitudeAtLatitude) inside = !inside;
    }
    return inside;
  }

  static bool _pointOnSegment(LatLng point, LatLng start, LatLng end) {
    const tolerance = 1e-9;
    final cross =
        (point.latitude - start.latitude) * (end.longitude - start.longitude) -
        (point.longitude - start.longitude) * (end.latitude - start.latitude);
    if (cross.abs() > tolerance) return false;
    final minLat = math.min(start.latitude, end.latitude) - tolerance;
    final maxLat = math.max(start.latitude, end.latitude) + tolerance;
    final minLng = math.min(start.longitude, end.longitude) - tolerance;
    final maxLng = math.max(start.longitude, end.longitude) + tolerance;
    return point.latitude >= minLat &&
        point.latitude <= maxLat &&
        point.longitude >= minLng &&
        point.longitude <= maxLng;
  }

  static bool _segmentsIntersect(LatLng a, LatLng b, LatLng c, LatLng d) {
    final o1 = _orientation(a, b, c);
    final o2 = _orientation(a, b, d);
    final o3 = _orientation(c, d, a);
    final o4 = _orientation(c, d, b);

    if (o1 != o2 && o3 != o4) return true;
    if (o1 == 0 && _pointOnSegment(c, a, b)) return true;
    if (o2 == 0 && _pointOnSegment(d, a, b)) return true;
    if (o3 == 0 && _pointOnSegment(a, c, d)) return true;
    if (o4 == 0 && _pointOnSegment(b, c, d)) return true;
    return false;
  }

  static int _orientation(LatLng a, LatLng b, LatLng c) {
    final cross =
        (b.longitude - a.longitude) * (c.latitude - a.latitude) -
        (b.latitude - a.latitude) * (c.longitude - a.longitude);
    if (cross.abs() <= _coordinateTolerance) return 0;
    return cross > 0 ? 1 : -1;
  }

  static bool _samePoint(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() <= _coordinateTolerance &&
        (a.longitude - b.longitude).abs() <= _coordinateTolerance;
  }

  static List<LatLng> _open(List<LatLng> ring) {
    if (ring.length > 1 && _samePoint(ring.first, ring.last)) {
      return ring.sublist(0, ring.length - 1);
    }
    return ring;
  }

  static List<LatLng> _closed(List<LatLng> ring) {
    if (ring.isEmpty) return ring;
    final first = ring.first;
    final last = ring.last;
    if (first.latitude == last.latitude && first.longitude == last.longitude) {
      return ring;
    }
    return [...ring, first];
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
