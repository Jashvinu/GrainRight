class DiseaseScreenResult {
  final String scanDate;
  final String crop;
  final String growthStage;
  final String season;
  final int imagesAnalyzed;
  final int riskCellsCount;
  final int highRiskCells;
  final List<Map<String, dynamic>> scoutZones;
  final List<FarmIssueCell> riskCells;
  final Map<String, dynamic>? weatherContext;
  final Map<String, double> topDiseaseRisks;
  final String? message;

  const DiseaseScreenResult({
    required this.scanDate,
    required this.crop,
    required this.growthStage,
    required this.season,
    required this.imagesAnalyzed,
    required this.riskCellsCount,
    required this.highRiskCells,
    required this.scoutZones,
    this.riskCells = const [],
    this.weatherContext,
    required this.topDiseaseRisks,
    this.message,
  });

  factory DiseaseScreenResult.fromJson(Map<String, dynamic> json) {
    final root = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final risksRaw = root['top_disease_risks'] as Map<String, dynamic>? ?? {};

    return DiseaseScreenResult(
      scanDate: root['scan_date'] as String? ?? '',
      crop: root['crop'] as String? ?? '',
      growthStage: root['growth_stage'] as String? ?? '',
      season: root['season'] as String? ?? '',
      imagesAnalyzed: (root['images_analyzed'] as num?)?.toInt() ?? 0,
      riskCellsCount: (root['risk_cells_count'] as num?)?.toInt() ?? 0,
      highRiskCells: (root['high_risk_cells'] as num?)?.toInt() ?? 0,
      scoutZones: (root['scout_zones'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
      riskCells: (root['risk_cells'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FarmIssueCell.fromJson)
          .where((cell) => cell.hasLocation)
          .toList(growable: false),
      weatherContext: root['weather_context'] as Map<String, dynamic>?,
      topDiseaseRisks: risksRaw.map(
        (key, value) => MapEntry(key, (value as num?)?.toDouble() ?? 0),
      ),
      message: root['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'scan_date': scanDate,
    'crop': crop,
    'growth_stage': growthStage,
    'season': season,
    'images_analyzed': imagesAnalyzed,
    'risk_cells_count': riskCellsCount,
    'high_risk_cells': highRiskCells,
    'scout_zones': scoutZones,
    if (weatherContext != null) 'weather_context': weatherContext,
    'top_disease_risks': topDiseaseRisks,
    if (message != null) 'message': message,
  };
}

/// One mapped issue location on the farm: either a satellite risk cell
/// (from the disease-risk-screen response or a disease_risk_cells REST row)
/// or a scout zone centroid.
class FarmIssueCell {
  final double lat;
  final double lng;
  final double compositeRisk;
  final List<String> diseaseCandidates;
  final bool likelyAbiotic;
  final Map<String, double> perDisease;
  final double? ndvi;
  final double? moisture;
  final double? weatherRisk;
  final bool isScoutZone;

  const FarmIssueCell({
    required this.lat,
    required this.lng,
    required this.compositeRisk,
    required this.diseaseCandidates,
    required this.likelyAbiotic,
    this.perDisease = const {},
    this.ndvi,
    this.moisture,
    this.weatherRisk,
    this.isScoutZone = false,
  });

  static double? _num(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  /// Parses both the edge-function shape (`lat`/`lng`/`per_disease`) and the
  /// disease_risk_cells REST row shape (`cell_lat`/`cell_lng`/`*_risk` columns).
  factory FarmIssueCell.fromJson(Map<String, dynamic> json) {
    final perDisease = <String, double>{};
    final perDiseaseRaw = json['per_disease'];
    if (perDiseaseRaw is Map) {
      perDiseaseRaw.forEach((key, value) {
        if (value is num) perDisease[key.toString()] = value.toDouble();
      });
    } else {
      const columns = {
        'rice_blast_risk': 'rice_blast',
        'sheath_blight_risk': 'sheath_blight',
        'blb_risk': 'bacterial_leaf_blight',
        'downy_mildew_risk': 'downy_mildew',
        'leaf_spot_risk': 'leaf_spot',
        'charcoal_rot_risk': 'charcoal_rot',
      };
      columns.forEach((column, disease) {
        final value = _num(json, [column]);
        if (value != null && value > 0) perDisease[disease] = value;
      });
    }

    final candidatesRaw = json['disease_candidates'];
    final candidates = candidatesRaw is List
        ? candidatesRaw
              .map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false)
        : perDisease.entries
              .where((entry) => entry.value > 0.30)
              .map((entry) => entry.key)
              .toList(growable: false);

    return FarmIssueCell(
      lat: _num(json, const ['lat', 'cell_lat', 'centroid_lat']) ?? 0,
      lng: _num(json, const ['lng', 'cell_lng', 'centroid_lng']) ?? 0,
      compositeRisk:
          _num(json, const [
            'composite_risk',
            'max_risk_score',
            'risk_score',
          ]) ??
          0,
      diseaseCandidates: candidates,
      likelyAbiotic: json['likely_abiotic'] == true,
      perDisease: perDisease,
      ndvi: _num(json, const ['ndvi']),
      moisture: _num(json, const ['moisture']),
      weatherRisk: _num(json, const ['weather_risk']),
      isScoutZone: json.containsKey('centroid_lat'),
    );
  }

  factory FarmIssueCell.fromScoutZone(Map<String, dynamic> json) {
    final cell = FarmIssueCell.fromJson(json);
    return FarmIssueCell(
      lat: cell.lat,
      lng: cell.lng,
      compositeRisk: cell.compositeRisk,
      diseaseCandidates: cell.diseaseCandidates,
      likelyAbiotic: cell.likelyAbiotic,
      perDisease: cell.perDisease,
      ndvi: cell.ndvi,
      moisture: cell.moisture,
      weatherRisk: cell.weatherRisk,
      isScoutZone: true,
    );
  }

  bool get hasLocation => lat != 0 && lng != 0;

  /// Disease (biotic) issues vs other stress (water/heat, abiotic).
  bool get isDisease => diseaseCandidates.isNotEmpty && !likelyAbiotic;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'composite_risk': compositeRisk,
    'disease_candidates': diseaseCandidates,
    'likely_abiotic': likelyAbiotic,
    if (perDisease.isNotEmpty) 'per_disease': perDisease,
    if (ndvi != null) 'ndvi': ndvi,
    if (moisture != null) 'moisture': moisture,
    if (weatherRisk != null) 'weather_risk': weatherRisk,
    'is_scout_zone': isScoutZone,
  };
}

/// VLM diagnosis returned by disease-image-diagnose for a farmer photo.
class FarmPhotoDiagnosis {
  final String diagnosis;
  final double confidence;
  final String severity;
  final List<String> differential;
  final List<String> evidence;
  final String scoutAction;
  final String? model;

  const FarmPhotoDiagnosis({
    required this.diagnosis,
    required this.confidence,
    required this.severity,
    required this.differential,
    required this.evidence,
    required this.scoutAction,
    this.model,
  });

  factory FarmPhotoDiagnosis.fromJson(Map<String, dynamic> json) {
    final root = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    List<String> strings(dynamic raw) => (raw as List? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);

    return FarmPhotoDiagnosis(
      diagnosis: root['diagnosis'] as String? ?? 'visual review needed',
      confidence: (root['confidence'] as num?)?.toDouble() ?? 0,
      severity: root['severity'] as String? ?? 'medium',
      differential: strings(root['differential']),
      evidence: strings(root['evidence']),
      scoutAction: root['scout_action'] as String? ?? '',
      model: root['model'] as String?,
    );
  }
}

class FarmAlertAdvice {
  final List<FarmAlertItem> importantAlerts;
  final List<FarmAlertItem> weatherAlerts;
  final List<String> nextActions;
  final String confidence;
  final String? model;

  const FarmAlertAdvice({
    required this.importantAlerts,
    required this.weatherAlerts,
    required this.nextActions,
    required this.confidence,
    this.model,
  });

  factory FarmAlertAdvice.fromJson(Map<String, dynamic> json) {
    final root = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final advice = root['advice'] is Map<String, dynamic>
        ? root['advice'] as Map<String, dynamic>
        : root;

    return FarmAlertAdvice(
      importantAlerts: _alerts(advice['important_alerts']),
      weatherAlerts: _alerts(advice['weather_alerts']),
      nextActions: (advice['next_actions'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false),
      confidence: advice['confidence'] as String? ?? 'medium',
      model: advice['model'] as String?,
    );
  }

  static List<FarmAlertItem> _alerts(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FarmAlertItem.fromJson)
        .where((item) => item.title.isNotEmpty)
        .toList(growable: false);
  }
}

class FarmAlertItem {
  final String title;
  final String detail;
  final String severity;
  final String action;

  const FarmAlertItem({
    required this.title,
    required this.detail,
    required this.severity,
    required this.action,
  });

  factory FarmAlertItem.fromJson(Map<String, dynamic> json) {
    return FarmAlertItem(
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      severity: json['severity'] as String? ?? 'medium',
      action: json['action'] as String? ?? '',
    );
  }
}
