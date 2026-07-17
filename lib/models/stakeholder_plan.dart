class StakeholderApplicationStatus {
  static const submitted = 'submitted';
  static const underReview = 'under_review';
  static const approved = 'approved';
  static const rejected = 'rejected';

  static const values = [submitted, underReview, approved, rejected];

  static String normalize(String value) {
    final normalized = value.trim().toLowerCase();
    return values.contains(normalized) ? normalized : submitted;
  }
}

class StakeholderPaymentMethod {
  static const none = 'none';
  static const razorpay = 'razorpay';
  static const bankTransfer = 'bank_transfer';
}

class StakeholderPaymentStatus {
  static const pending = 'pending';
  static const gatewayOrderCreated = 'gateway_order_created';
  static const gatewayVerified = 'gateway_verified';
  static const bankTransferSubmitted = 'bank_transfer_submitted';
  static const failed = 'failed';
}

class StakeholderPlan {
  static const double amountStep = 100;

  final String id;
  final String planCode;
  final String title;
  final String summary;
  final String currency;
  final double shareUnitValue;
  final double minAmount;
  final double maxAmount;
  final String status;
  final List<String> purpose;
  final List<String> useOfFunds;
  final List<String> stages;
  final List<String> riskNotes;
  final List<String> terms;
  final DateTime? openedAt;
  final DateTime? closesAt;

  const StakeholderPlan({
    required this.id,
    required this.planCode,
    required this.title,
    required this.summary,
    required this.currency,
    required this.shareUnitValue,
    required this.minAmount,
    required this.maxAmount,
    required this.status,
    required this.purpose,
    required this.useOfFunds,
    required this.stages,
    required this.riskNotes,
    required this.terms,
    this.openedAt,
    this.closesAt,
  });

  factory StakeholderPlan.fromJson(Map<String, dynamic> json) {
    return StakeholderPlan(
      id: _text(json['id']),
      planCode: _text(json['plan_code'] ?? json['planCode']),
      title: _text(json['title'], 'Kalsubai Farms Stakeholder Plan'),
      summary: _text(json['summary']),
      currency: _text(json['currency'], 'INR'),
      shareUnitValue:
          _double(json['share_unit_value'] ?? json['shareUnitValue']) ?? 100,
      minAmount: _double(json['min_amount'] ?? json['minAmount']) ?? 100,
      maxAmount: _double(json['max_amount'] ?? json['maxAmount']) ?? 25000,
      status: _text(json['status'], 'active'),
      purpose: _stringList(json['purpose']),
      useOfFunds: _stringList(json['use_of_funds'] ?? json['useOfFunds']),
      stages: _stringList(json['stages']),
      riskNotes: _stringList(json['risk_notes'] ?? json['riskNotes']),
      terms: _stringList(json['terms']),
      openedAt: _date(json['opened_at'] ?? json['openedAt']),
      closesAt: _date(json['closes_at'] ?? json['closesAt']),
    );
  }

  factory StakeholderPlan.fallback() {
    return const StakeholderPlan(
      id: '',
      planCode: 'kalsubai-farmer-stakeholder-v1',
      title: 'Kalsubai Farms Farmer Stakeholder Plan',
      summary:
          'Apply to buy farmer stakeholder shares. Final allocation is confirmed only after Kalsubai Farms review.',
      currency: 'INR',
      shareUnitValue: 100,
      minAmount: 100,
      maxAmount: 25000,
      status: 'active',
      purpose: [
        'Let registered farmers apply to buy Kalsubai Farms stakeholder shares.',
        'Keep farmer identity, PAN, 7/12 land record, bank, selected amount and payment details in one review-ready record.',
        'Prepare an auditable application before final approval and allocation.',
      ],
      useOfFunds: [
        'Farm aggregation and procurement readiness',
        'Millet quality, grading, and packaging operations',
        'Traceability, farmer services, and working capital planning',
      ],
      stages: [
        'Submit farmer account, KYC, 7/12 land record, bank and payment details',
        'Kalsubai Farms reviews farmer record, payment and plan capacity',
        'Approved allocation and documents are updated after admin review',
      ],
      riskNotes: [
        'Payment confirmation is not a confirmed share issue.',
        'Returns are not guaranteed and depend on final approval and business performance.',
        'Final terms must be reviewed before any allocation.',
      ],
      terms: [
        'The selected amount starts an application for review.',
        'Estimated shares are calculated from the current plan share value.',
        'Kalsubai Farms may approve, revise, or reject the application after review.',
      ],
    );
  }

