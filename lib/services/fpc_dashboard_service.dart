import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fpc_procurement_dashboard.dart';

class FpcDashboardException implements Exception {
  final String message;

  const FpcDashboardException(this.message);

  @override
  String toString() => message;
}

class FpcDashboardRequestTracker {
  int _generation = 0;

  int begin() => ++_generation;

  bool isCurrent(int request) => request == _generation;
}

class FpcDashboardService {
  final SupabaseClient? _supabaseClient;

  const FpcDashboardService({SupabaseClient? supabaseClient})
    : _supabaseClient = supabaseClient;

  SupabaseClient get _client => _supabaseClient ?? Supabase.instance.client;

  Future<FpcProcurementDashboardSnapshot> load({String? clusterId}) async {
    try {
      Object? response;
      try {
        response = await _client.rpc(
          'fpc_workspace_dashboard_snapshot',
          params: {'p_cluster_id': clusterId},
        );
      } on PostgrestException catch (error) {
        final unavailable =
            error.code == 'PGRST202' ||
            error.code == '42883' ||
            error.message.toLowerCase().contains('schema cache');
        if (!unavailable) rethrow;
        response = await _client.rpc(
          'fpc_procurement_dashboard_snapshot',
          params: {'p_cluster_id': clusterId},
        );
      }
      if (response is! Map) {
        throw const FpcDashboardException(
          'The procurement dashboard returned an invalid response.',
        );
      }
      return FpcProcurementDashboardSnapshot.fromJson(
        Map<String, dynamic>.from(response),
      );
    } on PostgrestException catch (error) {
      throw FpcDashboardException(
        error.message.trim().isEmpty
            ? 'Could not load the procurement dashboard.'
            : error.message,
      );
    }
  }

  Future<FpcProcurementDashboardSnapshot> loadOverview({
    String? clusterId,
  }) async {
    try {
      final response = await _client.rpc(
        'fpc_procurement_dashboard_overview',
        params: {'p_cluster_id': clusterId},
      );
      if (response is! Map) {
        throw const FpcDashboardException(
          'The procurement overview returned an invalid response.',
        );
      }
      return FpcProcurementDashboardSnapshot.fromJson(
        Map<String, dynamic>.from(response),
      );
    } on PostgrestException catch (error) {
      if (_isUnavailable(error)) return load(clusterId: clusterId);
      throw FpcDashboardException(
        error.message.trim().isEmpty
            ? 'Could not load the procurement overview.'
            : error.message,
      );
    }
  }

  Future<FpcFarmQueuePage> loadFarmQueue({
    String? clusterId,
    required int offset,
    int limit = 5,
  }) async {
    try {
      final response = await _client.rpc(
        'fpc_procurement_farm_queue',
        params: {
          'p_cluster_id': clusterId,
          'p_offset': offset,
          'p_limit': limit,
        },
      );
      if (response is! Map) {
        throw const FpcDashboardException(
          'The farm queue returned an invalid response.',
        );
      }
      return FpcFarmQueuePage.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      if (!_isUnavailable(error)) {
        throw FpcDashboardException(
          error.message.trim().isEmpty
              ? 'Could not load the farm queue.'
              : error.message,
        );
      }
      final snapshot = await load(clusterId: clusterId);
      final farms = snapshot.farms.skip(offset).take(limit).toList();
      return FpcFarmQueuePage(
        farms: farms,
        hasMore: offset + farms.length < snapshot.farms.length,
        nextOffset: offset + farms.length,
      );
    }
  }

