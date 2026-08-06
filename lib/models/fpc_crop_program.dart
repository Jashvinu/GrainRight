class FpcCropProgramSnapshot {
  final Map<String, dynamic> enrollment;
  final Map<String, dynamic> program;
  final Map<String, dynamic> fpc;
  final Map<String, dynamic> seedRequest;
  final Map<String, dynamic> seedIssue;
  final List<Map<String, dynamic>> availablePrograms;
  final List<Map<String, dynamic>> availableBatches;
  final List<Map<String, dynamic>> checks;
  final List<Map<String, dynamic>> evaluations;
  final bool seedBuyingEligible;

  const FpcCropProgramSnapshot({
    required this.enrollment,
    required this.program,
    required this.fpc,
    required this.seedRequest,
    required this.seedIssue,
    required this.availablePrograms,
    required this.availableBatches,
    required this.checks,
    required this.evaluations,
    required this.seedBuyingEligible,
  });

  const FpcCropProgramSnapshot.empty()
    : enrollment = const {},
      program = const {},
      fpc = const {},
      seedRequest = const {},
      seedIssue = const {},
      availablePrograms = const [],
      availableBatches = const [],
      checks = const [],
      evaluations = const [],
      seedBuyingEligible = true;

  factory FpcCropProgramSnapshot.fromJson(Object? value) {
    if (value is! Map) return const FpcCropProgramSnapshot.empty();
    final json = Map<String, dynamic>.from(value);
    return FpcCropProgramSnapshot(
      enrollment: _map(json['enrollment']),
      program: _map(json['program']),
      fpc: _map(json['fpc']),
      seedRequest: _map(json['seed_request']),
      seedIssue: _map(json['seed_issue']),
      availablePrograms: _rows(json['available_programs']),
      availableBatches: _rows(json['available_batches']),
      checks: _rows(json['checks']),
      evaluations: _rows(json['evaluations']),
      seedBuyingEligible: json['seed_buying_eligible'] != false,
    );
  }

  bool get hasContext =>
      exists ||
      hasSeedRequest ||
      availablePrograms.isNotEmpty ||
      availableBatches.isNotEmpty ||
      !seedBuyingEligible;
  bool get exists => enrollmentId.isNotEmpty;
  String get enrollmentId => _text(enrollment['id']);
  String get status => _text(enrollment['status']);
  String get programName => _text(program['name'], 'FPC crop program');
  String get sponsorName =>
      _text(fpc['name'], _text(_map(seedRequest['fpc'])['name'], 'Your FPC'));
  int get policyVersion => _integer(enrollment['policy_version']) ?? 1;
  bool get needsTerms => status == 'pending_farmer_acceptance';
  bool get needsSeedAcknowledgement =>
      status == 'awaiting_seed_ack' && seedIssueStatus == 'delivered';
  bool get isSaleBlocked => !{
    'compliant',
    'exclusive_sale',
    'procured',
    'released',
    'completed',
  }.contains(status);
  bool get isExclusive => {'compliant', 'exclusive_sale'}.contains(status);

  String get seedIssueId => _text(seedIssue['id']);
  String get seedIssueStatus => _text(seedIssue['status']);
  double? get seedQuantityKg => _number(seedIssue['quantity_kg']);
  Map<String, dynamic> get seedBatch => _map(seedIssue['seed_batch']);
  String get seedBatchCode => _text(seedBatch['batch_code']);

  bool get hasSeedRequest => seedRequestId.isNotEmpty;
  String get seedRequestId => _text(seedRequest['id']);
  String get seedRequestStatus => _text(seedRequest['status']);
  double? get requestedQuantityKg =>
      _number(seedRequest['requested_quantity_kg']);
  String get seedRequestNote => _text(seedRequest['farmer_note']);
  String get seedRequestResponse => _text(seedRequest['response_note']);
  String get seedRequestPaymentStatus =>
      _text(seedRequest['payment_status'], 'not_started');
  int? get seedRequestUnitPricePaise =>
      _integer(seedRequest['unit_price_paise']);
  int? get seedRequestAmountPaise => _integer(seedRequest['amount_paise']);
  DateTime? get seedReservationExpiresAt =>
      DateTime.tryParse(_text(seedRequest['reservation_expires_at']));
  bool get seedReservationActive {
    final expiry = seedReservationExpiresAt;
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  bool get canPaySeedRequest =>
      seedRequestStatus == 'approved' &&
      {
        'awaiting_payment',
        'order_created',
        'failed',
      }.contains(seedRequestPaymentStatus) &&
      seedReservationActive;
  bool get seedPaymentCaptured => seedRequestPaymentStatus == 'captured';
  String get seedRequestEnrollmentStatus =>
      _text(seedRequest['enrollment_status']);
  Map<String, dynamic> get requestedProgram => _map(seedRequest['program']);
  String get requestedProgramName =>
      _text(requestedProgram['name'], 'FPC seed program');
  bool get hasActiveSeedRequest => {
    'submitted',
    'approved',
    'seed_issued',
    'delivered',
  }.contains(seedRequestStatus);
  List<Map<String, dynamic>> get requestablePrograms => availablePrograms
      .where((program) => program['request_allowed'] != false)
      .toList(growable: false);
  bool get hasFarmMatchingProgram =>
      availablePrograms.any((program) => program['farm_matches_crop'] != false);
  bool get canRequestSeed =>
      seedBuyingEligible &&
      !exists &&
      !hasActiveSeedRequest &&
      requestableBatches.isNotEmpty;
  List<Map<String, dynamic>> get requestableBatches => availableBatches
      .where(
        (batch) =>
            batch['request_allowed'] != false &&
            (_number(batch['sellable_quantity_kg']) ?? 0) > 0 &&
            (_integer(batch['unit_price_paise']) ?? 0) > 0,
      )
      .toList(growable: false);

  int get requiredCheckCount =>
      checks.where((check) => check['required'] != false).length;
  int get verifiedCheckCount => checks
      .where(
        (check) =>
            check['required'] != false &&
            check['farmer_status'] == 'submitted' &&
            check['officer_status'] == 'verified',
      )
      .length;

  Map<String, dynamic> get latestEvaluation =>
      evaluations.isEmpty ? const {} : evaluations.first;
  String get latestEvaluationStatus => _text(latestEvaluation['status']);
  int? get latestAttempt => _integer(latestEvaluation['attempt_no']);
  double? get protectedFloorRate =>
      _number(latestEvaluation['protected_floor_rate']);
  List<String> get latestReasons {
    final reasons = latestEvaluation['reasons'];
    if (reasons is! List) return const [];
    return reasons
        .map((reason) => _text(reason))
        .where((reason) => reason.isNotEmpty)
        .toList(growable: false);
  }

  String get minimumGrade =>
      _text(_map(enrollment['policy_snapshot'])['minimum_grade'], 'C');
  double? get maxMoisturePercent =>
      _number(_map(enrollment['policy_snapshot'])['max_moisture_percent']);
  double? get referenceRatePerKg => _number(
    _map(enrollment['price_formula_snapshot'])['reference_rate_per_kg'],
  );
  String get releaseReason => _text(enrollment['release_reason']);
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _rows(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

String _text(Object? value, [String fallback = '']) {
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value));
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_text(value));
}
