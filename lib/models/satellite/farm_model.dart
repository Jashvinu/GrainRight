import 'dart:convert';

class Farm {
  final String id;
  final String name;
  final Map<String, dynamic> geometry;
  final Map<String, dynamic>? bounds;
  final double? areaHectares;
  final double? areaAcres;
  final String? userId;
  final String createdAt;
  final String? crop;
  final String? variety;
  final String? previousCrop;
  final String? season;
  final String? irrigation;
  final String? soilType;
  final String? ownershipType;
  final String? seedSource;
  final String? harvestIntent;

  const Farm({
    required this.id,
    required this.name,
    required this.geometry,
    this.bounds,
    this.areaHectares,
    this.areaAcres,
    this.userId,
    required this.createdAt,
    this.crop,
    this.variety,
    this.previousCrop,
    this.season,
    this.irrigation,
    this.soilType,
    this.ownershipType,
    this.seedSource,
    this.harvestIntent,
  });

  factory Farm.fromJson(Map<String, dynamic> json) {
    final geom = json['geometry'];
    final Map<String, dynamic> geometry;
    if (geom is String) {
      geometry = jsonDecode(geom) as Map<String, dynamic>;
    } else if (geom is Map<String, dynamic>) {
      geometry = geom;
    } else {
      geometry = {'type': 'Polygon', 'coordinates': []};
    }

    final boundsRaw = json['bounds'];
    Map<String, dynamic>? bounds;
    if (boundsRaw is Map<String, dynamic>) {
      bounds = boundsRaw;
    } else if (boundsRaw is String) {
      bounds = jsonDecode(boundsRaw) as Map<String, dynamic>;
    }

    return Farm(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed Farm',
      geometry: geometry,
      bounds: bounds,
      areaHectares: (json['area_hectares'] as num?)?.toDouble(),
      areaAcres: (json['area_acres'] as num?)?.toDouble(),
      userId: json['user_id'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      crop: json['crop'] as String?,
      variety: json['variety'] as String?,
      previousCrop: json['previous_crop'] as String?,
      season: json['season'] as String?,
      irrigation: json['irrigation'] as String?,
      soilType: json['soil_type'] as String?,
      ownershipType: json['ownership_type'] as String?,
      seedSource: json['seed_source'] as String?,
      harvestIntent: json['harvest_intent'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'name': name,
        'geometry': geometry,
        if (bounds != null) 'bounds': bounds,
        if (areaHectares != null) 'area_hectares': areaHectares,
        if (userId != null) 'user_id': userId,
      };
}
