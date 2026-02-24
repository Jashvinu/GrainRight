import 'package:get/get.dart';
import '../models/farmer_survey.dart';
import '../services/survey_service.dart';

class SurveyController extends GetxController {
  final _service = SurveyService();
  final surveys = <FarmerSurvey>[].obs;
  final isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadSurveys();
  }

  Future<void> loadSurveys() async {
    isLoading.value = true;
    try {
      surveys.value = await _service.fetchAll();
    } catch (e) {
      Get.snackbar('Error', 'Failed to load surveys: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> deleteSurvey(String id) async {
    try {
      await _service.delete(id);
      surveys.removeWhere((s) => s.id == id);
      Get.snackbar('Deleted', 'Survey removed');
    } catch (e) {
      Get.snackbar('Error', 'Failed to delete: $e');
    }
  }
}
