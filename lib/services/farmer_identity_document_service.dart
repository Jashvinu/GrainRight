import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class FarmerIdentityDocumentException implements Exception {
  final String message;
  final int? statusCode;

  const FarmerIdentityDocumentException(this.message, {this.statusCode});

  @override
  String toString() => 'FarmerIdentityDocumentException($statusCode): $message';
}

class FarmerIdentityOcrResult {
  static const bucket = 'farmer-identity-documents';

  final String documentPath;
  final String farmerName;
  final String aadhaarNumber;
  final String agriRecordId;
  final double? confidence;
  final String source;
  final bool ocrFailed;

  const FarmerIdentityOcrResult({
    required this.documentPath,
    this.farmerName = '',
    this.aadhaarNumber = '',
    this.agriRecordId = '',
    this.confidence,
    this.source = 'document_ocr',
    this.ocrFailed = false,
  });

  String get aadhaarDigits => aadhaarNumber.replaceAll(RegExp(r'\D'), '');
  String get aadhaarLast4 => aadhaarDigits.length >= 4
      ? aadhaarDigits.substring(aadhaarDigits.length - 4)
      : '';
  String get aadhaarMasked =>
      aadhaarLast4.isEmpty ? '' : 'XXXX XXXX $aadhaarLast4';

  factory FarmerIdentityOcrResult.fromJson(
    Map<String, dynamic> json, {
    required String documentPath,
  }) {
    final root = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final identity = root['identity'];
    final row = identity is Map ? identity : root;
    return FarmerIdentityOcrResult(
      documentPath: '${root['document_path'] ?? documentPath}',
      farmerName: _firstText(row, const [
        'farmer_name',
        'farmerName',
        'name',
        'full_name',
        'nav',
      ]),
      aadhaarNumber: _firstText(row, const [
        'aadhaar_number',
        'aadhaar',
        'aadhar_number',
        'aadhar',
      ]),
      agriRecordId: _firstText(row, const [
        'agri_record_id',
        'farm_id',
        'farmer_id',
        'farmer_registry_id',
        'agristack_id',
        'government_farmer_id',
      ]),
      confidence: _toNullableDouble(row['confidence']),
      source: '${row['source'] ?? 'document_ocr'}'.trim(),
    );
  }
}

class FarmerIdentityDocumentService {
  FarmerIdentityDocumentService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  SupabaseClient get _supabase => Supabase.instance.client;

  String? get _uid => _supabase.auth.currentUser?.id;

  String? get _jwt => _supabase.auth.currentSession?.accessToken;

  bool get isConfigured => _uid != null && (_jwt?.isNotEmpty ?? false);

