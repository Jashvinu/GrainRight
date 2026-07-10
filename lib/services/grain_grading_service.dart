import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../controllers/auth_controller.dart';
import '../models/grading/crop_option.dart';
import '../models/grading/grade_result.dart';
import 'backend_bridge_session.dart';

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

class MoistureOcrResult {
  final String? imagePath;
  final double? percent;
  final String source;
  final double? confidence;

  const MoistureOcrResult({
    this.imagePath,
    this.percent,
    this.source = 'unknown',
    this.confidence,
  });

  factory MoistureOcrResult.fromJson(
    Map<String, dynamic> json, {
    String? imagePath,
  }) {
    final moisture = json['moisture'];
    final row = moisture is Map<String, dynamic> ? moisture : json;
    return MoistureOcrResult(
      imagePath: imagePath ?? '${json['moisture_image_path'] ?? ''}'.trim(),
      percent: _toNullableDouble(
        row['percent'] ??
            row['percent_estimate'] ??
            row['machine_percent'] ??
            row['manual_moisture_percent'],
      ),
      source: '${row['source'] ?? 'unknown'}',
      confidence: _toNullableDouble(row['confidence'] ?? row['ocr_confidence']),
    );
  }
}

class GradingReviewJob {
  final String id;
  final String batchId;
  final String farmerId;
  final String farmId;
  final String cropType;
  final String variety;
  final String reviewStatus;
  final String status;
  final String? finalGrade;
  final double? finalScore;
  final double? moisturePercent;
  final String moistureRisk;
  final String errorMessage;
  final DateTime? createdAt;

  const GradingReviewJob({
    required this.id,
    required this.batchId,
    required this.farmerId,
    required this.farmId,
    required this.cropType,
    required this.variety,
    required this.reviewStatus,
    required this.status,
    this.finalGrade,
    this.finalScore,
    this.moisturePercent,
    this.moistureRisk = '',
    this.errorMessage = '',
    this.createdAt,
  });

  factory GradingReviewJob.fromJson(Map<String, dynamic> json) {
    return GradingReviewJob(
      id: '${json['id'] ?? ''}',
      batchId: '${json['batch_id'] ?? ''}',
      farmerId: '${json['farmer_id'] ?? ''}',
      farmId: '${json['farm_id'] ?? ''}',
      cropType: '${json['crop_type'] ?? ''}',
      variety: '${json['variety'] ?? ''}',
      reviewStatus: '${json['review_status'] ?? 'pending'}',
      status: '${json['status'] ?? ''}',
      finalGrade: json['final_grade']?.toString(),
      finalScore: _toNullableDouble(json['final_score']),
      moisturePercent: _toNullableDouble(json['moisture_percent']),
      moistureRisk: '${json['moisture_risk'] ?? ''}',
      errorMessage: '${json['error_message'] ?? ''}',
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
    );
  }
}

