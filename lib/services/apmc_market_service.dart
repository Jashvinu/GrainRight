import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/marketplace_listing.dart';

class ApmcMarketException implements Exception {
  final String message;

  const ApmcMarketException(this.message);

  @override
  String toString() => message;
}

class ApmcMarketResult {
  final List<ApmcMarketRate> rates;
  final String source;
  final bool refreshed;
  final String refreshReason;

  const ApmcMarketResult({
    required this.rates,
    required this.source,
    required this.refreshed,
    required this.refreshReason,
  });
}

class ApmcMarketService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<ApmcMarketResult> search({
    String query = '',
    String state = '',
    String district = '',
    String market = '',
    bool refresh = false,
  }) async {
    final response = await _client.functions.invoke(
      'apmc-market-rates',
      headers: _authHeaders(),
      body: {
        'query': query,
        'state': state,
        'district': district,
        'market': market,
        'refresh': refresh,
        'limit': 200,
      },
    );
    final data = _map(response.data);
    if (data['success'] == false) {
      throw ApmcMarketException('${data['error'] ?? 'APMC search failed.'}');
    }
    final rows = data['rates'];
    return ApmcMarketResult(
      rates: rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (row) =>
                      ApmcMarketRate.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList(growable: false)
          : const [],
      source: '${data['source'] ?? ''}',
      refreshed: data['refreshed'] == true,
      refreshReason: '${data['refreshReason'] ?? ''}',
    );
  }

  Map<String, String>? _authHeaders() {
    final token = _client.auth.currentSession?.accessToken;
    return token == null || token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _map(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }
}