  Future<FarmerIdentityOcrResult> readDocument({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _ensureConfigured();
    if (bytes.isEmpty) {
      throw const FarmerIdentityDocumentException(
        'The selected document image is empty. Please retake it.',
      );
    }
    final kind = _detectImageKind(bytes, fileName);
    final path = _documentPath(fileName, kind);
    final uploadedPath = await _uploadImageWithFallback(
      bytes,
      fileName: fileName,
      path: path,
      kind: kind,
    );
    return _readUploadedDocument(uploadedPath);
  }

  Future<FarmerIdentityOcrResult> _readUploadedDocument(String path) async {
    try {
      final body = await _invoke(
        'farmer-document-ocr',
        payload: {'document_path': path},
      );
      return FarmerIdentityOcrResult.fromJson(body, documentPath: path);
    } catch (_) {
      return FarmerIdentityOcrResult(
        documentPath: path,
        source: 'manual_after_ocr_failure',
        ocrFailed: true,
      );
    }
  }

  void _ensureConfigured() {
    if (_uid == null || _jwt == null || _jwt!.isEmpty) {
      throw const FarmerIdentityDocumentException(
        'Start farmer signup before uploading the document.',
      );
    }
  }

  Map<String, String> _functionHeaders() => {
    'Content-Type': 'application/json',
    'apikey': SupabaseConfig.anonKey,
    'Authorization': 'Bearer $_jwt',
  };

  Future<String> _uploadImage(
    Uint8List bytes, {
    required String path,
    required _ImageKind kind,
  }) async {
    final uri = Uri.parse(
      '${SupabaseConfig.url}/storage/v1/object/${FarmerIdentityOcrResult.bucket}/$path',
    );
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
      throw FarmerIdentityDocumentException(
        _uploadErrorMessage(response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    }
    return path;
  }

  Future<String> _uploadImageWithFallback(
    Uint8List bytes, {
    required String fileName,
    required String path,
    required _ImageKind kind,
  }) async {
    try {
      return await _uploadImageViaFunction(
        bytes,
        fileName: fileName,
        path: path,
        kind: kind,
      );
    } on FarmerIdentityDocumentException catch (error) {
      try {
        return await _uploadImage(bytes, path: path, kind: kind);
      } on FarmerIdentityDocumentException catch (storageError) {
        if (_looksLikeBucketSetupIssue(error) ||
            _looksLikeBucketSetupIssue(storageError)) {
          throw const FarmerIdentityDocumentException(
            'Could not save the agri record document. Please retry.',
          );
        }
        rethrow;
      }
    }
  }

  Future<String> _uploadImageViaFunction(
    Uint8List bytes, {
    required String fileName,
    required String path,
    required _ImageKind kind,
  }) async {
    final body = await _invoke(
      'farmer-document-ocr',
      payload: {
        'upload_only': true,
        'document_path': path,
        'file_name': fileName,
        'content_type': kind.contentType,
        'image_base64': base64Encode(bytes),
      },
    );
    final root = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : body;
    final uploadedPath = '${root['document_path'] ?? path}'.trim();
    if (uploadedPath.isEmpty) {
      throw const FarmerIdentityDocumentException(
        'Could not upload the document. Please try again.',
      );
    }
    return uploadedPath;
  }

  bool _looksLikeBucketSetupIssue(FarmerIdentityDocumentException error) {
    final message = error.message.toLowerCase();
    return error.statusCode == 403 ||
        error.statusCode == 404 ||
        message.contains('bucket') ||
        message.contains('storage');
  }

  Future<Map<String, dynamic>> _invoke(
    String function, {
    required Map<String, dynamic> payload,
  }) async {
    final response = await _client
        .post(
          Uri.parse('${SupabaseConfig.edgeFunctionsBase}/$function'),
          headers: _functionHeaders(),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 45));
    final body = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FarmerIdentityDocumentException(
        _extractError(body) ?? 'Could not read the document image.',
        statusCode: response.statusCode,
      );
    }
    if (body['success'] == false) {
      throw FarmerIdentityDocumentException(
        '${body['error'] ?? 'Could not read the document image.'}',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  Map<String, dynamic> _decode(String raw) {
    if (raw.trim().isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {'data': decoded};
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
    throw const FarmerIdentityDocumentException(
      'Unsupported image type. Please use a JPG, PNG, or WebP photo.',
    );
  }

  String _documentPath(String fileName, _ImageKind kind) {
    return '$_uid/${DateTime.now().microsecondsSinceEpoch}-${_safeFileStem(fileName)}.${kind.extension}';
  }

  String _safeFileStem(String fileName) {
    final raw = fileName.split(RegExp(r'[\\/]')).last;
    final withoutExt = raw.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final safe = withoutExt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return safe.isEmpty ? 'agri-record' : safe;
  }

  String _uploadErrorMessage(int statusCode, String body) {
    final parsed = _tryDecode(body);
    final detail = _extractError(parsed);
    switch (statusCode) {
      case 401:
        return 'Session expired. Login again.';
      case 403:
        return 'Document upload was blocked. Login again and retry.';
      case 404:
        return 'Document storage is not configured.';
      case 409:
        return 'This document file already exists. Please retry.';
      case 413:
        return 'The document image is too large. Retake it or choose a smaller image.';
      case 415:
        return 'Unsupported image type. Please use a JPG, PNG, or WebP photo.';
      default:
        return detail == null || detail.isEmpty
            ? 'Could not upload the document. Please try again.'
            : 'Could not upload the document: $detail';
    }
  }

  Map<String, dynamic> _tryDecode(String body) {
    if (body.trim().isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {'message': body};
  }

  String? _extractError(Map<String, dynamic> body) {
    return (body['message'] ??
            body['error'] ??
            body['error_description'] ??
            body['msg'])
        ?.toString();
  }
}

class _ImageKind {
  final String extension;
  final String contentType;

  const _ImageKind(this.extension, this.contentType);
}

double? _toNullableDouble(dynamic raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

String _firstText(Map row, List<String> keys) {
  for (final key in keys) {
    final value = '${row[key] ?? ''}'.trim();
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}
