import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import 'backend_bridge_session.dart';

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
  static const _restBase = '${SupabaseConfig.url}/rest/v1';

  Future<BackendBridgeSession> _session() async {
    try {
      return await ensureBackendBridgeSession();
    } catch (_) {
      throw const FpcProcurementException(
        'Login as FPC before receiving product.',
      );
    }
  }

  Map<String, String> _headers(String token, {bool jsonBody = false}) {
    return {
      'apikey': SupabaseConfig.anonKey,
      'Authorization': 'Bearer $token',
      if (jsonBody) 'Content-Type': 'application/json',
    };
  }

  Future<List<FpcProcurementRecord>> fetchRecords() async {
    final session = await _session();
    final uri = Uri.parse(
      '$_restBase/fpc_procurement_records'
      '?select=*&fpc_id=eq.${Uri.encodeQueryComponent(session.userId)}'
      '&order=received_at.desc&limit=100',
    );
    final response = await http
        .get(uri, headers: _headers(session.accessToken))
        .timeout(const Duration(seconds: 25));
    final rows = _decodeList(response);
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
    final session = await _session();
    final userId = session.userId;
    final batchId = _text(trace, 'batchId');
    if (batchId.isEmpty) {
      throw const FpcProcurementException(
        'Harvest QR is missing batch ID. Generate the harvest QR again.',
      );
    }
    final quantity = _toDouble(trace['totalKg']);
    final totalValue = quantity != null && pricePerKg != null
        ? quantity * pricePerKg
        : null;
    final analysisId = _uuidOrNull(_text(trace, 'analysisId'));
    final payload = {
      'fpc_id': userId,
      'farmer_id': _text(trace, 'farmerId'),
      'farm_id': _text(trace, 'farmId'),
      'analysis_id': analysisId,
      'batch_id': batchId,
      'customer_name': _text(
        trace,
        'farmerName',
        _text(trace, 'fpcCustomerName'),
      ),
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

    final existing = await _existingRecord(session, batchId);
    final response = existing == null
        ? await http
              .post(
                Uri.parse('$_restBase/fpc_procurement_records'),
                headers: {
                  ..._headers(session.accessToken, jsonBody: true),
                  'Prefer': 'return=representation',
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 25))
        : await http
              .patch(
                Uri.parse(
                  '$_restBase/fpc_procurement_records?id=eq.${Uri.encodeQueryComponent(existing)}',
                ),
                headers: {
                  ..._headers(session.accessToken, jsonBody: true),
                  'Prefer': 'return=representation',
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 25));
    final rows = _decodeList(response);
    if (rows.isEmpty) {
      throw const FpcProcurementException('Received lot was not saved.');
    }
    return FpcProcurementRecord.fromJson(rows.first);
  }

  Future<String?> _existingRecord(
    BackendBridgeSession session,
    String batchId,
  ) async {
    if (batchId.isEmpty) return null;
    final uri = Uri.parse(
      '$_restBase/fpc_procurement_records'
      '?select=id&fpc_id=eq.${Uri.encodeQueryComponent(session.userId)}'
      '&batch_id=eq.${Uri.encodeQueryComponent(batchId)}&limit=1',
    );
    final response = await http
        .get(uri, headers: _headers(session.accessToken))
        .timeout(const Duration(seconds: 20));
    final rows = _decodeList(response);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return '${row['id'] ?? ''}'.trim().isEmpty ? null : '${row['id']}';
  }

  List<Map<String, dynamic>> _decodeList(http.Response response) {
    dynamic body;
    try {
      body = response.body.isEmpty ? <dynamic>[] : jsonDecode(response.body);
    } catch (_) {
      body = response.body;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is List) {
        return body
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
      }
      return const [];
    }
    final message = body is Map
        ? '${body['message'] ?? body['error'] ?? 'HTTP ${response.statusCode}'}'
        : body is String && body.isNotEmpty
        ? body
        : 'HTTP ${response.statusCode}';
    throw FpcProcurementException(message);
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
