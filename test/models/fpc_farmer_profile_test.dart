import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/fpc_farmer_profile.dart';

void main() {
  test('merges the tenant link row with the verified farmer QR details', () {
    final profile = FpcFarmerProfile.fromLinkRow({
      'id': 'link-1',
      'farmer_id': 'FMR-101',
      'farmer_name': 'Savita Jadhav',
      'farmer_phone': '9876543210',
      'farm_id': 'farm-1',
      'farm_name': 'North field',
      'village': 'Rajur',
      'crop': 'Finger Millet',
      'kyc_status': 'verified',
      'status': 'active',
      'created_at': '2026-07-18T08:30:00Z',
      'source_payload': {
        'farmerName': 'Old QR name',
        'area': '2.5 acre',
        'lastYield': '820 kg',
        'lastGrade': 'A',
        'fpcRating': '4.8',
        'aadhaarLast4': '1234',
        'currentCrop': {
          'crop': 'Finger Millet',
          'variety': 'Dapoli-1',
          'season': 'Kharif 2026',
          'expectedYield': '900 kg',
        },
        'productionHistory': [
          {'season': 'Kharif 2025', 'crop': 'Finger Millet', 'yield': '820 kg'},
        ],
        'sellingHistory': [
          {'date': '2026-01-12', 'buyer': 'Kalsubai FPC', 'quantity': '600 kg'},
        ],
      },
    });

    expect(profile.name, 'Savita Jadhav');
    expect(profile.crop, 'Finger Millet');
    expect(profile.variety, 'Dapoli-1');
    expect(profile.season, 'Kharif 2026');
    expect(profile.maskedIdentity, 'XXXX XXXX 1234');
    expect(profile.productionHistory, hasLength(1));
    expect(profile.sellingHistory, hasLength(1));
    expect(profile.isActive, isTrue);
    expect(profile.isVerified, isTrue);
    expect(profile.searchText, contains('rajur'));
  });

  test('never exposes a raw Aadhaar value from the QR payload', () {
    final profile = FpcFarmerProfile.fromLinkRow({
      'farmer_id': 'FMR-102',
      'status': 'active',
      'source_payload': {
        'aadhaarNumber': '123456781234',
        'aadhaar_number': '987654321234',
      },
    });

    expect(profile.maskedIdentity, isEmpty);
    expect(profile.searchText, isNot(contains('123456781234')));
    expect(profile.searchText, isNot(contains('987654321234')));
  });
}