  int estimateShares(double amount) {
    if (shareUnitValue <= 0 || amount <= 0) return 0;
    return amount ~/ shareUnitValue;
  }

  bool isValidAmount(double amount) {
    return amount >= minAmount &&
        amount <= maxAmount &&
        _isAmountStep(amount) &&
        estimateShares(amount) > 0;
  }

  double snapAmount(double amount) {
    final clamped = amount.clamp(minAmount, maxAmount) as num;
    final snapped = (clamped / amountStep).round() * amountStep;
    return (snapped.clamp(minAmount, maxAmount) as num).toDouble();
  }

  bool _isAmountStep(double amount) {
    final remainder = amount % amountStep;
    return remainder.abs() < 0.001 || (amountStep - remainder).abs() < 0.001;
  }
}

class StakeholderApplication {
  final String id;
  final String planId;
  final String userId;
  final String farmerPhone;
  final String farmerId;
  final String farmerName;
  final String agriRecordId;
  final String aadhaarNumber;
  final String aadhaarLast4;
  final String farmerFullName;
  final String farmerFatherName;
  final String farmerMobileNumber;
  final String farmerAadhaarNumber;
  final String farmerAadhaarLast4;
  final String farmerAddress;
  final String farmerVillage;
  final String farmerTaluka;
  final String farmerDistrict;
  final String farmerPincode;
  final String farmerTotalLandAcres;
  final String farmerPhotoPath;
  final String nomineeName;
  final String nomineeAddress;
  final String nomineeMobileNumber;
  final String nomineeSignature;
  final int nomineeCount;
  final String nominee2Name;
  final String nominee2Address;
  final String nominee2MobileNumber;
  final String nominee2Signature;
  final String farmerSignature;
  final bool contractReadAccepted;
  final double selectedAmount;
  final int estimatedShares;
  final String status;
  final bool consentInterestOnly;
  final bool consentNoGuaranteedReturn;
  final bool consentDataUse;
  final String farmerNote;
  final String adminNote;
  final String panNumber;
  final String panHolderName;
  final String panDocumentPath;
  final String landRecordDetails;
  final String landRecordDocumentPath;
  final String accountHolderName;
  final String bankName;
  final String bankAccountNumber;
  final String ifscCode;
  final String upiId;
  final String passbookDocumentPath;
  final String paymentMethod;
  final String paymentStatus;
  final String razorpayOrderId;
  final String razorpayPaymentId;
  final String razorpaySignature;
  final String bankTransferReference;
  final String bankTransferProofPath;
  final DateTime? submittedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? paymentReviewedAt;
  final DateTime? kycReviewedAt;

  const StakeholderApplication({
    required this.id,
    required this.planId,
    required this.userId,
    required this.farmerPhone,
    required this.farmerId,
    required this.farmerName,
    required this.agriRecordId,
    required this.aadhaarNumber,
    required this.aadhaarLast4,
    required this.farmerFullName,
    required this.farmerFatherName,
    required this.farmerMobileNumber,
    required this.farmerAadhaarNumber,
    required this.farmerAadhaarLast4,
    required this.farmerAddress,
    required this.farmerVillage,
    required this.farmerTaluka,
    required this.farmerDistrict,
    required this.farmerPincode,
    required this.farmerTotalLandAcres,
    required this.farmerPhotoPath,
    required this.nomineeName,
    required this.nomineeAddress,
    required this.nomineeMobileNumber,
    required this.nomineeSignature,
    required this.nomineeCount,
    required this.nominee2Name,
    required this.nominee2Address,
    required this.nominee2MobileNumber,
    required this.nominee2Signature,
    required this.farmerSignature,
    required this.contractReadAccepted,
    required this.selectedAmount,
    required this.estimatedShares,
    required this.status,
    required this.consentInterestOnly,
    required this.consentNoGuaranteedReturn,
    required this.consentDataUse,
    required this.farmerNote,
    required this.adminNote,
    required this.panNumber,
    required this.panHolderName,
    required this.panDocumentPath,
    required this.landRecordDetails,
    required this.landRecordDocumentPath,
    required this.accountHolderName,
    required this.bankName,
    required this.bankAccountNumber,
    required this.ifscCode,
    required this.upiId,
    required this.passbookDocumentPath,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.razorpayOrderId,
    required this.razorpayPaymentId,
    required this.razorpaySignature,
    required this.bankTransferReference,
    required this.bankTransferProofPath,
    this.submittedAt,
    this.createdAt,
    this.updatedAt,
    this.paymentReviewedAt,
    this.kycReviewedAt,
  });

