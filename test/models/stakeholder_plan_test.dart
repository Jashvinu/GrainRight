import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/stakeholder_plan.dart';

void main() {
  test('estimates shares from selected amount and share unit value', () {
    final plan = StakeholderPlan.fromJson({
      'id': 'plan-1',
      'plan_code': 'stakeholder-v1',
      'title': 'Plan',
      'currency': 'INR',
      'share_unit_value': 1000,
      'min_amount': 1000,
      'max_amount': 25000,
      'purpose': ['member interest'],
    });

    expect(plan.estimateShares(5000), 5);
    expect(plan.estimateShares(5500), 5);
    expect(plan.snapAmount(5450), 5500);
    expect(plan.isValidAmount(1000), isTrue);
    expect(plan.isValidAmount(5500), isTrue);
    expect(plan.isValidAmount(5550), isFalse);
    expect(plan.isValidAmount(500), isFalse);
    expect(plan.isValidAmount(26000), isFalse);
  });

  test('fallback stakeholder plan starts at one hundred rupees', () {
    final plan = StakeholderPlan.fallback();

    expect(plan.minAmount, 100);
    expect(plan.shareUnitValue, 100);
    expect(plan.estimateShares(100), 1);
    expect(plan.isValidAmount(100), isTrue);
  });

  test('parses stakeholder application aliases', () {
    final application = StakeholderApplication.fromJson({
      'id': 'app-1',
      'plan_id': 'plan-1',
      'user_id': 'user-1',
      'farmer_phone': '+91 98765 43210',
      'farmer_id': 'FMR-001',
      'farmer_name': 'Farmer',
      'agri_record_id': 'AGR-123',
      'aadhaar_number': '123456786789',
      'aadhaar_last4': '6789',
      'farmer_full_name': 'Farmer Full Name',
      'farmer_father_name': 'Father Name',
      'farmer_mobile_number': '+91 98765 43210',
      'farmer_aadhaar_number': '123456786789',
      'farmer_aadhaar_last4': '6789',
      'farmer_address': 'At post Akole',
      'farmer_village': 'Akole',
      'farmer_taluka': 'Akole',
      'farmer_district': 'Ahmednagar',
      'farmer_pincode': '422601',
      'farmer_total_land_acres': '2.5',
      'nominee_name': 'Nominee Name',
      'nominee_address': 'At post Akole',
      'nominee_mobile_number': '9876501234',
      'nominee_signature': 'user/nominee_signature/nominee.jpg',
      'nominee_count': 2,
      'nominee2_name': 'Second Nominee',
      'nominee2_address': 'At post Akole',
      'nominee2_mobile_number': '+91 98765 09876',
      'nominee2_signature': 'user/nominee2_signature/nominee2.jpg',
      'farmer_signature': 'user/farmer_signature/farmer-signature.jpg',
      'contract_read_accepted': true,
      'selected_amount': '3000',
      'estimated_shares': '3',
      'status': 'under_review',
      'consent_interest_only': true,
      'consent_no_guaranteed_return': true,
      'consent_data_use': true,
      'pan_number': 'abcde1234f',
      'pan_holder_name': 'Farmer Name',
      'land_record_details':
          'Survey/Gat number: 45/2\nVillage: Akole\nTaluka: Akole\nDistrict: Ahmednagar\nOwner name on 7/12: Farmer Name\nLand area: 2 acres',
      'land_record_document_path': 'user/land_record/712.jpg',
      'passbook_document_path': 'user/passbook/passbook.jpg',
      'payment_method': 'razorpay',
      'payment_status': 'gateway_verified',
    });

    expect(application.farmerPhone, '9876543210');
    expect(application.selectedAmount, 3000);
    expect(application.estimatedShares, 3);
    expect(application.status, StakeholderApplicationStatus.underReview);
    expect(application.consentInterestOnly, isTrue);
    expect(application.farmerFullName, 'Farmer Full Name');
    expect(application.farmerFatherName, 'Father Name');
    expect(application.farmerMobileNumber, '9876543210');
    expect(application.aadhaarNumber, '123456786789');
    expect(application.farmerAadhaarNumber, '123456786789');
    expect(application.farmerAadhaarLast4, '6789');
    expect(application.farmerTotalLandAcres, '2.5');
    expect(application.farmerPhotoPath, isEmpty);
    expect(application.nomineeName, 'Nominee Name');
    expect(application.nomineeMobileNumber, '9876501234');
    expect(application.nomineeCount, 2);
    expect(application.nominee2Name, 'Second Nominee');
    expect(application.nominee2MobileNumber, '9876509876');
    expect(
      application.nominee2Signature,
      'user/nominee2_signature/nominee2.jpg',
    );
    expect(
      application.farmerSignature,
      'user/farmer_signature/farmer-signature.jpg',
    );
    expect(application.contractReadAccepted, isTrue);
    expect(application.panNumber, 'ABCDE1234F');
    expect(application.panHolderName, 'Farmer Name');
    expect(
      application.landRecordDetails,
      'Survey/Gat number: 45/2\nVillage: Akole\nTaluka: Akole\nDistrict: Ahmednagar\nOwner name on 7/12: Farmer Name\nLand area: 2 acres',
    );
    expect(application.landRecordDocumentPath, 'user/land_record/712.jpg');
    expect(application.passbookDocumentPath, 'user/passbook/passbook.jpg');
    expect(application.paymentMethod, StakeholderPaymentMethod.razorpay);
    expect(application.paymentStatus, StakeholderPaymentStatus.gatewayVerified);
  });
}
