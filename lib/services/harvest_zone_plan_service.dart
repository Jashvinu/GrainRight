import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/harvest_zone_plan.dart';

class HarvestZonePlanException implements Exception {
  final String message;

  const HarvestZonePlanException(this.message);

  @override
  String toString() => message;
}

class HarvestZonePlanService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<HarvestZonePlan> load({
    required String farmId,
    required String farmerPhone,
    required String farmerId,
    bool forceRefresh = false,
  }) async {
    final normalizedFarmId = farmId.trim();
    if (normalizedFarmId.isEmpty) {
      throw const HarvestZonePlanException(
        'Sync this farm before loading the harvest map.',
      );
    }
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const HarvestZonePlanException(
        'Sign in again before loading the harvest map.',
      );
    }

    try {
      final response = await _client.functions.invoke(
        'harvest-zone-plan',
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'farm_id': normalizedFarmId,
          'farmer_phone': farmerPhone.trim(),
          'farmer_id': farmerId.trim(),
          'force_refresh': forceRefresh,
        },
      );
      final data = response.data;
      final body = data is Map
          ? Map<String, dynamic>.from(data)
          : const <String, dynamic>{};
      if (body['success'] == false) {
        throw HarvestZonePlanException(
          '${body['details'] ?? body['error'] ?? 'Harvest map failed.'}',
        );
      }
      final plan = HarvestZonePlan.fromJson(body);
      if (plan.id.isEmpty) {
        throw const HarvestZonePlanException(
          'Harvest map response did not include a plan.',
        );
      }
      return plan;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map) {
        throw HarvestZonePlanException(
          '${details['details'] ?? details['error'] ?? error.reasonPhrase}',
        );
      }
      throw HarvestZonePlanException(
        error.reasonPhrase ?? 'Harvest map failed.',
      );
    } on HarvestZonePlanException {
      rethrow;
    } catch (error) {
      throw HarvestZonePlanException('Harvest map failed: $error');
    }
  }
}
