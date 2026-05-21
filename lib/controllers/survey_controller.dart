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

  /// Removes the survey from the app list and deletes it from Google Sheets.
  /// Does NOT delete from the Supabase database.
  Future<bool> deleteSurvey(FarmerSurvey survey) async {
    try {
      // Delete from Google Sheets in the background
      _sheetsService.deleteFromSheet(
        farmerName: survey.farmerName ?? '',
        surveyDate: survey.surveyDate,
        mobileNo: survey.mobileNo,
      );
      Get.snackbar('Deleted', 'Survey removed from app');
      return true;
    } catch (e, st) {
      debugPrint('[SurveyController.deleteSurvey] $e\n$st');
      Get.snackbar('Error', _friendlyError(e));
      return false;
    }
  }

  static String _friendlyError(Object e) {
    if (e is PostgrestException && e.code == '525') {
      return 'Server is temporarily unavailable. Please try again in a moment.';
    }
    return 'Something went wrong. Please check your connection and try again.';
  }
}
