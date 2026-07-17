import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class FpcProcurementException implements Exception {
  final String message;

  const FpcProcurementException(this.message);

  @override
  String toString() => message;
}

class FpcProcurementRecord {
  final String id;
  final String batchId;
  final String farmerId;
  final String farmId;
  final String customerName;
  final String cropType;
  final String variety;
  final double? quantityKg;
  final String grade;
  final double? pricePerKg;
  final double? totalValue;
  final String deliveryStatus;
  final int? fpcRating;
  final DateTime? receivedAt;
  final Map<String, dynamic> tracePayload;

  const FpcProcurementRecord({
    required this.id,
    required this.batchId,
    required this.farmerId,
    required this.farmId,
    required this.customerName,
    required this.cropType,
    required this.variety,
    this.quantityKg,
    required this.grade,
    this.pricePerKg,
    this.totalValue,
    required this.deliveryStatus,
    this.fpcRating,
    this.receivedAt,
    this.tracePayload = const {},
  });

  factory FpcProcurementRecord.fromJson(Map<String, dynamic> json) {
    return FpcProcurementRecord(
      id: '${json['id'] ?? ''}',
      batchId: '${json['batch_id'] ?? ''}',
      farmerId: '${json['farmer_id'] ?? ''}',
      farmId: '${json['farm_id'] ?? ''}',
      customerName: '${json['customer_name'] ?? ''}',
      cropType: '${json['crop_type'] ?? ''}',
      variety: '${json['variety'] ?? ''}',
      quantityKg: _toDouble(json['quantity_kg']),
      grade: '${json['grade'] ?? ''}',
      pricePerKg: _toDouble(json['price_per_kg']),
      totalValue: _toDouble(json['total_value']),
      deliveryStatus: '${json['delivery_status'] ?? 'received'}',
      fpcRating: _toInt(json['fpc_rating']),
      receivedAt: DateTime.tryParse(
        '${json['received_at'] ?? json['created_at'] ?? ''}',
      ),
      tracePayload: _toMap(json['trace_payload']),
    );
  }
}

class HarvestTraceParser {
  static Map<String, dynamic> parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FpcProcurementException('Scan a valid harvest QR first.');
    }
    if (value.startsWith('{')) {
      return ensureHarvestTrace(_decodeJson(value));
    }

    final token = _extractTraceToken(value);
    if (token.isEmpty) {
      throw const FpcProcurementException(
        'This is not a harvest trace QR. Use the farmer scanner for farmer profile QR.',
      );
    }
    final normalized = _padBase64(token);
    try {
      return ensureHarvestTrace(
        _decodeJson(utf8.decode(base64Url.decode(normalized))),
      );
    } on FpcProcurementException {
      rethrow;
    } catch (_) {
      throw const FpcProcurementException('Harvest QR payload is invalid.');
    }
  }

  static Map<String, dynamic> ensureHarvestTrace(Map<String, dynamic> payload) {
    if (_text(payload, 'type') == 'farmer_profile') {
      throw const FpcProcurementException(
        'This is a farmer profile QR. Use the farmer scanner for farmer profile QR.',
      );
    }
    if (_text(payload, 'brand') != 'Kalsubai Farms' ||
        _text(payload, 'traceType') != 'harvest' ||
        _toInt(payload['traceVersion']) != 2) {
      throw const FpcProcurementException(
        'This is not an original Kalsubai harvest QR.',
      );
    }
    const requiredFields = [
      'analysisId',
      'batchId',
      'farm',
      'farmId',
      'farmerId',
      'farmerName',
      'crop',
      'grade',
      'score',
      'bagSizeKg',
      'bagCount',
      'totalKg',
      'moisture',
    ];
    final missing = requiredFields
        .where((field) => _isBlankTraceValue(payload[field]))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw const FpcProcurementException(
        'Harvest QR is missing required production data. Generate it again from the app.',
      );
    }
    final batchId = _text(payload, 'batchId');
    final reviewStatus = _text(payload, 'reviewStatus').toLowerCase();
    if (batchId == 'KF-HV-20260606-001' ||
        reviewStatus == 'pending' ||
        reviewStatus == 'missing') {
      throw const FpcProcurementException(
        'This harvest QR is not ready for FPC receiving. Generate the final approved QR.',
      );
    }
    return payload;
  }

  static Map<String, dynamic> _decodeJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const FpcProcurementException('Harvest QR payload is invalid.');
    }
    throw const FpcProcurementException('Harvest QR payload is invalid.');
  }

  static String _extractTraceToken(String value) {
    final urlMatch = RegExp(r'(?:#\/|\/)trace\/([^\/?#]+)').firstMatch(value);
    if (urlMatch != null) return urlMatch.group(1) ?? '';
    if (!value.contains('/') && !value.contains(':')) return value;
    return '';
  }

  static String _padBase64(String value) {
    final remainder = value.length % 4;
    if (remainder == 0) return value;
    return value.padRight(value.length + 4 - remainder, '=');
  }
}