  factory StakeholderApplication.fromJson(Map<String, dynamic> json) {
    return StakeholderApplication(
      id: _text(json['id']),
      planId: _text(json['plan_id'] ?? json['planId']),
      userId: _text(json['user_id'] ?? json['userId']),
      farmerPhone: _normalizePhone(
        _text(json['farmer_phone'] ?? json['farmerPhone']),
      ),
      farmerId: _text(json['farmer_id'] ?? json['farmerId']),
      farmerName: _text(json['farmer_name'] ?? json['farmerName']),
      agriRecordId: _text(json['agri_record_id'] ?? json['agriRecordId']),
      aadhaarNumber: _text(json['aadhaar_number'] ?? json['aadhaarNumber']),
      aadhaarLast4: _text(json['aadhaar_last4'] ?? json['aadhaarLast4']),
      farmerFullName: _text(
        json['farmer_full_name'] ??
            json['farmerFullName'] ??
            json['farmer_name'] ??
            json['farmerName'],
      ),
      farmerFatherName: _text(
        json['farmer_father_name'] ?? json['farmerFatherName'],
      ),
      farmerMobileNumber: _normalizePhone(
        _text(
          json['farmer_mobile_number'] ??
              json['farmerMobileNumber'] ??
              json['farmer_phone'] ??
              json['farmerPhone'],
        ),
      ),
      farmerAadhaarNumber: _text(
        json['farmer_aadhaar_number'] ??
            json['farmerAadhaarNumber'] ??
            json['aadhaar_number'] ??
            json['aadhaarNumber'],
      ),
      farmerAadhaarLast4: _text(
        json['farmer_aadhaar_last4'] ??
            json['farmerAadhaarLast4'] ??
            json['aadhaar_last4'] ??
            json['aadhaarLast4'],
      ),
      farmerAddress: _text(json['farmer_address'] ?? json['farmerAddress']),
      farmerVillage: _text(json['farmer_village'] ?? json['farmerVillage']),
      farmerTaluka: _text(json['farmer_taluka'] ?? json['farmerTaluka']),
      farmerDistrict: _text(json['farmer_district'] ?? json['farmerDistrict']),
      farmerPincode: _text(json['farmer_pincode'] ?? json['farmerPincode']),
      farmerTotalLandAcres: _text(
        json['farmer_total_land_acres'] ?? json['farmerTotalLandAcres'],
      ),
      farmerPhotoPath: _text(
        json['farmer_photo_path'] ?? json['farmerPhotoPath'],
      ),
      nomineeName: _text(json['nominee_name'] ?? json['nomineeName']),
      nomineeAddress: _text(json['nominee_address'] ?? json['nomineeAddress']),
      nomineeMobileNumber: _normalizePhone(
        _text(json['nominee_mobile_number'] ?? json['nomineeMobileNumber']),
      ),
      nomineeSignature: _text(
        json['nominee_signature'] ?? json['nomineeSignature'],
      ),
      nomineeCount: ((_int(json['nominee_count'] ?? json['nomineeCount']) ?? 1)
          .clamp(1, 2)
          .toInt()),
      nominee2Name: _text(json['nominee2_name'] ?? json['nominee2Name']),
      nominee2Address: _text(
        json['nominee2_address'] ?? json['nominee2Address'],
      ),
      nominee2MobileNumber: _normalizePhone(
        _text(json['nominee2_mobile_number'] ?? json['nominee2MobileNumber']),
      ),
      nominee2Signature: _text(
        json['nominee2_signature'] ?? json['nominee2Signature'],
      ),
      farmerSignature: _text(
        json['farmer_signature'] ?? json['farmerSignature'],
      ),
      contractReadAccepted: _bool(
        json['contract_read_accepted'] ?? json['contractReadAccepted'],
      ),
      selectedAmount:
          _double(json['selected_amount'] ?? json['selectedAmount']) ?? 0,
      estimatedShares:
          _int(json['estimated_shares'] ?? json['estimatedShares']) ?? 0,
      status: StakeholderApplicationStatus.normalize(_text(json['status'])),
      consentInterestOnly: _bool(
        json['consent_interest_only'] ?? json['consentInterestOnly'],
      ),
      consentNoGuaranteedReturn: _bool(
        json['consent_no_guaranteed_return'] ??
            json['consentNoGuaranteedReturn'],
      ),
      consentDataUse: _bool(json['consent_data_use'] ?? json['consentDataUse']),
      farmerNote: _text(json['farmer_note'] ?? json['farmerNote']),
      adminNote: _text(json['admin_note'] ?? json['adminNote']),
      panNumber: _text(json['pan_number'] ?? json['panNumber']).toUpperCase(),
      panHolderName: _text(json['pan_holder_name'] ?? json['panHolderName']),
      panDocumentPath: _text(
        json['pan_document_path'] ?? json['panDocumentPath'],
      ),
      landRecordDetails: _text(
        json['land_record_details'] ?? json['landRecordDetails'],
      ),
      landRecordDocumentPath: _text(
        json['land_record_document_path'] ?? json['landRecordDocumentPath'],
      ),
      accountHolderName: _text(
        json['account_holder_name'] ?? json['accountHolderName'],
      ),
      bankName: _text(json['bank_name'] ?? json['bankName']),
      bankAccountNumber: _text(
        json['bank_account_number'] ?? json['bankAccountNumber'],
      ),
      ifscCode: _text(json['ifsc_code'] ?? json['ifscCode']).toUpperCase(),
      upiId: _text(json['upi_id'] ?? json['upiId']),
      passbookDocumentPath: _text(
        json['passbook_document_path'] ?? json['passbookDocumentPath'],
      ),
      paymentMethod: _text(
        json['payment_method'] ?? json['paymentMethod'],
        StakeholderPaymentMethod.none,
      ),
      paymentStatus: _text(
        json['payment_status'] ?? json['paymentStatus'],
        StakeholderPaymentStatus.pending,
      ),
      razorpayOrderId: _text(
        json['razorpay_order_id'] ?? json['razorpayOrderId'],
      ),
      razorpayPaymentId: _text(
        json['razorpay_payment_id'] ?? json['razorpayPaymentId'],
      ),
      razorpaySignature: _text(
        json['razorpay_signature'] ?? json['razorpaySignature'],
      ),
      bankTransferReference: _text(
        json['bank_transfer_reference'] ?? json['bankTransferReference'],
      ),
      bankTransferProofPath: _text(
        json['bank_transfer_proof_path'] ?? json['bankTransferProofPath'],
      ),
      submittedAt: _date(json['submitted_at'] ?? json['submittedAt']),
      createdAt: _date(json['created_at'] ?? json['createdAt']),
      updatedAt: _date(json['updated_at'] ?? json['updatedAt']),
      paymentReviewedAt: _date(
        json['payment_reviewed_at'] ?? json['paymentReviewedAt'],
      ),
      kycReviewedAt: _date(json['kyc_reviewed_at'] ?? json['kycReviewedAt']),
    );
  }
}

