import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/satellite_config.dart';
import '../controllers/farm_controller.dart';
import '../models/satellite/diagnostics_model.dart';
import '../models/satellite/farm_model.dart';
import '../services/satellite_service.dart';
import '../services/survey_service.dart';
import '../services/backend_bridge_session.dart';

class DiagnosticsHomeController extends GetxController {
  final _surveyService = SurveyService();
  final _satelliteService = SatelliteService();

  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final result = Rxn<DiagnosticsResult>();
  final selectedIndex = 'ndvi'.obs;
  final survey = Rxn<Map<String, dynamic>>();
  final activeFarm = Rxn<Farm>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final session = await ensureBackendBridgeSession();
      final farmCtrl = Get.isRegistered<FarmController>()
          ? Get.find<FarmController>()
          : Get.put(FarmController());
      if (farmCtrl.farms.isEmpty && !farmCtrl.isLoading.value) {
        await farmCtrl.loadFarms(forceRefresh: true);
      }
      final selectedFarm =
          farmCtrl.selectedFarm.value ??
          (farmCtrl.farms.isEmpty ? null : farmCtrl.farms.first);
      if (selectedFarm != null) {
        activeFarm.value = selectedFarm;
        survey.value = {'farm_polygon': selectedFarm.geometry};
        result.value = await _satelliteService.getDiagnostics(
          polygonJson: jsonEncode(selectedFarm.geometry),
          farmId: selectedFarm.id,
          indices: const [
            'nitrogen',
            'phosphorus',
            'potassium',
            'moisture',
            'ndvi',
          ],
          jwt: session.accessToken,
        );
        final available = result.value?.analysis.keys;
        if (available != null && available.isNotEmpty) {
          selectedIndex.value = available.first;
        }
        return;
      }

      final latest = await _surveyService.fetchLatestWithPolygon();
      if (latest == null) {
        errorMessage.value =
            'No farm boundary found. Open Farms, add or select a farm, then retry diagnostics.';
        return;
      }
      survey.value = latest;
      final polygon = latest['farm_polygon'];
      result.value = await _satelliteService.getDiagnostics(
        polygonJson: jsonEncode(polygon),
        farmId: latest['id'] as String?,
        indices: const [
          'nitrogen',
          'phosphorus',
          'potassium',
          'moisture',
          'ndvi',
        ],
        jwt: session.accessToken,
      );
      final available = result.value?.analysis.keys;
      if (available != null && available.isNotEmpty) {
        selectedIndex.value = available.first;
      }
    } catch (e, st) {
      debugPrint('[DiagnosticsHomeController.load] $e\n$st');
      errorMessage.value = 'Failed to load diagnostics: $e';
    } finally {
      isLoading.value = false;
    }
  }

  List<List<double>> polygonCoords() {
    final polygon = survey.value?['farm_polygon'];
    if (polygon is! Map) return [];
    final coords = polygon['coordinates'];
    if (coords is! List || coords.isEmpty) return [];
    final ring = coords.first as List;
    return ring.map((point) {
      final p = point as List;
      return [(p[0] as num).toDouble(), (p[1] as num).toDouble()];
    }).toList();
  }

  List<String> get indexChoices {
    final keys = result.value?.analysis.keys.toList();
    if (keys == null || keys.isEmpty) {
      return SatelliteConfig.allIndices.take(4).toList();
    }
    return keys;
  }
}
