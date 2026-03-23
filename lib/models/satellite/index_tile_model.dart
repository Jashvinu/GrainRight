class IndexTileResult {
  final String satellite;
  final String urlFormat;
  final double? meanValue;
  final double? minValue;
  final double? maxValue;
  final double? stdDev;
  final double? cloudCover;

  const IndexTileResult({
    required this.satellite,
    required this.urlFormat,
    this.meanValue,
    this.minValue,
    this.maxValue,
    this.stdDev,
    this.cloudCover,
  });

  factory IndexTileResult.fromJson(Map<String, dynamic> json) {
    return IndexTileResult(
      satellite: json['satellite'] as String? ?? '',
      urlFormat: json['urlFormat'] as String? ?? '',
      meanValue: (json['mean_value'] as num?)?.toDouble(),
      minValue: (json['min_value'] as num?)?.toDouble(),
      maxValue: (json['max_value'] as num?)?.toDouble(),
      stdDev: (json['std_dev'] as num?)?.toDouble(),
      cloudCover: (json['cloudCover'] as num?)?.toDouble(),
    );
  }
}
