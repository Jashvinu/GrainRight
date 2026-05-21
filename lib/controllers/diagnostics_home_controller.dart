import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/satellite_config.dart';
import '../models/satellite/diagnostics_model.dart';
import '../services/satellite_service.dart';
import '../services/survey_service.dart';

class DiagnosticsHomeController extends GetxController {
  final _surveyService = SurveyService();
  final _satelliteService = SatelliteService();

  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final result = Rxn<DiagnosticsResult>();
  final selectedIndex = 'ndvi'.obs;
  final survey = Rxn<Map<String, dynamic>>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final latest = await _surveyService.fetchLatestWithPolygon();
      if (latest == null) {
        errorMessage.value =
            'Submit a baseline survey with a farm boundary first.';
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
