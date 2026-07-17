import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/stakeholder_land_record.dart';
import '../models/stakeholder_plan.dart';
import '../models/verified_farmer_record.dart';

class StakeholderServiceException implements Exception {
  final String message;

  const StakeholderServiceException(this.message);

  @override
  String toString() => message;
}

String _normalizePan(String value) {
  return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}

class StakeholderService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<StakeholderPlanBundle> loadForFarmer(
    VerifiedFarmerRecord farmer,
  ) async {
    try {
      final response = await _invokeFunction({
        'action': 'load',
        'farmer': _farmerPayload(farmer),
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        if (_isFunctionNotFoundData(data)) {
          return _loadDirectOrFallback();
        }
        throw StakeholderServiceException(
          '${data['error'] ?? 'Stakeholder plan sync failed.'}',
        );
      }
      if (data.isEmpty) {
        throw const StakeholderServiceException(
          'Stakeholder plan sync failed.',
        );
      }
      return StakeholderPlanBundle.fromJson(data);
    } on StakeholderServiceException {
      rethrow;
    } catch (error) {
      if (_isFunctionNotFound(error)) {
        return _loadDirectOrFallback();
      }
      throw StakeholderServiceException(
        _cleanRemoteError(error, 'Stakeholder plan sync failed.'),
      );
    }
  }

  Future<StakeholderPlanBundle> submitInterest({
    required VerifiedFarmerRecord farmer,
    required StakeholderPlan plan,
    required StakeholderBuyApplicationInput input,
  }) async {
    try {
      if (!plan.isValidAmount(input.selectedAmount)) {
        throw const StakeholderServiceException(
          'Select an amount within the allowed plan range.',
        );
      }
      _validateBuyApplicationInput(input, farmer: farmer);
      final response = await _invokeFunction({
        'action': 'submit_interest',
        ..._buyApplicationPayload(farmer: farmer, plan: plan, input: input),
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        if (_isFunctionNotFoundData(data)) {
          return _submitInterestDirect(
            farmer: farmer,
            plan: plan,
            input: input,
          );
        }
        if (_isApplicationAlreadySubmittedData(data)) {
          return loadForFarmer(farmer);
        }
        throw StakeholderServiceException(
          '${data['error'] ?? 'Stakeholder interest submission failed.'}',
        );
      }
      if (data.isEmpty) {
        throw const StakeholderServiceException(
          'Stakeholder interest submission failed.',
        );
      }
      return StakeholderPlanBundle.fromJson(data);
    } on StakeholderServiceException {
      rethrow;
    } catch (error) {
      if (_isFunctionNotFound(error)) {
        return _submitInterestDirect(farmer: farmer, plan: plan, input: input);
      }
      if (_isApplicationAlreadySubmittedError(error)) {
        return loadForFarmer(farmer);
      }
      throw StakeholderServiceException(
        _cleanRemoteError(error, 'Stakeholder interest submission failed.'),
      );
    }
  }

  Future<StakeholderDocumentUpload> uploadDocument({
    required VerifiedFarmerRecord farmer,
    required Uint8List bytes,
    required String fileName,
    required String documentKind,
  }) async {
    if (bytes.isEmpty) {
      throw const StakeholderServiceException('Select a clear document image.');
    }
    try {
      final contentType = _contentTypeFor(fileName, bytes);
      final response = await _invokeFunction({
        'action': 'upload_document',
        'farmer': _farmerPayload(farmer),
        'documentKind': documentKind,
        'fileName': fileName,
        'contentType': contentType,
        'imageBase64': base64Encode(bytes),
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        if (_isFunctionNotFoundData(data)) {
          return _uploadDocumentDirect(
            farmer: farmer,
            bytes: bytes,
            fileName: fileName,
            documentKind: documentKind,
            contentType: contentType,
          );
        }
        throw StakeholderServiceException(
          '${data['error'] ?? 'Document upload failed.'}',
        );
      }
      return StakeholderDocumentUpload.fromJson(data);
    } on StakeholderServiceException {
      rethrow;
    } catch (error) {
      if (_isFunctionNotFound(error)) {
        return _uploadDocumentDirect(
          farmer: farmer,
          bytes: bytes,
          fileName: fileName,
          documentKind: documentKind,
          contentType: _contentTypeFor(fileName, bytes),
        );
      }
      throw StakeholderServiceException(
        _cleanRemoteError(error, 'Document upload failed.'),
      );
    }
  }

  Future<({StakeholderPlanBundle bundle, StakeholderRazorpayOrder order})>
  createRazorpayOrder({
    required VerifiedFarmerRecord farmer,
    required StakeholderPlan plan,
    required StakeholderBuyApplicationInput input,
  }) async {
    try {
      _validateBuyApplicationInput(input, farmer: farmer);
      final response = await _invokeFunction({
        'action': 'create_razorpay_order',
        ..._buyApplicationPayload(farmer: farmer, plan: plan, input: input),
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw StakeholderServiceException(
          '${data['error'] ?? 'Could not start payment.'}',
        );
      }
      final rawOrder = data['order'];
      if (rawOrder is! Map) {
        throw const StakeholderServiceException(
          'Could not start payment. Try again later.',
        );
      }
      return (
        bundle: StakeholderPlanBundle.fromJson(data),
        order: StakeholderRazorpayOrder.fromJson(
          Map<String, dynamic>.from(rawOrder),
        ),
      );
    } on StakeholderServiceException {
      rethrow;
    } catch (error) {
      throw StakeholderServiceException(
        _cleanRemoteError(error, 'Could not start payment.'),
      );
    }
  }

  Future<StakeholderPlanBundle> verifyRazorpayPayment({
    required VerifiedFarmerRecord farmer,
    required StakeholderPlan plan,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      final response = await _invokeFunction({
        'action': 'verify_razorpay_payment',
        'farmer': _farmerPayload(farmer),
        'planId': plan.id,
        'planCode': plan.planCode,
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw StakeholderServiceException(
          '${data['error'] ?? 'Payment verification failed.'}',
        );
      }
      return StakeholderPlanBundle.fromJson(data);
    } on StakeholderServiceException {
      rethrow;
    } catch (error) {
      throw StakeholderServiceException(
        _cleanRemoteError(error, 'Payment verification failed.'),
      );
    }
  }

  Future<StakeholderPlanBundle> submitBankTransfer({
    required VerifiedFarmerRecord farmer,
    required StakeholderPlan plan,
    required StakeholderBuyApplicationInput input,
    required String bankTransferReference,
    required String bankTransferProofPath,
  }) async {
    try {
      _validateBuyApplicationInput(input, farmer: farmer);
      final response = await _invokeFunction({
        'action': 'submit_bank_transfer',
        ..._buyApplicationPayload(farmer: farmer, plan: plan, input: input),
        'bankTransferReference': bankTransferReference.trim(),
        'bankTransferProofPath': bankTransferProofPath.trim(),
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw StakeholderServiceException(
          '${data['error'] ?? 'Bank transfer submission failed.'}',
        );
      }
      return StakeholderPlanBundle.fromJson(data);
    } on StakeholderServiceException {
      rethrow;
    } catch (error) {
      throw StakeholderServiceException(
        _cleanRemoteError(error, 'Bank transfer submission failed.'),
      );
    }
  }

  Future<dynamic> _invokeFunction(Map<String, Object?> body) {
    return _client.functions.invoke(
      'stakeholder-plan-sync',
      headers: _functionAuthHeaders(),
      body: body,
    );
  }

  Map<String, Object?> _buyApplicationPayload({
    required VerifiedFarmerRecord farmer,
    required StakeholderPlan plan,
    required StakeholderBuyApplicationInput input,
  }) {
    final nomineeCount = input.nomineeCount >= 2 ? 2 : 1;
    final farmerAadhaarNumber = _farmerAadhaarNumber(farmer, input);
    final farmerAadhaarLast4 = _farmerAadhaarLast4(farmer, input);
    return {
      'farmer': _farmerPayload(farmer),
      'planId': plan.id,
      'planCode': plan.planCode,
      'selectedAmount': input.selectedAmount,
      'estimatedShares': plan.estimateShares(input.selectedAmount),
      'farmerFullName': input.farmerFullName.trim(),
      'farmerFatherName': input.farmerFatherName.trim(),
      'farmerMobileNumber': _normalizePhone(input.farmerMobileNumber),
      'farmerAadhaarNumber': farmerAadhaarNumber,
      'farmerAadhaarLast4': farmerAadhaarLast4,
      'farmerAddress': input.farmerAddress.trim(),
      'farmerVillage': input.farmerVillage.trim(),
      'farmerTaluka': input.farmerTaluka.trim(),
      'farmerDistrict': input.farmerDistrict.trim(),
      'farmerPincode': input.farmerPincode.replaceAll(RegExp(r'\D'), ''),
      'farmerTotalLandAcres': input.farmerTotalLandAcres.trim(),
      'farmerAgriRecordId': input.farmerAgriRecordId.trim(),
      'nomineeName': input.nomineeName.trim(),
      'nomineeAddress': input.nomineeAddress.trim(),
      'nomineeMobileNumber': _normalizePhone(input.nomineeMobileNumber),
      'nomineeSignature': input.nomineeSignature.trim(),
      'nomineeCount': nomineeCount,
      'nominee2Name': nomineeCount == 2 ? input.nominee2Name.trim() : '',
      'nominee2Address': nomineeCount == 2 ? input.nominee2Address.trim() : '',
      'nominee2MobileNumber': nomineeCount == 2
          ? _normalizePhone(input.nominee2MobileNumber)
          : '',
      'nominee2Signature': nomineeCount == 2
          ? input.nominee2Signature.trim()
          : '',
      'farmerSignature': input.farmerSignature.trim(),
      'contractReadAccepted': input.contractReadAccepted,
      'farmerNote': input.farmerNote.trim(),
      'panNumber': _normalizePan(input.panNumber),
      'panHolderName': input.panHolderName.trim(),
      'panDocumentPath': input.panDocumentPath.trim(),
      'landRecordDetails': input.landRecordDetails.trim(),
      'landRecordDocumentPath': input.landRecordDocumentPath.trim(),
      'accountHolderName': input.accountHolderName.trim(),
      'bankName': input.bankName.trim(),
      'bankAccountNumber': input.bankAccountNumber.replaceAll(
        RegExp(r'\s'),
        '',
      ),
      'ifscCode': input.ifscCode.trim().toUpperCase(),
      'upiId': input.upiId.trim(),
      'passbookDocumentPath': input.passbookDocumentPath.trim(),
      'consentInterestOnly': true,
      'consentNoGuaranteedReturn': true,
      'consentDataUse': true,
    };
  }

  void _validateBuyApplicationInput(
    StakeholderBuyApplicationInput input, {
    VerifiedFarmerRecord? farmer,
  }) {
    final nomineeCount = input.nomineeCount >= 2 ? 2 : 1;
    final farmerPhone = _normalizePhone(input.farmerMobileNumber);
    final nomineePhone = _normalizePhone(input.nomineeMobileNumber);
    final nominee2Phone = _normalizePhone(input.nominee2MobileNumber);
    final farmerAadhaarNumber = farmer == null
        ? _aadhaarNumber(input.farmerAadhaarNumber)
        : _farmerAadhaarNumber(farmer, input);
    final farmerAadhaarLast4 = farmer == null
        ? _aadhaarLast4(input.farmerAadhaarLast4)
        : _farmerAadhaarLast4(farmer, input);
    final farmerAgriRecordId = input.farmerAgriRecordId.trim().isNotEmpty
        ? input.farmerAgriRecordId.trim()
        : farmer?.agriRecordId.trim() ?? '';
    final pincode = input.farmerPincode.replaceAll(RegExp(r'\D'), '');
    final totalLandAcres = double.tryParse(input.farmerTotalLandAcres.trim());
    if (input.farmerFullName.trim().length < 2 ||
        input.farmerFatherName.trim().length < 2 ||
        !RegExp(r'^[6-9][0-9]{9}$').hasMatch(farmerPhone) ||
        (farmerAadhaarNumber.length != 12 && farmerAadhaarLast4.length != 4) ||
        farmerAgriRecordId.isEmpty ||
        input.farmerAddress.trim().length < 5 ||
        input.farmerVillage.trim().length < 2 ||
        input.farmerTaluka.trim().length < 2 ||
        input.farmerDistrict.trim().length < 2 ||
        !RegExp(r'^[1-9][0-9]{5}$').hasMatch(pincode) ||
        totalLandAcres == null ||
        totalLandAcres <= 0 ||
        input.nomineeName.trim().length < 2 ||
        input.nomineeAddress.trim().length < 5 ||
        !RegExp(r'^[6-9][0-9]{9}$').hasMatch(nomineePhone) ||
        !_isUploadedDocumentPath(input.nomineeSignature, 'nominee_signature') ||
        (nomineeCount == 2 &&
            (input.nominee2Name.trim().length < 2 ||
                input.nominee2Address.trim().length < 5 ||
                !RegExp(r'^[6-9][0-9]{9}$').hasMatch(nominee2Phone) ||
                !_isUploadedDocumentPath(
                  input.nominee2Signature,
                  'nominee2_signature',
                )))) {
      throw const StakeholderServiceException(
        'Complete farmer and nominee details before selecting the amount.',
      );
    }

    if (!input.contractReadAccepted ||
        !_isUploadedDocumentPath(input.farmerSignature, 'farmer_signature')) {
      throw const StakeholderServiceException(
        'Read the contract and draw farmer signature before submitting interest.',
      );
    }

    final panManualValid = RegExp(
      r'^[A-Z]{5}[0-9]{4}[A-Z]$',
    ).hasMatch(_normalizePan(input.panNumber));
    final hasPanDocument = input.panDocumentPath.trim().isNotEmpty;
    if (!panManualValid && !hasPanDocument) {
      throw const StakeholderServiceException(
        'Enter a valid PAN number or upload a clear PAN document.',
      );
    }

    final hasLandRecordManual = StakeholderLandRecordDetails.isCompleteSummary(
      input.landRecordDetails,
    );
    final hasLandRecordDocument = input.landRecordDocumentPath
        .trim()
        .isNotEmpty;
    if (!hasLandRecordManual && !hasLandRecordDocument) {
      throw const StakeholderServiceException(
        'Enter 7/12 land details or upload the 7/12 land record image.',
      );
    }

    final bankManualValid =
        input.bankName.trim().length >= 2 &&
        input.accountHolderName.trim().length >= 2 &&
        RegExp(
          r'^[0-9]{6,20}$',
        ).hasMatch(input.bankAccountNumber.replaceAll(RegExp(r'\s'), '')) &&
        RegExp(
          r'^[A-Z]{4}0[A-Z0-9]{6}$',
        ).hasMatch(input.ifscCode.trim().toUpperCase());
    final hasPassbook = input.passbookDocumentPath.trim().isNotEmpty;
    if (!bankManualValid && !hasPassbook) {
      throw const StakeholderServiceException(
        'Enter bank details or upload passbook/cancelled cheque image.',
      );
    }
  }

  Future<StakeholderPlanBundle> _loadDirectOrFallback() async {
    try {
      return await _loadDirect();
    } catch (_) {
      return StakeholderPlanBundle.fallback();
    }
  }

  Future<StakeholderPlanBundle> _loadDirect() async {
    final plan = await _loadActivePlanDirect();
    if (plan == null) return StakeholderPlanBundle.fallback();
    final application = await _loadApplicationDirect(plan.id);
    final events = application == null
        ? const <StakeholderApplicationEvent>[]
        : await _loadEventsDirect(application.id);
    return StakeholderPlanBundle(
      plan: plan,
      application: application,
      events: events,
    );
  }

  Future<StakeholderPlanBundle> _submitInterestDirect({
    required VerifiedFarmerRecord farmer,
    required StakeholderPlan plan,
    required StakeholderBuyApplicationInput input,
  }) async {
    try {
      final activePlan = await _loadActivePlanDirect(
        planId: plan.id,
        planCode: plan.planCode,
      );
      if (activePlan == null || activePlan.id.isEmpty) {
        throw const StakeholderServiceException(
          'Stakeholder plan setup is not available yet. Try again later.',
        );
      }

      final existing = await _loadApplicationDirect(activePlan.id);
      final existingStatus = existing?.status.trim() ?? '';
      if (existingStatus.isNotEmpty) {
        final events = await _loadEventsDirect(existing!.id);
        return StakeholderPlanBundle(
          plan: activePlan,
          application: existing,
          events: events,
        );
      }

      final userId = _client.auth.currentUser?.id.trim();
      if (userId == null || userId.isEmpty) {
        throw const StakeholderServiceException(
          'Login as a farmer stakeholder first.',
        );
      }

      final nomineeCount = input.nomineeCount >= 2 ? 2 : 1;
      final farmerAadhaarNumber = _farmerAadhaarNumber(farmer, input);
      final farmerAadhaarLast4 = _farmerAadhaarLast4(farmer, input);
      final farmerAgriRecordId = input.farmerAgriRecordId.trim().isNotEmpty
          ? input.farmerAgriRecordId.trim()
          : farmer.agriRecordId;
      final row = <String, Object?>{
        'plan_id': activePlan.id,
        'user_id': userId,
        'farmer_phone': _normalizePhone(farmer.phone),
        'farmer_id': farmer.farmerId,
        'farmer_name': farmer.farmerName,
        'agri_record_id': farmerAgriRecordId,
        'aadhaar_number': farmerAadhaarNumber,
        'aadhaar_last4': farmerAadhaarLast4,
        'selected_amount': input.selectedAmount,
        'estimated_shares': activePlan.estimateShares(input.selectedAmount),
        'farmer_full_name': input.farmerFullName.trim(),
        'farmer_father_name': input.farmerFatherName.trim(),
        'farmer_mobile_number': _normalizePhone(input.farmerMobileNumber),
        'farmer_aadhaar_number': farmerAadhaarNumber,
        'farmer_aadhaar_last4': farmerAadhaarLast4,
        'farmer_address': input.farmerAddress.trim(),
        'farmer_village': input.farmerVillage.trim(),
        'farmer_taluka': input.farmerTaluka.trim(),
        'farmer_district': input.farmerDistrict.trim(),
        'farmer_pincode': input.farmerPincode.replaceAll(RegExp(r'\D'), ''),
        'farmer_total_land_acres': input.farmerTotalLandAcres.trim(),
        'farmer_photo_path': '',
        'nominee_name': input.nomineeName.trim(),
        'nominee_address': input.nomineeAddress.trim(),
        'nominee_mobile_number': _normalizePhone(input.nomineeMobileNumber),
        'nominee_signature': input.nomineeSignature.trim(),
        'nominee_count': nomineeCount,
        'nominee2_name': nomineeCount == 2 ? input.nominee2Name.trim() : '',
        'nominee2_address': nomineeCount == 2
            ? input.nominee2Address.trim()
            : '',
        'nominee2_mobile_number': nomineeCount == 2
            ? _normalizePhone(input.nominee2MobileNumber)
            : '',
        'nominee2_signature': nomineeCount == 2
            ? input.nominee2Signature.trim()
            : '',
        'farmer_signature': input.farmerSignature.trim(),
        'contract_read_accepted': input.contractReadAccepted,
        'status': StakeholderApplicationStatus.submitted,
        'consent_interest_only': true,
        'consent_no_guaranteed_return': true,
        'consent_data_use': true,
        'farmer_note': input.farmerNote.trim(),
        'pan_number': _normalizePan(input.panNumber),
        'pan_holder_name': input.panHolderName.trim(),
        'pan_document_path': input.panDocumentPath.trim(),
        'land_record_details': input.landRecordDetails.trim(),
        'land_record_document_path': input.landRecordDocumentPath.trim(),
        'account_holder_name': input.accountHolderName.trim(),
        'bank_name': input.bankName.trim(),
        'bank_account_number': input.bankAccountNumber.replaceAll(
          RegExp(r'\s'),
          '',
        ),
        'ifsc_code': input.ifscCode.trim().toUpperCase(),
        'upi_id': input.upiId.trim(),
        'passbook_document_path': input.passbookDocumentPath.trim(),
        'payment_method': StakeholderPaymentMethod.none,
        'payment_status': StakeholderPaymentStatus.pending,
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
      };
      final saved = await _upsertStakeholderApplication(row);
      if (saved == null) {
        throw const StakeholderServiceException(
          'Stakeholder interest submission failed.',
        );
      }
      return StakeholderPlanBundle(
        plan: activePlan,
        application: StakeholderApplication.fromJson(saved),
        events: const [],
      );
    } on StakeholderServiceException {
      rethrow;
    } catch (_) {
      throw const StakeholderServiceException(
        'Stakeholder interest submission failed. Try again later.',
      );
    }
  }

  Future<StakeholderPlan?> _loadActivePlanDirect({
    String planId = '',
    String planCode = '',
  }) async {
    dynamic query = _client
        .from('stakeholder_plans')
        .select()
        .eq('status', 'active');
    if (planId.trim().isNotEmpty) {
      query = query.eq('id', planId.trim());
    } else if (planCode.trim().isNotEmpty) {
      query = query.eq('plan_code', planCode.trim());
    }
    final rows = await query.order('created_at', ascending: false).limit(1);
    if (rows.isEmpty) return null;
    return StakeholderPlan.fromJson(Map<String, dynamic>.from(rows.first));
  }

  Future<StakeholderApplication?> _loadApplicationDirect(String planId) async {
    final userId = _client.auth.currentUser?.id.trim();
    if (userId == null || userId.isEmpty || planId.trim().isEmpty) return null;
    final rows = await _client
        .from('stakeholder_applications')
        .select()
        .eq('user_id', userId)
        .eq('plan_id', planId)
        .order('updated_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return StakeholderApplication.fromJson(
      Map<String, dynamic>.from(rows.first),
    );
  }

  Future<List<StakeholderApplicationEvent>> _loadEventsDirect(
    String applicationId,
  ) async {
    if (applicationId.trim().isEmpty) return const [];
    final rows = await _client
        .from('stakeholder_application_events')
        .select()
        .eq('application_id', applicationId)
        .order('created_at', ascending: true);
    return rows
        .map(
          (event) => StakeholderApplicationEvent.fromJson(
            Map<String, dynamic>.from(event),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> _upsertStakeholderApplication(
    Map<String, Object?> row,
  ) async {
    try {
      return await _client
          .from('stakeholder_applications')
          .upsert(row, onConflict: 'user_id,plan_id')
          .select()
          .maybeSingle();
    } catch (error) {
      if (!_isMissingFullAadhaarColumn(error)) rethrow;
      final legacyRow = Map<String, Object?>.from(row)
        ..remove('aadhaar_number')
        ..remove('farmer_aadhaar_number');
      return await _client
          .from('stakeholder_applications')
          .upsert(legacyRow, onConflict: 'user_id,plan_id')
          .select()
          .maybeSingle();
    }
  }

  Map<String, dynamic> _farmerPayload(VerifiedFarmerRecord farmer) {
    return {
      'phone': _normalizePhone(farmer.phone),
      'farmerId': farmer.farmerId,
      'farmerName': farmer.farmerName,
      'agriRecordId': farmer.agriRecordId,
      'aadhaarNumber': farmer.aadhaarNumber,
      'aadhaarLast4': farmer.aadhaarLast4,
    };
  }

  Map<String, String> _functionAuthHeaders() {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const StakeholderServiceException(
        'Login as a farmer stakeholder first.',
      );
    }
    return {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _responseMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const <String, dynamic>{};
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }

  bool _isMissingFullAadhaarColumn(Object error) {
    final text = error.toString().toLowerCase();
    return (text.contains('aadhaar_number') ||
            text.contains('farmer_aadhaar_number')) &&
        (text.contains('42703') ||
            text.contains('schema cache') ||
            text.contains('column') ||
            text.contains('does not exist'));
  }

  bool _isOptionalDocumentUploadRecordError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('stakeholder_document_uploads') ||
        text.contains('42p01') ||
        text.contains('pgrst204') ||
        text.contains('schema cache') ||
        text.contains('does not exist');
  }

  String _aadhaarLast4(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return digits;
    return digits.length == 12 ? digits.substring(digits.length - 4) : '';
  }

  String _aadhaarNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length == 12 ? digits : '';
  }

  String _farmerAadhaarNumber(
    VerifiedFarmerRecord farmer,
    StakeholderBuyApplicationInput input,
  ) {
    final inputNumber = _aadhaarNumber(input.farmerAadhaarNumber);
    if (inputNumber.isNotEmpty) return inputNumber;
    final legacyInputNumber = _aadhaarNumber(input.farmerAadhaarLast4);
    if (legacyInputNumber.isNotEmpty) return legacyInputNumber;
    final savedNumber = _aadhaarNumber(farmer.aadhaarNumber);
    if (savedNumber.isNotEmpty) return savedNumber;
    return '';
  }

  String _farmerAadhaarLast4(
    VerifiedFarmerRecord farmer,
    StakeholderBuyApplicationInput input,
  ) {
    final fullNumber = _farmerAadhaarNumber(farmer, input);
    if (fullNumber.isNotEmpty) return _aadhaarLast4(fullNumber);
    final inputLast4 = _aadhaarLast4(input.farmerAadhaarLast4);
    if (inputLast4.isNotEmpty) return inputLast4;
    final savedLast4 = _aadhaarLast4(farmer.aadhaarLast4);
    if (savedLast4.isNotEmpty) return savedLast4;
    return '';
  }

  bool _isUploadedDocumentPath(String value, String documentKind) {
    final path = value.trim();
    return path.contains('/$documentKind/') && path.split('/').length >= 3;
  }

  String _contentTypeFor(String fileName, Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    throw const StakeholderServiceException(
      'Upload a JPG, PNG or WebP document image.',
    );
  }

  Future<StakeholderDocumentUpload> _uploadDocumentDirect({
    required VerifiedFarmerRecord farmer,
    required Uint8List bytes,
    required String fileName,
    required String documentKind,
    required String contentType,
  }) async {
    final token = _client.auth.currentSession?.accessToken;
    final userId = _client.auth.currentUser?.id.trim();
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      throw const StakeholderServiceException(
        'Login as a farmer stakeholder first.',
      );
    }
    final path =
        '$userId/$documentKind/${DateTime.now().millisecondsSinceEpoch}-${_safeFileName(fileName, documentKind, contentType)}';
    final response = await http
        .post(
          Uri.parse(
            '${SupabaseConfig.url}/storage/v1/object/stakeholder-documents/$path',
          ),
          headers: {
            'apikey': SupabaseConfig.anonKey,
            'Authorization': 'Bearer $token',
            'Content-Type': contentType,
            'x-upsert': 'false',
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StakeholderServiceException(
        _uploadErrorMessage(response.statusCode, response.body),
      );
    }
    await _recordDocumentUploadDirect(
      userId: userId,
      farmerPhone: _normalizePhone(farmer.phone),
      documentKind: documentKind,
      documentPath: path,
      contentType: contentType,
    );
    return StakeholderDocumentUpload(path: path, kind: documentKind);
  }

  Future<void> _recordDocumentUploadDirect({
    required String userId,
    required String farmerPhone,
    required String documentKind,
    required String documentPath,
    required String contentType,
  }) async {
    try {
      await _client.from('stakeholder_document_uploads').insert({
        'user_id': userId,
        'farmer_phone': farmerPhone,
        'document_kind': documentKind,
        'document_path': documentPath,
        'content_type': contentType,
      });
    } catch (error) {
      if (!_isOptionalDocumentUploadRecordError(error)) rethrow;
    }
  }

  String _safeFileName(
    String fileName,
    String documentKind,
    String contentType,
  ) {
    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final raw = fileName.split(RegExp(r'[\\/]')).last;
    final withoutExt = raw.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final safe = withoutExt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final stem = safe.isEmpty ? documentKind : safe;
    return '$stem.$extension';
  }

  String _uploadErrorMessage(int statusCode, String body) {
    final detail = _extractRemoteError(body);
    switch (statusCode) {
      case 401:
        return 'Session expired. Login again.';
      case 403:
        return 'Document upload was blocked. Login again and retry.';
      case 404:
        return 'Stakeholder document storage is not configured.';
      case 409:
        return 'This document file already exists. Please retry.';
      default:
        return detail.isEmpty ? 'Document upload failed.' : detail;
    }
  }

  String _extractRemoteError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        for (final key in const ['message', 'error', 'error_description']) {
          final value = '${decoded[key] ?? ''}'.trim();
          if (value.isNotEmpty) return value;
        }
      }
    } catch (_) {
      // Use the raw body below when it is plain text.
    }
    return body.trim();
  }

  String _cleanRemoteError(Object error, String fallback) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) return fallback;
    if (_isFunctionNotFound(error)) {
      return 'Stakeholder plan sync is not available yet. Try again later.';
    }
    return text;
  }

  bool _isFunctionNotFound(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('statuscode: 404') ||
        text.contains('status code: 404') ||
        text.contains('status: 404') ||
        text.contains('http 404') ||
        text.contains('function not found') ||
        text.contains('stakeholder_plan_not_found');
  }

  bool _isFunctionNotFoundData(Map<String, dynamic> data) {
    final code = '${data['code'] ?? ''}'.toLowerCase();
    final error = '${data['error'] ?? data['message'] ?? ''}'.toLowerCase();
    return code == 'stakeholder_plan_not_found' ||
        code == 'not_found' ||
        code == 'function_not_found' ||
        error.contains('function not found') ||
        error.contains('edge function not found') ||
        error.contains('stakeholder plan is not available');
  }

  bool _isApplicationAlreadySubmittedData(Map<String, dynamic> data) {
    final code = '${data['code'] ?? ''}'.toLowerCase();
    final error = '${data['error'] ?? data['message'] ?? ''}'.toLowerCase();
    return code == 'stakeholder_application_locked' ||
        error.contains('already under review') ||
        error.contains('application is already');
  }

  bool _isApplicationAlreadySubmittedError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('stakeholder_application_locked') ||
        text.contains('already under review') ||
        text.contains('application is already');
  }
}
