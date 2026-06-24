import 'farm_alert_model.dart';

class FarmerFarmSummary {
  final FarmSummaryFarmInfo farm;
  final FarmSummaryMetric? waterLevel;
  final FarmSummaryMetric? cropHealth;
  final FarmSummaryMetric? canopy;
  final FarmSummaryMetric? cropTrend;
  final String? lastUpdate;
  final Map<String, dynamic>? weatherContext;
  final DiseaseScreenResult diseaseScreen;
  final List<Map<String, dynamic>> scoutZoneRows;
  final List<Map<String, dynamic>> riskCellRows;
  final double maxDiseaseRisk;
  final FarmAlertAdvice? advice;

  const FarmerFarmSummary({
    required this.farm,
    this.waterLevel,
    this.cropHealth,
    this.canopy,
    this.cropTrend,
    this.lastUpdate,
    this.weatherContext,
    required this.diseaseScreen,
    required this.scoutZoneRows,
    required this.riskCellRows,
    required this.maxDiseaseRisk,
    this.advice,
  });

  factory FarmerFarmSummary.fromJson(Map<String, dynamic> json) {
    final root = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final farmMap = _map(root['farm']);
    final metrics = _map(root['satellite_metrics']);
    final disease = _map(root['disease']);
    final weather = _mapOrNull(root['weather_context']);
    final scoutRows = _rows(disease['scout_zones']);
    final riskRows = _rows(disease['risk_cells']);
    final topRisks = _map(disease['top_disease_risks']);
    final farm = FarmSummaryFarmInfo.fromJson(farmMap);
    final diseaseScreen = DiseaseScreenResult.fromJson({
      'scan_date': disease['scan_date'] ?? metrics['last_update'] ?? '',
      'crop': disease['crop'] ?? farm.crop,
      'growth_stage': disease['growth_stage'] ?? '',
      'season': disease['season'] ?? farm.season,
      'images_analyzed': disease['images_analyzed'] ?? 0,
      'risk_cells_count': disease['risk_cells_count'] ?? riskRows.length,
      'high_risk_cells': disease['high_risk_cells'] ?? 0,
      'scout_zones': scoutRows,
      'risk_cells': riskRows,
      // ignore: use_null_aware_elements
      if (weather != null) 'weather_context': weather,
      'top_disease_risks': topRisks,
      // ignore: use_null_aware_elements
      if (disease['message'] != null) 'message': disease['message'],
    });

    return FarmerFarmSummary(
      farm: farm,
      waterLevel: FarmSummaryMetric.parse(metrics['water_level']),
      cropHealth: FarmSummaryMetric.parse(metrics['crop_health']),
      canopy: FarmSummaryMetric.parse(metrics['canopy']),
      cropTrend: FarmSummaryMetric.parse(metrics['crop_trend']),
      lastUpdate: _text(metrics['last_update']),
      weatherContext: weather,
      diseaseScreen: diseaseScreen,
      scoutZoneRows: scoutRows,
      riskCellRows: riskRows,
      maxDiseaseRisk:
          _double(disease['max_risk']) ?? _maxDiseaseRisk(diseaseScreen),
      advice: _advice(root['advice']),
    );
  }

  static Map<String, dynamic> _map(dynamic raw) {
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static Map<String, dynamic>? _mapOrNull(dynamic raw) {
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  static List<Map<String, dynamic>> _rows(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static String? _text(dynamic raw) {
    final value = '${raw ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }

  static double? _double(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static double _maxDiseaseRisk(DiseaseScreenResult screen) {
    var maxRisk = 0.0;
    for (final value in screen.topDiseaseRisks.values) {
      if (value > maxRisk) maxRisk = value;
    }
    for (final cell in screen.riskCells) {
      if (cell.compositeRisk > maxRisk) maxRisk = cell.compositeRisk;
    }
    return maxRisk;
  }

  static FarmAlertAdvice? _advice(dynamic raw) {
    if (raw is! Map || raw.isEmpty) return null;
    return FarmAlertAdvice.fromJson(Map<String, dynamic>.from(raw));
  }
}

class FarmSummaryFarmInfo {
  final String id;
  final String name;
  final String crop;
  final String variety;
  final String season;
  final double? areaAcres;

  const FarmSummaryFarmInfo({
    required this.id,
    required this.name,
    required this.crop,
    required this.variety,
    required this.season,
    this.areaAcres,
  });

  factory FarmSummaryFarmInfo.fromJson(Map<String, dynamic> json) {
    return FarmSummaryFarmInfo(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      crop: '${json['crop'] ?? ''}',
      variety: '${json['variety'] ?? ''}',
      season: '${json['season'] ?? ''}',
      areaAcres: FarmSummaryMetric.readDouble(json['area_acres']),
    );
  }
}

class FarmSummaryMetric {
  final double? value;
  final String? index;
  final String? date;
  final String? source;
  final String? status;

  const FarmSummaryMetric({
    this.value,
    this.index,
    this.date,
    this.source,
    this.status,
  });

  bool get hasValue => value != null;

  static FarmSummaryMetric? parse(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    return FarmSummaryMetric(
      value: readDouble(map['value']),
      index: _text(map['index']),
      date: _text(map['date']),
      source: _text(map['source']),
      status: _text(map['status']),
    );
  }

  static double? readDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static String? _text(dynamic raw) {
    final value = '${raw ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }
}
