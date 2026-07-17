import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/satellite_config.dart';
import '../models/satellite/farm_alert_model.dart';
import '../models/satellite/diagnostics_model.dart';
import '../services/satellite_service.dart';
import '../services/survey_service.dart';

class DiagnosticsHomeController extends GetxController {
  final _surveyService = SurveyService();
  final _satelliteService = SatelliteService();

  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final result = Rxn<DiagnosticsResult>();
  final advice = Rxn<FarmAlertAdvice>();
  final adviceError = ''.obs;
  final isAdviceLoading = false.obs;
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
    advice.value = null;
    adviceError.value = '';
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
      unawaited(loadAdvice());
    } catch (e, st) {
      debugPrint('[DiagnosticsHomeController.load] $e\n$st');
      errorMessage.value = 'Failed to load diagnostics: $e';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadAdvice() async {
    final diagnostics = result.value;
    final latest = survey.value;
    if (diagnostics == null || latest == null) return;

    isAdviceLoading.value = true;
    adviceError.value = '';
    try {
      final session = Supabase.instance.client.auth.currentSession;
      advice.value = await _satelliteService.getFarmAlertAdvice(
        body: _advicePayload(latest, diagnostics),
        jwt: session?.accessToken,
      );
    } catch (error, stack) {
      debugPrint('[DiagnosticsHomeController.loadAdvice] $error\n$stack');
      adviceError.value =
          'The farm guidance could not be loaded. Your diagnostics results are still available.';
    } finally {
      isAdviceLoading.value = false;
    }
  }

  Map<String, dynamic> _advicePayload(
    Map<String, dynamic> latest,
    DiagnosticsResult diagnostics,
  ) {
    final analysis = diagnostics.analysis.map(
      (key, value) => MapEntry(key, {
        'mean': value.mean,
        'min': value.min,
        'max': value.max,
        'std_dev': value.stdDev,
        'below_threshold': value.belowThreshold,
        if (value.trend != null) 'trend': value.trend,
        if (value.confidence != null) 'confidence': value.confidence,
      }),
    );
    final problems = diagnostics.problems
        .map(
          (problem) => {
            'index': problem.index,
            'type': problem.type,
            if (problem.avgValue != null) 'average_value': problem.avgValue,
            if (problem.avgDecline != null)
              'average_decline': problem.avgDecline,
            if (problem.threshold != null) 'threshold': problem.threshold,
            if (problem.confidence != null) 'confidence': problem.confidence,
          },
        )
        .toList(growable: false);

    return {
      'farm_name': _firstText(latest, const ['farm_name', 'farmer_name']),
      'crop': _firstText(latest, const [
        'main_crop',
        'crop_name',
        'affected_crop',
      ], fallback: 'millet'),
      'variety': _firstText(latest, const [
        'crop_variety',
        'millet_seed_variety',
      ]),
      'growth_stage': _firstText(latest, const [
        'growth_stage',
        'crop_stage',
      ], fallback: 'unknown'),
      'season': _firstText(latest, const ['season'], fallback: 'kharif'),
      'district': _firstText(latest, const ['district']),
      'local_status': {
        'analysis': analysis,
        'problems': problems,
        'images_analyzed': diagnostics.metadata.imagesAnalyzed,
        'days_analyzed': diagnostics.metadata.daysAnalyzed,
      },
    };
  }

  String _firstText(
    Map<String, dynamic> source,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = '${source[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return fallback;
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
