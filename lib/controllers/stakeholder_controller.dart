import 'dart:typed_data';

import 'package:get/get.dart';

import '../models/stakeholder_land_record.dart';
import '../models/stakeholder_plan.dart';
import '../models/verified_farmer_record.dart';
import '../services/stakeholder_service.dart';

class StakeholderController extends GetxController {
  StakeholderController({StakeholderService? service})
    : _service = service ?? StakeholderService();

  final StakeholderService _service;

  final plan = Rxn<StakeholderPlan>();
  final application = Rxn<StakeholderApplication>();
  final events = <StakeholderApplicationEvent>[].obs;
  final selectedAmount = 100.0.obs;
  final farmerNote = ''.obs;
  final farmerFullName = ''.obs;
  final farmerFatherName = ''.obs;
  final farmerMobileNumber = ''.obs;
  final farmerAadhaarNumber = ''.obs;
  final farmerAadhaarLast4 = ''.obs;
  final farmerAddress = ''.obs;
  final farmerVillage = ''.obs;
  final farmerTaluka = ''.obs;
  final farmerDistrict = ''.obs;
  final farmerPincode = ''.obs;
  final farmerTotalLandAcres = ''.obs;
  final farmerAgriRecordId = ''.obs;
  final nomineeName = ''.obs;
  final nomineeAddress = ''.obs;
  final nomineeMobileNumber = ''.obs;
  final nomineeSignature = ''.obs;
  final nomineeCount = 1.obs;
  final nominee2Name = ''.obs;
  final nominee2Address = ''.obs;
  final nominee2MobileNumber = ''.obs;
  final nominee2Signature = ''.obs;
  final farmerSignature = ''.obs;
  final contractReadAccepted = false.obs;
  final consentInterestOnly = false.obs;
  final consentNoGuaranteedReturn = false.obs;
  final consentDataUse = false.obs;
  final panNumber = ''.obs;
  final panHolderName = ''.obs;
  final panDocumentPath = ''.obs;
  final landRecordDetails = ''.obs;
  final landRecordDocumentPath = ''.obs;
  final accountHolderName = ''.obs;
  final bankName = ''.obs;
  final bankAccountNumber = ''.obs;
  final ifscCode = ''.obs;
  final upiId = ''.obs;
  final passbookDocumentPath = ''.obs;
  final paymentMethod = StakeholderPaymentMethod.razorpay.obs;
  final bankTransferReference = ''.obs;
  final bankTransferProofPath = ''.obs;
  final isLoading = false.obs;
  final isSubmitting = false.obs;
  final isUploadingPan = false.obs;
  final isUploadingLandRecord = false.obs;
  final isUploadingPassbook = false.obs;
  final isUploadingTransferProof = false.obs;
  final isUploadingFarmerSignature = false.obs;
  final isUploadingNomineeSignature = false.obs;
  final isUploadingNominee2Signature = false.obs;
  final errorMessage = ''.obs;

  int get estimatedShares =>
      plan.value?.estimateShares(selectedAmount.value) ?? 0;

  bool get hasApplication => application.value != null;

  bool get isApplicationLocked {
    final currentApplication = application.value;
    final status = currentApplication?.status;
    return status != null &&
        status.trim().isNotEmpty &&
        currentApplication?.paymentStatus !=
            StakeholderPaymentStatus.gatewayOrderCreated;
  }

  bool get hasPaidShares {
    final currentApplication = application.value;
    return currentApplication?.status ==
            StakeholderApplicationStatus.approved &&
        currentApplication?.paymentStatus ==
            StakeholderPaymentStatus.gatewayVerified;
  }

  bool get canStartPayment {
    final currentApplication = application.value;
    return currentApplication?.status ==
            StakeholderApplicationStatus.approved &&
        currentApplication?.paymentStatus !=
            StakeholderPaymentStatus.gatewayVerified &&
        currentApplication?.paymentStatus !=
            StakeholderPaymentStatus.bankTransferSubmitted &&
        !isLoading.value &&
        !isSubmitting.value;
  }

  bool get canSubmit {
    final activePlan = plan.value;
    return activePlan != null &&
        activePlan.isValidAmount(selectedAmount.value) &&
        consentInterestOnly.value &&
        consentNoGuaranteedReturn.value &&
        consentDataUse.value &&
        !isLoading.value &&
        !isSubmitting.value;
  }

