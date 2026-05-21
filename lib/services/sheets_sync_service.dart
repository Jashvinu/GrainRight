import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';

/// Calls Supabase Edge Functions to sync survey data to Google Sheets.
class SheetsSyncService {
  static const _functionUrl =
      '${SupabaseConfig.edgeFunctionsBase}/sync-to-sheets';
  static const _deleteUrl =
      '${SupabaseConfig.edgeFunctionsBase}/delete-from-sheets';

  /// Fire-and-forget: pushes survey data to Google Sheets via edge function.
  /// Returns true on success, false on failure (never throws).
  Future<bool> syncToSheet(Map<String, dynamic> surveyData) async {
    try {
      final response = await http.post(
        Uri.parse(_functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        },
        body: jsonEncode(surveyData),
      );

      if (response.statusCode == 200) {
        debugPrint('[SheetsSyncService] Synced to Google Sheets');
        return true;
      } else {
        debugPrint(
            '[SheetsSyncService] Failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[SheetsSyncService] Error: $e');
      return false;
    }
  }

  /// Deletes a survey row from Google Sheets by matching farmer details.
  /// Returns true on success, false on failure (never throws).
  Future<bool> deleteFromSheet({
    required String farmerName,
    String? surveyDate,
    String? mobileNo,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_deleteUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        },
        body: jsonEncode({
          'farmer_name': farmerName,
          if (surveyDate != null) 'survey_date': surveyDate, // ignore: use_null_aware_elements
          if (mobileNo != null) 'mobile_no': mobileNo, // ignore: use_null_aware_elements
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[SheetsSyncService] Deleted from Google Sheets');
        return true;
      } else {
        debugPrint(
            '[SheetsSyncService] Delete failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[SheetsSyncService] Delete error: $e');
      return false;
    }
  }
}