  Future<List<FpcFarmMapPoint>> loadFarmMapPoints({String? clusterId}) async {
    try {
      final response = await _client.rpc(
        'fpc_procurement_map_points',
        params: {'p_cluster_id': clusterId},
      );
      if (response is! List) {
        throw const FpcDashboardException(
          'The farm map returned an invalid response.',
        );
      }
      return response
          .whereType<Map>()
          .map(
            (row) => FpcFarmMapPoint.fromJson(Map<String, dynamic>.from(row)),
          )
          .where((point) => point.linkId.isNotEmpty)
          .toList(growable: false);
    } on PostgrestException catch (error) {
      if (_isUnavailable(error)) {
        final snapshot = await load(clusterId: clusterId);
        return snapshot.farms
            .where((farm) => farm.hasMapLocation)
            .map(FpcFarmMapPoint.fromFarm)
            .toList(growable: false);
      }
      throw FpcDashboardException(
        error.message.trim().isEmpty
            ? 'Could not load farm locations.'
            : error.message,
      );
    }
  }

  Future<FpcFarmWorkCard> loadFarmDetail({
    required String farmerLinkId,
    String? clusterId,
  }) async {
    try {
      final response = await _client.rpc(
        'fpc_procurement_farm_detail',
        params: {'p_farmer_link_id': farmerLinkId, 'p_cluster_id': clusterId},
      );
      if (response is! Map) {
        throw const FpcDashboardException(
          'The farm detail returned an invalid response.',
        );
      }
      return FpcFarmWorkCard.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      if (!_isUnavailable(error)) {
        throw FpcDashboardException(
          error.message.trim().isEmpty
              ? 'Could not load farm details.'
              : error.message,
        );
      }
      final snapshot = await load(clusterId: clusterId);
      for (final farm in snapshot.farms) {
        if (farm.linkId == farmerLinkId) return farm;
      }
      throw const FpcDashboardException('The selected farm is unavailable.');
    }
  }

  bool _isUnavailable(PostgrestException error) {
    return error.code == 'PGRST202' ||
        error.code == '42883' ||
        error.message.toLowerCase().contains('schema cache');
  }

  Future<FpcOperatingCluster> createCluster({
    required String name,
    required String district,
    required String state,
    required String preferredApmcMarket,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.length < 2) {
      throw const FpcDashboardException(
        'Enter a cluster name with at least two characters.',
      );
    }
    final row = await _client
        .from('fpc_operating_clusters')
        .insert({
          'fpc_id': await _activeFpcId(),
          'name': normalizedName,
          'district': district.trim(),
          'state': state.trim().isEmpty ? 'Maharashtra' : state.trim(),
          'preferred_apmc_market': preferredApmcMarket.trim(),
        })
        .select()
        .single();
    return FpcOperatingCluster.fromJson(row);
  }

  Future<void> updateCluster({
    required String clusterId,
    required String name,
    required String district,
    required String state,
    required String preferredApmcMarket,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.length < 2) {
      throw const FpcDashboardException(
        'Enter a cluster name with at least two characters.',
      );
    }
    await _client
        .from('fpc_operating_clusters')
        .update({
          'name': normalizedName,
          'district': district.trim(),
          'state': state.trim().isEmpty ? 'Maharashtra' : state.trim(),
          'preferred_apmc_market': preferredApmcMarket.trim(),
        })
        .eq('id', clusterId);
  }

  Future<void> deactivateCluster(String clusterId) async {
    await _client
        .from('fpc_operating_clusters')
        .update({'active': false})
        .eq('id', clusterId);
  }

  Future<void> assignFarmToCluster({
    required String farmerLinkId,
    String? clusterId,
  }) async {
    await _client
        .from('fpc_farmer_links')
        .update({'cluster_id': clusterId})
        .eq('id', farmerLinkId);
  }

  Future<String> _activeFpcId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const FpcDashboardException(
        'Sign in with an FPC administrator account.',
      );
    }
    final row = await _client
        .from('fpc_memberships')
        .select('fpc_id')
        .eq('user_id', userId)
        .eq('status', 'active')
        .eq('role', 'fpc_admin')
        .maybeSingle();
    final fpcId = row?['fpc_id']?.toString().trim() ?? '';
    if (fpcId.isEmpty) {
      throw const FpcDashboardException(
        'No active FPC administrator membership was found.',
      );
    }
    return fpcId;
  }
}
