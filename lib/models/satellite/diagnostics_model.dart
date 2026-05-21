class DiagnosticsResult {
  final Map<String, IndexAnalysis> analysis;
  final List<Problem> problems;
  final List<CellData> cellData;
  final Map<String, String> rasterUrls;
  final List<List<double>>? rasterBounds;
  final bool cached;
  final String? expiresAt;
  final DiagnosticsMetadata metadata;

  const DiagnosticsResult({
    required this.analysis,
    required this.problems,
    required this.cellData,
    required this.rasterUrls,
    this.rasterBounds,
    required this.cached,
    this.expiresAt,
    required this.metadata,
  });

  factory DiagnosticsResult.fromJson(Map<String, dynamic> json) {
    final root = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final analysisRaw = root['analysis'] as Map<String, dynamic>? ?? {};
    final analysis = analysisRaw.map(
      (k, v) => MapEntry(k, IndexAnalysis.fromJson(v as Map<String, dynamic>)),
    );

    final problemsRaw = root['problems'] as List? ?? [];
    final problems = problemsRaw
        .map((e) => Problem.fromJson(e as Map<String, dynamic>))
        .toList();

    final cellRaw =
        root['cell_stats'] as List? ?? root['cellData'] as List? ?? [];
    final cellData = cellRaw
        .map((e) => CellData.fromJson(e as Map<String, dynamic>))
        .toList();

    final rasterUrlsRaw = root['raster_urls'] as Map<String, dynamic>? ?? {};
    final rasterUrls = rasterUrlsRaw.map(
      (key, value) => MapEntry(key, value.toString()),
    );

    return DiagnosticsResult(
      analysis: analysis,
      problems: problems,
      cellData: cellData,
      rasterUrls: rasterUrls,
      rasterBounds: _parseBounds(root['bounds']),
      cached: root['cached'] as bool? ?? false,
      expiresAt: root['expires_at'] as String?,
      metadata: DiagnosticsMetadata.fromJson(
        root['metadata'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  static List<List<double>>? _parseBounds(dynamic raw) {
    if (raw is! List || raw.length < 2) return null;
    final sw = raw[0];
    final ne = raw[1];
    if (sw is! List || ne is! List || sw.length < 2 || ne.length < 2) {
      return null;
    }
    return [
      [(sw[0] as num).toDouble(), (sw[1] as num).toDouble()],
      [(ne[0] as num).toDouble(), (ne[1] as num).toDouble()],
    ];
  }
}

class IndexAnalysis {
  final double mean;
  final double min;
  final double max;
  final double stdDev;
  final bool belowThreshold;
  final double? trend;
  final String? trendUnit;
  final bool trendDetected;
  final String? confidence;
  final String? modelVersion;
  final String? unit;
  final String? tileUrlFormat;

  const IndexAnalysis({
    required this.mean,
    required this.min,
    required this.max,
    required this.stdDev,
    required this.belowThreshold,
    this.trend,
    this.trendUnit,
    required this.trendDetected,
    this.confidence,
    this.modelVersion,
    this.unit,
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
      trendUnit: json['trendUnit'] as String?,
      trendDetected: json['trendDetected'] as bool? ?? false,
      confidence: json['confidence'] as String?,
      modelVersion: json['modelVersion'] as String?,
      unit: json['unit'] as String?,
      tileUrlFormat: mapData?['urlFormat'] as String?,
    );
  }
}

class Problem {
  final String index;
  final String type;
  final double? avgValue;
  final double? avgDecline;
  final String? trendUnit;
  final double? threshold;
  final String? confidence;

  const Problem({
    required this.index,
    required this.type,
    this.avgValue,
    this.avgDecline,
    this.trendUnit,
    this.threshold,
    this.confidence,
  });

  factory Problem.fromJson(Map<String, dynamic> json) {
    return Problem(
      index: json['index'] as String? ?? '',
      type: json['type'] as String? ?? '',
      avgValue: (json['avgValue'] as num?)?.toDouble(),
      avgDecline: (json['avgDecline'] as num?)?.toDouble(),
      trendUnit: json['trendUnit'] as String?,
      threshold: (json['threshold'] as num?)?.toDouble(),
      confidence: json['confidence'] as String?,
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
  final int imagesAnalyzed;
  final double? cloudCover;
  final String resolution;
  final List<String> indices;
  final String season;
  final Map<String, dynamic>? nutrientModel;

  const DiagnosticsMetadata({
    required this.daysAnalyzed,
    required this.imagesAnalyzed,
    this.cloudCover,
    required this.resolution,
    required this.indices,
    required this.season,
    this.nutrientModel,
  });

  factory DiagnosticsMetadata.fromJson(Map<String, dynamic> json) {
    final idxRaw = json['indices'] as List? ?? [];
    return DiagnosticsMetadata(
      daysAnalyzed: json['daysAnalyzed'] as int? ?? 14,
      imagesAnalyzed:
          json['imagesAnalyzed'] as int? ?? json['daysAnalyzed'] as int? ?? 14,
      cloudCover: (json['cloudCover'] as num? ?? json['cloud_cover'] as num?)
          ?.toDouble(),
      resolution: json['resolution'] as String? ?? '10m',
      indices: idxRaw.map((e) => e.toString()).toList(),
      season: json['season'] as String? ?? '',
      nutrientModel: json['nutrientModel'] as Map<String, dynamic>?,
    );
  }
}