double? _toNullableDouble(dynamic raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

/// Client for the Supabase-hosted grain-grading backend.
///
/// Grading lives entirely in Supabase (matching the app's other AI): images go
/// to private Storage buckets, then the `grain-grade` Edge Function signs them,
/// runs Qwen-VL + the ragi rule engine, and returns the result inline.
/// See docs/11_grain_grading_integration.md.
class GrainGradingService {
  GrainGradingService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  SupabaseClient get _supabase => Supabase.instance.client;

  String? get _uid {
    final backendUserId = Get.isRegistered<AuthController>()
        ? Get.find<AuthController>().currentUser.value?.id.trim()
        : null;
    if (backendUserId != null && backendUserId.isNotEmpty) {
      return backendUserId;
    }
    return _supabase.auth.currentUser?.id;
  }

  String? get _jwt {
    final backendToken = Get.isRegistered<AuthController>()
        ? Get.find<AuthController>().accessToken.value.trim()
        : null;
    if (backendToken != null && backendToken.isNotEmpty) return backendToken;
    return _supabase.auth.currentSession?.accessToken;
  }

  /// Grading requires an authenticated backend session so uploads satisfy RLS.
  bool get isConfigured => _uid != null && (_jwt?.isNotEmpty ?? false);

  Map<String, String> _functionHeaders() => {
    'Content-Type': 'application/json',
    'apikey': SupabaseConfig.anonKey,
    'Authorization': 'Bearer ${_jwt ?? SupabaseConfig.anonKey}',
  };

  void _ensureConfigured() {
    if (_uid == null) {
      throw GradingException('Sign in to grade grain.', notConfigured: true);
    }
    if (_jwt == null || _jwt!.isEmpty) {
      throw GradingException('Your session expired. Please login again.');
    }
  }

  /// Crop + variety catalog from the `grain-crops` Edge Function.
  Future<List<CropOption>> fetchCrops() async {
    await ensureBackendBridgeSession();
    final body = await _invoke('grain-crops', method: 'GET');
    final crops = body['crops'];
    if (crops is! List) return const [];
    return crops
        .whereType<Map<String, dynamic>>()
        .map(CropOption.fromJson)
        .toList();
  }

  /// Upload/read the moisture meter before the grain image is captured.
  Future<MoistureOcrResult> readMoisture({
    Uint8List? moistureImageBytes,
    String moistureImageName = 'moisture.jpg',
    double? manualMoisturePercent,
  }) async {
    await ensureBackendBridgeSession();
    _ensureConfigured();
    if (moistureImageBytes == null && manualMoisturePercent == null) {
      throw GradingException(
        'Provide a moisture-meter photo or a moisture reading.',
      );
    }

    if (moistureImageBytes == null) {
      return MoistureOcrResult(
        percent: manualMoisturePercent,
        source: 'manual',
        confidence: 1,
      );
    }

    final path = await _uploadImage(
      'moisture-images',
      moistureImageBytes,
      fileName: moistureImageName,
    );
    final body = await _invoke(
      'grain-moisture-ocr',
      payload: {
        'moisture_image_path': path,
        // ignore: use_null_aware_elements
        if (manualMoisturePercent != null)
          'manual_moisture_percent': manualMoisturePercent,
      },
    );
    return MoistureOcrResult.fromJson(body, imagePath: path);
  }

  /// Upload the photos to Storage, then call `grain-grade`.
  Future<GradeResult> analyze({
    required Uint8List grainImageBytes,
    String grainImageName = 'grain.jpg',
    Uint8List? moistureImageBytes,
    String moistureImageName = 'moisture.jpg',
    String? moistureImagePath,
    double? manualMoisturePercent,
    required String cropType,
    String cropVariety = '',
    String? farmerId,
    String? farmId,
    String? batchId,
    double? bagSizeKg,
    int? bagCount,
    String actorRole = 'farmer',
    String? fpcCustomerId,
    String? fpcCustomerName,
    String source = 'app',
    int confidenceThreshold = 60,
  }) async {
    await ensureBackendBridgeSession();
    _ensureConfigured();
    if (moistureImageBytes == null &&
        moistureImagePath == null &&
        manualMoisturePercent == null) {
      throw GradingException(
        'Provide a moisture-meter photo or a moisture reading.',
      );
    }

    final grainPath = await _uploadImage(
      'grain-images',
      grainImageBytes,
      fileName: grainImageName,
    );
    String? moisturePath = moistureImagePath;
    if (moisturePath == null && moistureImageBytes != null) {
      moisturePath = await _uploadImage(
        'moisture-images',
        moistureImageBytes,
        fileName: moistureImageName,
      );
    }

    final payload = <String, dynamic>{
      'grain_image_path': grainPath,
      'crop_type': cropType,
      'crop_variety': cropVariety,
      'confidence_threshold': confidenceThreshold,
      'operator_id': _uid,
      'actor_role': actorRole.trim().isEmpty ? 'farmer' : actorRole.trim(),
      'source': source.trim().isEmpty ? 'app' : source.trim(),
      if (farmerId != null && farmerId.trim().isNotEmpty)
        'farmer_id': farmerId.trim(),
      if (farmId != null && farmId.trim().isNotEmpty) 'farm_id': farmId.trim(),
      if (fpcCustomerId != null && fpcCustomerId.trim().isNotEmpty)
        'fpc_customer_id': fpcCustomerId.trim(),
      if (fpcCustomerName != null && fpcCustomerName.trim().isNotEmpty)
        'fpc_customer_name': fpcCustomerName.trim(),
      if (batchId != null && batchId.trim().isNotEmpty)
        'batch_id': batchId.trim(),
      // ignore: use_null_aware_elements
      if (bagSizeKg != null) 'bag_size_kg': bagSizeKg,
      // ignore: use_null_aware_elements
      if (bagCount != null) 'bag_count': bagCount,
    };
    if (moisturePath != null) {
      payload['moisture_image_path'] = moisturePath;
    }
    if (manualMoisturePercent != null) {
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
    await ensureBackendBridgeSession();
    _ensureConfigured();
    await _invoke(
      'grain-grade-feedback',
      payload: {
        'analysis_id': analysisId,
        'true_grade': trueGrade,
        'true_moisture_risk': trueMoistureRisk.apiValue,
        'notes': notes,
        'operator_id': _uid,
      },
    );
  }

  // ─── internals ─────────────────────────────────────────────────────────────

  /// Uploads bytes to a private bucket under `{uid}/{ts}.{ext}` (satisfies the
  /// per-user storage RLS) and returns the object path.
  Future<String> _uploadImage(
    String bucket,
    Uint8List bytes, {
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw GradingException('The selected photo is empty. Please retake it.');
    }
    final kind = _detectImageKind(bytes, fileName);
    final path =
        '${_uid!}/${DateTime.now().microsecondsSinceEpoch}-${_safeFileStem(fileName)}.${kind.extension}';
    final uri = Uri.parse(
      '${SupabaseConfig.url}/storage/v1/object/$bucket/$path',
    );
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'apikey': SupabaseConfig.anonKey,
              'Authorization': 'Bearer $_jwt',
              'Content-Type': kind.contentType,
              'x-upsert': 'false',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 && response.statusCode != 201) {
        if (kDebugMode) {
          debugPrint(
            'Grain upload failed: bucket=$bucket status=${response.statusCode} body=${response.body}',
          );
        }
        throw GradingException(
          _uploadErrorMessage(response.statusCode, response.body),
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

  Future<List<GradingReviewJob>> fetchReviewJobs() async {
    await ensureBackendBridgeSession();
    _ensureConfigured();
    final uri = Uri.parse(
      '${SupabaseConfig.url}/rest/v1/analysis_jobs'
      '?select=*'
      '&or=(review_status.in.(pending,recapture_requested),status.eq.failed)'
      '&order=created_at.desc'
      '&limit=100',
    );
    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'apikey': SupabaseConfig.anonKey,
              'Authorization': 'Bearer $_jwt',
            },
          )
          .timeout(const Duration(seconds: 30));
      final decoded = _decodeRestList(response);
      return decoded.map(GradingReviewJob.fromJson).toList(growable: false);
    } on GradingException {
      rethrow;
    } catch (e) {
      throw GradingException('Could not load grading review jobs. $e');
    }
  }

  Future<void> updateReviewJob({
    required String analysisId,
    required String reviewStatus,
    String notes = '',
  }) async {
    await ensureBackendBridgeSession();
    _ensureConfigured();
    final uri = Uri.parse(
      '${SupabaseConfig.url}/rest/v1/analysis_jobs?id=eq.$analysisId',
    );
    final userId = _uid;
    try {
      final response = await _client
          .patch(
            uri,
            headers: {
              'apikey': SupabaseConfig.anonKey,
              'Authorization': 'Bearer $_jwt',
              'Content-Type': 'application/json',
              'Prefer': 'return=minimal',
            },
            body: jsonEncode({
              'review_status': reviewStatus,
              'reviewed_by': userId,
              'reviewed_at': DateTime.now().toUtc().toIso8601String(),
              'review_notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GradingException(
          _extractError(response.body) ?? 'Could not update review job.',
          statusCode: response.statusCode,
        );
      }
    } on GradingException {
      rethrow;
    } catch (e) {
      throw GradingException('Could not update review job. $e');
    }
  }

  _ImageKind _detectImageKind(Uint8List bytes, String fileName) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return const _ImageKind('jpg', 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return const _ImageKind('png', 'image/png');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return const _ImageKind('webp', 'image/webp');
    }

    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return const _ImageKind('jpg', 'image/jpeg');
    }
    if (lower.endsWith('.png')) return const _ImageKind('png', 'image/png');
    if (lower.endsWith('.webp')) return const _ImageKind('webp', 'image/webp');
    throw GradingException(
      'Unsupported image type. Please use a JPG, PNG, or WebP photo.',
    );
  }

  String _safeFileStem(String fileName) {
    final raw = fileName.split(RegExp(r'[\\/]')).last;
    final withoutExt = raw.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final safe = withoutExt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return safe.isEmpty ? 'photo' : safe;
  }

  String _uploadErrorMessage(int statusCode, String body) {
    final detail = _extractError(body);
    switch (statusCode) {
      case 401:
        return 'Please login again before grading.';
      case 403:
        return 'Photo upload was blocked by storage permissions. Please login again.';
      case 404:
        return 'Grading photo storage is not configured. Missing bucket: grain-images or moisture-images.';
      case 409:
        return 'A photo with this name already exists. Please try again.';
      case 413:
        return 'The photo is too large. Retake it or choose a smaller image.';
      case 415:
        return 'Unsupported image type. Please use a JPG, PNG, or WebP photo.';
      default:
        return detail == null || detail.isEmpty
            ? 'Could not upload the photo. Please try again.'
            : 'Could not upload the photo: $detail';
    }
  }

  String? _extractError(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return (decoded['message'] ??
                decoded['error'] ??
                decoded['error_description'] ??
                decoded['msg'])
            ?.toString();
      }
    } catch (_) {
      // Keep the raw response below for non-JSON Supabase errors.
    }
    return body.length > 160 ? '${body.substring(0, 160)}...' : body;
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
                .post(
                  uri,
                  headers: _functionHeaders(),
                  body: jsonEncode(payload ?? {}),
                )
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
      body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
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

  List<Map<String, dynamic>> _decodeRestList(http.Response response) {
    dynamic body;
    try {
      body = response.body.isEmpty ? <dynamic>[] : jsonDecode(response.body);
    } catch (_) {
      body = <dynamic>[];
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
    throw GradingException(
      _extractError(response.body) ?? 'HTTP ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  void dispose() => _client.close();
}

class _ImageKind {
  final String extension;
  final String contentType;

  const _ImageKind(this.extension, this.contentType);
}
