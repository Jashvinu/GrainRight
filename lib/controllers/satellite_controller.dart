import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/auth_controller.dart';
import '../controllers/farm_controller.dart';
import '../models/satellite/satellite_date_model.dart';
import '../models/satellite/index_tile_model.dart';
import '../models/satellite/timeline_entry_model.dart';
import '../models/satellite/diagnostics_model.dart';
import '../models/satellite/advanced_monitoring_model.dart';
import '../services/satellite_service.dart';

class _CachedTile {
  final String urlFormat;
  final DateTime cachedAt;
  _CachedTile(this.urlFormat, this.cachedAt);
  bool get isExpired =>
      DateTime.now().difference(cachedAt) > const Duration(hours: 2);
}

class SatelliteController extends GetxController {
  final _service = SatelliteService();

  // Selection state
  final selectedIndex = 'ndvi'.obs;
  final selectedDate = Rxn<SatelliteDate>();
  final availableDates = <SatelliteDate>[].obs;
  final datesLoading = false.obs;

  // Tile state
  final tileUrl = Rxn<String>();
  final tileIsLoading = false.obs;
  final _tileCache = <String, _CachedTile>{};
  final currentTileResult = Rxn<IndexTileResult>();

  // Timeline
  final timeline = <TimelineEntry>[].obs;
  final timelineIsLoading = false.obs;

  // Diagnostics
  final diagnosticsResult = Rxn<DiagnosticsResult>();
  final diagnosticsIsLoading = false.obs;
  final diagnosticsIndex = 'ndvi'.obs;

  // Advanced monitoring
  final advancedResult = Rxn<AdvancedMonitoringResult>();
  final advancedIsLoading = false.obs;
  final selectedAlgorithms =
      <String>['optram_moisture', 'nitrogen_gndvi'].obs;
  final advancedStartDate = ''.obs;
  final advancedEndDate = ''.obs;
  final advancedError = ''.obs;

  String get _jwt => Get.find<AuthController>().accessToken.value;

  @override
  void onInit() {
    super.onInit();
    // Default date range for advanced monitoring (6 months)
    final now = DateTime.now();
    final sixMonthsAgo = DateTime(now.year, now.month - 6, now.day);
    advancedEndDate.value = _fmt(now);
    advancedStartDate.value = _fmt(sixMonthsAgo);

    // React to farm changes
    ever(Get.find<FarmController>().selectedFarm, (farm) {
      if (farm != null) onFarmChanged(farm);
    });

    // Load initial data if farm already selected
    final farm = Get.find<FarmController>().selectedFarm.value;
    if (farm != null) onFarmChanged(farm);
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void onFarmChanged(dynamic farm) {
    tileUrl.value = null;
    currentTileResult.value = null;
    availableDates.clear();
    selectedDate.value = null;
    timeline.clear();
    diagnosticsResult.value = null;
    advancedResult.value = null;
    loadAvailableDates(farm.id);
    loadTimeline(farm.id);
    backgroundSync(farm.id);
  }

  Future<void> loadAvailableDates(String farmId) async {
    datesLoading.value = true;
    try {
      final dates = await _service.getAvailableDates(farmId, _jwt.isEmpty ? null : _jwt);
      availableDates.assignAll(dates);
      if (dates.isNotEmpty && selectedDate.value == null) {
        selectedDate.value = dates.first;
        await loadTile(farmId: farmId, index: selectedIndex.value, date: dates.first);
      }
    } catch (_) {
      // Silent fail for dates — show empty state
    } finally {
      datesLoading.value = false;
    }
  }

  Future<void> loadTile({
    required String farmId,
    required String index,
    required SatelliteDate date,
  }) async {
    final cacheKey = '${farmId}_${index}_${date.date}';
    final cached = _tileCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      tileUrl.value = cached.urlFormat;
      return;
    }

    tileIsLoading.value = true;
    tileUrl.value = null;
    try {
      // Use a 7-day window around the selected date
      final dt = DateTime.parse(date.date);
      final start = _fmt(dt.subtract(const Duration(days: 3)));
      final end = _fmt(dt.add(const Duration(days: 3)));

      final results = await _service.getAgriculturalIndex(
        index: index,
        start: start,
        end: end,
        farmId: farmId,
        jwt: _jwt.isEmpty ? null : _jwt,
      );
      if (results.isNotEmpty) {
        final best = results.first;
        _tileCache[cacheKey] = _CachedTile(best.urlFormat, DateTime.now());
        tileUrl.value = best.urlFormat;
        currentTileResult.value = best;
      }
    } catch (_) {
      tileUrl.value = null;
    } finally {
      tileIsLoading.value = false;
    }
  }

