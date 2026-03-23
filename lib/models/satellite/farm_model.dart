import 'dart:convert';

class Farm {
  final String id;
  final String name;
  final Map<String, dynamic> geometry;
  final Map<String, dynamic>? bounds;
  final double? areaHectares;
  final String? userId;
  final String createdAt;

  const Farm({
    required this.id,
    required this.name,
    required this.geometry,
    this.bounds,
    this.areaHectares,
    this.userId,
    required this.createdAt,
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
      userId: json['user_id'] as String?,
      createdAt: json['created_at'] as String? ?? '',
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
