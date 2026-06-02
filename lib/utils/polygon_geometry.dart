import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class PolygonGeometry {
  static const double _earthRadiusM = 6371008.8;

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
