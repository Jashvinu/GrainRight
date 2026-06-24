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
    'risk_cells': riskCells.map((cell) => cell.toJson()).toList(),
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
        final parsed = double.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static bool _bool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
    }
    return false;
  }

  /// Parses both the edge-function shape (`lat`/`lng`/`per_disease`) and the
  /// disease_risk_cells REST row shape (`cell_lat`/`cell_lng`/`*_risk` columns).
  factory FarmIssueCell.fromJson(Map<String, dynamic> json) {
    final perDisease = <String, double>{};
    final perDiseaseRaw = json['per_disease'];
    if (perDiseaseRaw is Map) {
      perDiseaseRaw.forEach((key, value) {
        final parsed = switch (value) {
          num number => number.toDouble(),
          String text => double.tryParse(text.trim()),
          _ => null,
        };
        if (parsed != null && parsed > 0) {
          perDisease[key.toString()] = parsed;
        }
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
    final likelyAbioticRaw = json['likely_abiotic'];
    final likelyAbiotic =
        (switch (likelyAbioticRaw) {
          bool value => value,
          num value => value != 0,
          String value => value.toLowerCase() == 'true' || value == '1',
          _ => false,
        }) ||
        _bool(json, const ['is_abiotic', 'abiotic', 'water_stress_cell']);

    return FarmIssueCell(
      lat:
          _num(json, const [
            'lat',
            'latitude',
            'cell_lat',
            'center_lat',
            'centroid_lat',
            'y',
          ]) ??
          0,
      lng:
          _num(json, const [
            'lng',
            'lon',
            'long',
            'longitude',
            'cell_lng',
            'center_lng',
            'centroid_lng',
            'x',
          ]) ??
          0,
      compositeRisk:
          _num(json, const [
            'composite_risk',
            'max_risk_score',
            'risk_score',
            'max_risk',
            'risk',
            'risk_probability',
            'probability',
          ]) ??
          0,
      diseaseCandidates: candidates,
      likelyAbiotic: likelyAbiotic,
      perDisease: perDisease,
      ndvi: _num(json, const [
        'ndvi',
        'ndvi_value',
        'mean_ndvi',
        'avg_ndvi',
        'vegetation_index',
        'vegetation_index_value',
      ]),
      moisture: _num(json, const [
        'moisture',
        'moisture_value',
        'soil_moisture',
        'soil_moisture_percent',
        'moisture_percent',
        'moisture_index',
        'ndwi',
        'water_index',
        'water_signal',
      ]),
      weatherRisk: _num(json, const [
        'weather_risk',
        'weather_risk_score',
        'weather_risk_max',
        'weather_score',
        'crop_weather_score',
        'disease_weather_risk',
      ]),
      isScoutZone:
          json.containsKey('centroid_lat') ||
          _bool(json, const ['is_scout_zone', 'scout_zone']),
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

  Map<String, dynamic> toJson() => {
    'important_alerts': importantAlerts.map((item) => item.toJson()).toList(),
    'weather_alerts': weatherAlerts.map((item) => item.toJson()).toList(),
    'next_actions': nextActions,
    'confidence': confidence,
    if (model != null) 'model': model,
  };
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

  Map<String, dynamic> toJson() => {
    'title': title,
    'detail': detail,
    'severity': severity,
    'action': action,
  };
}
