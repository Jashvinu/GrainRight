import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_survey.dart';
import '../services/survey_service.dart';
import '../services/sheets_sync_service.dart';

class SurveyController extends GetxController {
  final _service = SurveyService();
  final _sheetsService = SheetsSyncService();
  final surveys = <FarmerSurvey>[].obs;
  final isLoading = false.obs;
  final hasError = false.obs;
  final errorMessage = ''.obs;
  final deletingSurveyIds = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    loadSurveys();
  }

  Future<void> loadSurveys() async {
    isLoading.value = true;
    hasError.value = false;
    try {
      surveys.value = await _service.fetchAll();
    } catch (e, st) {
      debugPrint('[SurveyController.loadSurveys] $e\n$st');
      hasError.value = true;
      errorMessage.value = _friendlyError(e);
    } finally {
      isLoading.value = false;
    }
  }

  bool isDeleting(String? surveyId) =>
      surveyId != null && deletingSurveyIds.contains(surveyId);

  /// Deletes the survey from Supabase, then mirrors the delete to Google Sheets.
  Future<bool> deleteSurvey(FarmerSurvey survey) async {
    final id = survey.id;
    if (id == null || id.isEmpty) {
      Get.snackbar('Delete failed', 'This survey is missing a database id.');
      return false;
    }
    if (deletingSurveyIds.contains(id)) return false;

    deletingSurveyIds.add(id);
    try {
      final deleted = await _service.delete(id);
      if (!deleted) {
        Get.snackbar(
          'Delete failed',
          'Survey was not deleted. It may already be gone, or this user may not own it.',
        );
        return false;
      }

      unawaited(
        _sheetsService.deleteFromSheet(
          farmerName: survey.farmerName ?? '',
          surveyDate: survey.surveyDate,
          mobileNo: survey.mobileNo,
        ),
      );
      Get.snackbar('Deleted', 'Survey deleted from the remote database');
      return true;
    } catch (e, st) {
      debugPrint('[SurveyController.deleteSurvey] $e\n$st');
      Get.snackbar('Error', _friendlyError(e));
      return false;
    } finally {
      deletingSurveyIds.remove(id);
    }
  }

  static String _friendlyError(Object e) {
    if (e is PostgrestException && e.code == '525') {
      return 'Server is temporarily unavailable. Please try again in a moment.';
    }
    return 'Something went wrong. Please check your connection and try again.';
  }
}
