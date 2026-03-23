class DiagnosticsResult {
  final Map<String, IndexAnalysis> analysis;
  final List<Problem> problems;
  final List<CellData> cellData;
  final DiagnosticsMetadata metadata;

  const DiagnosticsResult({
    required this.analysis,
    required this.problems,
    required this.cellData,
    required this.metadata,
  });

  factory DiagnosticsResult.fromJson(Map<String, dynamic> json) {
    final analysisRaw = json['analysis'] as Map<String, dynamic>? ?? {};
    final analysis = analysisRaw.map(
      (k, v) => MapEntry(k, IndexAnalysis.fromJson(v as Map<String, dynamic>)),
    );

    final problemsRaw = json['problems'] as List? ?? [];
    final problems = problemsRaw
        .map((e) => Problem.fromJson(e as Map<String, dynamic>))
        .toList();

    final cellRaw = json['cellData'] as List? ?? [];
    final cellData = cellRaw
        .map((e) => CellData.fromJson(e as Map<String, dynamic>))
        .toList();

    return DiagnosticsResult(
      analysis: analysis,
      problems: problems,
      cellData: cellData,
      metadata: DiagnosticsMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class IndexAnalysis {
  final double mean;
  final double min;
  final double max;
  final double stdDev;
  final bool belowThreshold;
  final double? trend;
  final bool trendDetected;
  final String? tileUrlFormat;

  const IndexAnalysis({
    required this.mean,
    required this.min,
    required this.max,
    required this.stdDev,
    required this.belowThreshold,
    this.trend,
    required this.trendDetected,
    this.tileUrlFormat,
  });

  factory IndexAnalysis.fromJson(Map<String, dynamic> json) {
    final mapData = json['mapData'] as Map<String, dynamic>?;
    return IndexAnalysis(
      mean: (json['mean'] as num?)?.toDouble() ?? 0.0,
      min: (json['min'] as num?)?.toDouble() ?? 0.0,
      max: (json['max'] as num?)?.toDouble() ?? 0.0,
      stdDev: (json['stdDev'] as num?)?.toDouble() ?? 0.0,
      belowThreshold: json['belowThreshold'] as bool? ?? false,
      trend: (json['trend'] as num?)?.toDouble(),
      trendDetected: json['trendDetected'] as bool? ?? false,
      tileUrlFormat: mapData?['urlFormat'] as String?,
    );
  }
}

class Problem {
  final String index;
  final String type;
  final double? avgValue;
  final double? avgDecline;
  final double? threshold;

  const Problem({
    required this.index,
    required this.type,
    this.avgValue,
    this.avgDecline,
    this.threshold,
  });

  factory Problem.fromJson(Map<String, dynamic> json) {
    return Problem(
      index: json['index'] as String? ?? '',
      type: json['type'] as String? ?? '',
      avgValue: (json['avgValue'] as num?)?.toDouble(),
      avgDecline: (json['avgDecline'] as num?)?.toDouble(),
      threshold: (json['threshold'] as num?)?.toDouble(),
    );
  }
}

class CellData {
  final double lat;
  final double lng;
  final Map<String, double> values;

  const CellData({required this.lat, required this.lng, required this.values});

  factory CellData.fromJson(Map<String, dynamic> json) {
    final values = <String, double>{};
    json.forEach((k, v) {
      if (k != 'lat' && k != 'lng' && v is num) {
        values[k] = v.toDouble();
      }
    });
    return CellData(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      values: values,
    );
  }
}

class DiagnosticsMetadata {
  final int daysAnalyzed;
  final String resolution;
  final List<String> indices;
  final String season;

  const DiagnosticsMetadata({
    required this.daysAnalyzed,
    required this.resolution,
    required this.indices,
    required this.season,
  });

  factory DiagnosticsMetadata.fromJson(Map<String, dynamic> json) {
    final idxRaw = json['indices'] as List? ?? [];
    return DiagnosticsMetadata(
      daysAnalyzed: json['daysAnalyzed'] as int? ?? 14,
      resolution: json['resolution'] as String? ?? '10m',
      indices: idxRaw.map((e) => e.toString()).toList(),
      season: json['season'] as String? ?? '',
    );
  }
}
