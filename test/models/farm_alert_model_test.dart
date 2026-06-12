import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/satellite/farm_alert_model.dart';

void main() {
  group('DiseaseScreenResult', () {
    test('parses edge function response payload', () {
      final result = DiseaseScreenResult.fromJson({
        'scan_date': '2026-06-11',
        'crop': 'rice',
        'growth_stage': 'vegetative',
        'season': 'kharif',
        'images_analyzed': 4,
        'risk_cells_count': 12,
        'high_risk_cells': 3,
        'scout_zones': [
          {
            'centroid_lat': 19.54,
            'centroid_lng': 73.75,
            'max_risk_score': 0.76,
          },
        ],
        'risk_cells': [
          {
            'lat': 19.541,
            'lng': 73.752,
            'composite_risk': 0.66,
            'disease_candidates': ['rice_blast'],
            'likely_abiotic': false,
            'per_disease': {'rice_blast': 0.66, 'sheath_blight': 0.21},
            'ndvi': 0.41,
            'moisture': 24.5,
          },
          {'lat': 0, 'lng': 0, 'composite_risk': 0.2},
        ],
        'weather_context': {'total_rain_mm': 18.4, 'leaf_wetness_hours': 32},
        'top_disease_risks': {'rice_blast': 0.61, 'sheath_blight': 0.42},
      });

      expect(result.scanDate, '2026-06-11');
      expect(result.crop, 'rice');
      expect(result.imagesAnalyzed, 4);
      expect(result.riskCellsCount, 12);
      expect(result.scoutZones, hasLength(1));
      expect(result.weatherContext?['total_rain_mm'], 18.4);
      expect(result.topDiseaseRisks['rice_blast'], 0.61);
      // Cells without a usable location are dropped.
      expect(result.riskCells, hasLength(1));
      expect(result.riskCells.single.compositeRisk, 0.66);
      expect(result.riskCells.single.isDisease, isTrue);
    });
  });

  group('FarmIssueCell', () {
    test('parses edge function cell shape', () {
      final cell = FarmIssueCell.fromJson({
        'lat': 19.61,
        'lng': 73.75,
        'composite_risk': 0.58,
        'disease_candidates': ['leaf_spot', 'downy_mildew'],
        'likely_abiotic': false,
        'per_disease': {'leaf_spot': 0.58},
        'ndvi': 0.39,
        'moisture': 18.2,
        'weather_risk': 0.44,
      });

      expect(cell.hasLocation, isTrue);
      expect(cell.compositeRisk, 0.58);
      expect(cell.diseaseCandidates, ['leaf_spot', 'downy_mildew']);
      expect(cell.isDisease, isTrue);
      expect(cell.isScoutZone, isFalse);
      expect(cell.perDisease['leaf_spot'], 0.58);
    });

    test('parses disease_risk_cells REST row shape', () {
      final cell = FarmIssueCell.fromJson({
        'cell_lat': '19.6101',
        'cell_lng': '73.7522',
        'composite_risk': '0.47',
        'downy_mildew_risk': 0.47,
        'leaf_spot_risk': 0.12,
        'ndvi': 0.42,
      });

      expect(cell.lat, 19.6101);
      expect(cell.lng, 73.7522);
      expect(cell.compositeRisk, 0.47);
      // Candidates derived from per-disease columns above the 0.30 floor.
      expect(cell.diseaseCandidates, ['downy_mildew']);
      expect(cell.isDisease, isTrue);
    });

    test('classifies abiotic stress cells as non-disease', () {
      final cell = FarmIssueCell.fromJson({
        'lat': 19.6,
        'lng': 73.7,
        'composite_risk': 0.51,
        'disease_candidates': ['leaf_spot'],
        'likely_abiotic': true,
      });

      expect(cell.isDisease, isFalse);
    });

    test('marks scout zones from centroid shape', () {
      final zone = FarmIssueCell.fromScoutZone({
        'centroid_lat': 19.55,
        'centroid_lng': 73.76,
        'max_risk_score': 0.71,
        'disease_candidates': ['rice_blast'],
      });

      expect(zone.isScoutZone, isTrue);
      expect(zone.lat, 19.55);
      expect(zone.compositeRisk, 0.71);
    });
  });

  group('FarmPhotoDiagnosis', () {
    test('parses disease-image-diagnose response payload', () {
      final diagnosis = FarmPhotoDiagnosis.fromJson({
        'data': {
          'diagnosis': 'likely leaf spot',
          'confidence': 0.72,
          'severity': 'medium',
          'differential': ['blast'],
          'evidence': ['brown circular lesions'],
          'scout_action': 'Check nearby plants for the same lesions.',
          'model': 'qwen-vl-max',
        },
      });

      expect(diagnosis.diagnosis, 'likely leaf spot');
      expect(diagnosis.confidence, 0.72);
      expect(diagnosis.severity, 'medium');
      expect(diagnosis.evidence.single, 'brown circular lesions');
      expect(diagnosis.scoutAction, 'Check nearby plants for the same lesions.');
      expect(diagnosis.model, 'qwen-vl-max');
    });
  });

  group('FarmAlertAdvice', () {
    test('parses Qwen advisor response payload', () {
      final advice = FarmAlertAdvice.fromJson({
        'advice': {
          'important_alerts': [
            {
              'title': 'Scout zone 1',
              'detail': 'High vegetation anomaly was detected.',
              'severity': 'high',
              'action': 'Inspect leaves in the highlighted area.',
            },
          ],
          'weather_alerts': [
            {
              'title': 'Wetness watch',
              'detail': 'Recent wetness supports fungal pressure.',
              'severity': 'medium',
              'action': 'Scout lower canopy first.',
            },
          ],
          'next_actions': ['Visit the marked zone today.'],
          'confidence': 'medium',
          'model': 'qwen3-235b-a22b',
        },
      });

      expect(advice.importantAlerts, hasLength(1));
      expect(advice.importantAlerts.first.title, 'Scout zone 1');
      expect(advice.weatherAlerts.first.severity, 'medium');
      expect(advice.nextActions.single, 'Visit the marked zone today.');
      expect(advice.confidence, 'medium');
      expect(advice.model, 'qwen3-235b-a22b');
    });
  });
}
