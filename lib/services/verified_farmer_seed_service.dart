import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/verified_farmer_record.dart';

class VerifiedFarmerSeedService {
  VerifiedFarmerSeedService._();

  static const String _assetPath = 'assets/verified_farmer_seed.json';
  static final VerifiedFarmerSeedService instance = VerifiedFarmerSeedService._();

  final Map<String, VerifiedFarmerRecord> _cache = {};
  bool _loaded = false;

  Future<VerifiedFarmerRecord?> getByPhone(String phone) async {
    await _load();
    final normalized = _normalizePhone(phone);
    return _cache[normalized];
  }

  String _normalizePhone(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _loaded = true;
        return;
      }

      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final record = VerifiedFarmerRecord.fromJson(item);
        final normalized = _normalizePhone(record.phone);
        if (normalized.isNotEmpty) {
          _cache[normalized] = record;
        }
      }
    } catch (_) {
      // keep caller-safe behavior if the local seed is unavailable.
    }
    _loaded = true;
  }
}
