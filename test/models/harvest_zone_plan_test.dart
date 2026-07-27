import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/harvest_zone_plan.dart';

void main() {
  test('parses full-field grade plan and polygon coordinates', () {
    final plan = HarvestZonePlan.fromJson({
      'plan': {
        'id': 'plan-1',
        'farm_id': 'farm-1',
        'growth_stage': 'Maturity',
        'readiness': 'ready',
        'confidence': 0.82,
        'coverage_percent': 100,
        'data_available': true,
        'scoring_version': 'field-grade-v2-three-region',
      },
      'farm_geometry': {
        'type': 'Polygon',
        'coordinates': [
          [
            [73.0, 18.0],
            [73.1, 18.0],
            [73.1, 18.1],
            [73.0, 18.0],
          ],
        ],
      },
      'zones': List.generate(3, (index) {
        final grade = const ['A', 'B', 'C'][index];
        return {
          'id': 'zone-${grade.toLowerCase()}',
          'plan_id': 'plan-1',
          'farm_id': 'farm-1',
          'zone_label': grade,
          'field_grade': grade.toLowerCase(),
          'field_score': 82.0 - (index * 12),
          'area_acres': 1.2,
          'area_percent': 100 / 3,
          'confidence': 0.82,
          'source_cell_count': 8,
          'quality_drivers': {'crop_vigor': 94 - index},
          'geometry': {
            'type': 'MultiPolygon',
            'coordinates': [
              [
                [
                  [73.0 + (index * 0.01), 18.0],
                  [73.01 + (index * 0.01), 18.0],
                  [73.01 + (index * 0.01), 18.01],
                  [73.0 + (index * 0.01), 18.0],
                ],
              ],
            ],
          },
        };
      }),
    });

    expect(plan.isHarvestReady, isTrue);
    expect(plan.coveragePercent, 100);
    expect(plan.farmBoundary, hasLength(4));
    expect(plan.scoringVersion, 'field-grade-v2-three-region');
    expect(plan.zones, hasLength(3));
    expect(plan.zones.map((zone) => zone.label), ['A', 'B', 'C']);
    expect(plan.zones.map((zone) => zone.fieldGrade), ['A', 'B', 'C']);
    expect(plan.zones.first.polygons.single.first.latitude, 18.0);
    expect(plan.zones.first.polygons.single.first.longitude, 73.0);
  });

  test('accepts encoded GeoJSON and clamps unsafe percentages', () {
    final polygons = geoJsonPolygons(
      jsonEncode({
        'type': 'Polygon',
        'coordinates': [
          [
            [74.0, 19.0],
            [74.1, 19.0],
            [74.0, 19.1],
          ],
        ],
      }),
    );
    final plan = HarvestZonePlan.fromJson({
      'plan': {
        'confidence': 4,
        'coverage_percent': 140,
        'data_available': false,
      },
    });

    expect(polygons.single, hasLength(3));
    expect(plan.confidence, 1);
    expect(plan.coveragePercent, 100);
    expect(plan.dataAvailable, isFalse);
  });
}
