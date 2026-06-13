import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/grading/crop_option.dart';
import '../models/grading/grade_result.dart';

/// Raised by [GrainGradingService] for any non-success path so the UI can show
/// a single, localized error/empty state.
class GradingException implements Exception {
  final String message;
  final int? statusCode;
  final bool notConfigured;

  GradingException(this.message, {this.statusCode, this.notConfigured = false});

  @override
  String toString() => 'GradingException($statusCode): $message';
}

/// Client for the Supabase-hosted grain-grading backend.
///
/// Grading lives entirely in Supabase (matching the app's other AI): images go
/// to private Storage buckets, then the `grain-grade` Edge Function signs them,
/// runs Qwen-VL + the ragi rule engine, and returns the result inline.
/// See docs/11_grain_grading_integration.md.
class GrainGradingService {
  GrainGradingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  SupabaseClient get _supabase => Supabase.instance.client;

  String? get _uid => _supabase.auth.currentUser?.id;

  String? get _jwt => _supabase.auth.currentSession?.accessToken;

  /// Grading requires an authenticated (or guest) Supabase session so uploads
  /// satisfy the per-user storage RLS.
  bool get isConfigured => _uid != null;

  Map<String, String> _functionHeaders() => {
        'Content-Type': 'application/json',
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${_jwt ?? SupabaseConfig.anonKey}',
      };

  void _ensureConfigured() {
    if (!isConfigured) {
      throw GradingException(
        'Sign in to grade grain.',
        notConfigured: true,
      );
    }
  }

  /// Crop + variety catalog from the `grain-crops` Edge Function.
  Future<List<CropOption>> fetchCrops() async {
    final body = await _invoke('grain-crops', method: 'GET');
    final crops = body['crops'];
    if (crops is! List) return const [];
    return crops
        .whereType<Map<String, dynamic>>()
        .map(CropOption.fromJson)
        .toList();
  }

  /// Upload the photos to Storage, then call `grain-grade`.
  Future<GradeResult> analyze({
    required Uint8List grainImageBytes,
    String grainImageName = 'grain.jpg',
    Uint8List? moistureImageBytes,
    String moistureImageName = 'moisture.jpg',
    double? manualMoisturePercent,
    required String cropType,
    String cropVariety = '',
    int confidenceThreshold = 60,
  }) async {
    _ensureConfigured();
    if (moistureImageBytes == null && manualMoisturePercent == null) {
      throw GradingException('Provide a moisture-meter photo or a moisture reading.');
    }

    final grainPath = await _uploadImage('grain-images', grainImageBytes);
    String? moisturePath;
    if (moistureImageBytes != null) {
      moisturePath = await _uploadImage('moisture-images', moistureImageBytes);
    }

    final payload = <String, dynamic>{
      'grain_image_path': grainPath,
      'crop_type': cropType,
      'crop_variety': cropVariety,
      'confidence_threshold': confidenceThreshold,
      'operator_id': _uid,
    };
    if (moisturePath != null) {
      payload['moisture_image_path'] = moisturePath;
    } else if (manualMoisturePercent != null) {
      payload['manual_moisture_percent'] = manualMoisturePercent;
    }

    final body = await _invoke('grain-grade', payload: payload);
    return GradeResult.fromJson(body);
  }

  /// Submit an operator correction via `grain-grade-feedback`.
  Future<void> submitFeedback({
    required String analysisId,
    required String trueGrade, // A | B | C
    required MoistureRisk trueMoistureRisk,
    String notes = '',
  }) async {
    _ensureConfigured();
    await _invoke('grain-grade-feedback', payload: {
      'analysis_id': analysisId,
      'true_grade': trueGrade,
      'true_moisture_risk': trueMoistureRisk.apiValue,
      'notes': notes,
      'operator_id': _uid,
    });
  }

  // ─── internals ─────────────────────────────────────────────────────────────

  /// Uploads bytes to a private bucket under `{uid}/{ts}.jpg` (satisfies the
  /// per-user storage RLS) and returns the object path.
  Future<String> _uploadImage(String bucket, Uint8List bytes) async {
    final path = '${_uid!}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final uri = Uri.parse('${SupabaseConfig.url}/storage/v1/object/$bucket/$path');
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'apikey': SupabaseConfig.anonKey,
              'Authorization': 'Bearer ${_jwt ?? SupabaseConfig.anonKey}',
              'Content-Type': 'image/jpeg',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw GradingException(
          'Could not upload the photo.',
          statusCode: response.statusCode,
        );
      }
      return path;
    } on GradingException {
      rethrow;
    } catch (e) {
      throw GradingException('Could not reach the grading service. $e');
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String function, {
    String method = 'POST',
    Map<String, dynamic>? payload,
  }) async {
    final uri = Uri.parse('${SupabaseConfig.edgeFunctionsBase}/$function');
    try {
      final response = method == 'GET'
          ? await _client
              .get(uri, headers: _functionHeaders())
              .timeout(const Duration(seconds: 30))
          : await _client
              .post(uri, headers: _functionHeaders(), body: jsonEncode(payload ?? {}))
              .timeout(const Duration(seconds: 90));
      return _decode(response);
    } on GradingException {
      rethrow;
    } catch (e) {
      throw GradingException('Could not reach the grading service. $e');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic body;
    try {
      body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    } catch (_) {
      body = <String, dynamic>{};
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is Map<String, dynamic> && body['success'] == false) {
        throw GradingException(
          body['error']?.toString() ?? 'Request failed.',
          statusCode: response.statusCode,
        );
      }
      return body is Map<String, dynamic> ? body : <String, dynamic>{};
    }
    final message = body is Map
        ? (body['error'] ?? body['detail'] ?? 'HTTP ${response.statusCode}')
        : 'HTTP ${response.statusCode}';
    throw GradingException(message.toString(), statusCode: response.statusCode);
  }

  void dispose() => _client.close();
}
