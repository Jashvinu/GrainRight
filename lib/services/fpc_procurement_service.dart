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
      receivedAt: DateTime.tryParse('${json['received_at'] ?? json['created_at'] ?? ''}'),
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
      return _decodeJson(value);
    }

    final token = _extractTraceToken(value);
    if (token.isEmpty) {
      throw const FpcProcurementException(
        'This is not a harvest trace QR. Use the farmer scanner for farmer profile QR.',
      );
    }
    final normalized = _padBase64(token);
    try {
      return _decodeJson(utf8.decode(base64Url.decode(normalized)));
    } catch (_) {
      throw const FpcProcurementException('Harvest QR payload is invalid.');
    }
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

class FpcProcurementService {
  SupabaseClient get _client => Supabase.instance.client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null || id.isEmpty) {
      throw const FpcProcurementException('Login as FPC before receiving product.');
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
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => FpcProcurementRecord.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<FpcProcurementRecord> saveHarvestTrace({
    required Map<String, dynamic> trace,
    double? pricePerKg,
    int? fpcRating,
    String notes = '',
  }) async {
    final userId = _uid;
    final batchId = _text(trace, 'batchId');
    if (batchId.isEmpty) {
      throw const FpcProcurementException(
        'Harvest QR is missing batch ID. Generate the harvest QR again.',
      );
    }
    final quantity = _toDouble(trace['totalKg']);
    final totalValue = quantity != null && pricePerKg != null ? quantity * pricePerKg : null;
    final analysisId = _uuidOrNull(_text(trace, 'analysisId'));
    final payload = {
      'fpc_id': userId,
      'farmer_id': _text(trace, 'farmerId'),
      'farm_id': _text(trace, 'farmId'),
      'analysis_id': analysisId,
      'batch_id': batchId,
      'customer_name': _text(trace, 'farmerName', _text(trace, 'fpcCustomerName')),
      'crop_type': _text(trace, 'crop'),
      'variety': _text(trace, 'variety'),
      'quantity_kg': quantity,
      'grade': _text(trace, 'grade'),
      'price_per_kg': pricePerKg,
      'total_value': totalValue,
      'delivery_status': 'received',
      'fpc_rating': fpcRating,
      'rating_notes': notes,
      'trace_payload': trace,
      'received_at': DateTime.now().toUtc().toIso8601String(),
    };

    final existing = await _existingRecord(userId, batchId);
    final saved = existing == null
        ? await _client.from('fpc_procurement_records').insert(payload).select().single()
        : await _client
            .from('fpc_procurement_records')
            .update(payload)
            .eq('id', existing)
            .select()
            .single();
    return FpcProcurementRecord.fromJson(Map<String, dynamic>.from(saved as Map));
  }

  Future<String?> _existingRecord(String userId, String batchId) async {
    if (batchId.isEmpty) return null;
    final rows = await _client
        .from('fpc_procurement_records')
        .select('id')
        .eq('fpc_id', userId)
        .eq('batch_id', batchId)
        .limit(1);
    if (rows is! List || rows.isEmpty) return null;
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
