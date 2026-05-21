import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/satellite_config.dart';
import '../models/satellite/farm_model.dart';
import '../models/satellite/satellite_date_model.dart';
import '../models/satellite/index_tile_model.dart';
import '../models/satellite/timeline_entry_model.dart';
import '../models/satellite/diagnostics_model.dart';
import '../models/satellite/advanced_monitoring_model.dart';

class SatelliteApiException implements Exception {
  final String message;
  final int? statusCode;
  SatelliteApiException(this.message, {this.statusCode});

  @override
  String toString() => 'SatelliteApiException: $message';
}

class AuthResult {
  final String accessToken;
  final String? refreshToken;
  final String userId;
  final String email;

  const AuthResult({
    required this.accessToken,
    this.refreshToken,
    required this.userId,
    required this.email,
  });
}

class SatelliteService {
  Map<String, String> _headers(String? jwt) => {
    'Content-Type': 'application/json',
    'apikey': SatelliteConfig.anonKey,
    'Authorization': 'Bearer ${jwt ?? SatelliteConfig.anonKey}',
  };

  // ─── Retry wrappers ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String url, String? jwt) async {
    Exception? last;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: _headers(jwt))
            .timeout(const Duration(seconds: 30));
        return _parse(response);
      } on Exception catch (e) {
        last = e;
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
    throw last!;
  }

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body,
    String? jwt,
  ) async {
    Exception? last;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: _headers(jwt),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 60));
        return _parse(response);
      } on Exception catch (e) {
        last = e;
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
    throw last!;
  }

  Map<String, dynamic> _parse(http.Response response) {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is Map<String, dynamic>) {
        if (body['success'] == false) {
          throw SatelliteApiException(
            body['error'] as String? ?? 'Unknown error',
            statusCode: response.statusCode,
          );
        }
        return body;
      }
      return {'data': body};
    }
    final msg = body is Map
        ? (body['error'] ?? body['message'] ?? 'HTTP ${response.statusCode}')
        : 'HTTP ${response.statusCode}';
    throw SatelliteApiException(
      msg.toString(),
      statusCode: response.statusCode,
    );
  }

  // ─── Auth ──────────────────────────────────────────────────────────────────

  Future<AuthResult> signIn(String email, String password) async {
    final url = '${SatelliteConfig.authBase}/token?grant_type=password';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'apikey': SatelliteConfig.anonKey,
          },
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw SatelliteApiException(
        body['error_description'] as String? ??
            body['msg'] as String? ??
            'Login failed',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>? ?? {};
    return AuthResult(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String?,
      userId: user['id'] as String? ?? '',
      email: user['email'] as String? ?? email,
    );
  }

  Future<AuthResult> signUp(String email, String password) async {
    final url = '${SatelliteConfig.authBase}/signup';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'apikey': SatelliteConfig.anonKey,
          },
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = jsonDecode(response.body);
      throw SatelliteApiException(
        body['error_description'] as String? ??
            body['msg'] as String? ??
            'Signup failed',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    // Supabase signup may return the session directly or require email confirmation
    final session = data['session'] as Map<String, dynamic>?;
    final user = data['user'] as Map<String, dynamic>? ?? {};
    if (session == null) {
      // Email confirmation required — return partial result
      return AuthResult(
        accessToken: '',
        userId: user['id'] as String? ?? '',
        email: user['email'] as String? ?? email,
      );
    }
    return AuthResult(
      accessToken: session['access_token'] as String? ?? '',
      refreshToken: session['refresh_token'] as String?,
      userId: user['id'] as String? ?? '',
      email: user['email'] as String? ?? email,
    );
  }

  Future<AuthResult?> refreshToken(String refreshToken) async {
    final url = '${SatelliteConfig.authBase}/token?grant_type=refresh_token';
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'apikey': SatelliteConfig.anonKey,
            },
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>? ?? {};
      return AuthResult(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String?,
        userId: user['id'] as String? ?? '',
        email: user['email'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Farms ─────────────────────────────────────────────────────────────────

  Future<List<Farm>> getFarms(String jwt) async {
    final url =
        '${SatelliteConfig.restBase}/farms?select=id,name,geometry,bounds,area_hectares,user_id,created_at&order=created_at.desc';
    final response = await http
        .get(
          Uri.parse(url),
          headers: {..._headers(jwt), 'Prefer': 'return=representation'},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw SatelliteApiException(
        'Failed to load farms',
        statusCode: response.statusCode,
      );
    }
    final list = jsonDecode(response.body) as List;
    return list.map((e) => Farm.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Farm> insertFarm(Map<String, dynamic> farmJson, String jwt) async {
    final url = '${SatelliteConfig.restBase}/farms';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {..._headers(jwt), 'Prefer': 'return=representation'},
          body: jsonEncode(farmJson),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw SatelliteApiException(
        'Failed to save farm',
        statusCode: response.statusCode,
      );
    }
    final list = jsonDecode(response.body) as List;
    return Farm.fromJson(list.first as Map<String, dynamic>);
  }

  // ─── Edge Functions ─────────────────────────────────────────────────────────

  Future<List<SatelliteDate>> getAvailableDates(
    String farmId,
    String? jwt,
  ) async {
    final url =
        '${SatelliteConfig.edgeFunctionsBase}/get-available-dates?farm_id=$farmId&months=6';
    final data = await _get(url, jwt);
    final list = data['available_dates'] as List? ?? [];
    return list
        .map((e) => SatelliteDate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<IndexTileResult>> getAgriculturalIndex({
    required String index,
    required String start,
    required String end,
    required String farmId,
    String? jwt,
  }) async {
    final url =
        '${SatelliteConfig.edgeFunctionsBase}/agricultural-indices'
        '?index=$index&start=$start&end=$end&farm_id=$farmId';
    final data = await _get(url, jwt);
    final satellites = data['satellites'] as List? ?? [];
    return satellites
        .map((e) => IndexTileResult.fromJson(e as Map<String, dynamic>))
        .where((r) => r.urlFormat.isNotEmpty)
        .toList();
  }

  Future<List<TimelineEntry>> getFarmTimeline(
    String farmId,
    String? jwt,
  ) async {
    final url =
        '${SatelliteConfig.edgeFunctionsBase}/farm-timeline?farm_id=$farmId';
    final data = await _get(url, jwt);
    final timeline = data['timeline'] as Map<String, dynamic>? ?? {};
    final entries = <TimelineEntry>[];
    timeline.forEach((date, indexList) {
      if (indexList is List) {
        for (final item in indexList) {
          if (item is Map<String, dynamic>) {
            entries.add(
              TimelineEntry.fromJson({...item, 'observation_date': date}),
            );
          }
        }
      }
    });
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  Future<DiagnosticsResult> getDiagnostics({
    required String polygonJson,
    String? farmId,
    required List<String> indices,
    int days = 14,
    int cloud = 50,
    String? jwt,
  }) async {
    final encoded = Uri.encodeComponent(polygonJson);
    final indicesParam = indices.join(',');
    final farmParam = farmId == null || farmId.isEmpty
        ? ''
        : '&farm_id=${Uri.encodeComponent(farmId)}';
    final url =
        '${SatelliteConfig.edgeFunctionsBase}/diagnostics'
        '?polygon=$encoded$farmParam&indices=$indicesParam&days=$days&cloud=$cloud';
    final data = await _get(url, jwt);
    return DiagnosticsResult.fromJson(data);
  }

  Future<AdvancedMonitoringResult> postAdvancedMonitoring({
    required Map<String, dynamic> body,
    required String jwt,
  }) async {
    final url = '${SatelliteConfig.edgeFunctionsBase}/advanced-monitoring';
    final data = await _post(url, body, jwt);
    return AdvancedMonitoringResult.fromJson(data);
  }

  Future<void> syncSatelliteDates(String farmId, String? jwt) async {
    try {
      final url =
          '${SatelliteConfig.edgeFunctionsBase}/sync-satellite-dates?farm_id=$farmId';
      await http
          .get(Uri.parse(url), headers: _headers(jwt))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // Fire and forget — ignore errors
    }
  }
}
