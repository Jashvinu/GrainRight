import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/controllers/stakeholder_controller.dart';
import 'package:kalsubai_farms/models/stakeholder_land_record.dart';
import 'package:kalsubai_farms/models/stakeholder_plan.dart';
import 'package:kalsubai_farms/models/verified_farmer_record.dart';
import 'package:kalsubai_farms/services/stakeholder_service.dart';

class _SignatureUploadService extends StakeholderService {
  _SignatureUploadService({this.failUploads = false});

  final bool failUploads;
  final uploadedKinds = <String>[];

  @override
  Future<StakeholderDocumentUpload> uploadDocument({
    required VerifiedFarmerRecord farmer,
    required Uint8List bytes,
    required String fileName,
    required String documentKind,
  }) async {
    if (failUploads) {
      throw const StakeholderServiceException(
        'Stakeholder document storage is not configured.',
      );
    }
    uploadedKinds.add(documentKind);
    return StakeholderDocumentUpload(
      path: 'user/$documentKind/$fileName',
      kind: documentKind,
    );
  }
}

const _farmer = VerifiedFarmerRecord(
  phone: '9876543210',
  farmerId: 'FMR-001',
  farmerName: 'Farmer Name',
  defaultLocation: 'Akole',
  agriRecordId: 'AGR-123',
  aadhaarNumber: '123456786789',
  aadhaarLast4: '6789',
  lots: [],
);

const landRecordSummary = '''
Survey/Gat number: 45/2
Village: Akole
Taluka: Akole
District: Ahmednagar
Owner name on 7/12: Farmer Name
Land area: 2 acres''';

