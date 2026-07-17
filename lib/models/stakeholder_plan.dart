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

class StakeholderPlan {
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
          _double(json['share_unit_value'] ?? json['shareUnitValue']) ?? 1000,
      minAmount: _double(json['min_amount'] ?? json['minAmount']) ?? 1000,
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
          'Register interest as a farmer stakeholder. Final allocation is reviewed by the Kalsubai Farms team.',
      currency: 'INR',
      shareUnitValue: 1000,
      minAmount: 1000,
      maxAmount: 25000,
      status: 'active',
      purpose: [
        'Let registered farmers express interest in Kalsubai Farms participation.',
        'Keep farmer identity, selected amount, and consent in one review-ready record.',
        'Prepare an auditable queue before final approval and allocation.',
      ],
      useOfFunds: [
        'Farm aggregation and procurement readiness',
        'Millet quality, grading, and packaging operations',
        'Traceability, farmer services, and working capital planning',
      ],
      stages: [
        'Submit interest with selected amount',
        'Kalsubai Farms reviews farmer record and plan capacity',
        'Approved allocation and documents are updated later',
      ],
      riskNotes: [
        'This is not a payment receipt or confirmed share issue.',
        'Returns are not guaranteed and depend on final approval and business performance.',
        'Final terms must be reviewed before any payment or allocation.',
      ],
      terms: [
        'The selected amount is only an expression of interest.',
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
        estimateShares(amount) > 0;
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
  final String aadhaarLast4;
  final double selectedAmount;
  final int estimatedShares;
  final String status;
  final bool consentInterestOnly;
  final bool consentNoGuaranteedReturn;
  final bool consentDataUse;
  final String farmerNote;
  final String adminNote;
  final DateTime? submittedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StakeholderApplication({
    required this.id,
    required this.planId,
    required this.userId,
    required this.farmerPhone,
    required this.farmerId,
    required this.farmerName,
    required this.agriRecordId,
    required this.aadhaarLast4,
    required this.selectedAmount,
    required this.estimatedShares,
    required this.status,
    required this.consentInterestOnly,
    required this.consentNoGuaranteedReturn,
    required this.consentDataUse,
    required this.farmerNote,
    required this.adminNote,
    this.submittedAt,
    this.createdAt,
    this.updatedAt,
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
      aadhaarLast4: _text(json['aadhaar_last4'] ?? json['aadhaarLast4']),
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
      submittedAt: _date(json['submitted_at'] ?? json['submittedAt']),
      createdAt: _date(json['created_at'] ?? json['createdAt']),
      updatedAt: _date(json['updated_at'] ?? json['updatedAt']),
    );
  }
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