class FarmerProfileQrParser {
  static Map<String, dynamic> parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FpcProcurementException('Scan a valid farmer QR first.');
    }
    final decoded = _decodeJson(value);
    if (_text(decoded, 'type') != 'farmer_profile' ||
        _text(decoded, 'allowedRole') != 'fpo_fpc' ||
        _text(decoded, 'brand') != 'Kalsubai Farms' ||
        _text(decoded, 'source') != 'remote_supabase' ||
        decoded['verified'] != true) {
      throw const FpcProcurementException(
        'This is not an original Kalsubai farmer QR.',
      );
    }
    const requiredFields = [
      'farmerId',
      'farmerName',
      'phone',
      'village',
      'primaryFarm',
      'crop',
    ];
    final missing = requiredFields
        .where((field) => _isBlankTraceValue(decoded[field]))
        .toList(growable: false);
    if (missing.isNotEmpty || !_isValidPhone(_text(decoded, 'phone'))) {
      throw const FpcProcurementException(
        'Farmer QR is missing verified farmer details. Open the farmer profile and generate it again.',
      );
    }
    return decoded;
  }

  static Map<String, dynamic> _decodeJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const FpcProcurementException('Farmer QR payload is invalid.');
    }
    throw const FpcProcurementException('Farmer QR payload is invalid.');
  }
}

class FpcProcurementService {
  SupabaseClient get _client => Supabase.instance.client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null || id.isEmpty) {
      throw const FpcProcurementException(
        'Login as FPC before receiving product.',
      );
    }
    return id;
  }

  Future<List<FpcProcurementRecord>> fetchRecords() async {
    final rows = await _client
        .from('fpc_procurement_records')
        .select()
        .eq('fpc_id', _uid)
        .order('received_at', ascending: false)
        .limit(100);
    return rows
        .whereType<Map>()
        .map(
          (row) =>
              FpcProcurementRecord.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<FpcProcurementRecord> saveHarvestTrace({
    required Map<String, dynamic> trace,
    double? pricePerKg,
    int? fpcRating,
    String notes = '',
  }) async {
    final strictTrace = HarvestTraceParser.ensureHarvestTrace(trace);
    final userId = _uid;
    final batchId = _text(strictTrace, 'batchId');
    if (batchId.isEmpty) {
      throw const FpcProcurementException(
        'Harvest QR is missing batch ID. Generate the harvest QR again.',
      );
    }
    final quantity = _toDouble(strictTrace['totalKg']);
    final totalValue = quantity != null && pricePerKg != null
        ? quantity * pricePerKg
        : null;
    final analysisId = _uuidOrNull(_text(strictTrace, 'analysisId'));
    final payload = {
      'fpc_id': userId,
      'farmer_id': _text(strictTrace, 'farmerId'),
      'farm_id': _text(strictTrace, 'farmId'),
      'analysis_id': analysisId,
      'batch_id': batchId,
      'customer_name': _text(
        strictTrace,
        'farmerName',
        _text(strictTrace, 'fpcCustomerName'),
      ),
      'crop_type': _text(strictTrace, 'crop'),
      'variety': _text(strictTrace, 'variety'),
      'quantity_kg': quantity,
      'grade': _text(strictTrace, 'grade'),
      'price_per_kg': pricePerKg,
      'total_value': totalValue,
      'delivery_status': 'received',
      'fpc_rating': fpcRating,
      'rating_notes': notes,
      'trace_payload': strictTrace,
      'received_at': DateTime.now().toUtc().toIso8601String(),
    };

    final existing = await _existingRecord(userId, batchId);
    final saved = existing == null
        ? await _client
              .from('fpc_procurement_records')
              .insert(payload)
              .select()
              .single()
        : await _client
              .from('fpc_procurement_records')
              .update(payload)
              .eq('id', existing)
              .select()
              .single();
    return FpcProcurementRecord.fromJson(
      Map<String, dynamic>.from(saved as Map),
    );
  }

  Future<String?> _existingRecord(String userId, String batchId) async {
    if (batchId.isEmpty) return null;
    final rows = await _client
        .from('fpc_procurement_records')
        .select('id')
        .eq('fpc_id', userId)
        .eq('batch_id', batchId)
        .limit(1);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    return '${row['id'] ?? ''}'.trim().isEmpty ? null : '${row['id']}';
  }
}

String _text(Map<String, dynamic> source, String key, [String fallback = '']) {
  final value = source[key];
  final text = value == null ? '' : '$value'.trim();
  if (text.isEmpty || text == '--' || text.toLowerCase() == 'unknown') {
    return fallback;
  }
  return text;
}

double? _toDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  final text = raw == null ? '' : '$raw';
  final match = RegExp(r'-?\d+(\.\d+)?').firstMatch(text);
  return match == null ? null : double.tryParse(match.group(0)!);
}

int? _toInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return int.tryParse('${raw ?? ''}');
}

bool _isBlankTraceValue(Object? raw) {
  final text = raw == null ? '' : '$raw'.trim();
  if (text.isEmpty || text == '--') return true;
  final normalized = text.toLowerCase();
  return normalized == 'unknown' ||
      normalized == 'pending' ||
      normalized == 'null';
}

bool _isValidPhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return RegExp(r'^[6-9][0-9]{9}$').hasMatch(digits);
}

Map<String, dynamic> _toMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}

String? _uuidOrNull(String value) {
  final trimmed = value.trim();
  final isUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(trimmed);
  return isUuid ? trimmed : null;
}
