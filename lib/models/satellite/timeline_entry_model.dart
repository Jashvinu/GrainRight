class TimelineEntry {
  final String date;
  final String indexType;
  final double meanValue;
  final double? minValue;
  final double? maxValue;
  final double? stdDev;
  final String? tileUrl;

  const TimelineEntry({
    required this.date,
    required this.indexType,
    required this.meanValue,
    this.minValue,
    this.maxValue,
    this.stdDev,
    this.tileUrl,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    return TimelineEntry(
      date: json['observation_date'] as String? ?? json['date'] as String? ?? '',
      indexType: json['index_type'] as String? ?? '',
      meanValue: (json['mean_value'] as num?)?.toDouble() ?? 0.0,
      minValue: (json['min_value'] as num?)?.toDouble(),
      maxValue: (json['max_value'] as num?)?.toDouble(),
      stdDev: (json['std_dev'] as num?)?.toDouble(),
      tileUrl: json['tile_url'] as String?,
    );
  }
}