class StakeholderRazorpayOrder {
  final String keyId;
  final String orderId;
  final int amountSubunits;
  final String currency;
  final String receipt;

  const StakeholderRazorpayOrder({
    required this.keyId,
    required this.orderId,
    required this.amountSubunits,
    required this.currency,
    required this.receipt,
  });

  factory StakeholderRazorpayOrder.fromJson(Map<String, dynamic> json) {
    return StakeholderRazorpayOrder(
      keyId: _text(json['keyId'] ?? json['key_id']),
      orderId: _text(json['orderId'] ?? json['order_id']),
      amountSubunits:
          _int(json['amountSubunits'] ?? json['amount_subunits']) ?? 0,
      currency: _text(json['currency'], 'INR'),
      receipt: _text(json['receipt']),
    );
  }
}

class StakeholderDocumentUpload {
  final String path;
  final String kind;

  const StakeholderDocumentUpload({required this.path, required this.kind});

  factory StakeholderDocumentUpload.fromJson(Map<String, dynamic> json) {
    return StakeholderDocumentUpload(
      path: _text(json['documentPath'] ?? json['document_path']),
      kind: _text(json['documentKind'] ?? json['document_kind']),
    );
  }
}

class StakeholderBuyApplicationInput {
  final double selectedAmount;
  final String farmerFullName;
  final String farmerFatherName;
  final String farmerMobileNumber;
  final String farmerAadhaarNumber;
  final String farmerAadhaarLast4;
  final String farmerAddress;
  final String farmerVillage;
  final String farmerTaluka;
  final String farmerDistrict;
  final String farmerPincode;
  final String farmerTotalLandAcres;
  final String farmerAgriRecordId;
  final String nomineeName;
  final String nomineeAddress;
  final String nomineeMobileNumber;
  final String nomineeSignature;
  final int nomineeCount;
  final String nominee2Name;
  final String nominee2Address;
  final String nominee2MobileNumber;
  final String nominee2Signature;
  final String farmerSignature;
  final bool contractReadAccepted;
  final String farmerNote;
  final String panNumber;
  final String panHolderName;
  final String panDocumentPath;
  final String landRecordDetails;
  final String landRecordDocumentPath;
  final String accountHolderName;
  final String bankName;
  final String bankAccountNumber;
  final String ifscCode;
  final String upiId;
  final String passbookDocumentPath;

