import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/satellite/farm_alert_model.dart';

class FarmAlertCacheSnapshot {
  final DateTime cachedAt;
  final DiseaseScreenResult? diseaseScreen;
  final FarmAlertAdvice? advice;
  final List<Map<String, dynamic>> scoutZones;
  final List<Map<String, dynamic>> riskCells;

  const FarmAlertCacheSnapshot({
    required this.cachedAt,
    this.diseaseScreen,
    this.advice,
    this.scoutZones = const [],
    this.riskCells = const [],
  });

  factory FarmAlertCacheSnapshot.fromJson(Map<String, dynamic> json) {
    final diseaseScreenRaw = json['disease_screen'];
    final adviceRaw = json['advice'];
    return FarmAlertCacheSnapshot(
      cachedAt:
          DateTime.tryParse(json['cached_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      diseaseScreen: diseaseScreenRaw is Map<String, dynamic>
          ? DiseaseScreenResult.fromJson(diseaseScreenRaw)
          : null,
      advice: adviceRaw is Map<String, dynamic>
          ? FarmAlertAdvice.fromJson(adviceRaw)
          : null,
      scoutZones: _mapList(json['scout_zones']),
      riskCells: _mapList(json['risk_cells']),
    );
  }

  Map<String, dynamic> toJson() => {
    'cached_at': cachedAt.toIso8601String(),
    if (diseaseScreen != null) 'disease_screen': diseaseScreen!.toJson(),
    if (advice != null) 'advice': advice!.toJson(),
    'scout_zones': scoutZones,
    'risk_cells': riskCells,
  };

  static List<Map<String, dynamic>> _mapList(Object? raw) {
    return (raw as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }
}

class FarmAlertCacheService {
  static const _prefix = 'farm_alert_cache_v1';

  String _key(String farmKey) => '$_prefix:$farmKey';

  Future<FarmAlertCacheSnapshot?> load(String farmKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(farmKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return FarmAlertCacheSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String farmKey,
    required FarmAlertCacheSnapshot snapshot,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(farmKey), jsonEncode(snapshot.toJson()));
  }
}
