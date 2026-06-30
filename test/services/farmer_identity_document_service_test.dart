import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/services/farmer_identity_document_service.dart';

void main() {
  test('parses farm id aliases from OCR response', () {
    final result = FarmerIdentityOcrResult.fromJson({
      'document_path': 'farmer-session/agri-record.jpg',
      'identity': {
        'farmer_name': 'राम भाऊ शिंदे',
        'aadhaar_number': '1234 5678 9012',
        'farm_id': 'MH-AGR-7788',
        'confidence': 0.82,
      },
    }, documentPath: 'fallback.jpg');

    expect(result.documentPath, 'farmer-session/agri-record.jpg');
    expect(result.farmerName, 'राम भाऊ शिंदे');
    expect(result.aadhaarDigits, '123456789012');
    expect(result.agriRecordId, 'MH-AGR-7788');
    expect(result.confidence, 0.82);
  });

  test('parses wrapped OCR response aliases', () {
    final result = FarmerIdentityOcrResult.fromJson({
      'data': {
        'document_path': 'farmer-session/agri-record-2.jpg',
        'identity': {'aadhar_number': '987654321098', 'farmer_id': 'FARM-4455'},
      },
    }, documentPath: 'fallback.jpg');

    expect(result.documentPath, 'farmer-session/agri-record-2.jpg');
    expect(result.aadhaarDigits, '987654321098');
    expect(result.agriRecordId, 'FARM-4455');
  });

  test('parses name aliases from OCR response', () {
    final result = FarmerIdentityOcrResult.fromJson({
      'identity': {'nav': 'सुनिता गणपत जाधव', 'agri_record_id': 'AGR-9911'},
    }, documentPath: 'farmer-session/agri-record-3.jpg');

    expect(result.farmerName, 'सुनिता गणपत जाधव');
    expect(result.agriRecordId, 'AGR-9911');
  });
}
