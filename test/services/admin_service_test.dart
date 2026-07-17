import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/services/admin_service.dart';

void main() {
  test('parses stakeholder review document paths and timeline events', () {
    final record = AdminStakeholderRecord.fromJson(
      {
        'id': 'app-1',
        'farmer_id': 'FMR-001',
        'farmer_name': 'Farmer',
        'farmer_phone': '+91 98765 43210',
        'farmer_full_name': 'Farmer Full Name',
        'farmer_mobile_number': '9876543210',
        'selected_amount': 500,
        'estimated_shares': 5,
        'status': 'under_review',
        'payment_status': 'pending',
        'pan_number': 'ABCDE1234F',
        'pan_document_path': 'user/pan/pan.jpg',
        'land_record_details':
            'Survey/Gat number: 45/2\nVillage: Akole\nTaluka: Akole\nDistrict: Ahmednagar\nOwner name on 7/12: Farmer\nLand area: 2 acres',
        'land_record_document_path': 'user/land_record/712.jpg',
        'bank_name': 'State Bank of India',
        'account_holder_name': 'Farmer Full Name',
        'bank_account_number': '1234567890',
        'ifsc_code': 'SBIN0001234',
        'passbook_document_path': 'user/passbook/passbook.jpg',
        'farmer_signature': 'user/farmer_signature/sign.jpg',
        'nominee_signature': 'user/nominee_signature/sign.jpg',
        'submitted_at': '2026-07-03T10:00:00Z',
        'reviewed_at': '2026-07-03T10:05:00Z',
      },
      events: [
        {
          'status': 'submitted',
          'title': 'Application submitted',
          'note': 'Saved for review.',
          'actor_role': 'farmer',
          'created_at': '2026-07-03T10:00:00Z',
        },
        {
          'status': 'under_review',
          'title': 'Application under review',
          'note': 'Admin started review.',
          'actor_role': 'admin',
          'created_at': '2026-07-03T10:05:00Z',
        },
      ],
    );

    expect(record.farmerPhone, '9876543210');
    expect(record.panDocumentPath, 'user/pan/pan.jpg');
    expect(record.landRecordDocumentPath, 'user/land_record/712.jpg');
    expect(record.passbookDocumentPath, 'user/passbook/passbook.jpg');
    expect(record.farmerSignaturePath, 'user/farmer_signature/sign.jpg');
    expect(record.nomineeSignaturePath, 'user/nominee_signature/sign.jpg');
    expect(record.panSource, 'Manual + PAN document');
    expect(record.landRecordSource, 'Manual + 7/12 image');
    expect(record.bankSource, 'Manual + Passbook');
    expect(record.timeline, hasLength(2));
    expect(record.timeline.last.actorRole, 'admin');
    expect(record.timeline.last.note, 'Admin started review.');
    expect(record.submittedAt, isNotNull);
    expect(record.reviewedAt, isNotNull);
  });
}