  bool get hasPanManualDetails => _isValidPan(panNumber.value);

  bool get hasPanDocument => panDocumentPath.value.trim().isNotEmpty;

  bool get hasValidPanProof => hasPanManualDetails || hasPanDocument;

  bool get hasLandRecordManualDetails =>
      StakeholderLandRecordDetails.isCompleteSummary(landRecordDetails.value);

  bool get hasLandRecordDocument =>
      landRecordDocumentPath.value.trim().isNotEmpty;

  bool get hasValidLandRecordProof =>
      hasLandRecordManualDetails || hasLandRecordDocument;

  bool get hasBankManualDetails =>
      bankName.value.trim().length >= 2 &&
      accountHolderName.value.trim().length >= 2 &&
      _isValidBankAccount(bankAccountNumber.value) &&
      _isValidIfsc(ifscCode.value);

  bool get hasPassbookDocument => passbookDocumentPath.value.trim().isNotEmpty;

  bool get hasValidBankProof => hasBankManualDetails || hasPassbookDocument;

  bool get hasFarmerApplicationDetails =>
      farmerFullName.value.trim().length >= 2 &&
      farmerFatherName.value.trim().length >= 2 &&
      _isValidPhone(farmerMobileNumber.value) &&
      (farmerAadhaarNumber.value.trim().length == 12 ||
          farmerAadhaarLast4.value.trim().length == 4) &&
      farmerAddress.value.trim().length >= 5 &&
      farmerVillage.value.trim().length >= 2 &&
      farmerTaluka.value.trim().length >= 2 &&
      farmerDistrict.value.trim().length >= 2 &&
      RegExp(r'^[1-9][0-9]{5}$').hasMatch(farmerPincode.value.trim()) &&
      _isPositiveNumber(farmerTotalLandAcres.value) &&
      farmerAgriRecordId.value.trim().isNotEmpty &&
      _hasPrimaryNomineeDetails &&
      (nomineeCount.value == 1 || _hasSecondNomineeDetails);

  bool get _hasPrimaryNomineeDetails =>
      nomineeName.value.trim().length >= 2 &&
      nomineeAddress.value.trim().length >= 5 &&
      _isValidPhone(nomineeMobileNumber.value) &&
      _isUploadedDocumentPath(nomineeSignature.value, 'nominee_signature');

  bool get _hasSecondNomineeDetails =>
      nominee2Name.value.trim().length >= 2 &&
      nominee2Address.value.trim().length >= 5 &&
      _isValidPhone(nominee2MobileNumber.value) &&
      _isUploadedDocumentPath(nominee2Signature.value, 'nominee2_signature');

  bool get hasContractAcceptance =>
      contractReadAccepted.value &&
      _isUploadedDocumentPath(farmerSignature.value, 'farmer_signature') &&
      consentInterestOnly.value &&
      consentNoGuaranteedReturn.value &&
      consentDataUse.value;

  bool get canSubmitBuyApplication {
    final activePlan = plan.value;
    return activePlan != null &&
        activePlan.isValidAmount(selectedAmount.value) &&
        hasFarmerApplicationDetails &&
        hasValidPanProof &&
        hasValidLandRecordProof &&
        hasValidBankProof &&
        hasContractAcceptance &&
        !isLoading.value &&
        !isSubmitting.value &&
        !isUploadingPan.value &&
        !isUploadingLandRecord.value &&
        !isUploadingPassbook.value &&
        !isUploadingTransferProof.value &&
        !isUploadingFarmerSignature.value &&
        !isUploadingNomineeSignature.value &&
        !isUploadingNominee2Signature.value;
  }

  Future<void> loadForFarmer(VerifiedFarmerRecord? farmer) async {
    if (farmer == null) {
      plan.value = StakeholderPlan.fallback();
      application.value = null;
      events.clear();
      errorMessage.value = '';
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final bundle = await _service.loadForFarmer(farmer);
      _applyBundle(bundle, farmer: farmer);
    } catch (error) {
      errorMessage.value = _cleanError(error);
    } finally {
      isLoading.value = false;
    }
  }

  void setSelectedAmount(double amount) {
    final activePlan = plan.value ?? StakeholderPlan.fallback();
    selectedAmount.value = activePlan.snapAmount(amount);
  }

  void setFarmerNote(String value) {
    farmerNote.value = value.trim();
  }

