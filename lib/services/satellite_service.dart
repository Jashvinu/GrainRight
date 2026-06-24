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
import '../models/satellite/farm_alert_model.dart';
import '../models/satellite/farm_assistant_model.dart';
import '../models/satellite/farm_timeline_event_model.dart';
import '../models/satellite/farm_summary_model.dart';
import '../models/satellite/farm_weather_model.dart';

class SatelliteApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final String? details;
  SatelliteApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.details,
  });

  @override
  String toString() {
    final parts = [
      'SatelliteApiException',
      if (statusCode != null) '$statusCode',
      if (code != null && code!.isNotEmpty) code!,
      message,
      if (details != null && details!.isNotEmpty) details!,
    ];
    return parts.join(': ');
  }
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

class FarmerDiseaseData {
  final List<Map<String, dynamic>> scoutZones;
  final List<Map<String, dynamic>> riskCells;

  const FarmerDiseaseData({required this.scoutZones, required this.riskCells});
}

class SatelliteService {
  static const _farmSelect = '*';

  Map<String, String> _headers(String? jwt) {
    final bearer = jwt == null || jwt.trim().isEmpty
        ? SatelliteConfig.anonKey
        : jwt.trim();
    return {
      'Content-Type': 'application/json',
      'apikey': SatelliteConfig.anonKey,
      'Authorization': 'Bearer $bearer',
    };
  }

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
    String? jwt, {
    bool retryHttpErrors = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    Exception? last;
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(url),
              headers: _headers(jwt),
              body: jsonEncode(body),
            )
            .timeout(timeout);
        return _parse(response);
      } on SatelliteApiException catch (e) {
        last = e;
        final permanentHttpFailure =
            e.statusCode != null && e.statusCode! < 500;
        if (!retryHttpErrors || permanentHttpFailure) {
          rethrow;
        }
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 1 << attempt));
        }
      } on Exception catch (e) {
        last = e;
        if (!retryHttpErrors) {
          rethrow;
        }
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
    throw last!;
  }

  Map<String, dynamic> _parse(http.Response response) {
    final bodyText = response.body.trim();
    dynamic body;
    try {
      body = bodyText.isEmpty ? null : jsonDecode(bodyText);
    } catch (_) {
      body = bodyText;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is Map<String, dynamic>) {
        if (body['success'] == false) {
          throw SatelliteApiException(
            body['error'] as String? ?? 'Unknown error',
            statusCode: response.statusCode,
            code: body['code']?.toString(),
            details: body['details']?.toString(),
          );
        }
        return body;
      }
      return {'data': body};
    }
    final code = body is Map ? body['code']?.toString() : null;
    final details = body is Map ? body['details']?.toString() : null;
    final msg = body is Map
        ? (body['error'] ?? body['message'] ?? 'HTTP ${response.statusCode}')
        : body is String && body.isNotEmpty
        ? body
        : 'HTTP ${response.statusCode}';
    throw SatelliteApiException(
      msg.toString(),
      statusCode: response.statusCode,
      code: code,
      details: details,
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

  Future<AuthResult> signInAnonymously({
    Map<String, dynamic> metadata = const {},
  }) async {
    final url = '${SatelliteConfig.authBase}/signup';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'apikey': SatelliteConfig.anonKey,
          },
          body: jsonEncode({'data': metadata}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200 && response.statusCode != 201) {
      final body = jsonDecode(response.body);
      throw SatelliteApiException(
        body['error_description'] as String? ??
            body['msg'] as String? ??
            'Anonymous farmer session failed',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final session = data['session'] as Map<String, dynamic>?;
    final user = data['user'] as Map<String, dynamic>? ?? {};
    return AuthResult(
      accessToken:
          data['access_token'] as String? ??
          session?['access_token'] as String? ??
          '',
      refreshToken:
          data['refresh_token'] as String? ??
          session?['refresh_token'] as String?,
      userId: user['id'] as String? ?? '',
      email: user['email'] as String? ?? 'verified-farmer@local',
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

  Future<List<Farm>> getFarms(String jwt, {String? ownerUserId}) async {
    final owner = ownerUserId?.trim();
    final ownerFilter = owner == null || owner.isEmpty
        ? ''
        : '&user_id=eq.${Uri.encodeQueryComponent(owner)}';
    final url =
        '${SatelliteConfig.restBase}/farms?select=$_farmSelect&order=created_at.desc$ownerFilter';
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

  Future<List<Farm>> getFarmsForFarmerPhone({
    required String phone,
    String? farmerId,
    String? preferredFarmId,
    required String jwt,
    bool retryHttpErrors = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (phone.trim().isEmpty || jwt.trim().isEmpty) return const [];
    final body = <String, dynamic>{'phone': phone};
    final farmerIdValue = farmerId?.trim();
    if (farmerIdValue != null && farmerIdValue.isNotEmpty) {
      body['farmerId'] = farmerIdValue;
    }
    final preferredFarmIdValue = preferredFarmId?.trim();
    if (preferredFarmIdValue != null && preferredFarmIdValue.isNotEmpty) {
      body['farmId'] = preferredFarmIdValue;
    }
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/farmer-phone-farms',
      body,
      jwt,
      retryHttpErrors: retryHttpErrors,
      timeout: timeout,
    );
    final list = data['farms'] as List? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Farm.fromJson)
        .toList(growable: false);
  }

  bool _looksLikeColumnSchemaError(SatelliteApiException error) {
    final raw = [
      error.code,
      error.message,
      error.details,
    ].whereType<String>().join(' ').toLowerCase();
    return raw.contains('column') ||
        raw.contains('schema cache') ||
        raw.contains('pgrst204') ||
        raw.contains('42703');
  }

  Map<String, dynamic> _pickFarmJson(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    final picked = <String, dynamic>{};
    for (final key in keys) {
      if (source.containsKey(key)) {
        picked[key] = source[key];
      }
    }
    return picked;
  }

  List<Map<String, dynamic>> _farmInsertAttempts(
    Map<String, dynamic> farmJson,
  ) {
    return [
      Map<String, dynamic>.from(farmJson),
      _pickFarmJson(farmJson, const [
        'name',
        'geometry',
        'bounds',
        'area_hectares',
        'area_acres',
        'user_id',
        'crop',
        'variety',
        'previous_crop',
        'season',
        'irrigation',
        'soil_type',
        'ownership_type',
        'seed_source',
        'harvest_intent',
      ]),
      _pickFarmJson(farmJson, const [
        'name',
        'geometry',
        'bounds',
        'area_hectares',
        'area_acres',
        'user_id',
      ]),
      _pickFarmJson(farmJson, const [
        'name',
        'geometry',
        'area_hectares',
        'user_id',
      ]),
    ];
  }

  Future<Farm> _insertFarmOnce(
    Map<String, dynamic> farmJson,
    String jwt,
  ) async {
    final url = '${SatelliteConfig.restBase}/farms';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {..._headers(jwt), 'Prefer': 'return=representation'},
          body: jsonEncode(farmJson),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 201 && response.statusCode != 200) {
      final body = response.body.trim();
      dynamic parsed;
      try {
        parsed = body.isEmpty ? null : jsonDecode(body);
      } catch (_) {
        parsed = body;
      }
      final message = parsed is Map
          ? '${parsed['message'] ?? parsed['error'] ?? 'Failed to save farm'}'
          : body.isEmpty
          ? 'Failed to save farm'
          : body;
      throw SatelliteApiException(
        message,
        statusCode: response.statusCode,
        code: parsed is Map ? parsed['code']?.toString() : null,
        details: parsed is Map ? parsed['details']?.toString() : null,
      );
    }
    final list = jsonDecode(response.body) as List;
    return Farm.fromJson(list.first as Map<String, dynamic>);
  }

  Future<Farm> insertFarm(Map<String, dynamic> farmJson, String jwt) async {
    SatelliteApiException? lastError;
    for (final attempt in _farmInsertAttempts(farmJson)) {
      try {
        return await _insertFarmOnce(attempt, jwt);
      } on SatelliteApiException catch (error) {
        lastError = error;
        if (!_looksLikeColumnSchemaError(error)) rethrow;
      }
    }
    throw lastError ?? SatelliteApiException('Failed to save farm');
  }

  Future<Farm> insertFarmerLinkedFarm({
    required Map<String, dynamic> farmJson,
    required String farmerPhone,
    required String jwt,
    String? farmerId,
  }) async {
    final body = <String, dynamic>{
      'phone': farmerPhone,
      if (farmerId != null && farmerId.trim().isNotEmpty)
        'farmerId': farmerId.trim(),
      'farm': farmJson,
    };
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/farmer-farm-save',
      body,
      jwt,
      retryHttpErrors: false,
    );
    final farm = data['farm'];
    if (farm is! Map) {
      throw SatelliteApiException('Saved farm response was invalid');
    }
    return Farm.fromJson(Map<String, dynamic>.from(farm));
  }

  Future<FarmWeatherSnapshot> getLiveWeather({
    required double latitude,
    required double longitude,
    String? crop,
    String? growthStage,
    int? daysAfterSowing,
    double? satelliteMoisture,
    String language = 'en',
    String? jwt,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today
        .subtract(const Duration(days: 7))
        .toIso8601String()
        .split('T')
        .first;
    final endDate = today.toIso8601String().split('T').first;
    final query = <String, String>{
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'start_date': startDate,
      'mode': 'forecast',
      'start': startDate,
      if (crop != null && crop.trim().isNotEmpty) 'crop': crop.trim(),
      if (growthStage != null && growthStage.trim().isNotEmpty)
        'growth_stage': growthStage.trim(),
      if (daysAfterSowing != null) 'days_after_sowing': '$daysAfterSowing',
      if (satelliteMoisture != null) 'satellite_moisture': '$satelliteMoisture',
      'language': language,
    };
    final uri = Uri.parse(
      '${SatelliteConfig.edgeFunctionsBase}/weather',
    ).replace(queryParameters: query);
    Map<String, dynamic> data;
    try {
      data = await _get(uri.toString(), jwt);
    } on SatelliteApiException catch (error) {
      final message = error.message.toLowerCase();
      if (!message.contains('end_date') &&
          !message.contains('date_range') &&
          !message.contains('date range')) {
        rethrow;
      }
      final retryUri = Uri.parse('${SatelliteConfig.edgeFunctionsBase}/weather')
          .replace(
            queryParameters: {...query, 'end_date': endDate, 'end': endDate},
          );
      data = await _get(retryUri.toString(), jwt);
    }
    return FarmWeatherSnapshot.fromJson(data);
  }

  Future<Map<String, dynamic>> saveFarmStatusUpdate({
    required String farmId,
    required String farmerPhone,
    required String? jwt,
    String? farmerId,
    required String farmerName,
    required String farmName,
    required String crop,
    required String variety,
    required String stage,
    required String stageQuestion,
    required int daysAfterSowing,
    required String statusText,
    String? priorStatus,
    String? source,
  }) async {
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/farm-status-update',
      {
        'farmId': farmId,
        'phone': farmerPhone,
        if (farmerId != null && farmerId.trim().isNotEmpty)
          'farmerId': farmerId.trim(),
        'farmerName': farmerName,
        'farmName': farmName,
        'crop': crop,
        'variety': variety,
        'stage': stage,
        'stageQuestion': stageQuestion,
        'daysAfterSowing': daysAfterSowing,
        'statusText': statusText,
        // ignore: use_null_aware_elements
        if (priorStatus != null) 'priorStatus': priorStatus,
        'source': source ?? 'farmer_dashboard_status_chat',
        'updatedAt': DateTime.now().toIso8601String(),
      },
      jwt,
    );
    return data;
  }

  Future<FarmTimelineEvent?> createFarmTimelineEvent({
    required String farmId,
    required String farmerPhone,
    required String? jwt,
    String? farmerId,
    required String eventType,
    required String title,
    required String message,
    String? stage,
    String severity = 'info',
    Map<String, dynamic> payload = const {},
  }) async {
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/farm-timeline-events',
      {
        'action': 'create',
        'farmId': farmId,
        'phone': farmerPhone,
        if (farmerId != null && farmerId.trim().isNotEmpty)
          'farmerId': farmerId.trim(),
        'eventType': eventType,
        'title': title,
        'message': message,
        if (stage != null && stage.trim().isNotEmpty) 'stage': stage.trim(),
        'severity': severity,
        'payload': payload,
        'createdAt': DateTime.now().toIso8601String(),
      },
      jwt,
    );
    final raw = data['event'];
    if (raw is Map) {
      return FarmTimelineEvent.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  Future<void> saveFarmDataSnapshot({
    required String farmId,
    required String farmerPhone,
    required String? jwt,
    String? farmerId,
    required String source,
    required Map<String, dynamic> snapshot,
  }) async {
    await _post('${SatelliteConfig.edgeFunctionsBase}/farm-data-snapshots', {
      'action': 'record',
      'farmId': farmId,
      'phone': farmerPhone,
      if (farmerId != null && farmerId.trim().isNotEmpty)
        'farmerId': farmerId.trim(),
      'source': source,
      'snapshot': snapshot,
      'collectedAt': DateTime.now().toIso8601String(),
    }, jwt);
  }

  Future<List<FarmTimelineEvent>> listFarmTimelineEvents({
    required String farmId,
    required String farmerPhone,
    required String? jwt,
    String? farmerId,
    int limit = 80,
  }) async {
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/farm-timeline-events',
      {
        'action': 'list',
        'farmId': farmId,
        'phone': farmerPhone,
        if (farmerId != null && farmerId.trim().isNotEmpty)
          'farmerId': farmerId.trim(),
        'limit': limit,
      },
      jwt,
    );
    final raw = data['events'];
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => FarmTimelineEvent.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<CropLifecycleAdvice> getCropLifecycleAdvice({
    required String farmId,
    required String farmerPhone,
    required String? jwt,
    String? farmerId,
    required String crop,
    required String growthStage,
    required int daysAfterSowing,
    String? variety,
    String? district,
  }) async {
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/crop-lifecycle-advice',
      {
        'farmId': farmId,
        'phone': farmerPhone,
        if (farmerId != null && farmerId.trim().isNotEmpty)
          'farmerId': farmerId.trim(),
        'crop': crop,
        'growthStage': growthStage,
        'daysAfterSowing': daysAfterSowing,
        if (variety != null && variety.trim().isNotEmpty)
          'variety': variety.trim(),
        if (district != null && district.trim().isNotEmpty)
          'district': district.trim(),
      },
      jwt,
    );
    return CropLifecycleAdvice.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> getDiseaseScoutZones({
    required String farmId,
    required String? jwt,
    String? farmerPhone,
    String? farmerId,
  }) async {
    final phone = farmerPhone?.trim();
    if (phone != null && phone.isNotEmpty) {
      final summary = await getFarmerFarmSummary(
        farmId: farmId,
        jwt: jwt,
        farmerPhone: phone,
        farmerId: farmerId,
      );
      return summary.scoutZoneRows;
    }

    final url =
        '${SatelliteConfig.restBase}/disease_scout_zones'
        '?select=*&farm_id=eq.$farmId&order=scan_date.desc,zone_rank.asc';
    final response = await http
        .get(Uri.parse(url), headers: _headers(jwt))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw SatelliteApiException(
        'Failed to load disease scout zones',
        statusCode: response.statusCode,
      );
    }
    final list = jsonDecode(response.body) as List;
    return list.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<FarmerDiseaseData> getFarmerDiseaseData({
    required String farmId,
    required String? jwt,
    required String farmerPhone,
    String? farmerId,
  }) async {
    final phone = farmerPhone.trim();
    if (phone.isEmpty) {
      throw SatelliteApiException('Farmer phone is required');
    }
    final summary = await getFarmerFarmSummary(
      farmId: farmId,
      jwt: jwt,
      farmerPhone: phone,
      farmerId: farmerId,
    );
    return FarmerDiseaseData(
      scoutZones: summary.scoutZoneRows,
      riskCells: summary.riskCellRows,
    );
  }

  Future<FarmerFarmSummary> getFarmerFarmSummary({
    required String farmId,
    required String? jwt,
    required String farmerPhone,
    String? farmerId,
  }) async {
    final phone = farmerPhone.trim();
    if (phone.isEmpty) {
      throw SatelliteApiException('Farmer phone is required');
    }
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/farmer-farm-summary',
      {
        'farmId': farmId,
        'phone': phone,
        if (farmerId != null && farmerId.trim().isNotEmpty)
          'farmerId': farmerId.trim(),
      },
      jwt,
    );
    return FarmerFarmSummary.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> getDiseaseRiskCells({
    required String farmId,
    required String? jwt,
    String? farmerPhone,
    String? farmerId,
  }) async {
    final phone = farmerPhone?.trim();
    if (phone != null && phone.isNotEmpty) {
      final summary = await getFarmerFarmSummary(
        farmId: farmId,
        jwt: jwt,
        farmerPhone: phone,
        farmerId: farmerId,
      );
      return summary.riskCellRows;
    }

    final url =
        '${SatelliteConfig.restBase}/disease_risk_cells'
        '?select=*&farm_id=eq.$farmId&order=scan_date.desc,composite_risk.desc&limit=60';
    final response = await http
        .get(Uri.parse(url), headers: _headers(jwt))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw SatelliteApiException(
        'Failed to load disease risk cells',
        statusCode: response.statusCode,
      );
    }
    final list = jsonDecode(response.body) as List;
    return list.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> insertDiseaseScoutZone({
    required Map<String, dynamic> payload,
    required String? jwt,
    String? farmerPhone,
    String? farmerId,
  }) async {
    final url = '${SatelliteConfig.restBase}/disease_scout_zones';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {..._headers(jwt), 'Prefer': 'return=minimal'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw SatelliteApiException(
        'Failed to save disease scout zone',
        statusCode: response.statusCode,
      );
    }
  }

  Future<void> insertFarmIssueAction({
    required Map<String, dynamic> payload,
    required String? jwt,
    String? farmerPhone,
    String? farmerId,
  }) async {
    final body = <String, dynamic>{
      ...payload,
      if (farmerPhone != null && farmerPhone.trim().isNotEmpty)
        'farmer_phone': farmerPhone.trim(),
      if (farmerId != null && farmerId.trim().isNotEmpty)
        'farmer_id': farmerId.trim(),
    };
    final response = await http
        .post(
          Uri.parse('${SatelliteConfig.restBase}/farm_issue_actions'),
          headers: {
            ..._headers(jwt),
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 201 &&
        response.statusCode != 200 &&
        response.statusCode != 204) {
      throw SatelliteApiException(
        'Failed to save farm issue action',
        statusCode: response.statusCode,
      );
    }
  }

  Future<DiseaseScreenResult> runDiseaseScreen({
    required String farmId,
    required String crop,
    required String growthStage,
    required String season,
    Map<String, dynamic>? geometry,
    required String? jwt,
    String? farmerPhone,
    String? farmerId,
  }) async {
    final phone = farmerPhone?.trim();
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/disease-risk-screen',
      {
        'farm_id': farmId,
        'crop': crop,
        'growth_stage': growthStage,
        'season': season,
        // ignore: use_null_aware_elements
        if (geometry != null) 'geometry': geometry,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (phone != null &&
            phone.isNotEmpty &&
            farmerId != null &&
            farmerId.trim().isNotEmpty)
          'farmerId': farmerId.trim(),
      },
      jwt,
    );
    return DiseaseScreenResult.fromJson(data);
  }

  Future<FarmAlertAdvice> getFarmAlertAdvice({
    required Map<String, dynamic> body,
    required String? jwt,
  }) async {
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/farm-alert-advisor',
      body,
      jwt,
    );
    return FarmAlertAdvice.fromJson(data);
  }

  Future<FarmAssistantAnswer> askFarmAssistant({
    required String farmId,
    required String farmerPhone,
    String? farmerId,
    required String question,
    required String? jwt,
    String language = 'en',
    String? farmName,
    String? crop,
    String? variety,
    String? location,
    String? growthStage,
    int? daysAfterSowing,
  }) async {
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/farm-assistant-chat',
      {
        'farmId': farmId,
        'phone': farmerPhone,
        if (farmerId != null && farmerId.trim().isNotEmpty)
          'farmerId': farmerId.trim(),
        'question': question,
        'language': language,
        if (farmName != null && farmName.trim().isNotEmpty)
          'farmName': farmName.trim(),
        if (crop != null && crop.trim().isNotEmpty) 'crop': crop.trim(),
        if (variety != null && variety.trim().isNotEmpty)
          'variety': variety.trim(),
        if (location != null && location.trim().isNotEmpty)
          'location': location.trim(),
        if (growthStage != null && growthStage.trim().isNotEmpty)
          'growthStage': growthStage.trim(),
        // ignore: use_null_aware_elements
        if (daysAfterSowing != null) 'daysAfterSowing': daysAfterSowing,
      },
      jwt,
    );
    return FarmAssistantAnswer.fromJson(data);
  }

  /// Uploads a field photo to the private disease-photos bucket and returns
  /// the storage path used by disease-image-diagnose.
  Future<String> uploadDiseasePhoto({
    required List<int> bytes,
    required String farmId,
    required String? jwt,
  }) async {
    final path = '$farmId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final url = '${SatelliteConfig.url}/storage/v1/object/disease-photos/$path';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {..._headers(jwt), 'Content-Type': 'image/jpeg'},
          body: bytes,
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw SatelliteApiException(
        'Failed to upload field photo',
        statusCode: response.statusCode,
      );
    }
    return path;
  }

  Future<FarmPhotoDiagnosis> diagnoseDiseasePhoto({
    required Map<String, dynamic> body,
    required String? jwt,
  }) async {
    final data = await _post(
      '${SatelliteConfig.edgeFunctionsBase}/disease-image-diagnose',
      body,
      jwt,
    );
    return FarmPhotoDiagnosis.fromJson(data);
  }

  Future<void> upsertFarmerPhoneProfile({
    required String userId,
    required String phone,
    required String farmerId,
    required String farmerName,
    required String? jwt,
  }) async {
    final url =
        '${SatelliteConfig.restBase}/farmer_phone_profiles?on_conflict=user_id';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            ..._headers(jwt),
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          body: jsonEncode({
            'user_id': userId,
            'phone': phone,
            'farmer_id': farmerId,
            'farmer_name': farmerName,
            'auth_method': 'anonymous_link',
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 201 &&
        response.statusCode != 200 &&
        response.statusCode != 204) {
      throw SatelliteApiException(
        'Failed to link farmer profile',
        statusCode: response.statusCode,
      );
    }
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
