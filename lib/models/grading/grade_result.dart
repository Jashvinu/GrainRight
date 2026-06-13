/// Moisture risk bands returned by the grading service.
enum MoistureRisk { low, moderate, high, critical, unknown }

MoistureRisk _moistureRiskFrom(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'LOW':
      return MoistureRisk.low;
    case 'MODERATE':
      return MoistureRisk.moderate;
    case 'HIGH':
      return MoistureRisk.high;
    case 'CRITICAL':
      return MoistureRisk.critical;
    default:
      return MoistureRisk.unknown;
  }
}

extension MoistureRiskApi on MoistureRisk {
  /// API token expected by `POST /api/feedback` (`true_moisture_risk`).
  String get apiValue {
    switch (this) {
      case MoistureRisk.low:
        return 'LOW';
      case MoistureRisk.moderate:
        return 'MODERATE';
      case MoistureRisk.high:
        return 'HIGH';
      case MoistureRisk.critical:
        return 'CRITICAL';
      case MoistureRisk.unknown:
        return 'MODERATE';
    }
  }
}

/// A single grading rule the engine applied, for the "why" reveal.
class AppliedRule {
  final String name;
  final String evidence;
  final double? confidence;

  const AppliedRule({
    required this.name,
    this.evidence = '',
    this.confidence,
  });

  factory AppliedRule.fromJson(Map<String, dynamic> json) {
    return AppliedRule(
      name: '${json['rule_name'] ?? json['rule_id'] ?? 'Rule'}',
      evidence: '${json['evidence'] ?? ''}',
      confidence: _toDouble(json['rule_confidence']),
    );
  }
}

/// Flattened view of the grading service `POST /api/analyze` response.
/// See docs/11_grain_grading_integration.md §4 for the raw contract.
class GradeResult {
  final String analysisId;

  // Quality
  final String grade; // A | B | C
  final String grainGrade;
  final double? brokenGrainPercent;
  final double? foreignMatterPercent;
  final double? uniformityScore;
  final bool moldVisible;
  final bool rejectRecommended;
  final List<String> rejectReasons;

  // Moisture
  final MoistureRisk moistureRisk;
  final double? moisturePercent;
  final String moistureSource;

  // Confidence + selection
  final double? confidenceOverall; // 0-100
  final String selectedCrop;
  final String selectedVariety;

  // Narrative
  final bool manualReviewRequired;
  final String operatorSummary;
  final List<String> signalHighlights;
  final List<AppliedRule> appliedRules;

  const GradeResult({
    required this.analysisId,
    required this.grade,
    required this.grainGrade,
    this.brokenGrainPercent,
    this.foreignMatterPercent,
    this.uniformityScore,
    this.moldVisible = false,
    this.rejectRecommended = false,
    this.rejectReasons = const [],
    this.moistureRisk = MoistureRisk.unknown,
    this.moisturePercent,
    this.moistureSource = '',
    this.confidenceOverall,
    this.selectedCrop = '',
    this.selectedVariety = '',
    this.manualReviewRequired = false,
    this.operatorSummary = '',
    this.signalHighlights = const [],
    this.appliedRules = const [],
  });

  factory GradeResult.fromJson(Map<String, dynamic> json) {
    final quality = _map(json['quality']);
    final moisture = _map(json['moisture']);
    final confidence = _map(json['confidence']);
    final selection = _map(json['selection']);

    final moisturePercent =
        _toDouble(moisture['percent_estimate']) ??
        _toDouble(moisture['machine_percent']);

    return GradeResult(
      analysisId: '${json['analysis_id'] ?? ''}',
      grade: _grade(quality['grade']),
      grainGrade: _grade(quality['grain_grade'] ?? quality['grade']),
      brokenGrainPercent: _toDouble(quality['broken_grain_percent']),
      foreignMatterPercent: _toDouble(quality['foreign_matter_percent']),
      uniformityScore: _toDouble(quality['uniformity_score']),
      moldVisible: quality['mold_visible'] == true,
      rejectRecommended: quality['reject_recommended'] == true,
      rejectReasons: _stringList(quality['reject_reasons']),
      moistureRisk: _moistureRiskFrom('${moisture['risk_level'] ?? ''}'),
      moisturePercent: moisturePercent,
      moistureSource: '${moisture['source'] ?? ''}',
      confidenceOverall: _toDouble(confidence['overall']),
      selectedCrop: '${selection['selected_crop'] ?? ''}',
      selectedVariety: '${selection['selected_variety'] ?? ''}',
      manualReviewRequired: json['manual_review_required'] == true,
      operatorSummary: '${json['operator_summary'] ?? ''}',
      signalHighlights: _stringList(json['signal_highlights']),
      appliedRules: (json['applied_rules'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AppliedRule.fromJson)
          .toList(),
    );
  }

  static Map<String, dynamic> _map(dynamic raw) =>
      raw is Map<String, dynamic> ? raw : const {};

  static String _grade(dynamic raw) {
    final value = '${raw ?? ''}'.toUpperCase().trim();
    return (value == 'A' || value == 'B' || value == 'C') ? value : 'B';
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
  }
}

double? _toDouble(dynamic raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}
