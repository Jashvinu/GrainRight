class AdvancedMonitoringResult {
  final List<AlgorithmTimeSeries> timeseries;
  final List<TrendResult> trends;
  final AdvancedMetadata metadata;

  const AdvancedMonitoringResult({
    required this.timeseries,
    required this.trends,
    required this.metadata,
  });

  factory AdvancedMonitoringResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final tsRaw = data['timeseries'] as List? ?? [];
    final trendsRaw = data['trends'] as List? ?? [];

    return AdvancedMonitoringResult(
      timeseries: tsRaw
          .map((e) => AlgorithmTimeSeries.fromJson(e as Map<String, dynamic>))
          .toList(),
      trends: trendsRaw
          .map((e) => TrendResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      metadata: AdvancedMetadata.fromJson(
          data['metadata'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class AlgorithmTimeSeries {
  final String algorithm;
  final List<TimeWindow> windows;

  const AlgorithmTimeSeries({required this.algorithm, required this.windows});

  factory AlgorithmTimeSeries.fromJson(Map<String, dynamic> json) {
    final windowsRaw = json['windows'] as List? ?? [];
    return AlgorithmTimeSeries(
      algorithm: json['algorithm'] as String? ?? '',
      windows: windowsRaw
          .map((e) => TimeWindow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TimeWindow {
  final String startDate;
  final String endDate;
  final double mean;
  final double stdDev;
  final double min;
  final double max;
  final int pixelCount;
  final double? cloudCover;

  const TimeWindow({
    required this.startDate,
    required this.endDate,
    required this.mean,
    required this.stdDev,
    required this.min,
    required this.max,
    required this.pixelCount,
    this.cloudCover,
  });

  factory TimeWindow.fromJson(Map<String, dynamic> json) {
    return TimeWindow(
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      mean: (json['mean'] as num?)?.toDouble() ?? 0.0,
      stdDev: (json['stdDev'] as num?)?.toDouble() ?? 0.0,
      min: (json['min'] as num?)?.toDouble() ?? 0.0,
      max: (json['max'] as num?)?.toDouble() ?? 0.0,
      pixelCount: json['pixelCount'] as int? ?? 0,
      cloudCover: (json['cloudCover'] as num?)?.toDouble(),
    );
  }
}

class TrendResult {
  final String algorithm;
  final double theilsenSlope;
  final String trendDirection;
  final double pValue;
  final double rSquared;
  final double? confidenceIntervalLow;
  final double? confidenceIntervalHigh;
  final int windowCount;

  const TrendResult({
    required this.algorithm,
    required this.theilsenSlope,
    required this.trendDirection,
    required this.pValue,
    required this.rSquared,
    this.confidenceIntervalLow,
    this.confidenceIntervalHigh,
    required this.windowCount,
  });

  factory TrendResult.fromJson(Map<String, dynamic> json) {
    return TrendResult(
      algorithm: json['algorithm'] as String? ?? '',
      theilsenSlope: (json['theilsenSlope'] as num?)?.toDouble() ?? 0.0,
      trendDirection: json['trendDirection'] as String? ?? 'Stable',
      pValue: (json['pValue'] as num?)?.toDouble() ?? 1.0,
      rSquared: (json['rSquared'] as num?)?.toDouble() ?? 0.0,
      confidenceIntervalLow:
          (json['confidenceIntervalLow'] as num?)?.toDouble(),
      confidenceIntervalHigh:
          (json['confidenceIntervalHigh'] as num?)?.toDouble(),
      windowCount: json['windowCount'] as int? ?? 0,
    );
  }
}

class AdvancedMetadata {
  final String farmId;
  final int windowCount;
  final int windowSizeDays;
  final int algorithmCount;

  const AdvancedMetadata({
    required this.farmId,
    required this.windowCount,
    required this.windowSizeDays,
    required this.algorithmCount,
  });

  factory AdvancedMetadata.fromJson(Map<String, dynamic> json) {
    return AdvancedMetadata(
      farmId: json['farmId'] as String? ?? '',
      windowCount: json['windowCount'] as int? ?? 0,
      windowSizeDays: json['windowSizeDays'] as int? ?? 10,
      algorithmCount: json['algorithmCount'] as int? ?? 0,
    );
  }
}