void main() {
  StakeholderController readyController() {
    final controller = StakeholderController();
    controller.plan.value = StakeholderPlan.fallback();
    controller.selectedAmount.value = 100;
    controller.consentInterestOnly.value = true;
    controller.consentNoGuaranteedReturn.value = true;
    controller.consentDataUse.value = true;
    controller.contractReadAccepted.value = true;
    controller.farmerFullName.value = 'Farmer Name';
    controller.farmerFatherName.value = 'Father Name';
    controller.farmerMobileNumber.value = '9876543210';
    controller.farmerAadhaarNumber.value = '123456786789';
    controller.farmerAadhaarLast4.value = '6789';
    controller.farmerAddress.value = 'At post Akole';
    controller.farmerVillage.value = 'Akole';
    controller.farmerTaluka.value = 'Akole';
    controller.farmerDistrict.value = 'Ahmednagar';
    controller.farmerPincode.value = '422601';
    controller.farmerTotalLandAcres.value = '2.5';
    controller.farmerAgriRecordId.value = 'AGR-123';
    controller.nomineeName.value = 'Nominee Name';
    controller.nomineeAddress.value = 'At post Akole';
    controller.nomineeMobileNumber.value = '9876501234';
    controller.nomineeSignature.value = 'user/nominee_signature/nominee.jpg';
    controller.farmerSignature.value =
        'user/farmer_signature/farmer-signature.jpg';
    return controller;
  }

  test('keeps full Aadhaar number and derives last four digits', () {
    final controller = StakeholderController();

    controller.setFarmerAadhaarNumber('1234 5678 9012');

    expect(controller.farmerAadhaarNumber.value, '123456789012');
    expect(controller.farmerAadhaarLast4.value, '9012');
  });

  test('allows manual PAN and manual bank details without uploads', () {
    final controller = readyController()
      ..setPanNumber('abcde 1234 f')
      ..panHolderName.value = 'Farmer Name'
      ..setLandRecordDetails(landRecordSummary)
      ..bankName.value = 'State Bank of India'
      ..accountHolderName.value = 'Farmer Name'
      ..bankAccountNumber.value = '1234567890'
      ..ifscCode.value = 'SBIN0001234';

    expect(controller.panNumber.value, 'ABCDE1234F');
    expect(controller.hasValidPanProof, isTrue);
    expect(controller.hasValidBankProof, isTrue);
    expect(controller.canSubmitBuyApplication, isTrue);
  });

  test('allows uploaded PAN and passbook without manual details', () {
    final controller = readyController()
      ..panDocumentPath.value = 'user/pan/pan.jpg'
      ..landRecordDocumentPath.value = 'user/land_record/712.jpg'
      ..passbookDocumentPath.value = 'user/passbook/passbook.jpg';

    expect(controller.hasValidPanProof, isTrue);
    expect(controller.hasValidBankProof, isTrue);
    expect(controller.canSubmitBuyApplication, isTrue);
  });

  test('allows both manual details and uploaded documents', () {
    final controller = readyController()
      ..panNumber.value = 'ABCDE1234F'
      ..panHolderName.value = 'Farmer Name'
      ..panDocumentPath.value = 'user/pan/pan.jpg'
      ..setLandRecordDetails(landRecordSummary)
      ..landRecordDocumentPath.value = 'user/land_record/712.jpg'
      ..bankName.value = 'HDFC Bank'
      ..accountHolderName.value = 'Farmer Name'
      ..bankAccountNumber.value = '9876543210'
      ..ifscCode.value = 'HDFC0001234'
      ..passbookDocumentPath.value = 'user/passbook/passbook.jpg';

    expect(controller.canSubmitBuyApplication, isTrue);
    expect(controller.hasValidLandRecordProof, isTrue);
  });

  test('accepts manual 7/12 details without upload', () {
    final controller = readyController()
      ..setPanNumber('ABCDE1234F')
      ..setLandRecordDetails(landRecordSummary)
      ..bankName.value = 'HDFC Bank'
      ..accountHolderName.value = 'Farmer Name'
      ..bankAccountNumber.value = '9876543210'
      ..ifscCode.value = 'HDFC0001234';

    expect(controller.landRecordDocumentPath.value, isEmpty);
    expect(controller.hasValidLandRecordProof, isTrue);
    expect(controller.canSubmitBuyApplication, isTrue);
  });

  test('stores remote signature paths after upload', () async {
    final service = _SignatureUploadService();
    final controller = StakeholderController(service: service);
    final bytes = Uint8List.fromList([1, 2, 3]);

    final nomineeSaved = await controller.uploadNomineeSignature(
      farmer: _farmer,
      bytes: bytes,
      fileName: 'nominee-signature.png',
    );
    final farmerSaved = await controller.uploadFarmerSignature(
      farmer: _farmer,
      bytes: bytes,
      fileName: 'farmer-signature.png',
    );

    expect(nomineeSaved, isTrue);
    expect(farmerSaved, isTrue);
    expect(
      controller.nomineeSignature.value,
      'user/nominee_signature/nominee-signature.png',
    );
    expect(
      controller.farmerSignature.value,
      'user/farmer_signature/farmer-signature.png',
    );
    expect(service.uploadedKinds, ['nominee_signature', 'farmer_signature']);
  });

  test(
    'keeps signature steps non-blocking when upload storage fails',
    () async {
      final service = _SignatureUploadService(failUploads: true);
      final controller = StakeholderController(service: service)
        ..plan.value = StakeholderPlan.fallback()
        ..selectedAmount.value = 100
        ..consentInterestOnly.value = true
        ..consentNoGuaranteedReturn.value = true
        ..consentDataUse.value = true
        ..contractReadAccepted.value = true
        ..farmerFullName.value = 'Farmer Name'
        ..farmerFatherName.value = 'Father Name'
        ..farmerMobileNumber.value = '9876543210'
        ..farmerAadhaarNumber.value = '123456786789'
        ..farmerAadhaarLast4.value = '6789'
        ..farmerAddress.value = 'At post Akole'
        ..farmerVillage.value = 'Akole'
        ..farmerTaluka.value = 'Akole'
        ..farmerDistrict.value = 'Ahmednagar'
        ..farmerPincode.value = '422601'
        ..farmerTotalLandAcres.value = '2.5'
        ..farmerAgriRecordId.value = 'AGR-123'
        ..nomineeName.value = 'Nominee Name'
        ..nomineeAddress.value = 'At post Akole'
        ..nomineeMobileNumber.value = '9876501234'
        ..setPanNumber('ABCDE1234F')
        ..setLandRecordDetails(landRecordSummary)
        ..bankName.value = 'HDFC Bank'
        ..accountHolderName.value = 'Farmer Name'
        ..bankAccountNumber.value = '9876543210'
        ..ifscCode.value = 'HDFC0001234';
      final bytes = Uint8List.fromList([1, 2, 3]);

      final nomineeSaved = await controller.uploadNomineeSignature(
        farmer: _farmer,
        bytes: bytes,
        fileName: 'nominee-signature.png',
      );
      final farmerSaved = await controller.uploadFarmerSignature(
        farmer: _farmer,
        bytes: bytes,
        fileName: 'farmer-signature.png',
      );

      expect(nomineeSaved, isTrue);
      expect(farmerSaved, isTrue);
      expect(
        controller.nomineeSignature.value,
        contains('/nominee_signature/'),
      );
      expect(controller.nomineeSignature.value, startsWith('local/'));
      expect(controller.farmerSignature.value, contains('/farmer_signature/'));
      expect(controller.farmerSignature.value, startsWith('local/'));
      expect(controller.errorMessage.value, isEmpty);
      expect(controller.hasFarmerApplicationDetails, isTrue);
      expect(controller.hasContractAcceptance, isTrue);
      expect(controller.canSubmitBuyApplication, isTrue);
      expect(service.uploadedKinds, isEmpty);
    },
  );

  test('keeps expanded manual 7/12 fields in the saved summary', () {
    const details = StakeholderLandRecordDetails(
      surveyGatNumber: '45/2',
      subDivisionNumber: '2A',
      village: 'Akole',
      taluka: 'Akole',
      district: 'Ahmednagar',
      ownerName: 'Farmer Name',
      landArea: '2 acres',
      cultivableArea: '1.75 acres',
      khataNumber: '123',
      cropOrUse: 'Ragi',
      irrigationSource: 'Well',
      mutationEntryNumber: 'Ferfar 87',
      landRevenue: 'Rs 12.50',
      otherRights: 'Bank charge noted',
    );

    final parsed = StakeholderLandRecordDetails.fromSummary(details.summary);

    expect(parsed.hasRequiredManualDetails, isTrue);
    expect(parsed.subDivisionNumber, '2A');
    expect(parsed.cultivableArea, '1.75 acres');
    expect(parsed.irrigationSource, 'Well');
    expect(parsed.mutationEntryNumber, 'Ferfar 87');
    expect(parsed.landRevenue, 'Rs 12.50');
    expect(parsed.otherRights, 'Bank charge noted');
  });

  test('blocks incomplete manual 7/12 fields without upload', () {
    final controller = readyController()
      ..setPanNumber('ABCDE1234F')
      ..setLandRecordDetails('Survey/Gat number: 45/2')
      ..bankName.value = 'HDFC Bank'
      ..accountHolderName.value = 'Farmer Name'
      ..bankAccountNumber.value = '9876543210'
      ..ifscCode.value = 'HDFC0001234';

    expect(controller.hasValidPanProof, isTrue);
    expect(controller.hasValidBankProof, isTrue);
    expect(controller.hasValidLandRecordProof, isFalse);
    expect(controller.canSubmitBuyApplication, isFalse);
  });

  test('blocks submission when farmer and nominee details are missing', () {
    final controller = readyController()
      ..farmerFullName.value = ''
      ..nomineeName.value = ''
      ..setPanNumber('ABCDE1234F')
      ..setLandRecordDetails(landRecordSummary)
      ..bankName.value = 'HDFC Bank'
      ..accountHolderName.value = 'Farmer Name'
      ..bankAccountNumber.value = '9876543210'
      ..ifscCode.value = 'HDFC0001234';

    expect(controller.hasFarmerApplicationDetails, isFalse);
    expect(controller.hasValidPanProof, isTrue);
    expect(controller.hasValidBankProof, isTrue);
    expect(controller.canSubmitBuyApplication, isFalse);
  });

  test(
    'requires second nominee details only when two nominees are selected',
    () {
      final controller = readyController()
        ..setPanNumber('ABCDE1234F')
        ..setLandRecordDetails(landRecordSummary)
        ..bankName.value = 'HDFC Bank'
        ..accountHolderName.value = 'Farmer Name'
        ..bankAccountNumber.value = '9876543210'
        ..ifscCode.value = 'HDFC0001234';

      controller.setNomineeCount(2);
      expect(controller.hasFarmerApplicationDetails, isFalse);
      expect(controller.canSubmitBuyApplication, isFalse);

      controller
        ..setNominee2Name('Second Nominee')
        ..setNominee2MobileNumber('9876509876')
        ..setNominee2Address('At post Akole')
        ..setNominee2Signature('user/nominee2_signature/nominee2.jpg');

      expect(controller.hasFarmerApplicationDetails, isTrue);
      expect(controller.canSubmitBuyApplication, isTrue);
    },
  );

  test('blocks submission when contract is not read and signed', () {
    final controller = readyController()
      ..contractReadAccepted.value = false
      ..farmerSignature.value = ''
      ..setPanNumber('ABCDE1234F')
      ..setLandRecordDetails(landRecordSummary)
      ..bankName.value = 'HDFC Bank'
      ..accountHolderName.value = 'Farmer Name'
      ..bankAccountNumber.value = '9876543210'
      ..ifscCode.value = 'HDFC0001234';

    expect(controller.hasFarmerApplicationDetails, isTrue);
    expect(controller.hasContractAcceptance, isFalse);
    expect(controller.canSubmitBuyApplication, isFalse);
  });

  test('blocks submission when PAN and bank proof are both missing', () {
    final controller = readyController();

    expect(controller.hasValidPanProof, isFalse);
    expect(controller.hasValidBankProof, isFalse);
    expect(controller.canSubmitBuyApplication, isFalse);
  });

  test('blocks submission when 7/12 proof is missing', () {
    final controller = readyController()
      ..setPanNumber('ABCDE1234F')
      ..bankName.value = 'HDFC Bank'
      ..accountHolderName.value = 'Farmer Name'
      ..bankAccountNumber.value = '9876543210'
      ..ifscCode.value = 'HDFC0001234';

    expect(controller.hasValidPanProof, isTrue);
    expect(controller.hasValidBankProof, isTrue);
    expect(controller.hasValidLandRecordProof, isFalse);
    expect(controller.canSubmitBuyApplication, isFalse);
  });
}
