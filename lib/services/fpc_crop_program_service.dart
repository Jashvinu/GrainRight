import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/fpc_crop_program.dart';

class FpcCropProgramService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<FpcCropProgramSnapshot> loadForFarm(String farmId) async {
    if (farmId.trim().isEmpty) return const FpcCropProgramSnapshot.empty();
    try {
      final result = await _client.rpc(
        'farmer_seed_store_for_farm',
        params: {'p_farm_id': farmId.trim()},
      );
      return FpcCropProgramSnapshot.fromJson(result);
    } on PostgrestException catch (error) {
      if (isUnavailableFarmerFarmError(error)) {
        return const FpcCropProgramSnapshot.empty();
      }
      rethrow;
    }
  }

  static bool isUnavailableFarmerFarmError(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'P0001' &&
        (message.contains('farmer farm not found') ||
            message.contains('farm not found for this farmer'));
  }

  Future<void> acceptTerms({
    required String enrollmentId,
    required int policyVersion,
  }) async {
    await _client.rpc(
      'farmer_accept_crop_program',
      params: {
        'p_enrollment_id': enrollmentId,
        'p_terms_version': policyVersion,
      },
    );
  }

  Future<void> acknowledgeSeed(String seedIssueId) async {
    await _client.rpc(
      'farmer_acknowledge_crop_program_seed',
      params: {'p_seed_issue_id': seedIssueId},
    );
  }

  Future<void> requestSeed({
    required String farmId,
    required String seedBatchId,
    required double quantityKg,
    String note = '',
  }) async {
    await _client.rpc(
      'farmer_request_seed_purchase',
      params: {
        'p_farm_id': farmId.trim(),
        'p_seed_batch_id': seedBatchId,
        'p_quantity_kg': quantityKg,
        'p_farmer_note': note.trim(),
        'p_client_request_id': const Uuid().v4(),
      },
    );
  }

  Future<Map<String, dynamic>> evaluateHarvest(String inventoryItemId) async {
    final result = await _client.rpc(
      'submit_crop_program_harvest',
      params: {'p_inventory_item_id': inventoryItemId},
    );
    return result is Map ? Map<String, dynamic>.from(result) : const {};
  }
}
