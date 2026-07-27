import 'dart:convert';

import 'package:latlong2/latlong.dart';

class HarvestGradeZone {
  final String id;
  final String planId;
  final String farmId;
  final String label;
  final String fieldGrade;
  final double fieldScore;
  final double areaAcres;
  final double areaPercent;
  final double confidence;
  final int sourceCellCount;
  final Map<String, double> qualityDrivers;
  final List<List<LatLng>> polygons;

  const HarvestGradeZone({
    required this.id,
    required this.planId,
    required this.farmId,
    required this.label,
    required this.fieldGrade,
    required this.fieldScore,
    required this.areaAcres,
    required this.areaPercent,
    required this.confidence,
    required this.sourceCellCount,
    required this.qualityDrivers,
    required this.polygons,
  });

  factory HarvestGradeZone.fromJson(Map<String, dynamic> json) {
    return HarvestGradeZone(
      id: _text(json['id']),
      planId: _text(json['plan_id']),
      farmId: _text(json['farm_id']),
      label: _text(json['zone_label']),
      fieldGrade: _text(json['field_grade'], 'C').toUpperCase(),
      fieldScore: _number(json['field_score']),
      areaAcres: _number(json['area_acres']),
      areaPercent: _number(json['area_percent']),
      confidence: _number(json['confidence']).clamp(0, 1),
      sourceCellCount: _integer(json['source_cell_count']),
      qualityDrivers: _numberMap(json['quality_drivers']),
      polygons: geoJsonPolygons(json['geometry']),
    );
  }
}

class HarvestZonePlan {
  final String id;
  final String farmId;
  final DateTime? sourceScanDate;
  final String growthStage;
  final String readiness;
  final double confidence;
  final double coveragePercent;
  final bool dataAvailable;
  final String scoringVersion;
  final DateTime? generatedAt;
  final Map<String, dynamic> summary;
  final List<HarvestGradeZone> zones;
  final List<LatLng> farmBoundary;

  const HarvestZonePlan({
    required this.id,
    required this.farmId,
    required this.sourceScanDate,
    required this.growthStage,
    required this.readiness,
    required this.confidence,
    required this.coveragePercent,
    required this.dataAvailable,
    required this.scoringVersion,
    required this.generatedAt,
    required this.summary,
    required this.zones,
    required this.farmBoundary,
  });

  bool get isHarvestReady => readiness == 'ready';

  factory HarvestZonePlan.fromJson(Map<String, dynamic> json) {
    final planRaw = json['plan'];
    final plan = planRaw is Map
        ? Map<String, dynamic>.from(planRaw)
        : const <String, dynamic>{};
    final zoneRows = json['zones'];
    final farmParts = geoJsonPolygons(json['farm_geometry']);
    return HarvestZonePlan(
      id: _text(plan['id']),
      farmId: _text(plan['farm_id']),
      sourceScanDate: DateTime.tryParse(_text(plan['source_scan_date'])),
      growthStage: _text(plan['growth_stage']),
      readiness: _text(plan['readiness'], 'unknown'),
      confidence: _number(plan['confidence']).clamp(0, 1),
      coveragePercent: _number(plan['coverage_percent']).clamp(0, 100),
      dataAvailable: plan['data_available'] == true,
      scoringVersion: _text(plan['scoring_version']),
      generatedAt: DateTime.tryParse(_text(plan['generated_at'])),
      summary: plan['summary'] is Map
          ? Map<String, dynamic>.from(plan['summary'] as Map)
          : const <String, dynamic>{},
      zones: zoneRows is List
          ? zoneRows
                .whereType<Map>()
                .map(
                  (row) =>
                      HarvestGradeZone.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList(growable: false)
          : const [],
      farmBoundary: farmParts.isEmpty ? const [] : farmParts.first,
    );
  }
}

List<List<LatLng>> geoJsonPolygons(Object? raw) {
  if (raw is String) {
    try {
      return geoJsonPolygons(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }
  if (raw is! Map) return const [];
  final json = Map<String, dynamic>.from(raw);
  final type = _text(json['type']);
  final coordinates = json['coordinates'];
  if (coordinates is! List) return const [];

  if (type == 'Polygon') {
    final polygon = _geoJsonRing(coordinates);
    return polygon.isEmpty ? const [] : [polygon];
  }
  if (type == 'MultiPolygon') {
    return coordinates
        .whereType<List>()
        .map(_geoJsonRing)
        .where((ring) => ring.length >= 3)
        .toList(growable: false);
  }
  return const [];
}

List<LatLng> _geoJsonRing(List<dynamic> polygon) {
  if (polygon.isEmpty || polygon.first is! List) return const [];
  return (polygon.first as List)
      .whereType<List>()
      .where((point) => point.length >= 2)
      .map((point) => LatLng(_number(point[1]), _number(point[0])))
      .toList(growable: false);
}

Map<String, double> _numberMap(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries) entry.key.toString(): _number(entry.value),
  };
}

String _text(Object? raw, [String fallback = '']) {
  final value = raw == null ? '' : '$raw'.trim();
  return value.isEmpty || value.toLowerCase() == 'null' ? fallback : value;
}

double _number(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(_text(raw)) ?? 0;
}

int _integer(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return int.tryParse(_text(raw)) ?? 0;
}
