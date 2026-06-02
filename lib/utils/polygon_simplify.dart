import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class PolygonSimplifier {
  static List<LatLng> simplify(List<LatLng> stroke, {double? tolerance}) {
    if (stroke.length < 3) return [];

    final cleaned = <LatLng>[];
    for (final point in stroke) {
      if (cleaned.isEmpty ||
          cleaned.last.latitude != point.latitude ||
          cleaned.last.longitude != point.longitude) {
        cleaned.add(point);
      }
    }
    if (cleaned.length < 3) return [];

    final tol =
        tolerance ?? math.max(0.5, _bboxDiagonalMeters(cleaned) * 0.015);
    final simplified = _rdp(cleaned, tol);
    if (simplified.length < 3) return [];

    final first = simplified.first;
    final last = simplified.last;
    if (first.latitude != last.latitude || first.longitude != last.longitude) {
      simplified.add(first);
    }
    return simplified.length >= 4 ? simplified : [];
  }

  static List<LatLng> _rdp(List<LatLng> points, double epsilonMeters) {
    if (points.length < 3) return [...points];

    var index = 0;
    var maxDistance = 0.0;
    for (var i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(
        points[i],
        points.first,
        points.last,
      );
      if (distance > maxDistance) {
        index = i;
        maxDistance = distance;
      }
    }

    if (maxDistance <= epsilonMeters) {
      return [points.first, points.last];
    }

    final left = _rdp(points.sublist(0, index + 1), epsilonMeters);
    final right = _rdp(points.sublist(index), epsilonMeters);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  static double _perpendicularDistance(LatLng p, LatLng a, LatLng b) {
    final originLat = (a.latitude + b.latitude + p.latitude) / 3;
    final ap = _metersFrom(a, p, originLat);
    final ab = _metersFrom(a, b, originLat);
    final abLen2 = ab.$1 * ab.$1 + ab.$2 * ab.$2;
    if (abLen2 == 0) {
      return math.sqrt(ap.$1 * ap.$1 + ap.$2 * ap.$2);
    }
    final t = ((ap.$1 * ab.$1 + ap.$2 * ab.$2) / abLen2).clamp(0.0, 1.0);
    final projX = ab.$1 * t;
    final projY = ab.$2 * t;
    final dx = ap.$1 - projX;
    final dy = ap.$2 - projY;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _bboxDiagonalMeters(List<LatLng> pts) {
    var minLat = pts.first.latitude;
    var maxLat = pts.first.latitude;
    var minLng = pts.first.longitude;
    var maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final originLat = (minLat + maxLat) / 2;
    final diagonal = _metersFrom(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
      originLat,
    );
    return math.sqrt(diagonal.$1 * diagonal.$1 + diagonal.$2 * diagonal.$2);
  }

  static (double, double) _metersFrom(LatLng a, LatLng b, double originLat) {
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng =
        metersPerDegreeLat *
        math.cos(originLat * math.pi / 180).abs().clamp(0.01, 1.0);
    return (
      (b.longitude - a.longitude) * metersPerDegreeLng,
      (b.latitude - a.latitude) * metersPerDegreeLat,
    );
  }
}
