import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/farm_health_score.dart';
import 'package:kalsubai_farms/models/fpc_procurement_dashboard.dart';
import 'package:kalsubai_farms/services/fpc_dashboard_service.dart';

void main() {
  group('FarmHealthScore', () {
    test('matches the dashboard SQL score for available risk signals', () {
      expect(
        FarmHealthScore.calculate(
          waterStress: 0.5,
          weatherRisk: 0.5,
          diseaseRisk: 0.25,
        ),
        67,
      );
    });

    test('keeps Farmer Home scoring behavior for extended signals', () {
      expect(
        FarmHealthScore.calculate(
          ndvi: 0.75,
          moisture: 0.20,
          waterStress: 0.20,
          weatherRisk: 0.10,
          diseaseRisk: 0.25,
          highRiskCells: 2,
        ),
        56,
      );
    });

    test('preserves Farmer Home health-label fallbacks', () {
      expect(FarmHealthScore.calculate(healthLabel: 'High risk'), 46);
      expect(FarmHealthScore.calculate(healthLabel: 'Watch'), 68);
      expect(FarmHealthScore.calculate(healthLabel: 'Attention'), 68);
      expect(FarmHealthScore.calculate(healthLabel: 'Healthy'), 84);
    });

    test('returns null instead of inventing health without signals', () {
      expect(FarmHealthScore.calculate(), isNull);
    });
  });

  group('grade normalization', () {
    test('normalizes verified grade variants', () {
      expect(normalizeFpcGrade('A'), 'Grade A');
      expect(normalizeFpcGrade('premium grade'), 'Grade A');
      expect(normalizeFpcGrade('standard'), 'Grade B');
      expect(normalizeFpcGrade('Grade-C'), 'Grade C');
    });

    test('keeps explicit unknown grades and labels missing data', () {
      expect(normalizeFpcGrade('Export Select'), 'Export Select');
      expect(normalizeFpcGrade(null), 'Not graded');
    });
  });

  test('parses the snapshot contract, geometry, and missing states', () {
    final snapshot = FpcProcurementDashboardSnapshot.fromJson({
      'generated_at': '2026-07-28T02:00:00Z',
      'fpc_id': 'fpc-1',
      'selected_cluster_id': 'cluster-1',
      'unassigned_farm_count': 2,
      'clusters': [
        {
          'id': 'cluster-1',
          'name': 'Nashik belt',
          'district': 'Nashik',
          'state': 'Maharashtra',
          'preferred_apmc_market': 'Nashik APMC',
          'active': true,
          'farm_count': 1,
          'ready_count': 1,
          'expected_quantity_kg': '1250',
        },
      ],
      'summary': {
        'network_farms': 1,
        'ready_farms': 1,
        'expected_procurement_kg': '1250',
        'open_lots': 2,
        'needs_review': 1,
        'health_average': 72,
        'health_coverage': 1,
        'grade_mix': [
          {'grade': 'premium', 'count': 1},
        ],
      },
      'seed_requests': {
        'total': 8,
        'submitted': 2,
        'awaiting_farmer': 1,
        'ready_to_issue': 3,
        'in_delivery': 1,
        'completed': 1,
      },
      'farms': [
        {
          'link_id': 'link-1',
          'cluster_id': 'cluster-1',
          'farmer_id': 'farmer-1',
          'farmer_name': 'Savita Pawara',
          'farm_id': 'farm-1',
          'farm_name': 'West plot',
          'crop': 'Pearl millet',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [73.70, 19.90],
                [73.71, 19.90],
                [73.71, 19.91],
                [73.70, 19.90],
              ],
            ],
          },
          'centroid_lat': 19.905,
          'centroid_lng': 73.705,
          'readiness': 'ready',
          'is_ready': true,
          'latest_grade': 'A',
          'needs_review': true,
          'open_lots': 2,
          'health_score': 72,
        },
      ],
    });

    expect(snapshot.selectedCluster?.name, 'Nashik belt');
    expect(snapshot.summary.expectedProcurementKg, 1250);
    expect(snapshot.summary.gradeMix.single.grade, 'Grade A');
    expect(snapshot.seedRequests.actionRequired, 5);
    expect(snapshot.seedRequests.awaitingFarmer, 1);
    expect(snapshot.farms.single.polygons.single, hasLength(4));
    expect(snapshot.farms.single.hasMapLocation, isTrue);
    expect(snapshot.farms.single.photoUrl, isNull);

    final mapPoint = FpcFarmMapPoint.fromFarm(snapshot.farms.single);
    expect(mapPoint.linkId, 'link-1');
    expect(mapPoint.latitude, 19.905);
    expect(mapPoint.longitude, 73.705);
  });

  test('request tracker rejects a completed stale response', () {
    final tracker = FpcDashboardRequestTracker();
    final first = tracker.begin();
    final second = tracker.begin();

    expect(tracker.isCurrent(first), isFalse);
    expect(tracker.isCurrent(second), isTrue);
  });

  test('parses a compact farm queue page without map payloads', () {
    final page = FpcFarmQueuePage.fromJson({
      'has_more': true,
      'next_offset': 5,
      'farms': [
        {
          'link_id': 'link-1',
          'farmer_id': 'farmer-1',
          'farmer_name': 'Savita Pawara',
          'farm_id': 'farm-1',
          'farm_name': 'West plot',
          'village': 'Sinnar',
          'crop': 'Finger millet',
          'expected_harvest_date': '2026-08-15T00:00:00Z',
          'expected_quantity_kg': '1250',
          'readiness': 'ready',
          'is_ready': true,
        },
      ],
    });

    expect(page.hasMore, isTrue);
    expect(page.nextOffset, 5);
    expect(page.farms.single.farmerName, 'Savita Pawara');
    expect(page.farms.single.polygons, isEmpty);
    expect(page.farms.single.expectedHarvestDate, isNotNull);
  });
}
