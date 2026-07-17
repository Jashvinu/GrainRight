import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/verified_farmer_record.dart';

void main() {
  test('parses farmer identity metadata from response json', () {
    final record = VerifiedFarmerRecord.fromJson({
      'phone': '9876543210',
      'farmerId': 'FMR-123',
      'farmerName': 'Test Farmer',
      'defaultLocation': 'Rajur',
      'agri_record_id': 'AGR-456',
      'aadhaar_masked': 'XXXX XXXX 1234',
      'aadhaar_last4': '1234',
      'identity_document_path': 'user-id/document.jpg',
    });

    expect(record.phone, '9876543210');
    expect(record.farmerId, 'FMR-123');
    expect(record.agriRecordId, 'AGR-456');
    expect(record.aadhaarMasked, 'XXXX XXXX 1234');
    expect(record.aadhaarLast4, '1234');
    expect(record.identityDocumentPath, 'user-id/document.jpg');
  });
}
