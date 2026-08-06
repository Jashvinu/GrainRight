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

  test('parses merged verified shareholder directory payload', () {
    final page = AdminShareholderCandidatePage.fromJson({
      'rows': [
        {
          'id': 'candidate-1',
          'source_record_key': List.filled(64, 'a').join(),
          'directory_source': 'candidate_roster',
          'source_file': 'electoral-roll-part-11.pdf',
          'source_sheet': '',
          'source_part_no': 11,
          'source_page': 3,
          'source_ordinal': 1,
          'full_name': 'Candidate Farmer',
          'gender': 'Female',
          'village': 'Nalavanevadi (Shenit)',
          'main_village': 'Shenit Bk',
          'taluka': 'Akole',
          'district': 'Ahmednagar',
          'member_address': '',
          'address_inferred': false,
          'proposed_share_count': 1,
          'share_unit_value': 100,
          'proposed_total_amount': 100,
          'amount_recorded': true,
          'share_status': 'proposed',
          'farmer_status': 'unverified',
          'candidate_status': 'pending_consent_kyc_payment',
          'ocr_confidence': 94.5,
          'admin_promoted': true,
          'admin_promotion_basis': 'admin_override_without_kyc',
          'verification_status': 'verified_shareholder_override',
        },
        {
          'id': 'register-1',
          'source_record_key': 'register:register-1',
          'directory_source': 'shareholder_register',
          'source_file': 'SHARE HOLDER LIST FORMAT.xlsx',
          'source_sheet': 'Sheet1',
          'source_part_no': 0,
          'source_page': 0,
          'source_ordinal': 8,
          'full_name': 'Registered Farmer',
          'gender': '',
          'village': 'Kondani',
          'main_village': 'Ranad Bk',
          'taluka': 'Akole',
          'district': 'Ahmednagar',
          'member_address':
              'At Kondani Post Ranad Bk Tal Akole Dist Ahilynagar',
          'address_inferred': false,
          'proposed_share_count': 100,
          'share_unit_value': 0,
          'proposed_total_amount': 0,
          'amount_recorded': false,
          'share_status': 'allotted',
          'farmer_status': 'not_recorded',
          'candidate_status': 'verified_shareholder',
          'ocr_confidence': 0,
          'admin_promoted': false,
          'admin_promotion_basis': 'audited_shareholder_register',
          'verification_status': 'verified_shareholder',
        },
      ],
      'totalCount': 3237,
      'offset': 0,
      'limit': 100,
      'filters': {
        'villages': ['Nalavanevadi (Shenit)', 'Gaonatha (Shenit)'],
        'talukas': ['Akole'],
        'districts': ['Ahmednagar'],
      },
      'summary': {
        'totalRecords': 3237,
        'verifiedShareholders': 3237,
        'adminPromotedWithoutKyc': 3000,
        'candidateRecords': 3000,
        'verifiedFarmers': 0,
        'pendingKyc': 3000,
        'allottedShares': 2424,
        'proposedShares': 3000,
        'proposedCapital': 300000,
      },
    });

    expect(page.rows, hasLength(2));
    expect(page.totalCount, 3237);
    expect(page.villages, hasLength(2));
    expect(page.summary['proposedCapital'], 300000);
    expect(page.summary['verifiedShareholders'], 3237);
    expect(page.rows.first.fullName, 'Candidate Farmer');
    expect(page.rows.first.adminPromoted, isTrue);
    expect(page.rows.first.verificationStatus, 'verified_shareholder_override');
    expect(page.rows.last.fullName, 'Registered Farmer');
    expect(page.rows.last.directorySource, 'shareholder_register');
    expect(page.rows.last.proposedShareCount, 100);
    expect(page.rows.last.amountRecorded, isFalse);
    expect(page.rows.last.verificationStatus, 'verified_shareholder');
  });
}
