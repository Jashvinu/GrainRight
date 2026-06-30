import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/stakeholder_plan.dart';
import '../models/verified_farmer_record.dart';

class StakeholderServiceException implements Exception {
  final String message;

  const StakeholderServiceException(this.message);

  @override
  String toString() => message;
}

class StakeholderService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<StakeholderPlanBundle> loadForFarmer(
    VerifiedFarmerRecord farmer,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'stakeholder-plan-sync',
        headers: _functionAuthHeaders(),
        body: {'action': 'load', 'farmer': _farmerPayload(farmer)},
      );
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw StakeholderServiceException(
          '${data['error'] ?? 'Stakeholder plan sync failed.'}',
        );
      }
      if (data.isEmpty) {
        throw const StakeholderServiceException(
          'Stakeholder plan sync failed.',
        );
      }
      return StakeholderPlanBundle.fromJson(data);
    } on StakeholderServiceException {
      rethrow;
    } catch (error) {
      throw StakeholderServiceException(
        _cleanRemoteError(error, 'Stakeholder plan sync failed.'),
      );
    }
  }

  Future<StakeholderPlanBundle> submitInterest({
    required VerifiedFarmerRecord farmer,
    required StakeholderPlan plan,
    required double selectedAmount,
    required String farmerNote,
  }) async {
    try {
      final shares = plan.estimateShares(selectedAmount);
      if (!plan.isValidAmount(selectedAmount)) {
        throw const StakeholderServiceException(
          'Select an amount within the allowed plan range.',
        );
      }
      final response = await _client.functions.invoke(
        'stakeholder-plan-sync',
        headers: _functionAuthHeaders(),
        body: {
          'action': 'submit_interest',
          'planId': plan.id,
          'planCode': plan.planCode,
          'farmer': _farmerPayload(farmer),
          'selectedAmount': selectedAmount,
          'estimatedShares': shares,
          'farmerNote': farmerNote.trim(),
          'consentInterestOnly': true,
          'consentNoGuaranteedReturn': true,
          'consentDataUse': true,
        },
      );
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw StakeholderServiceException(
          '${data['error'] ?? 'Stakeholder interest submission failed.'}',
        );
      }
      if (data.isEmpty) {
        throw const StakeholderServiceException(
          'Stakeholder interest submission failed.',
        );
      }
      return StakeholderPlanBundle.fromJson(data);
    } on StakeholderServiceException {
      rethrow;
    } catch (error) {
      throw StakeholderServiceException(
        _cleanRemoteError(error, 'Stakeholder interest submission failed.'),
      );
    }
  }

  Map<String, dynamic> _farmerPayload(VerifiedFarmerRecord farmer) {
    return {
      'phone': _normalizePhone(farmer.phone),
      'farmerId': farmer.farmerId,
      'farmerName': farmer.farmerName,
      'agriRecordId': farmer.agriRecordId,
      'aadhaarLast4': farmer.aadhaarLast4,
    };
  }

  Map<String, String>? _functionAuthHeaders() {
    final token = _client.auth.currentSession?.accessToken;
    return token == null || token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _responseMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const <String, dynamic>{};
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }

  String _cleanRemoteError(Object error, String fallback) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? fallback : text;
  }
}
