class SatelliteDate {
  final String date;
  final String satellite;
  final double? cloudCover;
  final String tileId;
  final List<String> availableIndices;

  const SatelliteDate({
    required this.date,
    required this.satellite,
    this.cloudCover,
    required this.tileId,
    required this.availableIndices,
  });

  factory SatelliteDate.fromJson(Map<String, dynamic> json) {
    final indices = json['available_indices'];
    return SatelliteDate(
      date: json['date'] as String,
      satellite: json['satellite'] as String? ?? '',
      cloudCover: (json['cloud_cover'] as num?)?.toDouble(),
      tileId: json['tile_id'] as String? ?? '',
      availableIndices: indices is List
          ? indices.map((e) => e.toString()).toList()
          : [],
    );
  }

  String get satelliteShort {
    if (satellite.contains('Sentinel-2')) return 'S2';
    if (satellite.contains('Landsat-8')) return 'L8';
    if (satellite.contains('Landsat-9')) return 'L9';
    if (satellite.contains('SAR')) return 'SAR';
    return satellite;
  }
}
