import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/services/fpc_procurement_service.dart';

void main() {
  group('HarvestTraceParser', () {
    test('parses original Kalsubai harvest trace URL', () {
      final payload = _harvestPayload();
      final parsed = HarvestTraceParser.parse(_traceUrl(payload));

      expect(parsed['traceType'], 'harvest');
      expect(parsed['batchId'], 'KF-HV-20260703-001');
      expect(parsed['farmerId'], 'FMR-001');
    });

    test('rejects sample harvest QR payload', () {
      final sample = _harvestPayload(batchId: 'KF-HV-20260606-001');

      expect(
        () => HarvestTraceParser.parse(_traceUrl(sample)),
        throwsA(isA<FpcProcurementException>()),
      );
    });

    test('rejects farmer profile QR in harvest receiver', () {
      expect(
        () => HarvestTraceParser.parse(jsonEncode(_farmerQrPayload())),
        throwsA(isA<FpcProcurementException>()),
      );
    });

    test('rejects harvest payload missing production fields', () {
      final missing = _harvestPayload()..remove('moisture');

      expect(
        () => HarvestTraceParser.parse(_traceUrl(missing)),
        throwsA(isA<FpcProcurementException>()),
      );
    });
  });

  group('FarmerProfileQrParser', () {
    test('parses original farmer profile QR', () {
      final parsed = FarmerProfileQrParser.parse(
        jsonEncode(_farmerQrPayload()),
      );

      expect(parsed['type'], 'farmer_profile');
      expect(parsed['allowedRole'], 'fpo_fpc');
      expect(parsed['farmerId'], 'FMR-001');
    });

    test('rejects non-original farmer payload', () {
      final payload = _farmerQrPayload()..remove('source');

      expect(
        () => FarmerProfileQrParser.parse(jsonEncode(payload)),
        throwsA(isA<FpcProcurementException>()),
      );
    });
  });
}

Map<String, dynamic> _harvestPayload({String batchId = 'KF-HV-20260703-001'}) {
  return {
    'brand': 'Kalsubai Farms',
    'traceType': 'harvest',
    'traceVersion': 2,
    'generatedAt': '2026-07-03T10:00:00Z',
    'analysisId': 'analysis-001',
    'batchId': batchId,
    'farm': 'Akole Millet Plot',
    'farmId': 'farm-001',
    'product': 'Ragi',
    'farmerId': 'FMR-001',
    'village': 'Akole',
    'farmerName': 'Farmer Name',
    'crop': 'Finger Millet',
    'variety': 'Local',
    'standards': 'FAQ',
    'grade': 'A',
    'score': '86',
    'bagSizeKg': '50',
    'bagCount': '12',
    'totalKg': '600',
    'moisture': '11.2',
    'moistureSource': 'meter_photo',
    'grader': 'Microservice',
    'reviewStatus': 'not_required',
    'actorRole': 'farmer',
  };
}

Map<String, dynamic> _farmerQrPayload() {
  return {
    'type': 'farmer_profile',
    'allowedRole': 'fpo_fpc',
    'brand': 'Kalsubai Farms',
    'farmerId': 'FMR-001',
    'farmerName': 'Farmer Name',
    'phone': '9876543210',
    'village': 'Akole',
    'primaryFarm': 'Akole Millet Plot',
    'crop': 'Finger Millet',
    'source': 'remote_supabase',
    'verified': true,
  };
}

String _traceUrl(Map<String, dynamic> payload) {
  final token = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'https://kalsubai.farms/#/trace/$token';
}