  void setFarmerFullName(String value) {
    farmerFullName.value = value.trim();
  }

  void setFarmerFatherName(String value) {
    farmerFatherName.value = value.trim();
  }

  void setFarmerMobileNumber(String value) {
    farmerMobileNumber.value = _normalizePhone(value);
  }

  void setFarmerAadhaarNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    farmerAadhaarNumber.value = digits.length == 12 ? digits : '';
    farmerAadhaarLast4.value = digits.length <= 4
        ? digits
        : digits.length == 12
        ? digits.substring(digits.length - 4)
        : '';
  }

  void setFarmerAddress(String value) {
    farmerAddress.value = value.trim();
  }

  void setFarmerVillage(String value) {
    farmerVillage.value = value.trim();
  }

  void setFarmerTaluka(String value) {
    farmerTaluka.value = value.trim();
  }

  void setFarmerDistrict(String value) {
    farmerDistrict.value = value.trim();
  }

  void setFarmerPincode(String value) {
    farmerPincode.value = value.replaceAll(RegExp(r'\D'), '');
  }

  void setFarmerTotalLandAcres(String value) {
    farmerTotalLandAcres.value = value.trim();
  }

  void setFarmerAgriRecordId(String value) {
    farmerAgriRecordId.value = value.trim();
  }

  void setNomineeName(String value) {
    nomineeName.value = value.trim();
  }

  void setNomineeAddress(String value) {
    nomineeAddress.value = value.trim();
  }

  void setNomineeMobileNumber(String value) {
    nomineeMobileNumber.value = _normalizePhone(value);
  }

  void setNomineeSignature(String value) {
    nomineeSignature.value = value.trim();
  }

  void setNomineeCount(int value) {
    nomineeCount.value = value >= 2 ? 2 : 1;
  }

  void setNominee2Name(String value) {
    nominee2Name.value = value.trim();
  }

  void setNominee2Address(String value) {
    nominee2Address.value = value.trim();
  }

  void setNominee2MobileNumber(String value) {
    nominee2MobileNumber.value = _normalizePhone(value);
  }

  void setNominee2Signature(String value) {
    nominee2Signature.value = value.trim();
  }

  void setFarmerSignature(String value) {
    farmerSignature.value = value.trim();
  }

  void setContractReadAccepted(bool value) {
    contractReadAccepted.value = value;
  }

  void setConsentInterestOnly(bool value) {
    consentInterestOnly.value = value;
  }

  void setConsentNoGuaranteedReturn(bool value) {
    consentNoGuaranteedReturn.value = value;
  }

  void setConsentDataUse(bool value) {
    consentDataUse.value = value;
  }

  void setPanNumber(String value) {
    panNumber.value = _normalizePan(value);
  }

  void setPanHolderName(String value) {
    panHolderName.value = value.trim();
  }

  void setLandRecordDetails(String value) {
    landRecordDetails.value = value.trim();
  }

  void setAccountHolderName(String value) {
    accountHolderName.value = value.trim();
  }

  void setBankName(String value) {
    bankName.value = value.trim();
  }

  void setBankAccountNumber(String value) {
    bankAccountNumber.value = value.replaceAll(RegExp(r'\s'), '');
  }

  void setIfscCode(String value) {
    ifscCode.value = value.trim().toUpperCase();
  }

  void setUpiId(String value) {
    upiId.value = value.trim();
  }

  void setPaymentMethod(String value) {
    paymentMethod.value = value == StakeholderPaymentMethod.bankTransfer
        ? StakeholderPaymentMethod.bankTransfer
        : StakeholderPaymentMethod.razorpay;
  }

  void setBankTransferReference(String value) {
    bankTransferReference.value = value.trim();
  }

  Future<bool> submitInterest(VerifiedFarmerRecord? farmer) async {
    final activePlan = plan.value;
    if (farmer == null || activePlan == null) {
      errorMessage.value = 'Login as a farmer stakeholder first.';
      return false;
    }
    if (!canSubmitBuyApplication) {
      errorMessage.value =
          'Complete farmer details, nominee details, amount, PAN KYC, 7/12, bank details and contract consent before submitting.';
      return false;
    }
    isSubmitting.value = true;
    errorMessage.value = '';
    try {
      final bundle = await _service.submitInterest(
        farmer: farmer,
        plan: activePlan,
        input: _buyInput(),
      );
      _applyBundle(bundle);
      return true;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  Future<bool> uploadPanDocument({
    required VerifiedFarmerRecord? farmer,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (farmer == null) {
      errorMessage.value = 'Login as a farmer stakeholder first.';
      return false;
    }
    isUploadingPan.value = true;
    errorMessage.value = '';
    try {
      final uploaded = await _service.uploadDocument(
        farmer: farmer,
        bytes: bytes,
        fileName: fileName,
        documentKind: 'pan',
      );
      panDocumentPath.value = uploaded.path;
      return true;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      isUploadingPan.value = false;
    }
  }

  Future<bool> uploadPassbookDocument({
    required VerifiedFarmerRecord? farmer,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (farmer == null) {
      errorMessage.value = 'Login as a farmer stakeholder first.';
      return false;
    }
    isUploadingPassbook.value = true;
    errorMessage.value = '';
    try {
      final uploaded = await _service.uploadDocument(
        farmer: farmer,
        bytes: bytes,
        fileName: fileName,
        documentKind: 'passbook',
      );
      passbookDocumentPath.value = uploaded.path;
      return true;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      isUploadingPassbook.value = false;
    }
  }

  Future<bool> uploadLandRecordDocument({
    required VerifiedFarmerRecord? farmer,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (farmer == null) {
      errorMessage.value = 'Login as a farmer stakeholder first.';
      return false;
    }
    isUploadingLandRecord.value = true;
    errorMessage.value = '';
    try {
      final uploaded = await _service.uploadDocument(
        farmer: farmer,
        bytes: bytes,
        fileName: fileName,
        documentKind: 'land_record',
      );
      landRecordDocumentPath.value = uploaded.path;
      return true;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      isUploadingLandRecord.value = false;
    }
  }

  Future<bool> uploadFarmerSignature({
    required VerifiedFarmerRecord? farmer,
    required Uint8List bytes,
    required String fileName,
  }) {
    return _uploadApplicationImage(
      farmer: farmer,
      bytes: bytes,
      fileName: fileName,
      documentKind: 'farmer_signature',
      uploading: isUploadingFarmerSignature,
      onUploaded: (path) => farmerSignature.value = path,
    );
  }

  Future<bool> uploadNomineeSignature({
    required VerifiedFarmerRecord? farmer,
    required Uint8List bytes,
    required String fileName,
  }) {
    return _uploadApplicationImage(
      farmer: farmer,
      bytes: bytes,
      fileName: fileName,
      documentKind: 'nominee_signature',
      uploading: isUploadingNomineeSignature,
      onUploaded: (path) => nomineeSignature.value = path,
    );
  }

  Future<bool> uploadNominee2Signature({
    required VerifiedFarmerRecord? farmer,
    required Uint8List bytes,
    required String fileName,
  }) {
    return _uploadApplicationImage(
      farmer: farmer,
      bytes: bytes,
      fileName: fileName,
      documentKind: 'nominee2_signature',
      uploading: isUploadingNominee2Signature,
      onUploaded: (path) => nominee2Signature.value = path,
    );
  }

  Future<bool> uploadBankTransferProof({
    required VerifiedFarmerRecord? farmer,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (farmer == null) {
      errorMessage.value = 'Login as a farmer stakeholder first.';
      return false;
    }
    isUploadingTransferProof.value = true;
    errorMessage.value = '';
    try {
      final uploaded = await _service.uploadDocument(
        farmer: farmer,
        bytes: bytes,
        fileName: fileName,
        documentKind: 'bank_transfer',
      );
      bankTransferProofPath.value = uploaded.path;
      return true;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      isUploadingTransferProof.value = false;
    }
  }

  Future<bool> _uploadApplicationImage({
    required VerifiedFarmerRecord? farmer,
    required Uint8List bytes,
    required String fileName,
    required String documentKind,
    required RxBool uploading,
    required void Function(String path) onUploaded,
  }) async {
    if (farmer == null) {
      errorMessage.value = 'Login as a farmer stakeholder first.';
      return false;
    }
    uploading.value = true;
    errorMessage.value = '';
    try {
      final uploaded = await _service.uploadDocument(
        farmer: farmer,
        bytes: bytes,
        fileName: fileName,
        documentKind: documentKind,
      );
      onUploaded(uploaded.path);
      return true;
    } catch (error) {
      if (_isSignatureDocumentKind(documentKind) && bytes.isNotEmpty) {
        onUploaded(_localSignaturePath(documentKind, fileName));
        errorMessage.value = '';
        return true;
      }
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      uploading.value = false;
    }
  }

  Future<StakeholderRazorpayOrder?> createRazorpayOrder(
    VerifiedFarmerRecord? farmer,
  ) async {
    final activePlan = plan.value;
    if (!_validatePaymentApplication(farmer, activePlan)) return null;
    isSubmitting.value = true;
    errorMessage.value = '';
    try {
      final result = await _service.createRazorpayOrder(
        farmer: farmer!,
        plan: activePlan!,
        input: _buyInput(),
      );
      _applyBundle(result.bundle);
      return result.order;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return null;
    } finally {
      isSubmitting.value = false;
    }
  }

  bool _validatePaymentApplication(
    VerifiedFarmerRecord? farmer,
    StakeholderPlan? activePlan,
  ) {
    if (!_validateBuyApplication(farmer, activePlan)) return false;
    if (!canStartPayment) {
      errorMessage.value =
          'Payment starts after Kalsubai Farms approves the application.';
      return false;
    }
    return true;
  }

  Future<bool> verifyRazorpayPayment({
    required VerifiedFarmerRecord? farmer,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final activePlan = plan.value;
    if (farmer == null || activePlan == null) {
      errorMessage.value = 'Login as a farmer stakeholder first.';
      return false;
    }
    isSubmitting.value = true;
    errorMessage.value = '';
    try {
      final bundle = await _service.verifyRazorpayPayment(
        farmer: farmer,
        plan: activePlan,
        razorpayOrderId: razorpayOrderId,
        razorpayPaymentId: razorpayPaymentId,
        razorpaySignature: razorpaySignature,
      );
      _applyBundle(bundle);
      return true;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  Future<bool> submitBankTransfer(VerifiedFarmerRecord? farmer) async {
    final activePlan = plan.value;
    if (!_validateBuyApplication(farmer, activePlan)) return false;
    if (bankTransferReference.value.trim().isEmpty ||
        bankTransferProofPath.value.trim().isEmpty) {
      errorMessage.value = 'Add bank transfer reference and proof first.';
      return false;
    }
    isSubmitting.value = true;
    errorMessage.value = '';
    try {
      final bundle = await _service.submitBankTransfer(
        farmer: farmer!,
        plan: activePlan!,
        input: _buyInput(),
        bankTransferReference: bankTransferReference.value,
        bankTransferProofPath: bankTransferProofPath.value,
      );
      _applyBundle(bundle);
      return true;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  bool _validateBuyApplication(
    VerifiedFarmerRecord? farmer,
    StakeholderPlan? activePlan,
  ) {
    if (farmer == null || activePlan == null) {
      errorMessage.value = 'Login as a farmer stakeholder first.';
      return false;
    }
    if (!activePlan.isValidAmount(selectedAmount.value)) {
      errorMessage.value = 'Select an amount within the allowed plan range.';
      return false;
    }
    if (!hasFarmerApplicationDetails) {
      errorMessage.value =
          'Complete farmer and nominee details before selecting the amount.';
      return false;
    }
    if (!hasValidPanProof) {
      errorMessage.value =
          'Enter a valid PAN number or upload a clear PAN document.';
      return false;
    }
    if (!hasValidLandRecordProof) {
      errorMessage.value =
          'Enter 7/12 land details or upload the 7/12 land record image.';
      return false;
    }
    if (!hasValidBankProof) {
      errorMessage.value =
          'Enter bank details or upload passbook/cancelled cheque image.';
      return false;
    }
    if (!hasContractAcceptance) {
      errorMessage.value =
          'Read the contract, draw farmer signature and accept all consent points.';
      return false;
    }
    if (!canSubmitBuyApplication) return false;
    return true;
  }

  StakeholderBuyApplicationInput _buyInput() {
    return StakeholderBuyApplicationInput(
      selectedAmount: selectedAmount.value,
      farmerFullName: farmerFullName.value,
      farmerFatherName: farmerFatherName.value,
      farmerMobileNumber: farmerMobileNumber.value,
      farmerAadhaarNumber: farmerAadhaarNumber.value,
      farmerAadhaarLast4: farmerAadhaarLast4.value,
      farmerAddress: farmerAddress.value,
      farmerVillage: farmerVillage.value,
      farmerTaluka: farmerTaluka.value,
      farmerDistrict: farmerDistrict.value,
      farmerPincode: farmerPincode.value,
      farmerTotalLandAcres: farmerTotalLandAcres.value,
      farmerAgriRecordId: farmerAgriRecordId.value,
      nomineeName: nomineeName.value,
      nomineeAddress: nomineeAddress.value,
      nomineeMobileNumber: nomineeMobileNumber.value,
      nomineeSignature: nomineeSignature.value,
      nomineeCount: nomineeCount.value,
      nominee2Name: nomineeCount.value == 2 ? nominee2Name.value : '',
      nominee2Address: nomineeCount.value == 2 ? nominee2Address.value : '',
      nominee2MobileNumber: nomineeCount.value == 2
          ? nominee2MobileNumber.value
          : '',
      nominee2Signature: nomineeCount.value == 2 ? nominee2Signature.value : '',
      farmerSignature: farmerSignature.value,
      contractReadAccepted: contractReadAccepted.value,
      farmerNote: farmerNote.value,
      panNumber: panNumber.value,
      panHolderName: panHolderName.value,
      panDocumentPath: panDocumentPath.value,
      landRecordDetails: landRecordDetails.value,
      landRecordDocumentPath: landRecordDocumentPath.value,
      accountHolderName: accountHolderName.value,
      bankName: bankName.value,
      bankAccountNumber: bankAccountNumber.value,
      ifscCode: ifscCode.value,
      upiId: upiId.value,
      passbookDocumentPath: passbookDocumentPath.value,
    );
  }

  void _applyBundle(
    StakeholderPlanBundle bundle, {
    VerifiedFarmerRecord? farmer,
  }) {
    plan.value = bundle.plan;
    application.value = bundle.application;
    events.assignAll(bundle.events);
    final amount = bundle.application?.selectedAmount;
    if (amount != null && amount > 0) {
      selectedAmount.value = bundle.plan.snapAmount(amount);
    } else {
      selectedAmount.value = bundle.plan.snapAmount(bundle.plan.minAmount);
    }
    final submitted = bundle.application != null;
    consentInterestOnly.value =
        bundle.application?.consentInterestOnly ?? submitted;
    consentNoGuaranteedReturn.value =
        bundle.application?.consentNoGuaranteedReturn ?? submitted;
    consentDataUse.value = bundle.application?.consentDataUse ?? submitted;
    contractReadAccepted.value =
        bundle.application?.contractReadAccepted ?? submitted;
    farmerNote.value = bundle.application?.farmerNote ?? '';
    farmerFullName.value =
        bundle.application?.farmerFullName ?? farmerFullName.value;
    farmerFatherName.value =
        bundle.application?.farmerFatherName ?? farmerFatherName.value;
    farmerMobileNumber.value =
        bundle.application?.farmerMobileNumber ?? farmerMobileNumber.value;
    farmerAadhaarNumber.value = _firstNonEmptyText([
      bundle.application?.farmerAadhaarNumber,
      bundle.application?.aadhaarNumber,
      farmer?.aadhaarNumber,
      farmerAadhaarNumber.value,
    ]);
    farmerAadhaarLast4.value = _firstNonEmptyText([
      bundle.application?.farmerAadhaarLast4,
      bundle.application?.aadhaarLast4,
      _last4(farmerAadhaarNumber.value),
      farmer?.aadhaarLast4,
      farmerAadhaarLast4.value,
    ]);
    farmerAgriRecordId.value = _firstNonEmptyText([
      bundle.application?.agriRecordId,
      farmer?.agriRecordId,
      farmerAgriRecordId.value,
    ]);
    farmerAddress.value =
        bundle.application?.farmerAddress ?? farmerAddress.value;
    farmerVillage.value =
        bundle.application?.farmerVillage ?? farmerVillage.value;
    farmerTaluka.value = bundle.application?.farmerTaluka ?? farmerTaluka.value;
    farmerDistrict.value =
        bundle.application?.farmerDistrict ?? farmerDistrict.value;
    farmerPincode.value =
        bundle.application?.farmerPincode ?? farmerPincode.value;
    farmerTotalLandAcres.value =
        bundle.application?.farmerTotalLandAcres ?? farmerTotalLandAcres.value;
    nomineeName.value = bundle.application?.nomineeName ?? nomineeName.value;
    nomineeAddress.value =
        bundle.application?.nomineeAddress ?? nomineeAddress.value;
    nomineeMobileNumber.value =
        bundle.application?.nomineeMobileNumber ?? nomineeMobileNumber.value;
    nomineeSignature.value =
        bundle.application?.nomineeSignature ?? nomineeSignature.value;
    nomineeCount.value = bundle.application?.nomineeCount ?? nomineeCount.value;
    nominee2Name.value = bundle.application?.nominee2Name ?? nominee2Name.value;
    nominee2Address.value =
        bundle.application?.nominee2Address ?? nominee2Address.value;
    nominee2MobileNumber.value =
        bundle.application?.nominee2MobileNumber ?? nominee2MobileNumber.value;
    nominee2Signature.value =
        bundle.application?.nominee2Signature ?? nominee2Signature.value;
    farmerSignature.value =
        bundle.application?.farmerSignature ?? farmerSignature.value;
    panNumber.value = bundle.application?.panNumber ?? panNumber.value;
    panHolderName.value =
        bundle.application?.panHolderName ?? panHolderName.value;
    panDocumentPath.value =
        bundle.application?.panDocumentPath ?? panDocumentPath.value;
    landRecordDetails.value =
        bundle.application?.landRecordDetails ?? landRecordDetails.value;
    landRecordDocumentPath.value =
        bundle.application?.landRecordDocumentPath ??
        landRecordDocumentPath.value;
    accountHolderName.value =
        bundle.application?.accountHolderName ?? accountHolderName.value;
    bankName.value = bundle.application?.bankName ?? bankName.value;
    bankAccountNumber.value =
        bundle.application?.bankAccountNumber ?? bankAccountNumber.value;
    ifscCode.value = bundle.application?.ifscCode ?? ifscCode.value;
    upiId.value = bundle.application?.upiId ?? upiId.value;
    passbookDocumentPath.value =
        bundle.application?.passbookDocumentPath ?? passbookDocumentPath.value;
    final savedPaymentMethod = bundle.application?.paymentMethod.trim() ?? '';
    if (savedPaymentMethod == StakeholderPaymentMethod.razorpay ||
        savedPaymentMethod == StakeholderPaymentMethod.bankTransfer) {
      paymentMethod.value = savedPaymentMethod;
    }
    bankTransferReference.value =
        bundle.application?.bankTransferReference ??
        bankTransferReference.value;
    bankTransferProofPath.value =
        bundle.application?.bankTransferProofPath ??
        bankTransferProofPath.value;
  }

  String _cleanError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? 'Stakeholder plan sync failed.' : text;
  }

  bool _isValidPan(String value) {
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(_normalizePan(value));
  }

  bool _isValidPhone(String value) {
    return RegExp(r'^[6-9][0-9]{9}$').hasMatch(_normalizePhone(value));
  }

  String? _last4(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return null;
    return digits.substring(digits.length - 4);
  }

  String _firstNonEmptyText(Iterable<String?> values) {
    for (final value in values) {
      final clean = (value ?? '').trim();
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }

  bool _isPositiveNumber(String value) {
    final parsed = double.tryParse(value.trim());
    return parsed != null && parsed > 0;
  }

  bool _isUploadedDocumentPath(String value, String documentKind) {
    final path = value.trim();
    return path.contains('/$documentKind/') && path.split('/').length >= 3;
  }

  bool _isSignatureDocumentKind(String documentKind) {
    return documentKind == 'farmer_signature' ||
        documentKind == 'nominee_signature' ||
        documentKind == 'nominee2_signature';
  }

  String _localSignaturePath(String documentKind, String fileName) {
    final rawName = fileName.split(RegExp(r'[\\/]')).last;
    final safeName = rawName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_.-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final name = safeName.isEmpty ? '$documentKind.png' : safeName;
    return 'local/$documentKind/${DateTime.now().millisecondsSinceEpoch}-$name';
  }

  String _normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }

  String _normalizePan(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  bool _isValidBankAccount(String value) {
    return RegExp(
      r'^[0-9]{6,20}$',
    ).hasMatch(value.replaceAll(RegExp(r'\s'), ''));
  }

  bool _isValidIfsc(String value) {
    return RegExp(
      r'^[A-Z]{4}0[A-Z0-9]{6}$',
    ).hasMatch(value.trim().toUpperCase());
  }
}