  Future<void> loadTimeline(String farmId) async {
    timelineIsLoading.value = true;
    try {
      final entries = await _service.getFarmTimeline(farmId, _jwt.isEmpty ? null : _jwt);
      timeline.assignAll(entries);
    } catch (_) {
      // Silent fail
    } finally {
      timelineIsLoading.value = false;
    }
  }

  Future<void> loadDiagnostics(String farmId, Map<String, dynamic> polygon) async {
    diagnosticsIsLoading.value = true;
    diagnosticsResult.value = null;
    try {
      final polygonJson = jsonEncode(polygon);
      final result = await _service.getDiagnostics(
        polygonJson: polygonJson,
        indices: ['nitrogen', 'moisture', 'ndvi', 'phosphorus'],
        jwt: _jwt.isEmpty ? null : _jwt,
      );
      diagnosticsResult.value = result;
    } catch (e) {
      Get.snackbar('Error', 'Diagnostics failed: $e',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      diagnosticsIsLoading.value = false;
    }
  }

  Future<void> runAdvancedMonitoring(String farmId, Map<String, dynamic> polygon) async {
    if (selectedAlgorithms.isEmpty) {
      Get.snackbar('Select algorithms', 'Choose at least one algorithm',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    advancedIsLoading.value = true;
    advancedResult.value = null;
    advancedError.value = '';
    try {
      final body = {
        'polygon': polygon,
        'farmId': farmId,
        'startDate': advancedStartDate.value,
        'endDate': advancedEndDate.value,
        'algorithms': selectedAlgorithms.toList(),
        'includeTrends': true,
        'aggregationLevel': 'grid',
        'windowSizeDays': 10,
      };
      final result = await _service.postAdvancedMonitoring(body: body, jwt: _jwt);
      advancedResult.value = result;
    } catch (e) {
      advancedError.value = e.toString().replaceFirst('SatelliteApiException: ', '');
    } finally {
      advancedIsLoading.value = false;
    }
  }

  Future<void> backgroundSync(String farmId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getInt('last_sync_$farmId') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastSync < 3600000) return;
      unawaited(_service.syncSatelliteDates(farmId, _jwt.isEmpty ? null : _jwt));
      await prefs.setInt('last_sync_$farmId', now);
    } catch (_) {}
  }

  void selectDate(SatelliteDate date) {
    selectedDate.value = date;
    final farm = Get.find<FarmController>().selectedFarm.value;
    if (farm != null) {
      loadTile(farmId: farm.id, index: selectedIndex.value, date: date);
    }
  }

  void selectIndex(String index) {
    selectedIndex.value = index;
    final farm = Get.find<FarmController>().selectedFarm.value;
    final date = selectedDate.value;
    if (farm != null && date != null) {
      loadTile(farmId: farm.id, index: index, date: date);
    }
  }

  List<TimelineEntry> entriesForIndex(String index) =>
      timeline.where((e) => e.indexType == index).toList();

  TrendResult? trendFor(String algorithm) {
    return advancedResult.value?.trends
        .where((t) => t.algorithm == algorithm)
        .firstOrNull;
  }
}
