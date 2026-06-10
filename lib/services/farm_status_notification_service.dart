import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

class FarmStatusNotificationService {
  static const _notifyFunctionUrl =
      '${SupabaseConfig.edgeFunctionsBase}/farm-status-notify';

  Future<bool> sendFarmStatusNotification({
    required String farmerId,
    required String farmerName,
    required String farmName,
    required String crop,
    required String variety,
    required String location,
    required String stage,
    required String stageQuestion,
    required int daysAfterSowing,
    required String statusText,
    String? priorStatus,
  }) async {
    try {
      final payload = <String, dynamic>{
        'type': 'farm_status_update',
        'farmerId': farmerId,
        'farmerName': farmerName,
        'farmName': farmName,
        'crop': crop,
        'variety': variety,
        'location': location,
        'stage': stage,
        'stageQuestion': stageQuestion,
        'daysAfterSowing': daysAfterSowing,
        'statusText': statusText,
        'priorStatus': priorStatus,
        'source': 'farmer_dashboard_status_chat',
        'updatedAt': DateTime.now().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse(_notifyFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('[FarmStatusNotification] notification sent');
        return true;
      }

      debugPrint(
        '[FarmStatusNotification] failed: '
        '${response.statusCode} ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('[FarmStatusNotification] error: $e');
      return false;
    }
  }
}