  const StakeholderBuyApplicationInput({
    required this.selectedAmount,
    required this.farmerFullName,
    required this.farmerFatherName,
    required this.farmerMobileNumber,
    required this.farmerAadhaarNumber,
    required this.farmerAadhaarLast4,
    required this.farmerAddress,
    required this.farmerVillage,
    required this.farmerTaluka,
    required this.farmerDistrict,
    required this.farmerPincode,
    required this.farmerTotalLandAcres,
    required this.farmerAgriRecordId,
    required this.nomineeName,
    required this.nomineeAddress,
    required this.nomineeMobileNumber,
    required this.nomineeSignature,
    required this.nomineeCount,
    required this.nominee2Name,
    required this.nominee2Address,
    required this.nominee2MobileNumber,
    required this.nominee2Signature,
    required this.farmerSignature,
    required this.contractReadAccepted,
    required this.farmerNote,
    required this.panNumber,
    required this.panHolderName,
    required this.panDocumentPath,
    required this.landRecordDetails,
    required this.landRecordDocumentPath,
    required this.accountHolderName,
    required this.bankName,
    required this.bankAccountNumber,
    required this.ifscCode,
    required this.upiId,
    required this.passbookDocumentPath,
  });
}

class StakeholderApplicationEvent {
  final String id;
  final String status;
  final String title;
  final String note;
  final DateTime? createdAt;

  const StakeholderApplicationEvent({
    required this.id,
    required this.status,
    required this.title,
    required this.note,
    this.createdAt,
  });

  factory StakeholderApplicationEvent.fromJson(Map<String, dynamic> json) {
    return StakeholderApplicationEvent(
      id: _text(json['id']),
      status: StakeholderApplicationStatus.normalize(_text(json['status'])),
      title: _text(json['title']),
      note: _text(json['note']),
      createdAt: _date(json['created_at'] ?? json['createdAt']),
    );
  }
}

class StakeholderPlanBundle {
  final StakeholderPlan plan;
  final StakeholderApplication? application;
  final List<StakeholderApplicationEvent> events;

  const StakeholderPlanBundle({
    required this.plan,
    required this.application,
    required this.events,
  });

  factory StakeholderPlanBundle.fromJson(Map<String, dynamic> json) {
    final rawPlan = json['plan'];
    final rawApplication = json['application'];
    final rawEvents = json['events'];
    return StakeholderPlanBundle(
      plan: rawPlan is Map
          ? StakeholderPlan.fromJson(Map<String, dynamic>.from(rawPlan))
          : StakeholderPlan.fallback(),
      application: rawApplication is Map
          ? StakeholderApplication.fromJson(
              Map<String, dynamic>.from(rawApplication),
            )
          : null,
      events: rawEvents is List
          ? rawEvents
                .whereType<Map>()
                .map(
                  (event) => StakeholderApplicationEvent.fromJson(
                    Map<String, dynamic>.from(event),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }

  factory StakeholderPlanBundle.fallback() {
    return StakeholderPlanBundle(
      plan: StakeholderPlan.fallback(),
      application: null,
      events: const [],
    );
  }
}

String _text(Object? raw, [String fallback = '']) {
  final text = raw == null ? '' : '$raw'.trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
}

double? _double(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(_text(raw));
}

int? _int(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return int.tryParse(_text(raw));
}

bool _bool(Object? raw) {
  if (raw is bool) return raw;
  final text = _text(raw).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

DateTime? _date(Object? raw) {
  final text = _text(raw);
  return text.isEmpty ? null : DateTime.tryParse(text);
}

List<String> _stringList(Object? raw) {
  if (raw is List) {
    return raw.map(_text).where((value) => value.isNotEmpty).toList();
  }
  final text = _text(raw);
  return text.isEmpty ? const [] : [text];
}

String _normalizePhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
}
