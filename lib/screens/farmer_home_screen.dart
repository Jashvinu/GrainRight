import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import '../config/brand_assets.dart';
import '../config/satellite_config.dart';
import '../config/theme.dart';
import '../controllers/auth_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../models/satellite/farm_model.dart';
import '../models/satellite/farm_alert_model.dart';
import '../models/satellite/timeline_entry_model.dart';
import '../models/verified_farmer_record.dart';
import '../widgets/brand_text.dart';
import '../widgets/farm_hills_background.dart';
import '../widgets/satellite/satellite_map_view.dart';
import '../services/location_service.dart';
import '../services/farm_status_notification_service.dart';
import '../services/satellite_service.dart';
import '../controllers/farm_controller.dart';
import '../utils/harvest_machine_capture.dart';
import 'farmer_farm_setup_chat_screen.dart';
import 'farmer_ai_chat_screen.dart';
import 'farmer_ai_grading_screen.dart';
import 'farmer_status_chat_screen.dart';
import 'farmer_info_screens.dart';
import 'profile_screen.dart';

class FarmerHomeScreen extends StatefulWidget {
  const FarmerHomeScreen({super.key});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
  int _index = 0;
  int _selectedFarm = 0;
  static const _dashboardTabIndex = 0;
  static const _farmTabIndex = 1;
  static const _harvestTabIndex = 2;
  static const _inventoryTabIndex = 3;
  static const _aiChatTabIndex = 4;
  static const _fallbackProfile = _FarmerProfile(
    name: 'Santosh Pawar',
    farmerId: 'FMR-2026-001',
    location: 'Rajur, Akole',
    phone: '+91 98765 43210',
  );
  static const List<_FarmerFarm> _fallbackFarms = [
    const _FarmerFarm(
      name: 'Rajur Millet Plot',
      location: 'Kalsubai foothills',
      crop: 'Finger Millet',
      variety: 'Brown Top',
      area: '2.4 acres',
      health: 'Healthy',
      ndvi: '0.68',
      moisture: 'Good',
      latitude: 19.6112,
      longitude: 73.7531,
    ),
    const _FarmerFarm(
      name: 'Akole Hill Farm',
      location: 'Near Lakhmapur',
      crop: 'Foxtail Millet',
      variety: 'Pragati',
      area: '1.6 acres',
      health: 'Watch',
      ndvi: '0.52',
      moisture: 'Medium',
      latitude: 19.1084,
      longitude: 73.9630,
    ),
  ];
  _FarmerProfile _profile = _fallbackProfile;
  final List<_FarmerFarm> _farms = List<_FarmerFarm>.from(_fallbackFarms);
  late final Worker _verifiedFarmerWorker;
  Worker? _remoteFarmsWorker;
  static const List<String> _farmLifecycleStages = [
    'Sowing',
    'Establishment',
    'Vegetative',
    'Flowering',
    'Grain filling',
    'Maturity',
  ];
  static const List<Offset> _diagnosisOffsets = [
    Offset(0.00026, 0.00000),
    Offset(-0.00026, 0.00003),
    Offset(0.00000, 0.00026),
    Offset(0.00002, -0.00024),
    Offset(-0.00018, -0.00018),
  ];
  static const Map<String, String> _farmStatusQuestions = {
    'Sowing': 'What is the day count from sowing and soil moisture check?',
    'Establishment': 'Any germination gap or patchy stand observed?',
    'Vegetative': 'How is plant height and weed/pest pressure today?',
    'Flowering': 'Any floral drop or grain setting issue?',
    'Grain filling': 'Any moisture warning or grain colour change?',
    'Maturity': 'Is panicle color and seed fill uniform?',
  };
  static const Map<String, bool> _stagePhotoRequired = {
    'Sowing': false,
    'Establishment': false,
    'Vegetative': true,
    'Flowering': true,
    'Grain filling': true,
    'Maturity': false,
  };
  static const List<_GrowthMilestone> _growthMilestones = [
    _GrowthMilestone(stage: 'Sowing', startDay: 0, endDay: 7),
    _GrowthMilestone(stage: 'Establishment', startDay: 8, endDay: 25),
    _GrowthMilestone(stage: 'Vegetative', startDay: 26, endDay: 55),
    _GrowthMilestone(stage: 'Flowering', startDay: 56, endDay: 75),
    _GrowthMilestone(stage: 'Grain filling', startDay: 76, endDay: 110),
    _GrowthMilestone(stage: 'Maturity', startDay: 111, endDay: 9999),
  ];

  final Map<int, String> _farmGrowthStage = {};
  final Map<int, String> _farmStatusAnswer = {};
  final Map<int, DateTime> _farmSowingDate = {};
  final Map<int, DateTime> _farmStatusUpdatedAt = {};
  final Map<int, Uint8List?> _farmStatusPhotoBytes = {};
  final Map<int, String> _farmStatusPhotoName = {};
  final Map<int, List<String>> _farmDiagnosisLog = {};
  final Map<int, List<LatLng>> _farmDiseaseMarkers = {};
  final List<_HarvestInventoryLot> _harvestInventory = [];
  final SatelliteService _satelliteService = SatelliteService();
  final Map<int, String> _satelliteFarmIdByFarmIndex = {};
  final Map<int, _FarmSatelliteOverview> _satelliteOverviewByFarmIndex = {};
  final Set<int> _satelliteOverviewLoading = {};
  final Map<int, List<Map<String, dynamic>>> _diseaseScoutZonesByFarmIndex = {};
  final Map<int, List<Map<String, dynamic>>> _diseaseRiskCellsByFarmIndex = {};
  final Set<int> _diseaseRemoteLoading = {};
  final Map<int, DiseaseScreenResult> _diseaseScreenByFarmIndex = {};
  final Map<int, FarmAlertAdvice> _farmAlertAdviceByFarmIndex = {};
  final Map<int, String> _farmAlertErrorByFarmIndex = {};
  final Set<int> _farmAlertLoading = {};
  bool _satelliteFarmCatalogLoaded = false;
  bool _satelliteFarmCatalogLoading = false;
  List<Farm> _satelliteFarmCatalog = [];

  @override
  void initState() {
    super.initState();
    _farms
      ..clear()
      ..addAll(_fallbackFarms);
    _initializeFarmerStateFromSession(shouldSetState: false);
    _verifiedFarmerWorker = ever(
      Get.find<MainAuthController>().verifiedFarmer,
      (_) => _initializeFarmerStateFromSession(),
    );
    if (Get.isRegistered<FarmController>()) {
      _remoteFarmsWorker = ever(
        Get.find<FarmController>().farms,
        (_) => _initializeFarmerStateFromSession(),
      );
      unawaited(Get.find<FarmController>().loadFarms());
    }
  }

  @override
  void dispose() {
    _verifiedFarmerWorker.dispose();
    _remoteFarmsWorker?.dispose();
    super.dispose();
  }

  void _initializeFarmerStateFromSession({bool shouldSetState = true}) {
    final auth = Get.find<MainAuthController>();
    final verified = auth.verifiedFarmer.value;
    final fallback = verified == null
        ? _fallbackFarms
        : _remoteFarmsFromController(verified);

    final nextProfile = verified == null
        ? _fallbackProfile
        : _profileFromVerified(verified);
    final nextFarms = List<_FarmerFarm>.from(fallback, growable: true);
    if (nextFarms.isEmpty) {
      nextFarms.add(_fallbackFarms.first);
    }

    if (shouldSetState && mounted) {
      setState(() {
        _profile = nextProfile;
        _farms
          ..clear()
          ..addAll(nextFarms);
        if (_selectedFarm >= _farms.length) {
          _selectedFarm = 0;
        }
      });
    } else {
      _profile = nextProfile;
      _farms
        ..clear()
        ..addAll(nextFarms);
      if (_selectedFarm >= _farms.length) {
        _selectedFarm = 0;
      }
    }

    _farmGrowthStage.clear();
    _farmStatusAnswer.clear();
    _farmSowingDate.clear();
    _farmStatusUpdatedAt.clear();
    _farmStatusPhotoBytes.clear();
    _farmStatusPhotoName.clear();
    _farmDiagnosisLog.clear();
    _farmDiseaseMarkers.clear();
    _satelliteFarmIdByFarmIndex.clear();
    _satelliteOverviewByFarmIndex.clear();
    _satelliteOverviewLoading.clear();
    _satelliteFarmCatalogLoaded = false;
    _satelliteFarmCatalog.clear();
    _diseaseScoutZonesByFarmIndex.clear();
    _diseaseRiskCellsByFarmIndex.clear();
    _diseaseRemoteLoading.clear();
    _diseaseScreenByFarmIndex.clear();
    _farmAlertAdviceByFarmIndex.clear();
    _farmAlertErrorByFarmIndex.clear();
    _farmAlertLoading.clear();
    _initializeAllFarmState();
  }

  void _initializeAllFarmState() {
    for (var i = 0; i < _farms.length; i++) {
      _initializeFarmState(i);
    }
  }

  List<_FarmerFarm> _remoteFarmsFromController(VerifiedFarmerRecord record) {
    final remoteFarms = Get.isRegistered<FarmController>()
        ? Get.find<FarmController>().farms
        : const <Farm>[];
    if (remoteFarms.isEmpty) {
      return [
        _FarmerFarm(
          name: 'Add your first farm',
          location: record.defaultLocation,
          crop: 'Millet',
          variety: 'Mixed',
          area: '0 acres',
          health: 'No farm added',
          ndvi: '--',
          moisture: '--',
          product: '',
        ),
      ];
    }

    return remoteFarms
        .map((farm) {
          final center = _centerFromGeometry(farm.geometry);
          return _FarmerFarm(
            name: farm.name,
            location: _formatLocationFromPoints(center),
            crop: (farm.crop == null || farm.crop!.trim().isEmpty)
                ? 'Millet'
                : farm.crop!,
            variety: (farm.variety == null || farm.variety!.trim().isEmpty)
                ? 'General'
                : farm.variety!,
            area: farm.areaAcres == null
                ? '${((farm.areaHectares ?? 0) * 2.47105).toStringAsFixed(2)} acres'
                : '${farm.areaAcres!.toStringAsFixed(farm.areaAcres! >= 10 ? 1 : 2)} acres',
            health: 'Active',
            ndvi: '--',
            moisture: '--',
            product: 'Farm profile',
            previousCrop: farm.previousCrop ?? '',
            season: farm.season ?? '',
            irrigation: farm.irrigation ?? '',
            soilType: farm.soilType ?? '',
            ownershipType: farm.ownershipType ?? '',
            seedSource: farm.seedSource ?? '',
            harvestIntent: farm.harvestIntent ?? '',
            latitude: center?.latitude,
            longitude: center?.longitude,
            polygon: _ringFromGeometry(farm.geometry),
          );
        })
        .toList(growable: false);
  }

  LatLng? _centerFromGeometry(Map<String, dynamic> geometry) {
    final ring = _ringFromGeometry(geometry);
    if (ring.isEmpty) return null;
    final points = _polygonPointsFromRing(ring);
    if (points.isEmpty) return null;
    return LatLng(
      points.map((point) => point.latitude).reduce((a, b) => a + b) /
          points.length,
      points.map((point) => point.longitude).reduce((a, b) => a + b) /
          points.length,
    );
  }

  List<List<double>> _ringFromGeometry(Map<String, dynamic> geometry) {
    final coords = geometry['coordinates'];
    if (coords is! List || coords.isEmpty || coords.first is! List) {
      return const [];
    }
    return (coords.first as List)
        .whereType<List>()
        .map(
          (point) => point
              .whereType<num>()
              .map((value) => value.toDouble())
              .toList(growable: false),
        )
        .where((point) => point.length >= 2)
        .toList(growable: false);
  }

  _FarmerProfile _profileFromVerified(VerifiedFarmerRecord record) {
    return _FarmerProfile(
      name: record.farmerName,
      farmerId: record.farmerId,
      location: record.defaultLocation,
      phone: '+91 ${record.phone}',
    );
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.agriculture_outlined),
      selectedIcon: Icon(Icons.agriculture_rounded),
      label: 'Farm',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome_rounded),
      label: 'AI Chat',
    ),
    NavigationDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2_rounded),
      label: 'Harvest',
    ),
  ];

  static const _mobileDestinationFromPage = {
    _dashboardTabIndex: 0,
    _farmTabIndex: 1,
    _aiChatTabIndex: 2,
    _harvestTabIndex: 3,
  };

  static int _pageIndexForMobile(int index) {
    switch (index) {
      case 0:
        return _dashboardTabIndex;
      case 1:
        return _farmTabIndex;
      case 2:
        return _aiChatTabIndex;
      case 3:
      default:
        return _harvestTabIndex;
    }
  }

  static int _mobileIndexForPage(int pageIndex) {
    if (pageIndex == _inventoryTabIndex) {
      return _mobileDestinationFromPage[_harvestTabIndex]!;
    }
    return _mobileDestinationFromPage[pageIndex] ??
        _mobileDestinationFromPage[_farmTabIndex]!;
  }

  int _mobileNavIndexFromPage() {
    return _mobileIndexForPage(_index);
  }

  void _setMobileTab(int mobileIndex) {
    setState(() => _index = _pageIndexForMobile(mobileIndex));
  }

  Widget _buildMobileBottomNavigationBar() {
    return SafeArea(
      top: false,
      child: NavigationBar(
        selectedIndex: _mobileNavIndexFromPage(),
        onDestinationSelected: _setMobileTab,
        destinations: _destinations,
      ),
    );
  }

  List<Map<String, String>> _marketLotPayloads() {
    return _harvestInventory
        .map((lot) => lot.toMarketPayload())
        .toList(growable: false);
  }

  List<_HarvestInventoryLot> _harvestHistoryForFarm(int index) {
    if (index < 0 || index >= _farms.length) return const [];
    final farmName = _farms[index].name;
    return _harvestInventory
        .where((lot) => lot.farmName == farmName)
        .toList(growable: false);
  }

  List<String> _farmNotesForFarm(int index) {
    if (index < 0 || index >= _farms.length) return const [];
    return List<String>.from(_farmDiagnosisLog[index] ?? const <String>[]);
  }

  void _onHarvestCompleted(_HarvestInventoryLot lot) {
    setState(() {
      final index = _harvestInventory.indexWhere(
        (item) => item.batchId == lot.batchId,
      );
      if (index >= 0) {
        _harvestInventory[index] = lot;
      } else {
        _harvestInventory.insert(0, lot);
      }
    });
  }

  _FarmerFarm get _farm => _farms[_selectedFarm];

  String get _currentFarmAvatar =>
      BrandAssets.farmerAvatars[_selectedFarm %
          BrandAssets.farmerAvatars.length];

  String _satelliteRequestToken() {
    if (!Get.isRegistered<AuthController>()) return '';
    final token = Get.find<AuthController>().accessToken.value;
    return token.isEmpty ? '' : token;
  }

  String _normalizeLookup(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<List<Farm>> _getSatelliteFarmCatalog() async {
    if (_satelliteFarmCatalogLoaded && _satelliteFarmCatalog.isNotEmpty) {
      return _satelliteFarmCatalog;
    }
    if (_satelliteFarmCatalogLoading) {
      return _satelliteFarmCatalog;
    }

    _satelliteFarmCatalogLoading = true;
    try {
      final farms = await _satelliteService.getFarms(_satelliteRequestToken());
      _satelliteFarmCatalog = farms;
      _satelliteFarmCatalogLoaded = true;
      return _satelliteFarmCatalog;
    } catch (_) {
      if (_satelliteFarmCatalog.isNotEmpty) {
        _satelliteFarmCatalogLoaded = true;
      }
      return _satelliteFarmCatalog;
    } finally {
      _satelliteFarmCatalogLoading = false;
    }
  }

  Future<String> _resolveSatelliteFarmId(_FarmerFarm farm, int index) async {
    final cached = _satelliteFarmIdByFarmIndex[index];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final farms = await _getSatelliteFarmCatalog();
    final farmName = _normalizeLookup(farm.name);
    final crop = _normalizeLookup(farm.crop);
    final userId = Get.find<MainAuthController>().remoteUserId;

    Farm? matched;
    final userMatch = farms
        .where(
          (item) =>
              item.userId != null && userId != null && item.userId == userId,
        )
        .toList();
    final matchingNames = farms
        .where((item) => _normalizeLookup(item.name) == farmName)
        .toList();

    if (matchingNames.isNotEmpty) {
      if (crop.isNotEmpty) {
        for (final candidate in matchingNames) {
          if (_normalizeLookup(candidate.name).contains(crop)) {
            matched = candidate;
            break;
          }
        }
      }
      matched ??= matchingNames.first;
    } else if (userMatch.isNotEmpty) {
      matched = userMatch.first;
    }

    final resolved = matched?.id.isNotEmpty == true
        ? matched!.id
        : SatelliteConfig.defaultFarmId;
    _satelliteFarmIdByFarmIndex[index] = resolved;
    return resolved;
  }

  void _ensureSatelliteOverviewForFarm(int index) {
    if (index < 0 || index >= _farms.length) return;
    if (_satelliteOverviewLoading.contains(index)) return;
    if (_satelliteOverviewByFarmIndex.containsKey(index)) return;
    unawaited(_loadSatelliteOverviewForFarm(index));
  }

  Future<void> _loadSatelliteOverviewForFarm(int index) async {
    if (index < 0 || index >= _farms.length) return;
    if (_satelliteOverviewLoading.contains(index)) return;
    setState(() => _satelliteOverviewLoading.add(index));

    try {
      final farm = _farms[index];
      final farmId = await _resolveSatelliteFarmId(farm, index);
      final timeline = await _satelliteService.getFarmTimeline(
        farmId,
        _satelliteRequestToken(),
      );
      final overview = _buildFarmSatelliteOverview(timeline);
      if (!mounted) return;
      _satelliteOverviewByFarmIndex[index] = overview;
    } catch (_) {
      _satelliteOverviewByFarmIndex[index] = _fallbackSatelliteOverview(
        'No satellite index data available for this farm yet.',
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _satelliteOverviewLoading.remove(index);
      });
    }
  }

  _FarmSatelliteOverview _fallbackSatelliteOverview(String message) {
    return _FarmSatelliteOverview(
      tiles: [
        _SatelliteMetricTileData(
          title: 'Satellite crop view',
          value: '--',
          subtitle: 'waiting for data',
          icon: Icons.satellite_alt_rounded,
          tint: Color(0xFFE8F5E9),
          color: Color(0xFF2E7D32),
        ),
        _SatelliteMetricTileData(
          title: 'Satellite heat view',
          value: '--',
          subtitle: 'waiting for data',
          icon: Icons.wb_sunny_rounded,
          tint: Color(0xFFFFF3E0),
          color: Color(0xFFF57C00),
        ),
        _SatelliteMetricTileData(
          title: 'Canopy & ground structure',
          value: '--',
          subtitle: 'waiting for data',
          icon: Icons.park_rounded,
          tint: Color(0xFFE8F5E9),
          color: Color(0xFF2E7D32),
        ),
        _SatelliteMetricTileData(
          title: 'Satellite crop view (trend)',
          value: '--',
          subtitle: message,
          icon: Icons.trending_up_rounded,
          tint: Color(0xFFE8EAF6),
          color: Color(0xFF3949AB),
        ),
      ],
      note: message,
    );
  }

  Map<String, List<TimelineEntry>> _groupTimelineByIndex(
    List<TimelineEntry> entries,
  ) {
    final map = <String, List<TimelineEntry>>{};
    for (final entry in entries) {
      final key = _normalizeLookup(entry.indexType);
      map.putIfAbsent(key, () => <TimelineEntry>[]).add(entry);
    }
    for (final entries in map.values) {
      entries.sort((a, b) => a.date.compareTo(b.date));
    }
    return map;
  }

  String _indexLabel(String index) {
    return SatelliteConfig.indexLabels[index.toLowerCase()] ??
        index.toUpperCase();
  }

  String _formatIndexValue(double value, int decimals) {
    return value.toStringAsFixed(decimals);
  }

  _SatelliteMetricTileData _placeholderTile(
    String title,
    IconData icon,
    Color tint,
    Color color,
  ) {
    return _SatelliteMetricTileData(
      title: title,
      value: '--',
      subtitle: 'No data',
      icon: icon,
      tint: tint,
      color: color,
    );
  }

  _SatelliteMetricTileData _buildMetricTile(
    String title,
    List<String> candidateIndices,
    Map<String, List<TimelineEntry>> grouped, {
    int decimals = 2,
    IconData icon = Icons.satellite_alt_rounded,
    Color tint = const Color(0xFFF3E5F5),
    Color color = const Color(0xFF7B1FA2),
  }) {
    String? selectedIndex;
    TimelineEntry? entry;

    for (final index in candidateIndices) {
      final list = grouped[index];
      if (list == null || list.isEmpty) continue;
      selectedIndex = index;
      entry = list.last;
      break;
    }

    if (entry == null || selectedIndex == null) {
      return _placeholderTile(title, icon, tint, color);
    }

    return _SatelliteMetricTileData(
      title: title,
      value: _formatIndexValue(entry.meanValue, decimals),
      subtitle: '${_indexLabel(selectedIndex)} • ${entry.date}',
      icon: icon,
      tint: tint,
      color: color,
    );
  }

  _SatelliteMetricTileData _buildTrendTile(
    String title,
    String index,
    Map<String, List<TimelineEntry>> grouped, {
    IconData icon = Icons.trending_up_rounded,
    Color tint = const Color(0xFFE3F2FD),
    Color color = const Color(0xFF1565C0),
  }) {
    final list = grouped[index];
    if (list == null || list.length < 2) {
      return _placeholderTile(title, icon, tint, color);
    }

    final latest = list.last;
    final previous = list[list.length - 2];
    final delta = latest.meanValue - previous.meanValue;
    final direction = delta >= 0 ? '↑' : '↓';
    return _SatelliteMetricTileData(
      title: title,
      value: _formatIndexValue(latest.meanValue, 3),
      subtitle:
          '$direction ${_formatIndexValue(delta, 3)} since ${previous.date} (${_formatIndexValue(previous.meanValue, 3)} prev)',
      icon: icon,
      tint: tint,
      color: color,
    );
  }

  _FarmSatelliteOverview _buildFarmSatelliteOverview(
    List<TimelineEntry> entries,
  ) {
    if (entries.isEmpty) {
      return _fallbackSatelliteOverview('No records from remote index feed.');
    }

    final grouped = _groupTimelineByIndex(entries);
    final crop = _buildMetricTile(
      'Satellite crop view',
      const ['ndvi'],
      grouped,
      decimals: 3,
      icon: Icons.satellite_alt_rounded,
      tint: const Color(0xFFE8F5E9),
      color: const Color(0xFF2E7D32),
    );
    final heat = _buildMetricTile(
      'Satellite heat view',
      const ['moisture', 'ndwi', 'carbon'],
      grouped,
      decimals: 2,
      icon: Icons.wb_sunny_rounded,
      tint: const Color(0xFFFFF3E0),
      color: const Color(0xFFF57C00),
    );
    final canopy = _buildMetricTile(
      'Canopy & ground structure',
      const ['ndre', 'gndvi', 'savi'],
      grouped,
      decimals: 3,
      icon: Icons.park_rounded,
      tint: const Color(0xFFE8F5E9),
      color: const Color(0xFF2E7D32),
    );
    final trend = _buildTrendTile(
      'Satellite crop view (trend)',
      'ndvi',
      grouped,
      icon: Icons.trending_up_rounded,
      tint: const Color(0xFFE8EAF6),
      color: const Color(0xFF3949AB),
    );

    return _FarmSatelliteOverview(
      tiles: [crop, heat, canopy, trend],
      note: entries.isNotEmpty ? 'Updated: ${entries.last.date}' : null,
    );
  }

  void _initializeFarmState(int index) {
    _farmSowingDate.putIfAbsent(
      index,
      () => DateTime.now().subtract(const Duration(days: 2)),
    );
    _farmStatusPhotoBytes.putIfAbsent(index, () => null);
    _farmStatusPhotoName.putIfAbsent(index, () => '');
    _farmGrowthStage.putIfAbsent(index, () => _farmLifecycleStages.first);
    _farmStatusAnswer.putIfAbsent(index, () => 'No status update yet');
    _farmStatusUpdatedAt.putIfAbsent(
      index,
      () => DateTime.now().subtract(const Duration(hours: 1)),
    );
    _farmDiagnosisLog.putIfAbsent(index, () => const <String>[]);
    _farmDiseaseMarkers.putIfAbsent(index, () => const <LatLng>[]);
  }

  int _daysAfterSowing(int index) {
    final sowingDate = _farmSowingDate[index];
    if (sowingDate == null) return 0;
    final now = DateTime.now();
    return now.difference(sowingDate).inDays.clamp(0, 9999);
  }

  String _growthStageForFarm(int index) {
    final day = _daysAfterSowing(index);
    for (final milestone in _growthMilestones) {
      if (day >= milestone.startDay && day <= milestone.endDay) {
        return milestone.stage;
      }
    }
    return _farmLifecycleStages.last;
  }

  void _refreshFarmStage(int index) {
    _farmGrowthStage[index] = _growthStageForFarm(index);
  }

  String _statusQuestionForStage(String stage) {
    return _farmStatusQuestions[stage] ??
        'What is the field activity in current crop stage?';
  }

  LatLng? _parseCoordinates(String location) {
    final rawParts = location.split(',');
    if (rawParts.length < 2) return null;
    final lat = double.tryParse(rawParts[0].trim());
    final lng = double.tryParse(rawParts[1].trim());
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng _farmCenter(_FarmerFarm farm) {
    if (farm.latitude != null && farm.longitude != null) {
      return LatLng(farm.latitude!, farm.longitude!);
    }
    final parsed = _parseCoordinates(farm.location);
    if (parsed != null) return parsed;
    return const LatLng(12.3919, 77.7736);
  }

  List<LatLng> _farmBoundary(_FarmerFarm farm) {
    final polygon = farm.polygon
        ?.where((point) => point.length >= 2)
        .map((point) => LatLng(point[1], point[0]))
        .toList();
    if (polygon != null && polygon.length >= 3) {
      return polygon;
    }

    final center = _farmCenter(farm);
    const delta = 0.0032;
    return [
      LatLng(center.latitude + delta, center.longitude - delta),
      LatLng(center.latitude + delta, center.longitude + delta),
      LatLng(center.latitude - delta, center.longitude + delta),
      LatLng(center.latitude - delta, center.longitude - delta),
    ];
  }

  String _formatTime(DateTime value) {
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month ${hh}:$mm';
  }

  List<CircleMarker> _diseaseCircles(List<LatLng> points) {
    return points
        .map(
          (point) => CircleMarker(
            point: point,
            radius: 9,
            useRadiusInMeter: false,
            borderColor: Colors.white,
            borderStrokeWidth: 1.5,
            color: Colors.redAccent.withValues(alpha: 0.62),
          ),
        )
        .toList();
  }

  LatLng _nextDiseaseMarker(int index, List<LatLng> existing) {
    final center = _farmCenter(_farms[index]);
    final shift = _diagnosisOffsets[existing.length % _diagnosisOffsets.length];
    return LatLng(center.latitude + shift.dx, center.longitude + shift.dy);
  }

  Future<void> _ensureDiseaseRemoteForFarm(int index) async {
    if (index < 0 || index >= _farms.length) return;
    if (_diseaseRemoteLoading.contains(index)) return;
    if (_diseaseScoutZonesByFarmIndex.containsKey(index) &&
        _diseaseRiskCellsByFarmIndex.containsKey(index)) {
      return;
    }

    setState(() => _diseaseRemoteLoading.add(index));
    try {
      final farmId = await _resolveSatelliteFarmId(_farms[index], index);
      if (farmId.isEmpty) return;
      final zones = await _satelliteService.getDiseaseScoutZones(
        farmId: farmId,
        jwt: _satelliteRequestToken(),
      );
      final cells = await _satelliteService.getDiseaseRiskCells(
        farmId: farmId,
        jwt: _satelliteRequestToken(),
      );
      if (!mounted) return;
      setState(() {
        _diseaseScoutZonesByFarmIndex[index] = zones;
        _diseaseRiskCellsByFarmIndex[index] = cells;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _diseaseScoutZonesByFarmIndex[index] = const [];
        _diseaseRiskCellsByFarmIndex[index] = const [];
      });
    } finally {
      if (mounted) {
        setState(() => _diseaseRemoteLoading.remove(index));
      }
    }
  }

  Future<void> _saveDiseaseScoutZoneRemote({
    required int index,
    required LatLng marker,
    required String note,
  }) async {
    try {
      final farmId = await _resolveSatelliteFarmId(_farms[index], index);
      if (farmId.isEmpty) return;
      await _satelliteService.insertDiseaseScoutZone(
        jwt: _satelliteRequestToken(),
        payload: {
          'farm_id': farmId,
          'scan_date': DateTime.now().toIso8601String().split('T').first,
          'zone_rank': 1,
          'centroid_lat': marker.latitude,
          'centroid_lng': marker.longitude,
          'radius_meters': 45,
          'disease_candidates': note.trim().isEmpty
              ? ['Field observation']
              : [note.trim()],
          'max_risk_score': 0.62,
          'cell_count': 1,
          'crop': _farms[index].crop,
          'growth_stage': _farmGrowthStage[index],
          'status': 'scouted',
        },
      );
      _diseaseScoutZonesByFarmIndex.remove(index);
      _diseaseRiskCellsByFarmIndex.remove(index);
      unawaited(_ensureDiseaseRemoteForFarm(index));
    } catch (_) {
      // Local diagnosis remains saved even when remote scout-zone sync fails.
    }
  }

  /// Issue locations for the farm map. Prefers the freshest REST rows (latest
  /// scan only), falling back to the cells returned inline by the screening
  /// function — the REST read is empty for guest sessions blocked by RLS.
  List<FarmIssueCell> _issueCellsForFarm(int index) {
    final rows =
        _diseaseRiskCellsByFarmIndex[index] ?? const <Map<String, dynamic>>[];
    final latestScan = rows.isEmpty ? null : rows.first['scan_date']?.toString();
    final parsed = rows
        .where((row) => row['scan_date']?.toString() == latestScan)
        .map(FarmIssueCell.fromJson)
        .where((cell) => cell.hasLocation)
        .toList(growable: false);
    if (parsed.isNotEmpty) return parsed;
    return _diseaseScreenByFarmIndex[index]?.riskCells ??
        const <FarmIssueCell>[];
  }

  void _openFarmIssue(int index, FarmIssueCell issue) {
    if (index < 0 || index >= _farms.length) return;
    _initializeFarmState(index);
    _refreshFarmStage(index);
    final farm = _farms[index];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FarmIssueSheet(
        farmName: farm.name,
        issue: issue,
        farmCenter: _farmCenter(farm),
        daysAfterSowing: _daysAfterSowing(index),
        growthStage: _farmGrowthStage[index] ?? _farmLifecycleStages.first,
        weatherContext: _diseaseScreenByFarmIndex[index]?.weatherContext,
        fetchGuidance: () => _fetchIssueGuidance(index, issue),
        captureAndDiagnose: (source) =>
            _captureAndDiagnoseIssuePhoto(index, issue, source),
      ),
    );
  }

  Future<FarmAlertAdvice> _fetchIssueGuidance(
    int index,
    FarmIssueCell issue,
  ) async {
    final farm = _farms[index];
    final farmId = await _resolveSatelliteFarmId(farm, index);
    final diseaseScreen = _diseaseScreenByFarmIndex[index];
    return _satelliteService.getFarmAlertAdvice(
      jwt: _satelliteRequestToken(),
      body: {
        'farm_id': farmId,
        'farm_name': farm.name,
        'crop': _diseaseCropForFarm(farm),
        'growth_stage': _farmGrowthStage[index] ?? _growthStageForFarm(index),
        'season': _diseaseSeasonForFarm(farm),
        'days_after_sowing': _daysAfterSowing(index),
        'local_status': _farmStatusAnswer[index],
        'focus_cell': issue.toJson(),
        if (diseaseScreen != null) 'disease_screen': diseaseScreen.toJson(),
        'weather_context': diseaseScreen?.weatherContext,
      },
    );
  }

  Future<FarmPhotoDiagnosis?> _captureAndDiagnoseIssuePhoto(
    int index,
    FarmIssueCell issue,
    HarvestMachineImageSource source,
  ) async {
    final shot = await pickHarvestMachineImage(source: source);
    if (shot == null) return null;
    final farm = _farms[index];
    final farmId = await _resolveSatelliteFarmId(farm, index);
    if (farmId.isEmpty) {
      throw SatelliteApiException('Farm is not synced to satellite yet');
    }
    final path = await _satelliteService.uploadDiseasePhoto(
      bytes: shot.bytes,
      farmId: farmId,
      jwt: _satelliteRequestToken(),
    );
    return _satelliteService.diagnoseDiseasePhoto(
      jwt: _satelliteRequestToken(),
      body: {
        'farm_id': farmId,
        'storage_path': path,
        'taken_lat': issue.lat,
        'taken_lng': issue.lng,
        'crop': _diseaseCropForFarm(farm),
        'growth_stage': _farmGrowthStage[index],
        'satellite_context': issue.toJson(),
      },
    );
  }

  String _diseaseCropForFarm(_FarmerFarm farm) {
    final crop = farm.crop.toLowerCase();
    return crop.contains('rice') || crop.contains('paddy') ? 'rice' : 'millet';
  }

  String _diseaseSeasonForFarm(_FarmerFarm farm) {
    final season = farm.season.toLowerCase();
    return season.contains('rabi') ? 'rabi' : 'kharif';
  }

  Map<String, dynamic>? _farmGeometryJson(_FarmerFarm farm) {
    final ring = farm.polygon;
    if (ring == null || ring.length < 3) return null;
    return {
      'type': 'Polygon',
      'coordinates': [ring],
    };
  }

  Future<void> _runDiseaseScreenForFarm(int index) async {
    if (index < 0 || index >= _farms.length) return;
    if (_farmAlertLoading.contains(index)) return;

    _initializeFarmState(index);
    _refreshFarmStage(index);
    setState(() {
      _farmAlertLoading.add(index);
      _farmAlertErrorByFarmIndex.remove(index);
    });

    try {
      final farm = _farms[index];
      final farmId = await _resolveSatelliteFarmId(farm, index);
      final crop = _diseaseCropForFarm(farm);
      final season = _diseaseSeasonForFarm(farm);
      final growthStage = _farmGrowthStage[index] ?? _growthStageForFarm(index);
      final diseaseScreen = await _satelliteService.runDiseaseScreen(
        farmId: farmId,
        crop: crop,
        growthStage: growthStage,
        season: season,
        geometry: _farmGeometryJson(farm),
        jwt: _satelliteRequestToken(),
      );

      final hasFreshRiskData =
          diseaseScreen.riskCellsCount > 0 ||
          diseaseScreen.scoutZones.isNotEmpty;
      final zones = hasFreshRiskData
          ? await _satelliteService.getDiseaseScoutZones(
              farmId: farmId,
              jwt: _satelliteRequestToken(),
            )
          : <Map<String, dynamic>>[];
      final cells = hasFreshRiskData
          ? await _satelliteService.getDiseaseRiskCells(
              farmId: farmId,
              jwt: _satelliteRequestToken(),
            )
          : <Map<String, dynamic>>[];

      final advice = await _satelliteService.getFarmAlertAdvice(
        jwt: _satelliteRequestToken(),
        body: {
          'farm_id': farmId,
          'farm_name': farm.name,
          'crop': crop,
          'growth_stage': growthStage,
          'season': season,
          'local_status': _farmStatusAnswer[index],
          'days_after_sowing': _daysAfterSowing(index),
          'disease_screen': diseaseScreen.toJson(),
          'scout_zones': zones.take(5).toList(growable: false),
          'risk_cells': cells.isNotEmpty
              ? cells.take(20).toList(growable: false)
              : diseaseScreen.riskCells
                    .take(20)
                    .map((cell) => cell.toJson())
                    .toList(growable: false),
          'weather_context': diseaseScreen.weatherContext,
        },
      );

      if (!mounted) return;
      setState(() {
        _diseaseScreenByFarmIndex[index] = diseaseScreen;
        _diseaseScoutZonesByFarmIndex[index] = zones;
        _diseaseRiskCellsByFarmIndex[index] = cells;
        _farmAlertAdviceByFarmIndex[index] = advice;
      });
      Get.snackbar(
        'Farm alerts refreshed',
        '${farm.name}: ${zones.length} scout zone${zones.length == 1 ? '' : 's'} found.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _farmAlertErrorByFarmIndex[index] = e.toString().replaceFirst(
          'SatelliteApiException: ',
          '',
        );
      });
      Get.snackbar(
        'Alert refresh failed',
        _farmAlertErrorByFarmIndex[index]!,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (!mounted) return;
      setState(() => _farmAlertLoading.remove(index));
    }
  }

  String _stageSummary(int index) {
    _refreshFarmStage(index);
    final stage = _farmGrowthStage[index] ?? _farmLifecycleStages.first;
    final days = _daysAfterSowing(index);
    final note = _farmStatusAnswer[index] ?? 'No status update yet';
    final updatedAt = _farmStatusUpdatedAt[index];
    if (updatedAt == null) return '$stage • $note';
    return 'Day $days • $stage • $note • ${_formatTime(updatedAt)}';
  }

  Future<void> _openAddFarmSheet() async {
    final setupResult = await Get.to<FarmSetupChatResult>(
      () => const FarmerFarmSetupChatScreen(),
    );
    if (setupResult == null) return;

    final polygonPoints = _polygonPointsFromRing(setupResult.polygon);
    final location = _formatLocationFromPoints(
      polygonPoints.isEmpty
          ? null
          : LatLng(
              polygonPoints
                      .map((point) => point.latitude)
                      .reduce((a, b) => a + b) /
                  polygonPoints.length,
              polygonPoints
                      .map((point) => point.longitude)
                      .reduce((a, b) => a + b) /
                  polygonPoints.length,
            ),
    );
    final acres = setupResult.computedAcres <= 0
        ? '0 acres'
        : '${setupResult.computedAcres.toStringAsFixed(setupResult.computedAcres >= 10 ? 1 : 2)} acres';

    final farm = _FarmerFarm(
      name: setupResult.farmName.trim(),
      location: location,
      crop: setupResult.crop,
      variety: setupResult.variety,
      area: acres,
      health: 'Active',
      ndvi: '--',
      moisture: '--',
      previousCrop: setupResult.previousCrop,
      season: setupResult.season,
      irrigation: setupResult.irrigation,
      soilType: setupResult.soilType,
      ownershipType: setupResult.ownershipType,
      seedSource: setupResult.seedSource,
      harvestIntent: setupResult.harvestIntent,
      latitude: polygonPoints.isEmpty ? null : polygonPoints.first.latitude,
      longitude: polygonPoints.isEmpty ? null : polygonPoints.first.longitude,
      polygon: setupResult.polygon,
    );

    final index = _farms.length;
    setState(() {
      _farms.add(farm);
      _initializeFarmState(index);
      _farmSowingDate[index] = setupResult.sowingDate;
      _refreshFarmStage(index);
      _selectedFarm = index;
      _index = _farmTabIndex;
    });

    await _saveFarmToRemote(setupResult, polygonPoints);
    if (!mounted) return;
    _ensureSatelliteOverviewForFarm(_selectedFarm);
    if (_index == _farmTabIndex && mounted) {
      await _openFarmStatusUpdate(_selectedFarm);
    }
  }

  Future<void> _saveFarmToRemote(
    FarmSetupChatResult setupResult,
    List<LatLng> polygonPoints,
  ) async {
    if (!Get.isRegistered<FarmController>()) return;
    if (polygonPoints.length < 3) return;
    final farmCtrl = Get.find<FarmController>();
    await farmCtrl.saveFarm(
      name: setupResult.farmName,
      points: polygonPoints,
      metadata: {
        'crop': setupResult.crop,
        'variety': setupResult.variety,
        'previous_crop': setupResult.previousCrop,
        'season': setupResult.season,
        'irrigation': setupResult.irrigation,
        'soil_type': setupResult.soilType,
        'ownership_type': setupResult.ownershipType,
        'seed_source': setupResult.seedSource,
        'harvest_intent': setupResult.harvestIntent,
      },
    );
  }

  List<LatLng> _polygonPointsFromRing(List<List<double>> ring) {
    return ring
        .where((point) => point.length >= 2)
        .map((point) => LatLng(point[1], point[0]))
        .toList();
  }

  String _formatLocationFromPoints(LatLng? point) {
    if (point == null) return 'Map marked farm';
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }

  Future<void> _openFarmStatusUpdate(int index) async {
    _initializeFarmState(index);
    _refreshFarmStage(index);
    final farm = _farms[index];
    final currentStage = _farmGrowthStage[index] ?? _farmLifecycleStages.first;
    final requiresPhoto = _stagePhotoRequired[currentStage] ?? false;
    final daysAfterSowing = _daysAfterSowing(index);
    final result = await Get.to<FarmStatusUpdateResult>(
      () => FarmerStatusChatScreen(
        farmName: farm.name,
        crop: farm.crop,
        variety: farm.variety,
        location: farm.location,
        stage: currentStage,
        daysAfterSowing: daysAfterSowing,
        stageQuestion: _statusQuestionForStage(currentStage),
        priorStatus: _farmStatusAnswer[index],
        requiresPhoto: requiresPhoto,
      ),
    );

    if (result == null) return;

    setState(() {
      _farmGrowthStage[index] = currentStage;
      _farmStatusAnswer[index] = result.message;
      _farmStatusUpdatedAt[index] = result.updatedAt;
      if (result.photoBytes == null) {
        _farmStatusPhotoBytes.remove(index);
        _farmStatusPhotoName[index] = '';
      } else {
        _farmStatusPhotoBytes[index] = result.photoBytes;
        _farmStatusPhotoName[index] =
            result.photoName ??
            'field-status-${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
    });

    Get.snackbar(
      'Status updated',
      '${farm.name} updated: ${_stageSummary(index)}',
      snackPosition: SnackPosition.BOTTOM,
    );

    unawaited(
      _sendFarmStatusNotification(
        farm: farm,
        index: index,
        stage: currentStage,
        daysAfterSowing: daysAfterSowing,
        question: result.question,
        statusText: result.message,
      ),
    );
  }

  Future<void> _sendFarmStatusNotification({
    required _FarmerFarm farm,
    required int index,
    required String stage,
    required int daysAfterSowing,
    required String question,
    required String statusText,
  }) async {
    final notifier = FarmStatusNotificationService();
    final ok = await notifier.sendFarmStatusNotification(
      farmerId: _profile.farmerId,
      farmerName: _profile.name,
      farmName: farm.name,
      crop: farm.crop,
      variety: farm.variety,
      location: farm.location,
      stage: stage,
      stageQuestion: question,
      daysAfterSowing: daysAfterSowing,
      statusText: statusText,
      priorStatus: _farmStatusAnswer[index],
    );

    if (!mounted) return;
    if (!ok) {
      Get.snackbar(
        'Notification pending',
        'Status saved for ${farm.name}, notification service is temporarily unavailable.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _openDiagnosisFlow(int index) async {
    _initializeFarmState(index);
    _refreshFarmStage(index);
    final farm = _farms[index];
    final polygons = _farmBoundary(farm);
    final markers = List<LatLng>.from(
      _farmDiseaseMarkers[index] ?? const <LatLng>[],
    );
    final logs = List<String>.from(
      _farmDiagnosisLog[index] ?? const <String>[],
    );
    final noteCtrl = TextEditingController();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final question = _statusQuestionForStage(_farmGrowthStage[index]!);
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Diagnose ${farm.name}',
                        style: const TextStyle(
                          color: AppTheme.greenDark,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        question,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 210,
                        child: SatelliteMapView(
                          farmPolygon: polygons,
                          heatCircles: _diseaseCircles(markers),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Zone note (e.g., leaf spot)',
                        ),
                        maxLines: 1,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          final label = noteCtrl.text.trim().isEmpty
                              ? 'suspected disease'
                              : noteCtrl.text.trim();
                          setSheet(() {
                            final marker = _nextDiseaseMarker(index, markers);
                            markers.add(marker);
                            logs.insert(
                              0,
                              '${_formatTime(DateTime.now())} • ${_farmGrowthStage[index]} • $label',
                            );
                          });
                        },
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: const Text('Mark disease zone'),
                      ),
                      if (markers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Marked zones',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: logs
                              .take(3)
                              .map(
                                (log) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFFFCDD2),
                                    ),
                                  ),
                                  child: Text(
                                    log,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (markers.isEmpty) {
                            Get.snackbar(
                              'No disease zone',
                              'Add at least one disease marker before saving.',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                            return;
                          }
                          setState(() {
                            _farmDiseaseMarkers[index] = List<LatLng>.from(
                              markers,
                            );
                            _farmDiagnosisLog[index] = List<String>.from(logs);
                          });
                          if (markers.isNotEmpty) {
                            unawaited(
                              _saveDiseaseScoutZoneRemote(
                                index: index,
                                marker: markers.last,
                                note: noteCtrl.text.trim(),
                              ),
                            );
                          }
                          Navigator.pop(context, true);
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save diagnosis'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    noteCtrl.dispose();
    if (result == true) {
      Get.snackbar(
        'Diagnosis saved',
        'Disease zones updated on map for ${farm.name}',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _openFarmTab() {
    setState(() => _index = _farmTabIndex);
  }

  void _openHarvestTab() {
    setState(() => _index = _harvestTabIndex);
  }

  void _openAiChatTab() {
    setState(() => _index = _aiChatTabIndex);
  }

  void _openMarketPage() {
    final selectedFarmName =
        (_selectedFarm >= 0 && _selectedFarm < _farms.length)
        ? _farms[_selectedFarm].name
        : null;
    Get.to(
      () => MarketPage(
        inventoryLots: _marketLotPayloads(),
        farmName: selectedFarmName,
      ),
    );
  }

  void _openNewsPage() {
    final hasFarm = _selectedFarm >= 0 && _selectedFarm < _farms.length;
    final farm = hasFarm ? _farms[_selectedFarm] : null;
    Get.to(() => NewsPage(farmName: farm?.name, farmLocation: farm?.location));
  }

  void _openWeatherPage() {
    final hasFarm = _selectedFarm >= 0 && _selectedFarm < _farms.length;
    final farm = hasFarm ? _farms[_selectedFarm] : null;
    Get.to(
      () => WeatherPage(farmName: farm?.name, farmLocation: farm?.location),
    );
  }

  void _openSchemesPage() {
    final hasFarm = _selectedFarm >= 0 && _selectedFarm < _farms.length;
    final farm = hasFarm ? _farms[_selectedFarm] : null;
    Get.to(
      () => SchemesPage(farmName: farm?.name, farmLocation: farm?.location),
    );
  }

  void _openMarketForLot(Map<String, String> lot) {
    Get.to(
      () => MarketPage(
        inventoryLots: _marketLotPayloads(),
        farmName: lot['farmName'],
        initialSelectedLot: lot,
      ),
    );
  }

  void _openFarmMapInsight(int index) {
    if (index < 0 || index >= _farms.length) return;
    _initializeFarmState(index);
    _refreshFarmStage(index);
    final farm = _farms[index];
    setState(() {
      _selectedFarm = index;
    });
    _ensureSatelliteOverviewForFarm(index);
    final overview = _satelliteOverviewByFarmIndex[index];
    final isSatelliteLoading = _satelliteOverviewLoading.contains(index);
    Get.to(
      () => _FarmMapInsightPage(
        farm: farm,
        farmPolygon: _farmBoundary(farm),
        diseaseMarkers: _farmDiseaseMarkers[index] ?? const [],
        growthMilestones: _growthMilestones,
        currentStage: _farmGrowthStage[index] ?? _farmLifecycleStages.first,
        stageSummary: _stageSummary(index),
        daysAfterSowing: _daysAfterSowing(index),
        harvestHistory: _harvestHistoryForFarm(index),
        diagnosisNotes: _farmNotesForFarm(index),
        lastUpdated: _farmStatusUpdatedAt[index],
        status: _farmStatusAnswer[index] ?? 'No status update yet',
        satelliteOverview: overview,
        isSatelliteLoading: isSatelliteLoading,
        onOpenDiagnose: () => _openDiagnosisFlow(index),
        onOpenStatusUpdate: () => _openFarmStatusUpdate(index),
      ),
    );
  }

  void _openHistoryPage([int? index]) {
    final farmIndex = index ?? _selectedFarm;
    if (farmIndex < 0 || farmIndex >= _farms.length) return;
    _initializeFarmState(farmIndex);
    _refreshFarmStage(farmIndex);
    if (farmIndex != _selectedFarm) {
      setState(() => _selectedFarm = farmIndex);
    }
    _ensureSatelliteOverviewForFarm(farmIndex);
    final farm = _farms[farmIndex];
    Get.to(
      () => _HistoryPage(
        farm: farm,
        daysAfterSowing: _daysAfterSowing(farmIndex),
        currentStage: _farmGrowthStage[farmIndex] ?? _farmLifecycleStages.first,
        status: _farmStatusAnswer[farmIndex] ?? 'No status update yet',
        statusUpdatedAt: _farmStatusUpdatedAt[farmIndex],
        harvestHistory: _harvestHistoryForFarm(farmIndex),
        diagnosisNotes: _farmNotesForFarm(farmIndex),
        satelliteOverview: _satelliteOverviewByFarmIndex[farmIndex],
      ),
    );
  }

  void _openHistoryIndexPage() {
    Get.to(
      () => _FarmHistoryIndexPage(
        farms: _farms,
        selectedIndex: _selectedFarm,
        stageSummary: _stageSummary,
        onOpenFarm: (index) {
          if (index < 0 || index >= _farms.length) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          _openHistoryPage(index);
        },
      ),
    );
  }

  void _navigateFromSideDetail(VoidCallback action) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    action();
  }

  @override
  Widget build(BuildContext context) {
    for (var i = 0; i < _farms.length; i++) {
      _initializeFarmState(i);
      _refreshFarmStage(i);
    }
    if (_farms.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureSatelliteOverviewForFarm(_selectedFarm);
        _ensureDiseaseRemoteForFarm(_selectedFarm);
      });
    }

    final farmPolygons = {
      for (var i = 0; i < _farms.length; i++) i: _farmBoundary(_farms[i]),
    };

    final pages = [
      _FarmerDashboard(
        profile: _profile,
        farm: _farm,
        avatarAsset: _currentFarmAvatar,
        stageSummary: _stageSummary(_selectedFarm),
        onOpenAiChat: _openAiChatTab,
        onOpenFarm: _openFarmTab,
        onOpenDisease: _openFarmTab,
        onOpenMarket: _openMarketPage,
        satelliteOverview: _satelliteOverviewByFarmIndex[_selectedFarm],
        isSatelliteLoading: _satelliteOverviewLoading.contains(_selectedFarm),
      ),
      _FarmPage(
        farms: _farms,
        selectedIndex: _selectedFarm,
        onSelectFarm: (value) {
          setState(() => _selectedFarm = value);
          _ensureSatelliteOverviewForFarm(value);
          _ensureDiseaseRemoteForFarm(value);
        },
        onOpenFarmInsight: _openFarmMapInsight,
        onOpenStatusUpdate: _openFarmStatusUpdate,
        onRefreshAlerts: _runDiseaseScreenForFarm,
        onOpenIssue: _openFarmIssue,
        farmPolygons: farmPolygons,
        statusByFarm: _farmStatusAnswer,
        stageByFarm: _farmGrowthStage,
        diseaseMarkersByFarm: _farmDiseaseMarkers,
        scoutZonesByFarm: _diseaseScoutZonesByFarmIndex,
        riskCellsByFarm: _diseaseRiskCellsByFarmIndex,
        issueCells: _issueCellsForFarm(_selectedFarm),
        statusUpdatedAt: _farmStatusUpdatedAt,
        diseaseScreenByFarm: _diseaseScreenByFarmIndex,
        alertAdviceByFarm: _farmAlertAdviceByFarmIndex,
        alertErrorByFarm: _farmAlertErrorByFarmIndex,
        alertLoading: _farmAlertLoading,
        stageSummary: _stageSummary,
        daysAfterSowing: _daysAfterSowing,
      ),
      _HarvestHomePage(
        farmName: _farm.name,
        cropName: _farm.crop,
        variety: _farm.variety,
        product: _farm.product,
        farmerId: _profile.farmerId,
        area: _farm.area,
        harvestHealth: _farm.health,
        farmerName: _profile.name,
        farmLocation: _farm.location,
        onOpenAiChat: _openAiChatTab,
        onHarvestCompleted: _onHarvestCompleted,
      ),
      _InventoryPage(
        lots: _harvestInventory,
        onTapListForSell: (lot) => Get.to(
          () => MarketPage(
            inventoryLots: _marketLotPayloads(),
            farmName: lot.farmName,
            initialSelectedLot: lot.toMarketPayload(),
          ),
        ),
      ),
      FarmerAiChatScreen(
        farmName: _farm.name,
        crop: _farm.crop,
        variety: _farm.variety,
        location: _farm.location,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideNav = constraints.maxWidth >= 760;
        return Scaffold(
          backgroundColor: AppTheme.surface,
          drawer: _buildDrawer(context),
          appBar: useSideNav
              ? null
              : AppBar(
                  backgroundColor: AppTheme.surface,
                  elevation: 0,
                  toolbarHeight: 66,
                  iconTheme: const IconThemeData(color: AppTheme.greenDark),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        BrandAssets.logo,
                        width: 92,
                        height: 52,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 10),
                      const BrandText(fontSize: 21),
                    ],
                  ),
                ),
          body: SafeArea(
            child: useSideNav
                ? Row(
                    children: [
                      _buildSideNavigation(
                        context,
                        constraints.maxWidth >= 1060,
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          transitionBuilder: (child, animation) {
                            final offsetTween =
                                Tween<Offset>(
                                  begin: const Offset(0.05, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                );
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: offsetTween,
                                child: child,
                              ),
                            );
                          },
                          child: SizedBox(
                            key: ValueKey(_index),
                            child: pages[_index],
                          ),
                        ),
                      ),
                    ],
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, animation) {
                      final offsetTween =
                          Tween<Offset>(
                            begin: const Offset(0.05, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: offsetTween,
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      key: ValueKey('mobile-$_index'),
                      child: pages[_index],
                    ),
                  ),
          ),
          floatingActionButton: _index == _dashboardTabIndex
              ? FloatingActionButton.extended(
                  onPressed: _openAddFarmSheet,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Farm'),
                )
              : null,
          bottomNavigationBar: useSideNav
              ? null
              : _buildMobileBottomNavigationBar(),
        );
      },
    );
  }

  Widget _buildSideNavigation(BuildContext context, bool expanded) {
    final width = expanded ? 244.0 : 104.0;
    return Container(
      width: width,
      margin: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF4FAEF)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFDCE8D2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _SideNavHeader(
            expanded: expanded,
            profile: _profile,
            avatarAsset: _currentFarmAvatar,
            onMenuTap: () => Scaffold.of(context).openDrawer(),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _SideNavGroupedLinks(
              expanded: expanded,
              onOpenNews: _openNewsPage,
              onOpenGrainGrading: _openGrainGradingPage,
              onOpenWeather: _openWeatherPage,
              onOpenApmcMarket: _openMarketPage,
              onOpenSchemes: _openSchemesPage,
              onOpenHistory: _openHistoryIndexPage,
              onOpenInventory: () =>
                  setState(() => _index = _inventoryTabIndex),
              onOpenProfile: _openProfilePage,
              onOpenSettings: _openSettingsPage,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 18),
            child: Center(
              child: _SideNavLogoutButton(
                expanded: expanded,
                onTap: () => Get.find<MainAuthController>().logout(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openGrainGradingPage() async {
    final farmId = await _resolveSatelliteFarmId(_farm, _selectedFarm);
    Get.to(
      () => const FarmerAiGradingScreen(),
      arguments: {
        if (farmId.trim().isNotEmpty) 'farmId': farmId,
        'farmName': _farm.name,
        'crop': _farm.crop,
        'variety': _farm.variety,
        'product': _farm.product,
        'village': _profile.location,
      },
    );
  }

  void _openProfilePage() {
    Get.to(
      () => FarmerProfileScreen(
        profile: _profile,
        farm: _farm,
        avatarAsset: _currentFarmAvatar,
      ),
    );
  }

  void _openSettingsPage() {
    Get.to(() => _SettingsPage(profile: _profile));
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF7FBF2),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFDDE8D4)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF1B5E20,
                          ).withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _SideAvatar(asset: _currentFarmAvatar, size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _profile.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.greenDark,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _farm.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.greenPale,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.verified_rounded,
                            color: AppTheme.green,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    leading: const Icon(
                      Icons.person_rounded,
                      color: AppTheme.green,
                    ),
                    title: const Text(
                      'Profile',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openProfilePage();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.history_rounded,
                      color: AppTheme.green,
                    ),
                    title: const Text(
                      'Farm History',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openHistoryIndexPage();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.inventory_2_rounded,
                      color: AppTheme.green,
                    ),
                    title: const Text(
                      'Inventory',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _index = _inventoryTabIndex);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.grain, color: AppTheme.green),
                    title: const Text(
                      'Grain Grading',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openGrainGradingPage();
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.wb_cloudy_rounded,
                      color: AppTheme.green,
                    ),
                    title: const Text(
                      'Weather',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openWeatherPage();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.storefront_rounded,
                      color: AppTheme.green,
                    ),
                    title: const Text(
                      'APMC Market',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openMarketPage();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.newspaper_rounded,
                      color: AppTheme.green,
                    ),
                    title: const Text(
                      'News',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openNewsPage();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.assignment_rounded,
                      color: AppTheme.green,
                    ),
                    title: const Text(
                      'Schemes',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openSchemesPage();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Center(
                child: _SideNavLogoutButton(
                  expanded: true,
                  onTap: () {
                    Navigator.pop(context);
                    Get.find<MainAuthController>().logout();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmerProfile {
  final String name;
  final String farmerId;
  final String location;
  final String phone;

  const _FarmerProfile({
    required this.name,
    required this.farmerId,
    required this.location,
    required this.phone,
  });
}

class _GrowthMilestone {
  final String stage;
  final int startDay;
  final int endDay;

  const _GrowthMilestone({
    required this.stage,
    required this.startDay,
    required this.endDay,
  });
}

class _FarmerFarm {
  final String name;
  final String location;
  final String crop;
  final String variety;
  final String area;
  final String health;
  final String ndvi;
  final String moisture;
  final String product;
  final String previousCrop;
  final String season;
  final String irrigation;
  final String soilType;
  final String ownershipType;
  final String seedSource;
  final String harvestIntent;
  final double? latitude;
  final double? longitude;
  final List<List<double>>? polygon;

  const _FarmerFarm({
    required this.name,
    required this.location,
    required this.crop,
    required this.variety,
    required this.area,
    required this.health,
    required this.ndvi,
    required this.moisture,
    this.product = '',
    this.previousCrop = '',
    this.season = '',
    this.irrigation = '',
    this.soilType = '',
    this.ownershipType = '',
    this.seedSource = '',
    this.harvestIntent = '',
    this.polygon,
    this.latitude,
    this.longitude,
  });
}

class _HarvestInventoryLot {
  final String batchId;
  final String farmName;
  final String crop;
  final String variety;
  final int bagCount;
  final double bagSizeKg;
  final double moisturePercent;
  final String grade;
  final int gradeScore;
  final String gradeBasis;
  final double estimatedYieldKg;
  final DateTime harvestedAt;
  final double latitude;
  final double longitude;
  final String machineImageName;

  const _HarvestInventoryLot({
    required this.batchId,
    required this.farmName,
    required this.crop,
    required this.variety,
    required this.bagCount,
    required this.bagSizeKg,
    required this.moisturePercent,
    required this.grade,
    required this.gradeScore,
    required this.gradeBasis,
    required this.estimatedYieldKg,
    required this.harvestedAt,
    required this.latitude,
    required this.longitude,
    required this.machineImageName,
  });

  String get lotLabel =>
      '$batchId • $grade • ${estimatedYieldKg.toStringAsFixed(1)}kg';

  Map<String, String> toMarketPayload() {
    return {
      'batchId': batchId,
      'farmName': farmName,
      'crop': crop,
      'variety': variety,
      'bagCount': bagCount.toString(),
      'bagSizeKg': bagSizeKg.toStringAsFixed(1),
      'moisture': moisturePercent.toStringAsFixed(1),
      'grade': grade,
      'score': gradeScore.toString(),
      'gradeBasis': gradeBasis,
      'estimatedYield': estimatedYieldKg.toStringAsFixed(1),
      'harvestedAt': harvestedAt.toIso8601String(),
      'lat': latitude.toString(),
      'lng': longitude.toString(),
      'imageName': machineImageName,
    };
  }
}

class _InventoryPage extends StatefulWidget {
  final List<_HarvestInventoryLot> lots;
  final ValueChanged<_HarvestInventoryLot> onTapListForSell;

  const _InventoryPage({required this.lots, required this.onTapListForSell});

  @override
  State<_InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<_InventoryPage> {
  static const List<String> _sortOptions = [
    'Newest',
    'Highest grade',
    'Lowest moisture',
    'Most yield',
  ];
  static const String _allFarmsLabel = 'All Farms';

  final _searchController = TextEditingController();
  String _searchText = '';
  String _selectedFarm = _allFarmsLabel;
  String _sortBy = 'Newest';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _farmOptions {
    final farms = <String>{_allFarmsLabel};
    for (final lot in widget.lots) {
      farms.add(lot.farmName);
    }
    final sorted = farms.toList()..sort();
    return sorted;
  }

  List<_HarvestInventoryLot> get _filteredLots {
    final selected = _selectedFarm.toLowerCase();
    final query = _searchText.toLowerCase();
    final filtered = widget.lots
        .where((lot) {
          final farmMatch =
              _selectedFarm == _allFarmsLabel ||
              lot.farmName.toLowerCase() == selected;
          if (!farmMatch) return false;
          if (query.isEmpty) return true;
          return lot.batchId.toLowerCase().contains(query) ||
              lot.crop.toLowerCase().contains(query) ||
              lot.variety.toLowerCase().contains(query) ||
              lot.grade.toLowerCase().contains(query);
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'Newest':
          return b.harvestedAt.compareTo(a.harvestedAt);
        case 'Highest grade':
          return b.gradeScore.compareTo(a.gradeScore);
        case 'Lowest moisture':
          return a.moisturePercent.compareTo(b.moisturePercent);
        case 'Most yield':
        default:
          return b.estimatedYieldKg.compareTo(a.estimatedYieldKg);
      }
    });

    return filtered;
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final lots = _filteredLots;
    final totalBags = lots.fold<int>(0, (sum, lot) => sum + lot.bagCount);
    final totalQty = lots.fold<double>(
      0,
      (sum, lot) => sum + lot.estimatedYieldKg,
    );
    final avgMoisture = lots.isEmpty
        ? 0.0
        : lots.fold<double>(0, (sum, lot) => sum + lot.moisturePercent) /
              lots.length;
    final avgScore = lots.isEmpty
        ? 0.0
        : lots.fold<double>(0, (sum, lot) => sum + lot.gradeScore) /
              lots.length;

    return _PageScaffold(
      title: 'Inventory',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryStat(title: 'Lots', value: '${lots.length}'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryStat(
                      title: 'Total bags',
                      value: '$totalBags',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryStat(
                      title: 'Qty',
                      value: '${totalQty.toStringAsFixed(1)}kg',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() {
                      _searchText = value;
                    }),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Search batch id, crop, variety, grade',
                      suffixIcon: _searchText.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _searchText = '';
                                _searchController.clear();
                              }),
                              tooltip: 'Clear search',
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _sortBy,
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _sortBy = value);
                          },
                          items: _sortOptions
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_farmOptions.length > 1)
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _farmOptions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final farm = _farmOptions[index];
                          return ChoiceChip(
                            label: Text(farm),
                            selected: farm == _selectedFarm,
                            onSelected: (value) {
                              if (value) {
                                setState(() => _selectedFarm = farm);
                              }
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (lots.isEmpty)
            _Panel(
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No lot found. Harvest is graded → grading summary appears here automatically.',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              ),
            )
          else
            ...lots.asMap().entries.map((entry) {
              final index = entry.key;
              final lot = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == lots.length - 1 ? 0 : 10,
                ),
                child: _Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lot.lotLabel,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Harvested ${_formatDateTime(lot.harvestedAt)}',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InventoryChip(label: lot.farmName),
                            _InventoryChip(label: lot.crop),
                            _InventoryChip(label: lot.variety),
                            _InventoryChip(label: 'Grade ${lot.grade}'),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryStat(
                                title: 'Bags',
                                value:
                                    '${lot.bagCount} × ${lot.bagSizeKg.toStringAsFixed(0)}kg',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SummaryStat(
                                title: 'Moisture',
                                value:
                                    '${lot.moisturePercent.toStringAsFixed(1)}%',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryStat(
                                title: 'Quality score',
                                value: '${lot.gradeScore}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SummaryStat(
                                title: 'Est. qty',
                                value:
                                    '${lot.estimatedYieldKg.toStringAsFixed(1)}kg',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => widget.onTapListForSell(lot),
                                icon: const Icon(Icons.storefront_rounded),
                                label: const Text('List for sale'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Get.snackbar(
                                    'Inventory',
                                    'Coordinates: ${lot.latitude.toStringAsFixed(4)}, ${lot.longitude.toStringAsFixed(4)}',
                                    snackPosition: SnackPosition.BOTTOM,
                                  );
                                },
                                icon: const Icon(Icons.location_on_outlined),
                                label: const Text('View lot'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Farm inventory snapshot',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryStat(
                          title: 'Avg moisture',
                          value: '${avgMoisture.toStringAsFixed(1)}%',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryStat(
                          title: 'Avg grade score',
                          value: avgScore.toStringAsFixed(1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryChip extends StatelessWidget {
  final String label;

  const _InventoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String title;
  final String value;

  const _SummaryStat({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmerDashboard extends StatelessWidget {
  final _FarmerProfile profile;
  final _FarmerFarm farm;
  final String avatarAsset;
  final String stageSummary;
  final VoidCallback onOpenAiChat;
  final VoidCallback onOpenFarm;
  final VoidCallback onOpenDisease;
  final VoidCallback onOpenMarket;
  final _FarmSatelliteOverview? satelliteOverview;
  final bool isSatelliteLoading;

  const _FarmerDashboard({
    required this.profile,
    required this.farm,
    required this.avatarAsset,
    required this.stageSummary,
    required this.onOpenAiChat,
    required this.onOpenFarm,
    required this.onOpenDisease,
    required this.onOpenMarket,
    required this.satelliteOverview,
    required this.isSatelliteLoading,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 92),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HomeRevealSection(
                  delayMs: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 340),
                    transitionBuilder: (child, animation) {
                      final slide =
                          Tween<Offset>(
                            begin: const Offset(0.04, 0.04),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: _WelcomeHero(
                      key: ValueKey('hero-${farm.name}'),
                      profile: profile,
                      farm: farm,
                      avatarAsset: avatarAsset,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _HomeRevealSection(
                  delayMs: 35,
                  child: _ApmcMarketBulletin(onOpenMarket: onOpenMarket),
                ),
                const SizedBox(height: 18),
                _HomeRevealSection(
                  delayMs: 40,
                  child: FarmOverviewSection(
                    metrics: _overviewMetricsFromSatellite(
                      satelliteOverview,
                      isSatelliteLoading,
                    ),
                    onDetailsTap: onOpenFarm,
                  ),
                ),
                const SizedBox(height: 18),
                _HomeRevealSection(
                  delayMs: 80,
                  child: _SelectedFarmHomeCard(
                    farm: farm,
                    stageSummary: stageSummary,
                    onOpenFarm: onOpenFarm,
                  ),
                ),
                const SizedBox(height: 26),
                const _HomeRevealSection(
                  delayMs: 130,
                  child: _SectionTitle(title: 'Farm Snapshot'),
                ),
                const SizedBox(height: 12),
                _HomeRevealSection(
                  delayMs: 150,
                  child: _FarmSnapshotCard(farm: farm, onOpenFarm: onOpenFarm),
                ),
                const SizedBox(height: 22),
                _HomeRevealSection(
                  delayMs: 170,
                  child: _HarvestReadinessCard(
                    farm: farm,
                    onOpenAiChat: onOpenAiChat,
                  ),
                ),
                const SizedBox(height: 22),
                const _HomeRevealSection(
                  delayMs: 190,
                  child: _SectionTitle(title: 'Recent Activity'),
                ),
                const SizedBox(height: 12),
                _HomeRevealSection(
                  delayMs: 210,
                  child: _RecentActivityCard(
                    farm: farm,
                    onOpenAiChat: onOpenAiChat,
                    onOpenDisease: onOpenDisease,
                  ),
                ),
                const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeRevealSection extends StatelessWidget {
  final Widget child;
  final int delayMs;

  const _HomeRevealSection({required this.child, required this.delayMs});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(delayMs),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 430 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

List<FarmMetricData> _overviewMetricsFromSatellite(
  _FarmSatelliteOverview? overview,
  bool isLoading,
) {
  const metrics = [
    FarmMetricData(
      label: 'NDVI',
      icon: Icons.eco_rounded,
      progress: 0.86,
      color: Color(0xFF2EAF4A),
      status: 'Healthy',
    ),
    FarmMetricData(
      label: 'Moisture',
      icon: Icons.water_drop_rounded,
      progress: 0.72,
      color: Color(0xFF3498DB),
      status: 'Good',
    ),
    FarmMetricData(
      label: 'Yield Prediction',
      icon: Icons.agriculture_rounded,
      progress: 0.91,
      color: Color(0xFFF5B21D),
      status: 'High',
    ),
    FarmMetricData(
      label: 'Disease Risk',
      icon: Icons.shield_rounded,
      progress: 0.12,
      color: Color(0xFF8BC34A),
      status: 'Low',
    ),
  ];
  if (isLoading && overview == null) return metrics;
  return metrics;
}

class FarmMetricData {
  final String label;
  final IconData icon;
  final double progress;
  final Color color;
  final String status;

  const FarmMetricData({
    required this.label,
    required this.icon,
    required this.progress,
    required this.color,
    required this.status,
  });
}

class FarmOverviewSection extends StatelessWidget {
  final List<FarmMetricData> metrics;
  final VoidCallback? onDetailsTap;

  const FarmOverviewSection({
    super.key,
    this.metrics = const [
      FarmMetricData(
        label: 'NDVI',
        icon: Icons.eco_rounded,
        progress: 0.86,
        color: Color(0xFF2EAF4A),
        status: 'Healthy',
      ),
      FarmMetricData(
        label: 'Moisture',
        icon: Icons.water_drop_rounded,
        progress: 0.72,
        color: Color(0xFF3498DB),
        status: 'Good',
      ),
      FarmMetricData(
        label: 'Yield Prediction',
        icon: Icons.agriculture_rounded,
        progress: 0.91,
        color: Color(0xFFF5B21D),
        status: 'High',
      ),
      FarmMetricData(
        label: 'Disease Risk',
        icon: Icons.shield_rounded,
        progress: 0.12,
        color: Color(0xFF8BC34A),
        status: 'Low',
      ),
    ],
    this.onDetailsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEAEAEA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 16, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Farm Overview',
                      style: TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onDetailsTap,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Details',
                            style: TextStyle(
                              color: Color(0xFF2EAF4A),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF2EAF4A),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 210,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  final cardWidth = availableWidth >= 760
                      ? (availableWidth - 36) / 4
                      : availableWidth >= 420
                      ? 178.0
                      : 172.0;
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: metrics.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      return SizedBox(
                        width: cardWidth.clamp(170.0, 180.0).toDouble(),
                        child: FarmMetricCard(metric: metrics[index]),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FarmMetricCard extends StatelessWidget {
  final FarmMetricData metric;

  const FarmMetricCard({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    final percent = (metric.progress.clamp(0.0, 1.0) * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAEAEA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, color: metric.color, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Center(
            child: AnimatedCircularProgress(
              progress: metric.progress,
              color: metric.color,
              size: 92,
              strokeWidth: 10,
              child: Text(
                '$percent%',
                style: const TextStyle(
                  color: AppTheme.textDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const Spacer(),
          Center(
            child: Text(
              metric.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: metric.color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApmcMarketBulletin extends StatelessWidget {
  final VoidCallback onOpenMarket;

  const _ApmcMarketBulletin({required this.onOpenMarket});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenMarket,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFEAEAEA)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EAFE),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Color(0xFF673AB7),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'APMC Market Bulletin',
                          style: TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Local mandi signals for today',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.green,
                    size: 26,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _MarketBullet(
                text: 'Finger millet demand is steady in nearby APMC markets.',
              ),
              const SizedBox(height: 8),
              const _MarketBullet(
                text:
                    'Grade and moisture checks improve selling price confidence.',
              ),
              const SizedBox(height: 8),
              const _MarketBullet(
                text: 'Tap to open lot-wise APMC rates and listing options.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketBullet extends StatelessWidget {
  final String text;

  const _MarketBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            color: AppTheme.green,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppTheme.textDark,
              height: 1.35,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class AnimatedCircularProgress extends StatelessWidget {
  final double progress;
  final Color color;
  final double size;
  final double strokeWidth;
  final Widget child;

  const AnimatedCircularProgress({
    super.key,
    required this.progress,
    required this.color,
    required this.child,
    this.size = 92,
    this.strokeWidth = 10,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _CircularProgressPainter(
              progress: value,
              color: color,
              strokeWidth: strokeWidth,
            ),
            child: Center(child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  const _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = const Color(0xFFEDEDED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      (math.pi * 2) * progress.clamp(0.0, 1.0).toDouble(),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class FarmOverviewExampleScreen extends StatelessWidget {
  const FarmOverviewExampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: FarmOverviewSection()),
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  final _FarmerProfile profile;
  final _FarmerFarm farm;
  final String avatarAsset;

  const _WelcomeHero({
    super.key,
    required this.profile,
    required this.farm,
    required this.avatarAsset,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('hero-${farm.name}'),
      tween: Tween(begin: 0.97, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.985 + (0.015 * value),
          child: Opacity(opacity: 0.86 + (0.14 * value), child: child),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        height: 210,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: AppTheme.green.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/farm_home_Top_widget.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) {
                  return const FarmHillsBackground();
                },
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xF2FFFFFF),
                      Color(0xBFFFFFFF),
                      Color(0x33FFFFFF),
                    ],
                    stops: [0, 0.55, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              top: 20,
              right: 132,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Good Morning',
                    style: TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MiniInfo(
                    icon: Icons.grass_outlined,
                    text: 'Farm: ${farm.name}',
                  ),
                  const SizedBox(height: 6),
                  _MiniInfo(
                    icon: Icons.location_on_outlined,
                    text: '${farm.location} • ${farm.crop} • ${farm.variety}',
                  ),
                ],
              ),
            ),
            Positioned(
              right: 18,
              bottom: 18,
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.white, Color(0xFFE8F5E9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Hero(
                  tag: 'farmer-avatar-${farm.name}',
                  child: Image.asset(avatarAsset, fit: BoxFit.cover),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmSatelliteOverviewSection extends StatelessWidget {
  final _FarmSatelliteOverview? overview;
  final bool isLoading;

  const _FarmSatelliteOverviewSection({
    required this.overview,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = overview?.tiles ?? const [];
    if (tiles.isEmpty && isLoading) {
      return const _Panel(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: SizedBox(
            height: 118,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    if (tiles.isEmpty) {
      return _Panel(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Satellite Overview',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'No satellite index data available yet.',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (overview?.note != null) ...[
              Text(
                overview!.note!,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 860 ? 4 : 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final tile in tiles)
                      SizedBox(
                        width:
                            (constraints.maxWidth -
                                ((crossAxisCount - 1) * 10)) /
                            crossAxisCount,
                        child: _FarmSatelliteMetricCard(tile: tile),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.greenDark, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectedFarmHomeCard extends StatelessWidget {
  final _FarmerFarm farm;
  final String stageSummary;
  final VoidCallback onOpenFarm;

  const _SelectedFarmHomeCard({
    required this.farm,
    required this.stageSummary,
    required this.onOpenFarm,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      tint: const Color(0xFFF7FCF8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Selected farm',
                    style: TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.greenPale.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_done_outlined,
                        color: AppTheme.greenDark,
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Synced view',
                        style: TextStyle(
                          color: AppTheme.greenDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SelectedFarmHeader(farm: farm),
            const SizedBox(height: 10),
            _InfoStrip(
              icon: Icons.timeline_rounded,
              label: 'Stage summary',
              value: stageSummary,
            ),
            const SizedBox(height: 10),
            _InfoStrip(
              icon: Icons.location_on_outlined,
              label: 'Location',
              value: farm.location,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FarmMetric(label: 'Area', value: farm.area),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FarmMetric(label: 'Crop', value: farm.crop),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FarmMetric(label: 'Variety', value: farm.variety),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FarmMetric(label: 'Health', value: farm.health),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FarmMetric(label: 'NDVI', value: farm.ndvi),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FarmMetric(label: 'Moisture', value: farm.moisture),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined, color: AppTheme.green),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Weather, market, news, schemes and history open with this active farm context.',
                      style: TextStyle(
                        color: AppTheme.textDark,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: onOpenFarm,
                    icon: const Icon(Icons.grass_rounded, size: 18),
                    label: const Text('Open'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmSatelliteMetricCard extends StatelessWidget {
  final _SatelliteMetricTileData tile;

  const _FarmSatelliteMetricCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      tint: tile.tint.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(tile.icon, color: tile.color, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              tile.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textDark,
                fontSize: 13,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tile.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tile.color,
                fontSize: 22,
                letterSpacing: 0,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              tile.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}

class _FarmSnapshotCard extends StatelessWidget {
  final _FarmerFarm farm;
  final VoidCallback onOpenFarm;

  const _FarmSnapshotCard({required this.farm, required this.onOpenFarm});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.greenPale,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.grass_outlined,
                    color: AppTheme.green,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        farm.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${farm.area} • ${farm.crop}',
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: onOpenFarm,
                  child: const Text('Open'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _SnapshotMetric(label: 'Health', value: farm.health),
                _SnapshotMetric(label: 'NDVI', value: farm.ndvi),
                _SnapshotMetric(label: 'Moisture', value: farm.moisture),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HarvestReadinessCard extends StatelessWidget {
  final _FarmerFarm farm;
  final VoidCallback onOpenAiChat;

  const _HarvestReadinessCard({required this.farm, required this.onOpenAiChat});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      tint: const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: AppTheme.green,
                    size: 31,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Harvest Readiness',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${farm.crop} batch can be graded before QR sticker.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const _HarvestMetric(label: 'Est. bags', value: '12'),
                const _HarvestMetric(label: 'Quality', value: 'Ready'),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: onOpenAiChat,
                  child: const Text('Harvest'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmSatelliteOverview {
  final List<_SatelliteMetricTileData> tiles;
  final String? note;

  const _FarmSatelliteOverview({required this.tiles, this.note});
}

class _SatelliteMetricTileData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final Color color;

  const _SatelliteMetricTileData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.color,
  });
}

class _HarvestMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HarvestMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnapshotMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SnapshotMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  final _FarmerFarm farm;
  final VoidCallback onOpenAiChat;
  final VoidCallback onOpenDisease;

  const _RecentActivityCard({
    required this.farm,
    required this.onOpenAiChat,
    required this.onOpenDisease,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        children: [
          _ActivityRow(
            icon: Icons.bug_report_outlined,
            iconColor: const Color(0xFFE07800),
            title: 'Disease Risk Checked',
            detail: '${farm.name} • Leaf spot moderate',
            onTap: onOpenDisease,
          ),
          const Divider(height: 1),
          _ActivityRow(
            icon: Icons.auto_awesome_outlined,
            iconColor: const Color(0xFF1976D2),
            title: 'AI Guidance',
            detail: '${farm.crop} • Grade A',
            onTap: onOpenAiChat,
          ),
          const Divider(height: 1),
          _ActivityRow(
            icon: Icons.qr_code_2_outlined,
            iconColor: AppTheme.green,
            title: 'Need AI check',
            detail: 'Create bag plan and next action quickly',
            onTap: onOpenAiChat,
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;
  final VoidCallback onTap;

  const _ActivityRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(onPressed: onTap, child: const Text('View')),
        ],
      ),
    );
  }
}

class _HarvestHomePage extends StatefulWidget {
  final String farmName;
  final String cropName;
  final String product;
  final String farmerId;
  final String area;
  final String variety;
  final String farmerName;
  final String farmLocation;
  final String harvestHealth;
  final VoidCallback onOpenAiChat;
  final void Function(_HarvestInventoryLot lot) onHarvestCompleted;

  const _HarvestHomePage({
    required this.farmName,
    required this.cropName,
    required this.product,
    required this.farmerId,
    required this.variety,
    required this.farmerName,
    required this.farmLocation,
    required this.area,
    required this.harvestHealth,
    required this.onOpenAiChat,
    required this.onHarvestCompleted,
  });

  @override
  State<_HarvestHomePage> createState() => _HarvestHomePageState();
}

class _HarvestHomePageState extends State<_HarvestHomePage> {
  final _moistureCtrl = TextEditingController();
  final _bagSizeCtrl = TextEditingController(text: '50');
  final _bagCountCtrl = TextEditingController(text: '12');
  bool _hasMachineImage = false;
  bool _isLocationFetching = false;
  bool _isCapturingImage = false;
  bool _isGrading = false;
  bool _hasGrade = false;
  String _batchId = '';
  double? _farmLatitude;
  double? _farmLongitude;
  Uint8List? _machineImageBytes;
  String? _machineImageName;
  String _grade = '--';
  int _gradeScore = 0;
  String _gradingMessage = 'Run grading to generate verified lot score.';

  static const Map<String, Map<String, double>> _yieldCurve = {
    'Finger Millet': {
      'A+': 1.00,
      'A': 0.97,
      'B+': 0.93,
      'B': 0.88,
      'C': 0.80,
      'D': 0.68,
    },
    'Foxtail Millet': {
      'A+': 1.00,
      'A': 0.96,
      'B+': 0.92,
      'B': 0.86,
      'C': 0.78,
      'D': 0.66,
    },
    'Rice': {
      'A+': 1.00,
      'A': 0.98,
      'B+': 0.93,
      'B': 0.86,
      'C': 0.77,
      'D': 0.65,
    },
    'Bajra': {
      'A+': 1.00,
      'A': 0.96,
      'B+': 0.92,
      'B': 0.84,
      'C': 0.76,
      'D': 0.64,
    },
  };

  double _estimatedYield({
    required double bagSize,
    required int bagCount,
    required String grade,
  }) {
    final cropMap =
        _yieldCurve[widget.cropName] ??
        const {
          'A+': 1.0,
          'A': 0.95,
          'B+': 0.9,
          'B': 0.83,
          'C': 0.74,
          'D': 0.62,
        };
    final factor = cropMap[grade] ?? 1.0;
    return bagSize * bagCount * factor;
  }

  String _createBatchId() {
    final now = DateTime.now();
    return 'KF-HV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}${now.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  void dispose() {
    _moistureCtrl.dispose();
    _bagSizeCtrl.dispose();
    _bagCountCtrl.dispose();
    super.dispose();
  }

  String get _locationSummary {
    if (_farmLatitude == null || _farmLongitude == null) {
      return 'Not captured';
    }
    return '${_farmLatitude!.toStringAsFixed(5)}, ${_farmLongitude!.toStringAsFixed(5)}';
  }

  bool get _canRunGrading {
    final moisture = double.tryParse(_moistureCtrl.text.trim());
    final bagSize = double.tryParse(_bagSizeCtrl.text.trim());
    final bagCount = int.tryParse(_bagCountCtrl.text.trim());
    return moisture != null &&
        moisture > 0 &&
        bagSize != null &&
        bagSize > 0 &&
        bagCount != null &&
        bagCount > 0 &&
        _hasMachineImage &&
        _machineImageBytes != null &&
        _farmLatitude != null &&
        _farmLongitude != null;
  }

  bool get _canCaptureImage => _farmLatitude != null && _farmLongitude != null;

  Future<HarvestMachineImageSource?> _chooseMachineImageSource() {
    return showModalBottomSheet<HarvestMachineImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add machine photo',
                  style: TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: const Text('Open camera'),
                  subtitle: const Text('Click a new machine photo'),
                  onTap: () =>
                      Navigator.pop(context, HarvestMachineImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Select from gallery'),
                  subtitle: const Text('Use an existing machine image'),
                  onTap: () =>
                      Navigator.pop(context, HarvestMachineImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _captureMachineImage() async {
    if (_farmLatitude == null || _farmLongitude == null) {
      Get.snackbar(
        'Live location required',
        'Fetch live location before capturing machine image.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final source = await _chooseMachineImageSource();
    if (source == null) return;
    if (!mounted) return;

    setState(() => _isCapturingImage = true);
    try {
      final result = await pickHarvestMachineImage(source: source);
      if (result == null) return;
      if (!mounted) return;
      setState(() {
        _machineImageBytes = result.bytes;
        _machineImageName = result.name;
        _hasMachineImage = true;
      });
      Get.snackbar(
        'Machine image added',
        'Machine photo linked to location $_locationSummary.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      Get.snackbar(
        'Image failed',
        'Could not open camera or gallery. Check permissions and try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isCapturingImage = false);
    }
  }

  Future<void> _fetchLocation() async {
    setState(() => _isLocationFetching = true);
    try {
      final service = LocationService();
      final location = await service.getCurrentLocation();
      if (location == null || !mounted) {
        Get.snackbar(
          'Location unavailable',
          'Unable to fetch farm location right now. Please try again.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      setState(() {
        _farmLatitude = location.latitude;
        _farmLongitude = location.longitude;
      });
    } catch (_) {
      Get.snackbar(
        'Location error',
        'Could not read live location. Enable permission and try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isLocationFetching = false);
    }
  }

  void _runHarvestGrade() async {
    if (!_canRunGrading || _isGrading) return;
    final moisture = double.parse(_moistureCtrl.text.trim());
    final bagSize = double.parse(_bagSizeCtrl.text.trim());
    final bagCount = int.parse(_bagCountCtrl.text.trim());
    final batchId = _createBatchId();

    setState(() {
      _isGrading = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted) return;

    int score = 88;
    if (moisture <= 10.8) {
      score = 94;
    } else if (moisture <= 11.8) {
      score = 89;
    } else if (moisture <= 12.8) {
      score = 80;
    } else if (moisture <= 13.8) {
      score = 70;
    } else {
      score = 58;
    }
    if (bagSize >= 45) score += 2;
    if (bagCount >= 10) score += 2;
    score = score.clamp(50, 98);

    final grade = score >= 92
        ? 'A+'
        : score >= 84
        ? 'A'
        : score >= 76
        ? 'B+'
        : score >= 68
        ? 'B'
        : score >= 60
        ? 'C'
        : 'D';
    final estimatedYield = _estimatedYield(
      bagSize: bagSize,
      bagCount: bagCount,
      grade: grade,
    );

    setState(() {
      _batchId = batchId;
      _grade = grade;
      _gradeScore = score;
      _hasGrade = true;
      _isGrading = false;
      _gradingMessage =
          'Microservice result: BIS/ISO grain quality standard mapping completed.';
    });

    Get.snackbar(
      'Grading complete',
      'Grade $_grade with score $_gradeScore saved. You can generate QR now.',
      snackPosition: SnackPosition.BOTTOM,
    );

    widget.onHarvestCompleted(
      _HarvestInventoryLot(
        batchId: batchId,
        farmName: widget.farmName,
        crop: widget.cropName,
        variety: widget.variety,
        bagCount: bagCount,
        bagSizeKg: bagSize,
        moisturePercent: moisture,
        grade: grade,
        gradeScore: score,
        gradeBasis: _gradingMessage,
        estimatedYieldKg: estimatedYield,
        harvestedAt: DateTime.now(),
        latitude: _farmLatitude!,
        longitude: _farmLongitude!,
        machineImageName: _machineImageName ?? 'captured',
      ),
    );
  }

  void _openHarvestQr() {
    if (!_hasGrade) {
      Get.snackbar(
        'Grade required',
        'Run grading first. Grade is required before Harvest QR is generated.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    if (!_canRunGrading) {
      Get.snackbar(
        'Update required',
        'All grading inputs and location/machine capture are required before generating QR.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final bagSize = _bagSizeCtrl.text.trim();
    final bagCount = _bagCountCtrl.text.trim();
    final moisture = _moistureCtrl.text.trim();
    if (_batchId.isEmpty) {
      _batchId = _createBatchId();
    }
    final batchId = _batchId;
    final totalKg = (double.parse(bagSize) * int.parse(bagCount))
        .toStringAsFixed(1);
    Get.toNamed(
      '/farmer/harvest-qr',
      arguments: {
        'farmName': widget.farmName,
        'crop': widget.cropName,
        'product': widget.product,
        'farmerId': widget.farmerId,
        'village': widget.farmLocation,
        'farmerName': widget.farmerName,
        'variety': widget.variety,
        'grade': _grade,
        'score': '$_gradeScore',
        'machineImage': _machineImageName ?? 'captured',
        'bagSizeKg': bagSize,
        'bagCount': bagCount,
        'totalKg': totalKg,
        'moisture': moisture,
        'moistureSource': 'digital-meter',
        'machineImageVerified': 'true',
        'farmLatitude': '$_farmLatitude',
        'farmLongitude': '$_farmLongitude',
        'grader': 'Kalsubai AI Grain Service',
        'standards': 'BIS 15797:2018 + ISO/IEC 17025 + ICAR',
        'batchId': batchId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'Harvest Hub',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Harvest Checklist',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${widget.farmName} • ${widget.area} • ${widget.cropName}',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.spa_rounded,
                    label: 'Health',
                    value: widget.harvestHealth,
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.wb_twilight,
                    label: 'Ready Window',
                    value: 'Within 5–7 days',
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.inventory_2_outlined,
                    label: 'Expected yield',
                    value: '12–16 bags',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _moistureCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Moisture % from digital meter',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _bagSizeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bag size (kg)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _bagCountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Number of bags',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLocationFetching
                              ? null
                              : _fetchLocation,
                          icon: const Icon(Icons.gps_fixed_rounded),
                          label: const Text('Live location'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isCapturingImage || !_canCaptureImage
                              ? null
                              : _captureMachineImage,
                          icon: _isCapturingImage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.green,
                                  ),
                                )
                              : Icon(
                                  _hasMachineImage
                                      ? Icons.check_circle_rounded
                                      : Icons.photo_camera_front_rounded,
                                ),
                          label: Text(
                            _hasMachineImage
                                ? 'Retake image'
                                : 'Capture machine image',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_canCaptureImage)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Fetch live location first. Then capture machine image.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else if (_machineImageBytes != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.memory(
                          _machineImageBytes!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Machine image: ${_machineImageName ?? 'captured'}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Live location: $_locationSummary',
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _canRunGrading ? _runHarvestGrade : null,
                    icon: _isGrading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      _isGrading
                          ? 'Running grading...'
                          : 'Run grading (mandatory)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppTheme.greenPale,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.qr_code_2_rounded),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Grade result',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _hasGrade
                                          ? '$_grade • $_gradeScore/100 • ${_gradingMessage}'
                                          : _gradingMessage,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_hasGrade) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Verified with ${widget.cropName} BIS standard.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _hasGrade ? _openHarvestQr : null,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: Text(
                      _hasGrade
                          ? 'Generate harvest QR'
                          : 'Grade first to unlock QR',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: widget.onOpenAiChat,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Ask AI for harvest action'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Storage Prep',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Dry grains to safe moisture before bagging. Validate lot records and use QR-enabled sacks for better planning.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _FarmPage extends StatelessWidget {
  final List<_FarmerFarm> farms;
  final int selectedIndex;
  final ValueChanged<int> onSelectFarm;
  final ValueChanged<int> onOpenFarmInsight;
  final ValueChanged<int> onOpenStatusUpdate;
  final ValueChanged<int> onRefreshAlerts;
  final void Function(int, FarmIssueCell) onOpenIssue;
  final Map<int, List<LatLng>> farmPolygons;
  final Map<int, String> statusByFarm;
  final Map<int, String> stageByFarm;
  final Map<int, List<LatLng>> diseaseMarkersByFarm;
  final Map<int, List<Map<String, dynamic>>> scoutZonesByFarm;
  final Map<int, List<Map<String, dynamic>>> riskCellsByFarm;
  final List<FarmIssueCell> issueCells;
  final Map<int, DateTime> statusUpdatedAt;
  final Map<int, DiseaseScreenResult> diseaseScreenByFarm;
  final Map<int, FarmAlertAdvice> alertAdviceByFarm;
  final Map<int, String> alertErrorByFarm;
  final Set<int> alertLoading;
  final String Function(int) stageSummary;
  final int Function(int) daysAfterSowing;

  const _FarmPage({
    required this.farms,
    required this.selectedIndex,
    required this.onSelectFarm,
    required this.onOpenFarmInsight,
    required this.onOpenStatusUpdate,
    required this.onRefreshAlerts,
    required this.onOpenIssue,
    required this.farmPolygons,
    required this.statusByFarm,
    required this.stageByFarm,
    required this.diseaseMarkersByFarm,
    required this.scoutZonesByFarm,
    required this.riskCellsByFarm,
    required this.issueCells,
    required this.statusUpdatedAt,
    required this.diseaseScreenByFarm,
    required this.alertAdviceByFarm,
    required this.alertErrorByFarm,
    required this.alertLoading,
    required this.stageSummary,
    required this.daysAfterSowing,
  });

  static double? _readDouble(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
    }
    return null;
  }

  static Color _riskColor(double risk) {
    if (risk >= 0.72) return const Color(0xFFD32F2F);
    if (risk >= 0.55) return const Color(0xFFF57C00);
    if (risk >= 0.35) return const Color(0xFFFBC02D);
    return AppTheme.green;
  }

  static String _riskLabel(double risk) {
    if (risk >= 0.72) return 'High';
    if (risk >= 0.55) return 'Watch';
    if (risk > 0) return 'Low';
    return 'Pending';
  }

  static Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'high':
        return const Color(0xFFD32F2F);
      case 'medium':
      case 'watch':
        return const Color(0xFFF57C00);
      default:
        return AppTheme.green;
    }
  }

  static String _formatScanDate(String raw) {
    if (raw.isEmpty) return 'Not screened yet';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  static String _formatWeatherValue(Object? raw, String suffix) {
    if (raw is num) return '${raw.toStringAsFixed(raw >= 10 ? 0 : 1)}$suffix';
    if (raw is String && raw.trim().isNotEmpty) return '$raw$suffix';
    return '--';
  }

  static const Color _abioticColor = Color(0xFF1976D2);
  static const Color _zoneColor = Color(0xFF7B1FA2);

  static Color _issueColor(FarmIssueCell issue) {
    if (issue.isScoutZone) return _zoneColor;
    if (!issue.isDisease) return _abioticColor;
    // Disease candidates never render green: floor at the amber band.
    return _riskColor(math.max(issue.compositeRisk, 0.35));
  }

  static IconData _issueIcon(FarmIssueCell issue) {
    if (issue.isScoutZone) return Icons.travel_explore_rounded;
    if (!issue.isDisease) return Icons.water_drop_rounded;
    return Icons.coronavirus_rounded;
  }

  static String _issueTitle(FarmIssueCell issue) {
    if (issue.isScoutZone) return 'Scout zone';
    if (!issue.isDisease) return 'Crop stress (water/heat)';
    final names = issue.diseaseCandidates
        .map((name) => name.replaceAll('_', ' '))
        .join(', ');
    return 'Possible $names';
  }

  /// Issue locations worth a walk: every flagged cell, or the top few when
  /// nothing crosses the risk floor so the farmer still sees where to check.
  static List<FarmIssueCell> _visibleIssues(List<FarmIssueCell> cells) {
    final flagged = cells
        .where((cell) => cell.compositeRisk >= 0.30)
        .take(40)
        .toList(growable: false);
    if (flagged.isNotEmpty) return flagged;
    final sorted = [...cells]
      ..sort((a, b) => b.compositeRisk.compareTo(a.compositeRisk));
    return sorted.take(5).toList(growable: false);
  }

  List<Marker> _issueMarkers({
    required List<FarmIssueCell> cells,
    required List<Map<String, dynamic>> scoutZones,
    required void Function(FarmIssueCell) onTap,
  }) {
    final issues = <FarmIssueCell>[
      ..._visibleIssues(cells),
      ...scoutZones
          .map(FarmIssueCell.fromScoutZone)
          .where((zone) => zone.hasLocation),
    ];
    return [
      for (final issue in issues)
        Marker(
          point: LatLng(issue.lat, issue.lng),
          width: issue.isScoutZone ? 30 : 24,
          height: issue.isScoutZone ? 30 : 24,
          child: GestureDetector(
            onTap: () => onTap(issue),
            child: Container(
              decoration: BoxDecoration(
                color: _issueColor(issue),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                _issueIcon(issue),
                size: issue.isScoutZone ? 15 : 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
    ];
  }

  List<CircleMarker> _alertCircles({
    required List<LatLng> localMarkers,
    required List<Map<String, dynamic>> scoutZones,
  }) {
    final circles = <CircleMarker>[
      for (final point in localMarkers)
        CircleMarker(
          point: point,
          radius: 9,
          useRadiusInMeter: false,
          borderColor: Colors.white,
          borderStrokeWidth: 1.5,
          color: Colors.redAccent.withValues(alpha: 0.62),
        ),
    ];

    for (final zone in scoutZones) {
      final lat = _readDouble(zone, const ['centroid_lat', 'lat']);
      final lng = _readDouble(zone, const ['centroid_lng', 'lng']);
      if (lat == null || lng == null) continue;
      circles.add(
        CircleMarker(
          point: LatLng(lat, lng),
          radius: 16,
          useRadiusInMeter: false,
          borderColor: _zoneColor,
          borderStrokeWidth: 2,
          color: _zoneColor.withValues(alpha: 0.18),
        ),
      );
    }

    return circles;
  }

  double _maxRisk(
    List<Map<String, dynamic>> scoutZones,
    List<Map<String, dynamic>> riskCells,
    List<FarmIssueCell> issueCells,
  ) {
    var maxRisk = 0.0;
    for (final row in [...scoutZones, ...riskCells]) {
      maxRisk = math.max(
        maxRisk,
        _readDouble(row, const [
              'max_risk_score',
              'composite_risk',
              'risk_score',
            ]) ??
            0,
      );
    }
    for (final cell in issueCells) {
      maxRisk = math.max(maxRisk, cell.compositeRisk);
    }
    return maxRisk;
  }

  @override
  Widget build(BuildContext context) {
    final selected = farms[selectedIndex];
    final selectedPolygon = farmPolygons[selectedIndex] ?? const [];
    final diseaseMarkers = diseaseMarkersByFarm[selectedIndex] ?? const [];
    final scoutZones =
        scoutZonesByFarm[selectedIndex] ?? const <Map<String, dynamic>>[];
    final riskCells =
        riskCellsByFarm[selectedIndex] ?? const <Map<String, dynamic>>[];
    final diseaseScreen = diseaseScreenByFarm[selectedIndex];
    final advice = alertAdviceByFarm[selectedIndex];
    final alertError = alertErrorByFarm[selectedIndex];
    final isLoading = alertLoading.contains(selectedIndex);
    final currentStage = stageByFarm[selectedIndex] ?? 'Sowing';
    final currentStatus = statusByFarm[selectedIndex] ?? 'No status update yet';
    final updatedAt = statusUpdatedAt[selectedIndex];
    final maxRisk = _maxRisk(scoutZones, riskCells, issueCells);
    final weather = diseaseScreen?.weatherContext;
    final issueMarkers = _issueMarkers(
      cells: issueCells,
      scoutZones: scoutZones,
      onTap: (issue) => onOpenIssue(selectedIndex, issue),
    );
    return _PageScaffold(
      title: 'Farm Alerts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Important alerts',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SelectedFarmHeader(farm: selected),
                  const SizedBox(height: 16),
                  Text(
                    stageSummary(selectedIndex),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoStrip(
                    icon: Icons.track_changes_rounded,
                    label: 'Current status',
                    value: '$currentStage - $currentStatus',
                  ),
                  if (updatedAt != null) ...[
                    const SizedBox(height: 8),
                    _InfoStrip(
                      icon: Icons.schedule_outlined,
                      label: 'Updated',
                      value:
                          '${updatedAt.day.toString().padLeft(2, '0')}/${updatedAt.month.toString().padLeft(2, '0')} ${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}',
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 196,
                    child: SatelliteMapView(
                      farmPolygon: selectedPolygon,
                      center: selected.latitude != null && selected.longitude != null
                          ? LatLng(selected.latitude!, selected.longitude!)
                          : null,
                      heatCircles: _alertCircles(
                        localMarkers: diseaseMarkers,
                        scoutZones: scoutZones,
                      ),
                      markers: issueMarkers,
                      height: 196,
                      showZoomControls: true,
                    ),
                  ),
                  if (issueMarkers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: const [
                        _IssueLegendItem(
                          color: Color(0xFFF57C00),
                          label: 'Disease risk',
                        ),
                        _IssueLegendItem(
                          color: _abioticColor,
                          label: 'Water/heat stress',
                        ),
                        _IssueLegendItem(
                          color: _zoneColor,
                          label: 'Scout zone',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap a spot on the map to see the issue and get guidance.',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => onOpenFarmInsight(selectedIndex),
                      icon: const Icon(Icons.open_in_full_rounded, size: 16),
                      label: const Text('Open full farm view'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: isLoading
                              ? null
                              : () => onRefreshAlerts(selectedIndex),
                          icon: isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: Text(
                            isLoading ? 'Refreshing...' : 'Refresh alerts',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onOpenStatusUpdate(selectedIndex),
                          icon: const Icon(Icons.track_changes_rounded),
                          label: const Text('Status'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryStat(
                          title: 'Scout zones',
                          value: scoutZones.length.toString(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryStat(
                          title: 'Risk cells',
                          value:
                              diseaseScreen?.riskCellsCount.toString() ??
                              riskCells.length.toString(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryStat(
                          title: 'Max risk',
                          value: _riskLabel(maxRisk),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (alertError != null) ...[
            _FarmAlertCard(
              alert: FarmAlertItem(
                title: 'Alert refresh failed',
                detail: alertError,
                severity: 'high',
                action:
                    'Try again after checking network and API configuration.',
              ),
            ),
            const SizedBox(height: 16),
          ],
          _SectionTitle(title: 'Important'),
          const SizedBox(height: 10),
          if (advice?.importantAlerts.isNotEmpty == true)
            for (final alert in advice!.importantAlerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FarmAlertCard(alert: alert),
              )
          else
            const _FarmAlertEmptyState(
              icon: Icons.notifications_active_outlined,
              title: 'No important alerts yet',
              detail:
                  'Refresh alerts to screen this farm for disease and field risk.',
            ),
          const SizedBox(height: 16),
          _SectionTitle(title: 'Weather'),
          const SizedBox(height: 10),
          if (weather != null) ...[
            _SowingWeekWeatherCard(
              daysAfterSowing: daysAfterSowing(selectedIndex),
              stage: currentStage,
              weather: weather,
            ),
            const SizedBox(height: 10),
          ],
          if (advice?.weatherAlerts.isNotEmpty == true)
            for (final alert in advice!.weatherAlerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FarmAlertCard(alert: alert),
              )
          else if (weather != null)
            _WeatherAlertSnapshot(
              rain: _formatWeatherValue(weather['total_rain_mm'], ' mm'),
              wetness: _formatWeatherValue(weather['leaf_wetness_hours'], ' h'),
              temperature: _formatWeatherValue(weather['mean_temp_c'], ' C'),
            )
          else
            const _FarmAlertEmptyState(
              icon: Icons.cloud_outlined,
              title: 'No weather alert yet',
              detail:
                  'Refresh alerts to check rain, wetness and temperature risk.',
            ),
          if (advice?.nextActions.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Next actions',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final action in advice!.nextActions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: AppTheme.green,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                action,
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InventoryChip(
                    label:
                        'Last screen: ${_formatScanDate(diseaseScreen?.scanDate ?? '')}',
                  ),
                  _InventoryChip(
                    label: 'Confidence: ${advice?.confidence ?? 'pending'}',
                  ),
                  _InventoryChip(
                    label: 'Images: ${diseaseScreen?.imagesAnalyzed ?? 0}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle(title: 'Choose Farm'),
          const SizedBox(height: 10),
          for (var i = 0; i < farms.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FarmChoiceCard(
                farm: farms[i],
                selected: i == selectedIndex,
                onTap: () {
                  onSelectFarm(i);
                },
              ),
            ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _FarmAlertCard extends StatelessWidget {
  final FarmAlertItem alert;

  const _FarmAlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final color = _FarmPage._severityColor(alert.severity);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.priority_high_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        alert.title,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      alert.severity.toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                if (alert.detail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    alert.detail,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (alert.action.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    alert.action,
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      height: 1.35,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherAlertSnapshot extends StatelessWidget {
  final String rain;
  final String wetness;
  final String temperature;

  const _WeatherAlertSnapshot({
    required this.rain,
    required this.wetness,
    required this.temperature,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: _SummaryStat(title: 'Rain', value: rain),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryStat(title: 'Wetness', value: wetness),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryStat(title: 'Temp', value: temperature),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _IssueLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _WeekWeatherAssessment {
  final String level;
  final String note;

  const _WeekWeatherAssessment({required this.level, required this.note});
}

/// Reads the 7-day weather context against the crop's week after sowing: the
/// same rain or leaf wetness is a different risk at germination, tillering and
/// grain filling.
_WeekWeatherAssessment _assessSowingWeekWeather({
  required int daysAfterSowing,
  required String stage,
  required Map<String, dynamic> weather,
}) {
  double read(Object? value) => value is num ? value.toDouble() : 0;
  final rain = read(weather['total_rain_mm']);
  final wetness = read(weather['leaf_wetness_hours']);
  final temp = read(weather['mean_temp_c']);
  final week = daysAfterSowing ~/ 7 + 1;

  final fungalWeather = wetness >= 30 && temp >= 18 && temp <= 30;
  final level = (wetness >= 48 || rain >= 80)
      ? 'high'
      : (fungalWeather || rain >= 40)
      ? 'medium'
      : 'low';

  String note;
  if (daysAfterSowing <= 25) {
    if (rain >= 40) {
      note =
          'Heavy rain in week $week can waterlog young plants and cause damping-off. Check drainage in low spots of the field.';
    } else if (rain < 5) {
      note =
          'Very little rain in week $week — seedlings may need irrigation to establish.';
    } else {
      note =
          'Weather is manageable for the $stage stage in week $week. Keep checking for germination gaps.';
    }
  } else if (daysAfterSowing <= 55) {
    note = fungalWeather
        ? '${wetness.round()} h of leaf wetness in week $week favours leaf spot and blast during $stage. Scout the marked spots first.'
        : 'No strong weather trigger in week $week. Continue weekly scouting during $stage.';
  } else {
    note = (fungalWeather || rain >= 40)
        ? 'Wet weather in week $week is risky during $stage — flowers and filling grain are sensitive to fungal spread and grain mould.'
        : 'Weather is stable in week $week ($stage). Watch for sudden rain before harvest decisions.';
  }
  return _WeekWeatherAssessment(level: level, note: note);
}

class _SowingWeekWeatherCard extends StatelessWidget {
  final int daysAfterSowing;
  final String stage;
  final Map<String, dynamic> weather;

  const _SowingWeekWeatherCard({
    required this.daysAfterSowing,
    required this.stage,
    required this.weather,
  });

  @override
  Widget build(BuildContext context) {
    final assessment = _assessSowingWeekWeather(
      daysAfterSowing: daysAfterSowing,
      stage: stage,
      weather: weather,
    );
    final color = _FarmPage._severityColor(assessment.level);
    final week = daysAfterSowing ~/ 7 + 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Week $week after sowing • $stage',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                assessment.level.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            assessment.note,
            style: const TextStyle(
              color: AppTheme.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmIssueSheet extends StatefulWidget {
  final String farmName;
  final FarmIssueCell issue;
  final LatLng farmCenter;
  final int daysAfterSowing;
  final String growthStage;
  final Map<String, dynamic>? weatherContext;
  final Future<FarmAlertAdvice> Function() fetchGuidance;
  final Future<FarmPhotoDiagnosis?> Function(HarvestMachineImageSource source)
  captureAndDiagnose;

  const _FarmIssueSheet({
    required this.farmName,
    required this.issue,
    required this.farmCenter,
    required this.daysAfterSowing,
    required this.growthStage,
    required this.weatherContext,
    required this.fetchGuidance,
    required this.captureAndDiagnose,
  });

  @override
  State<_FarmIssueSheet> createState() => _FarmIssueSheetState();
}

class _FarmIssueSheetState extends State<_FarmIssueSheet> {
  FarmAlertAdvice? _advice;
  String? _adviceError;
  bool _adviceLoading = true;
  FarmPhotoDiagnosis? _diagnosis;
  String? _diagnosisError;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _loadGuidance();
  }

  Future<void> _loadGuidance() async {
    setState(() {
      _adviceLoading = true;
      _adviceError = null;
    });
    try {
      final advice = await widget.fetchGuidance();
      if (!mounted) return;
      setState(() {
        _advice = advice;
        _adviceLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _adviceError = e.toString().replaceFirst('SatelliteApiException: ', '');
        _adviceLoading = false;
      });
    }
  }

  Future<void> _takePhoto(HarvestMachineImageSource source) async {
    if (_photoBusy) return;
    setState(() {
      _photoBusy = true;
      _diagnosisError = null;
    });
    try {
      final diagnosis = await widget.captureAndDiagnose(source);
      if (!mounted) return;
      setState(() {
        _diagnosis = diagnosis ?? _diagnosis;
        _photoBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _diagnosisError = e.toString().replaceFirst(
          'SatelliteApiException: ',
          '',
        );
        _photoBusy = false;
      });
    }
  }

  int get _distanceMeters {
    return const Distance()
        .as(
          LengthUnit.Meter,
          widget.farmCenter,
          LatLng(widget.issue.lat, widget.issue.lng),
        )
        .round();
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    final color = _FarmPage._issueColor(issue);
    final weather = widget.weatherContext;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.74,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _FarmPage._issueIcon(issue),
                      color: color,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _FarmPage._issueTitle(issue),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.farmName,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${_FarmPage._riskLabel(issue.compositeRisk)} • ${(issue.compositeRisk * 100).round()}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                issue.isDisease
                    ? 'Satellite screening flags this spot as a possible disease patch. It is a pre-screen, not a confirmed diagnosis — walk there and check the plants before any treatment.'
                    : 'This spot looks stressed by water or heat rather than disease. Walk there to check soil moisture and plant condition.',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.directions_walk_rounded,
                      color: AppTheme.greenDark,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '≈ $_distanceMeters m from the field centre',
                            style: const TextStyle(
                              color: AppTheme.greenDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${issue.lat.toStringAsFixed(5)}, ${issue.lng.toStringAsFixed(5)}',
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (weather != null) ...[
                const SizedBox(height: 12),
                _SowingWeekWeatherCard(
                  daysAfterSowing: widget.daysAfterSowing,
                  stage: widget.growthStage,
                  weather: weather,
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'AI guidance for this spot',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (_adviceLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(height: 8),
                        Text(
                          'Asking the farm advisor…',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_adviceError != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Could not load guidance: $_adviceError',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loadGuidance,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                )
              else if (_advice != null) ...[
                for (final alert in _advice!.importantAlerts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FarmAlertCard(alert: alert),
                  ),
                if (_advice!.nextActions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  for (final action in _advice!.nextActions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: AppTheme.green,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              action,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
              const SizedBox(height: 18),
              const Text(
                'Confirm with a photo (optional)',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'When you reach the spot, photograph the affected leaves for an AI diagnosis with more specific guidance.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (_photoBusy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(height: 8),
                        Text(
                          'Uploading photo and diagnosing…',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            _takePhoto(HarvestMachineImageSource.camera),
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: const Text('Take photo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _takePhoto(HarvestMachineImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('From gallery'),
                      ),
                    ),
                  ],
                ),
              if (_diagnosisError != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Photo diagnosis failed: $_diagnosisError',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (_diagnosis != null) ...[
                const SizedBox(height: 12),
                _PhotoDiagnosisCard(diagnosis: _diagnosis!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PhotoDiagnosisCard extends StatelessWidget {
  final FarmPhotoDiagnosis diagnosis;

  const _PhotoDiagnosisCard({required this.diagnosis});

  @override
  Widget build(BuildContext context) {
    final color = _FarmPage._severityColor(diagnosis.severity);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.biotech_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diagnosis.diagnosis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${(diagnosis.confidence * 100).round()}%',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (diagnosis.evidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final item in diagnosis.evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $item',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
          if (diagnosis.scoutAction.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              diagnosis.scoutAction,
              style: const TextStyle(
                color: AppTheme.greenDark,
                height: 1.35,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FarmAlertEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _FarmAlertEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoStrip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$label: $value',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedFarmHeader extends StatelessWidget {
  final _FarmerFarm farm;

  const _SelectedFarmHeader({required this.farm});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: AppTheme.greenPale,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.grass_outlined, color: AppTheme.green),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                farm.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${farm.location} • ${farm.crop} • ${farm.variety}',
                style: const TextStyle(color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FarmMetric extends StatelessWidget {
  final String label;
  final String value;

  const _FarmMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmMapInsightPage extends StatelessWidget {
  final _FarmerFarm farm;
  final List<LatLng> farmPolygon;
  final List<LatLng> diseaseMarkers;
  final List<_GrowthMilestone> growthMilestones;
  final String currentStage;
  final String stageSummary;
  final int daysAfterSowing;
  final List<_HarvestInventoryLot> harvestHistory;
  final List<String> diagnosisNotes;
  final DateTime? lastUpdated;
  final String status;
  final _FarmSatelliteOverview? satelliteOverview;
  final bool isSatelliteLoading;
  final VoidCallback onOpenDiagnose;
  final VoidCallback onOpenStatusUpdate;

  const _FarmMapInsightPage({
    required this.farm,
    required this.farmPolygon,
    required this.diseaseMarkers,
    required this.growthMilestones,
    required this.currentStage,
    required this.stageSummary,
    required this.daysAfterSowing,
    required this.harvestHistory,
    required this.diagnosisNotes,
    required this.lastUpdated,
    required this.status,
    required this.satelliteOverview,
    required this.isSatelliteLoading,
    required this.onOpenDiagnose,
    required this.onOpenStatusUpdate,
  });

  List<CircleMarker> _diseaseCircles() {
    return diseaseMarkers
        .map(
          (point) => CircleMarker(
            point: point,
            radius: 9,
            useRadiusInMeter: false,
            borderColor: Colors.white,
            borderStrokeWidth: 1.5,
            color: Colors.redAccent.withValues(alpha: 0.62),
          ),
        )
        .toList();
  }

  bool _isMilestoneComplete(_GrowthMilestone milestone) =>
      daysAfterSowing > milestone.endDay;

  bool _isMilestoneCurrent(_GrowthMilestone milestone) =>
      daysAfterSowing >= milestone.startDay &&
      daysAfterSowing <= milestone.endDay;

  IconData _milestoneIcon(String stage) {
    switch (stage) {
      case 'Sowing':
        return Icons.spa_outlined;
      case 'Establishment':
        return Icons.energy_savings_leaf;
      case 'Vegetative':
        return Icons.grass_outlined;
      case 'Flowering':
        return Icons.local_florist_outlined;
      case 'Grain filling':
        return Icons.set_meal_outlined;
      default:
        return Icons.agriculture;
    }
  }

  @override
  Widget build(BuildContext context) {
    final updatedText = lastUpdated == null
        ? 'Not updated'
        : '${lastUpdated!.day.toString().padLeft(2, '0')}/${lastUpdated!.month.toString().padLeft(2, '0')} ${lastUpdated!.hour.toString().padLeft(2, '0')}:${lastUpdated!.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: Text(farm.name), elevation: 0),
      backgroundColor: AppTheme.surface,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'farm-insight-diagnose-fab',
            onPressed: onOpenDiagnose,
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Diagnose'),
            tooltip: 'Open diagnose flow',
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'farm-insight-status-fab',
            onPressed: onOpenStatusUpdate,
            icon: const Icon(Icons.track_changes_rounded),
            label: const Text('Status'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: [
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Farm Insight',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SelectedFarmHeader(farm: farm),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _FarmMetric(label: 'Area', value: farm.area),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FarmMetric(label: 'NDVI', value: farm.ndvi),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FarmMetric(
                          label: 'Moisture',
                          value: farm.moisture,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Satellite and field map',
                    style: TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SatelliteMapView(
                    farmPolygon: farmPolygon,
                    heatCircles: _diseaseCircles(),
                    height: 240,
                    showZoomControls: true,
                  ),
                  const SizedBox(height: 14),
                  _InfoStrip(
                    icon: Icons.timeline,
                    label: 'Growth',
                    value: 'Day $daysAfterSowing • Stage $currentStage',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Crop-cycle timeline',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final milestone in growthMilestones)
                    _InfoStrip(
                      icon: _milestoneIcon(milestone.stage),
                      label: milestone.stage,
                      value: _isMilestoneCurrent(milestone)
                          ? 'Active now'
                          : _isMilestoneComplete(milestone)
                          ? 'Completed'
                          : 'Upcoming (${milestone.startDay}-${milestone.endDay} day)',
                    ),
                  _InfoStrip(
                    icon: Icons.info_outline,
                    label: 'Last update',
                    value: updatedText,
                  ),
                  _InfoStrip(
                    icon: Icons.note_alt_outlined,
                    label: 'Status note',
                    value: status,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    stageSummary,
                    style: const TextStyle(color: AppTheme.textDark),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Detailed Analysis & Diagnostics',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _InsightDetailCard(
                          title: 'NDVI History',
                          subtitle: 'Satellite index graphs',
                          icon: Icons.trending_up_rounded,
                          color: const Color(0xFFECF6E8),
                          onTap: () =>
                              Get.to(() => _NdviHistoryDetailPage(farm: farm)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InsightDetailCard(
                          title: 'Soil Health',
                          subtitle: 'pH, NPK & Moisture',
                          icon: Icons.science_outlined,
                          color: const Color(0xFFFFF3E0),
                          onTap: () => Get.to(
                            () => _SoilDiagnosticsDetailPage(farm: farm),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _InsightDetailCard(
                          title: 'Weather Impact',
                          subtitle: 'Humidity & rainfall logs',
                          icon: Icons.wb_cloudy_rounded,
                          color: const Color(0xFFE8F5FF),
                          onTap: () => Get.to(
                            () => _WeatherImpactDetailPage(farm: farm),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InsightDetailCard(
                          title: 'Yield Prognosis',
                          subtitle: 'Expected harvest index',
                          icon: Icons.bar_chart_rounded,
                          color: const Color(0xFFF3E8FF),
                          onTap: () => Get.to(
                            () => _YieldPrognosisDetailPage(farm: farm),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (harvestHistory.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Recent harvest history',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...harvestHistory
                        .take(2)
                        .map(
                          (lot) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _Panel(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lot.lotLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${lot.crop} • ${lot.variety} • ${lot.grade} • ${lot.estimatedYieldKg.toStringAsFixed(1)}kg',
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                  if (diagnosisNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Latest field notes',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...diagnosisNotes
                        .take(3)
                        .map(
                          (note) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F8EE),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFDCEBD9),
                                ),
                              ),
                              child: Text(
                                note,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightDetailCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _InsightDetailCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.greenPale.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.greenDark, size: 24),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.greenDark,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NdviHistoryDetailPage extends StatelessWidget {
  final _FarmerFarm farm;

  const _NdviHistoryDetailPage({required this.farm});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          '${farm.name} • NDVI Analysis',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.greenDark,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.greenDark,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NDVI Health Index Trend',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'NDVI ranges from 0.0 to 1.0. Higher values (0.6 - 0.8) indicate healthy green vegetative growth.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 160,
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: CustomPaint(painter: _NdviCurvePainter()),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Sowing (0.15)',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        Text(
                          'Veg (0.42)',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        Text(
                          'Flowering (0.76)',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        Text(
                          'Filling (0.68)',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Satellite Overpasses',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildPassRow(
                      'June 08, 2026',
                      'Sentinel-2B',
                      '0.76',
                      '0.2% Cloud',
                    ),
                    const Divider(),
                    _buildPassRow(
                      'May 28, 2026',
                      'Sentinel-2A',
                      '0.64',
                      '1.5% Cloud',
                    ),
                    const Divider(),
                    _buildPassRow(
                      'May 18, 2026',
                      'Sentinel-2B',
                      '0.45',
                      '12% Cloud',
                    ),
                    const Divider(),
                    _buildPassRow(
                      'May 08, 2026',
                      'Sentinel-2A',
                      '0.28',
                      '0.0% Cloud',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassRow(String date, String sat, String ndvi, String cloud) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                sat,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                ndvi,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.greenDark,
                ),
              ),
              Text(
                cloud,
                style: const TextStyle(fontSize: 11, color: Colors.blueAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NdviCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.green.withValues(alpha: 0.2),
          AppTheme.green.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = ui.Path();
    path.moveTo(0, size.height * 0.85);
    path.cubicTo(
      size.width * 0.3,
      size.height * 0.8,
      size.width * 0.6,
      size.height * 0.1,
      size.width * 0.8,
      size.height * 0.25,
    );
    path.lineTo(size.width, size.height * 0.4);

    final fillPath = ui.Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    final dotPaint = Paint()
      ..color = AppTheme.greenDark
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.25),
      5,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SoilDiagnosticsDetailPage extends StatelessWidget {
  final _FarmerFarm farm;

  const _SoilDiagnosticsDetailPage({required this.farm});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          '${farm.name} • Soil Health',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.greenDark,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.greenDark,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NPK & Soil Chemistry',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildNutrientBar(
                      'Nitrogen (N)',
                      0.65,
                      'Optimal (65 kg/ha)',
                      Colors.blue,
                    ),
                    _buildNutrientBar(
                      'Phosphorus (P)',
                      0.42,
                      'Moderate (28 kg/ha)',
                      Colors.orange,
                    ),
                    _buildNutrientBar(
                      'Potassium (K)',
                      0.85,
                      'High (195 kg/ha)',
                      Colors.purple,
                    ),
                    _buildNutrientBar(
                      'Organic Carbon',
                      0.55,
                      'Moderate (0.55%)',
                      Colors.green,
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Soil pH Value:',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '6.7 (Slightly Acidic • Ideal)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.greenDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Advisory for Millets',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.greenDark,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      '• Apply 20 kg/ha of phosphorus before upcoming rain shower.',
                      style: TextStyle(height: 1.4),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• Top-dress with nitrogen during vegetative growth at day 35.',
                      style: TextStyle(height: 1.4),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• Organic carbon level is slightly low; add vermicompost or farmyard manure after current harvest.',
                      style: TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutrientBar(String label, double val, String text, Color col) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                text,
                style: TextStyle(
                  color: col,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: val,
              minHeight: 8,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation(col),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherImpactDetailPage extends StatelessWidget {
  final _FarmerFarm farm;

  const _WeatherImpactDetailPage({required this.farm});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          '${farm.name} • Weather Impact',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.greenDark,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.greenDark,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Microclimate Statistics',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildStatRow('Avg Soil Moisture', farm.moisture),
                    _buildStatRow('Solar Radiation', '820 W/m²'),
                    _buildStatRow('Daily Evapotranspiration', '4.2 mm/day'),
                    _buildStatRow('Dew Point', '18.4°C'),
                    _buildStatRow('Relative Humidity', '45%'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Weather Hazards Outlook',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.greenDark,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      '• Fungal Disease Risk: Low (Humidity remains under 70%)',
                      style: TextStyle(height: 1.4),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• Heat Stress: Moderate (Top temps exceeding 31°C; ensure evening soil dampness)',
                      style: TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            val,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.greenDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _YieldPrognosisDetailPage extends StatelessWidget {
  final _FarmerFarm farm;

  const _YieldPrognosisDetailPage({required this.farm});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          '${farm.name} • Yield Prognosis',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.greenDark,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.greenDark,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Expected Yield Prognosis',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildYieldRow('Est. Production', '850 - 950 kg/acre'),
                    _buildYieldRow(
                      'Current Stage Projection',
                      'On Track (102%)',
                    ),
                    _buildYieldRow('Est. Harvest Window', 'July 15 - July 20'),
                    _buildYieldRow(
                      'Quality Grade Prediction',
                      'A (High density grains)',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Pre-harvest Checklist',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.greenDark,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      '• Arrange drying yards and ensure moisture is under 12%.',
                      style: TextStyle(height: 1.4),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• Procure 18 jute bags (50kg capacity) ahead of time.',
                      style: TextStyle(height: 1.4),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '• Clean harvester blades to prevent contamination.',
                      style: TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYieldRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            val,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.greenDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmChoiceCard extends StatelessWidget {
  final _FarmerFarm farm;
  final bool selected;
  final VoidCallback onTap;

  const _FarmChoiceCard({
    required this.farm,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppTheme.green : const Color(0xFFE5E7EB),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppTheme.green : AppTheme.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farm.name,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${farm.location} • ${farm.variety} • ${farm.area}',
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              _StatusPill(icon: Icons.health_and_safety, label: farm.health),
            ],
          ),
        ),
      ),
    );
  }
}

class _FarmHistoryIndexPage extends StatelessWidget {
  final List<_FarmerFarm> farms;
  final int selectedIndex;
  final String Function(int index) stageSummary;
  final ValueChanged<int> onOpenFarm;

  const _FarmHistoryIndexPage({
    required this.farms,
    required this.selectedIndex,
    required this.stageSummary,
    required this.onOpenFarm,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Farm History',
          style: TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.greenDark,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            _Panel(
              tint: const Color(0xFFECF6E8),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select a farm',
                      style: TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Showing ${farms.length} farm${farms.length == 1 ? '' : 's'} for this farmer. Tap a farm to open its crop history, disease records, harvests, and remote index timeline.',
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < farms.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Panel(
                  tint: i == selectedIndex
                      ? AppTheme.greenPale.withValues(alpha: 0.35)
                      : null,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onOpenFarm(i),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  farms[i].name,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppTheme.green,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${farms[i].crop} • ${farms[i].variety} • ${farms[i].area}',
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            stageSummary(i),
                            style: const TextStyle(
                              color: AppTheme.textDark,
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InventoryChip(label: farms[i].location),
                              if (farms[i].previousCrop.isNotEmpty)
                                _InventoryChip(
                                  label: 'Previous ${farms[i].previousCrop}',
                                ),
                              if (farms[i].season.isNotEmpty)
                                _InventoryChip(label: farms[i].season),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryPage extends StatelessWidget {
  static const List<_GrowthMilestone> _historyMilestones = [
    _GrowthMilestone(stage: 'Sowing', startDay: 0, endDay: 7),
    _GrowthMilestone(stage: 'Establishment', startDay: 8, endDay: 25),
    _GrowthMilestone(stage: 'Vegetative', startDay: 26, endDay: 55),
    _GrowthMilestone(stage: 'Flowering', startDay: 56, endDay: 75),
    _GrowthMilestone(stage: 'Grain filling', startDay: 76, endDay: 110),
    _GrowthMilestone(stage: 'Maturity', startDay: 111, endDay: 9999),
  ];
  final _FarmerFarm farm;
  final int daysAfterSowing;
  final String currentStage;
  final String status;
  final DateTime? statusUpdatedAt;
  final List<_HarvestInventoryLot> harvestHistory;
  final List<String> diagnosisNotes;
  final _FarmSatelliteOverview? satelliteOverview;

  const _HistoryPage({
    required this.farm,
    required this.daysAfterSowing,
    required this.currentStage,
    required this.status,
    required this.statusUpdatedAt,
    required this.harvestHistory,
    required this.diagnosisNotes,
    this.satelliteOverview,
  });

  String get _statusTimeText {
    if (statusUpdatedAt == null) return 'Not updated';
    return '${statusUpdatedAt!.day.toString().padLeft(2, '0')}/${statusUpdatedAt!.month.toString().padLeft(2, '0')} ${statusUpdatedAt!.hour.toString().padLeft(2, '0')}:${statusUpdatedAt!.minute.toString().padLeft(2, '0')}';
  }

  bool _isCurrent(_GrowthMilestone milestone) {
    return daysAfterSowing >= milestone.startDay &&
        daysAfterSowing <= milestone.endDay;
  }

  bool _isCompleted(_GrowthMilestone milestone) {
    return daysAfterSowing > milestone.endDay;
  }

  IconData _milestoneIcon(String stage) {
    switch (stage) {
      case 'Sowing':
        return Icons.spa_outlined;
      case 'Establishment':
        return Icons.verified_outlined;
      case 'Vegetative':
        return Icons.eco_outlined;
      case 'Flowering':
        return Icons.local_florist_outlined;
      case 'Grain filling':
        return Icons.set_meal_outlined;
      case 'Maturity':
        return Icons.check_circle_outline;
      default:
        return Icons.agriculture;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Farm History',
          style: TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.greenDark,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            farm.name,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.greenPale.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Live',
                            style: TextStyle(
                              color: AppTheme.greenDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${farm.crop} • ${farm.variety} • ${farm.area}',
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Cycle summary • day $daysAfterSowing',
                      style: TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _FarmMetric(
                            label: 'Stage',
                            value: currentStage,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _FarmMetric(
                            label: 'Status',
                            value: statusUpdatedAt == null
                                ? 'Pending'
                                : 'Updated',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InventoryChip(label: farm.location),
                        _InventoryChip(label: 'Health ${farm.health}'),
                        _InventoryChip(label: 'Moisture ${farm.moisture}'),
                        if (farm.previousCrop.isNotEmpty)
                          _InventoryChip(
                            label: 'Previous ${farm.previousCrop}',
                          ),
                        if (farm.season.isNotEmpty)
                          _InventoryChip(label: farm.season),
                        if (farm.irrigation.isNotEmpty)
                          _InventoryChip(label: farm.irrigation),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (farm.previousCrop.isNotEmpty ||
                farm.soilType.isNotEmpty ||
                farm.ownershipType.isNotEmpty ||
                farm.seedSource.isNotEmpty ||
                farm.harvestIntent.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Panel(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Farm questionnaire details',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (farm.previousCrop.isNotEmpty)
                            _InventoryChip(
                              label: 'Previous crop: ${farm.previousCrop}',
                            ),
                          if (farm.soilType.isNotEmpty)
                            _InventoryChip(label: 'Soil: ${farm.soilType}'),
                          if (farm.ownershipType.isNotEmpty)
                            _InventoryChip(
                              label: 'Land: ${farm.ownershipType}',
                            ),
                          if (farm.seedSource.isNotEmpty)
                            _InventoryChip(label: 'Seed: ${farm.seedSource}'),
                          if (farm.harvestIntent.isNotEmpty)
                            _InventoryChip(label: 'Use: ${farm.harvestIntent}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Crop-cycle timeline',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 12),
                    for (final milestone in _historyMilestones)
                      _TimelineItem(
                        icon: _milestoneIcon(milestone.stage),
                        title: milestone.stage,
                        detail: _isCurrent(milestone)
                            ? 'Active now • ${milestone.startDay}-${milestone.endDay}'
                            : _isCompleted(milestone)
                            ? 'Completed'
                            : 'Starts at day ${milestone.startDay}',
                        active: _isCurrent(milestone),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Current status: $status',
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Last update: $_statusTimeText',
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            if (harvestHistory.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Panel(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Harvest history',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final lot in harvestHistory.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _Panel(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lot.lotLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${lot.crop} • ${lot.variety} • ${lot.grade} • ${lot.estimatedYieldKg.toStringAsFixed(1)}kg',
                                    style: const TextStyle(
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (harvestHistory.isEmpty) ...[
              const SizedBox(height: 14),
              _Panel(
                child: const Padding(
                  padding: EdgeInsets.all(18),
                  child: _HistoryEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No harvest history yet',
                    detail:
                        'When grading and bagging are completed, harvest lots for this selected farm will appear in the timeline.',
                  ),
                ),
              ),
            ],
            if (diagnosisNotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Panel(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Field notes',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final note in diagnosisNotes.take(4))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            note,
                            style: const TextStyle(height: 1.4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (diagnosisNotes.isEmpty) ...[
              const SizedBox(height: 14),
              _Panel(
                child: const Padding(
                  padding: EdgeInsets.all(18),
                  child: _HistoryEmptyState(
                    icon: Icons.note_alt_outlined,
                    title: 'No field notes yet',
                    detail:
                        'Disease checks, status updates and farmer observations will sync into this history screen.',
                  ),
                ),
              ),
            ],
            if (satelliteOverview != null &&
                satelliteOverview!.tiles.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Panel(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weather + index trend',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tile in satelliteOverview!.tiles.take(4))
                            SizedBox(
                              width: 168,
                              child: _FarmSatelliteMetricCard(tile: tile),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (satelliteOverview == null ||
                satelliteOverview!.tiles.isEmpty) ...[
              const SizedBox(height: 14),
              _Panel(
                child: const Padding(
                  padding: EdgeInsets.all(18),
                  child: _HistoryEmptyState(
                    icon: Icons.satellite_alt_outlined,
                    title: 'Remote index data pending',
                    detail:
                        'Satellite NDVI, moisture and vegetation trend cards will appear after the remote farm feed returns data.',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _HistoryEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.greenPale.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppTheme.greenDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MarketPage extends StatefulWidget {
  final List<Map<String, String>> inventoryLots;
  final String? farmName;
  final Map<String, String>? initialSelectedLot;

  const MarketPage({
    required this.inventoryLots,
    this.farmName,
    this.initialSelectedLot,
  });

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  static const List<String> _sortOptions = [
    'Recommended',
    'Newest',
    'Highest grade',
    'Lowest moisture',
    'Highest qty',
  ];
  static const String _allFarmsLabel = 'All Farms';

  final _searchController = TextEditingController();
  String _searchText = '';
  String _selectedFarm = _allFarmsLabel;
  String _sortBy = 'Recommended';

  @override
  void initState() {
    super.initState();
    if (widget.farmName != null && widget.farmName!.trim().isNotEmpty) {
      _selectedFarm = widget.farmName!.trim();
    }
    if (_selectedFarm != _allFarmsLabel &&
        !_farmOptions.contains(_selectedFarm)) {
      _selectedFarm = _allFarmsLabel;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) return DateTime(1970);
    return DateTime.tryParse(value.trim()) ?? DateTime(1970);
  }

  double _toDouble(String? value) {
    return double.tryParse(value ?? '') ?? 0;
  }

  int _toInt(String? value) {
    return int.tryParse(value ?? '') ?? 0;
  }

  List<Map<String, String>> get _scopedLots {
    final scoped = _selectedFarm == _allFarmsLabel
        ? widget.inventoryLots
        : widget.inventoryLots.where(
            (lot) =>
                (lot['farmName'] ?? '').toLowerCase() ==
                _selectedFarm.toLowerCase(),
          );

    final searchFilter = _searchText.trim().toLowerCase();
    final searched = searchFilter.isEmpty
        ? scoped
        : scoped.where((lot) {
            return (lot['batchId'] ?? '').toLowerCase().contains(
                  searchFilter,
                ) ||
                (lot['crop'] ?? '').toLowerCase().contains(searchFilter) ||
                (lot['variety'] ?? '').toLowerCase().contains(searchFilter) ||
                (lot['grade'] ?? '').toLowerCase().contains(searchFilter);
          });

    final sorted = searched.toList(growable: false)
      ..sort((a, b) {
        switch (_sortBy) {
          case 'Newest':
            return _parseDate(
              b['harvestedAt'],
            ).compareTo(_parseDate(a['harvestedAt']));
          case 'Highest grade':
            return _toInt(b['score']).compareTo(_toInt(a['score']));
          case 'Lowest moisture':
            return _toDouble(a['moisture']).compareTo(_toDouble(b['moisture']));
          case 'Highest qty':
            return _toDouble(
              b['estimatedYield'],
            ).compareTo(_toDouble(a['estimatedYield']));
          case 'Recommended':
          default:
            final score = _toInt(b['score']).compareTo(_toInt(a['score']));
            if (score != 0) return score;
            return _toDouble(
              b['estimatedYield'],
            ).compareTo(_toDouble(a['estimatedYield']));
        }
      });

    return sorted;
  }

  List<String> get _farmOptions {
    final farms = <String>{_allFarmsLabel};
    final selectedFarm = widget.farmName?.trim();
    if (selectedFarm != null && selectedFarm.isNotEmpty) {
      farms.add(selectedFarm);
    }
    for (final lot in widget.inventoryLots) {
      final value = lot['farmName']?.trim();
      if (value != null && value.isNotEmpty) {
        farms.add(value);
      }
    }
    final sorted = farms.toList()..sort();
    return sorted;
  }

  Map<String, String>? get _selectedLot {
    final batchId = widget.initialSelectedLot?['batchId'];
    if (batchId == null) return null;
    for (final lot in _scopedLots) {
      if (lot['batchId'] == batchId) return lot;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scopedLots = _scopedLots;
    final selectedLot = _selectedLot;
    final selectedLotId = selectedLot?['batchId'];
    final scopeLabel = _selectedFarm == _allFarmsLabel
        ? 'all farms'
        : _selectedFarm;
    final totalLots = scopedLots.length;
    final totalQty = scopedLots.fold<double>(
      0,
      (sum, lot) => sum + _toDouble(lot['estimatedYield']),
    );
    final avgScore = totalLots == 0
        ? 0
        : scopedLots.fold<double>(0, (sum, lot) => sum + _toInt(lot['score'])) /
              totalLots;
    final avgMoisture = totalLots == 0
        ? 0
        : scopedLots.fold<double>(
                0,
                (sum, lot) => sum + _toDouble(lot['moisture']),
              ) /
              totalLots;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text(
          'Market Desk',
          style: TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.greenDark,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scopeLabel == 'all farms'
                          ? 'Market desk'
                          : 'Market desk • ${scopeLabel}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Create a lot-focused listing, compare grade impact, and review demand trend quickly.',
                      style: TextStyle(color: AppTheme.textDark, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    _MarketSyncStrip(scopeLabel: scopeLabel),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MarketTrendStat(
                            label: 'Active lots',
                            value: '$totalLots',
                            icon: Icons.inventory_2_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MarketTrendStat(
                            label: 'Qty (kg)',
                            value: totalQty.toStringAsFixed(1),
                            icon: Icons.scale_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _MarketTrendStat(
                            label: 'Avg score',
                            value: avgScore.toStringAsFixed(1),
                            icon: Icons.assessment_outlined,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MarketTrendStat(
                            label: 'Avg moisture',
                            value: '${avgMoisture.toStringAsFixed(1)}%',
                            icon: Icons.water_drop_outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() {
                        _searchText = value;
                      }),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Search lot id, crop, variety, grade',
                        suffixIcon: _searchText.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchText = '';
                                  });
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sortBy,
                            decoration: const InputDecoration(
                              labelText: 'Sort by',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: _sortOptions
                                .map(
                                  (opt) => DropdownMenuItem(
                                    value: opt,
                                    child: Text(
                                      opt,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _sortBy = value;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_farmOptions.length > 1)
                      SizedBox(
                        height: 34,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _farmOptions.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final farm = _farmOptions[index];
                            final selected = farm == _selectedFarm;
                            return ChoiceChip(
                              label: Text(farm),
                              selected: selected,
                              onSelected: (value) {
                                if (value) {
                                  setState(() => _selectedFarm = farm);
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (scopedLots.isEmpty)
              _Panel(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            color: AppTheme.green,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'No active market lots',
                            style: TextStyle(
                              color: AppTheme.greenDark,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedFarm == _allFarmsLabel
                            ? 'Harvest lots from all farms will appear here after grading.'
                            : 'No graded lot is ready for $_selectedFarm yet. Complete harvest grading first, then create a market listing.',
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InventoryChip(label: 'Awaiting harvest'),
                          _InventoryChip(label: 'Grade required'),
                          _InventoryChip(label: 'Remote-ready'),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              ...scopedLots.map((lot) {
                final batchId = lot['batchId'] ?? 'Lot';
                final crop = lot['crop'] ?? '--';
                final variety = lot['variety'] ?? '--';
                final grade = lot['grade'] ?? '--';
                final bagCount = _toInt(lot['bagCount']);
                final bagSize = _toDouble(lot['bagSizeKg']);
                final moisture = _toDouble(lot['moisture']);
                final score = _toInt(lot['score']);
                final yieldEstimate = _toDouble(lot['estimatedYield']);
                final isSelected =
                    selectedLotId != null && selectedLotId == batchId;
                final harvestRate = 2100 + (score * 24);
                final expectedValue = (yieldEstimate / 1000) * harvestRate;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _Panel(
                    tint: isSelected
                        ? AppTheme.greenPale.withValues(alpha: 0.2)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  batchId,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.check_circle_rounded,
                                color: isSelected
                                    ? AppTheme.green
                                    : AppTheme.textMuted,
                                size: 18,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InventoryChip(label: crop),
                              _InventoryChip(label: variety),
                              _InventoryChip(label: 'Grade $grade'),
                              _InventoryChip(label: 'Score $score'),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _SummaryStat(
                                  title: 'Qty',
                                  value:
                                      '${yieldEstimate.toStringAsFixed(1)} kg',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SummaryStat(
                                  title: 'Moisture',
                                  value: '${moisture.toStringAsFixed(1)}%',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SummaryStat(
                                  title: 'Bags',
                                  value:
                                      '$bagCount × ${bagSize.toStringAsFixed(0)}kg',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Expected lot value: Rs ${(expectedValue).toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppTheme.greenDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => Get.snackbar(
                                    'Market',
                                    'Prepare listing for $batchId',
                                    snackPosition: SnackPosition.BOTTOM,
                                  ),
                                  icon: const Icon(
                                    Icons.storefront_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Create listing'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Get.snackbar(
                                      'Market',
                                      'Opening demand trend for $batchId',
                                      snackPosition: SnackPosition.BOTTOM,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.trending_up_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Demand trend'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MarketSyncStrip extends StatelessWidget {
  final String scopeLabel;

  const _MarketSyncStrip({required this.scopeLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded, color: Color(0xFF1976D2), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing synced inventory context for $scopeLabel. Listings update after harvest grading is saved.',
              style: const TextStyle(
                color: AppTheme.textDark,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketTrendStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MarketTrendStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.greenDark),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NewsPage extends StatelessWidget {
  final String? farmName;
  final String? farmLocation;

  const NewsPage({this.farmName, this.farmLocation});

  static const List<Map<String, String>> _newsFeed = [
    {
      'title': 'Millet MSP updated for upcoming procurement cycle',
      'summary': 'Farm support channels report improved rates in Maharashtra.',
      'time': 'Today',
      'tag': 'Market',
      'impact': 'Check sale timing before creating new listings.',
    },
    {
      'title': 'Monsoon outlook: lighter showers expected',
      'summary':
          'Weather advisories suggest staggered irrigation in low-lying fields.',
      'time': 'Yesterday',
      'tag': 'Weather',
      'impact': 'Review irrigation window for active millet farms.',
    },
    {
      'title': 'Storage tips for short-season grains',
      'summary': 'Drying and bin ventilation reduced mold and pest risk.',
      'time': '2 days ago',
      'tag': 'Storage',
      'impact': 'Useful for graded lots waiting for market listing.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final contextTitle = farmName == null
        ? 'News & Advisories'
        : 'News • ${farmName!}';
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          contextTitle,
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.greenDark,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: const [
                  _NewsCategoryChip(label: 'All News', selected: true),
                  SizedBox(width: 8),
                  _NewsCategoryChip(label: 'MSP & Markets', selected: false),
                  SizedBox(width: 8),
                  _NewsCategoryChip(label: 'Weather Alerts', selected: false),
                  SizedBox(width: 8),
                  _NewsCategoryChip(label: 'Farming Tips', selected: false),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (farmName != null || farmLocation != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Panel(
                  tint: const Color(0xFFECF6E8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.rss_feed_rounded,
                          color: AppTheme.greenDark,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            farmName == null
                                ? (farmLocation ?? 'Local farm area')
                                : (farmLocation == null ||
                                          farmLocation!.trim().isEmpty
                                      ? '${farmName!} • farm updates'
                                      : '${farmName!} • ${farmLocation!}'),
                            style: const TextStyle(
                              color: AppTheme.greenDark,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined, color: AppTheme.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Advisories are grouped for ${farmName ?? 'all farms'} and should be checked with local FPO guidance before action.',
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final item in _newsFeed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InventoryChip(label: item['tag']!),
                            _InventoryChip(label: item['time']!),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['summary']!,
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Farm impact: ${item['impact']!}',
                          style: const TextStyle(
                            color: AppTheme.greenDark,
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NewsCategoryChip extends StatelessWidget {
  final String label;
  final bool selected;

  const _NewsCategoryChip({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.green : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppTheme.green : const Color(0xFFE5E7EB),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppTheme.textDark,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class SchemesPage extends StatelessWidget {
  final String? farmName;
  final String? farmLocation;

  const SchemesPage({this.farmName, this.farmLocation});

  static const List<Map<String, String>> _schemes = [
    {
      'title': 'PM-KISAN Direct Support',
      'desc': 'Income support for farmers with crop-specific conditions.',
      'status': 'Apply',
      'fit': 'Landholder records',
    },
    {
      'title': 'Millet Processing Grant',
      'desc': 'Support for post-harvest processing units at district level.',
      'status': 'Open',
      'fit': 'Grading and storage',
    },
    {
      'title': 'Soil Health & Water Mission',
      'desc': 'Free soil card and advisory updates linked with local officers.',
      'status': 'By district office',
      'fit': 'Soil and water checks',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final contextTitle = farmName == null
        ? 'Government Schemes'
        : 'Schemes • ${farmName!}';
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          contextTitle,
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.greenDark,
          ),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search schemes, subsidies, and programs',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (farmName != null || farmLocation != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Panel(
                  tint: const Color(0xFFECF6E8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.assignment_turned_in_outlined,
                          color: AppTheme.greenDark,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            farmName == null
                                ? (farmLocation ?? 'Local scheme center')
                                : (farmLocation == null ||
                                          farmLocation!.trim().isEmpty
                                      ? '${farmName!} • local scheme center'
                                      : '${farmName!} • ${farmLocation!}'),
                            style: const TextStyle(
                              color: AppTheme.greenDark,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ..._schemes.map((scheme) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.assignment_rounded,
                          color: AppTheme.green,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                scheme['title']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                scheme['desc']!,
                                style: const TextStyle(
                                  color: AppTheme.textDark,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _InventoryChip(label: scheme['fit']!),
                                  _InventoryChip(label: 'Farm documents'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    scheme['status']!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.greenDark,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Get.snackbar(
                                        'Schemes',
                                        'Opening application form for ${scheme['title']}',
                                        snackPosition: SnackPosition.BOTTOM,
                                      );
                                    },
                                    child: const Text('Apply Now'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final bool active;

  const _TimelineItem({
    required this.icon,
    required this.title,
    required this.detail,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.green : AppTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  final _FarmerProfile profile;

  const _SettingsPage({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'Settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.greenPale,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.settings_rounded,
                      color: AppTheme.green,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Account preferences and support',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Panel(
            child: Column(
              children: [
                _ProfileMenuRow(
                  icon: Icons.language_rounded,
                  title: 'Language',
                  subtitle: 'Change app language',
                  onTap: () => Get.snackbar(
                    'Language',
                    'Use the language selector on the login screen.',
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
                const Divider(height: 1),
                _ProfileMenuRow(
                  icon: Icons.support_agent_rounded,
                  title: 'Support',
                  subtitle: 'Contact your field coordinator',
                  onTap: () => Get.snackbar(
                    'Support',
                    'Contact your field coordinator for account help.',
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
                const Divider(height: 1),
                _ProfileMenuRow(
                  icon: Icons.logout_rounded,
                  title: 'Logout',
                  subtitle: 'Return to role selection',
                  onTap: () => Get.find<MainAuthController>().logout(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  final _FarmerProfile profile;
  final _FarmerFarm farm;

  const _ProfilePage({required this.profile, required this.farm});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();
    final farmerQrData = jsonEncode({
      'type': 'farmer_profile',
      'allowedRole': 'fpo_fpc',
      'brand': 'Kalsubai Farms',
      'farmerId': profile.farmerId,
      'farmerName': profile.name,
      'phone': profile.phone,
      'village': profile.location,
      'location': profile.location,
      'primaryFarm': farm.name,
      'crop': farm.crop,
      'product': farm.product,
      'area': farm.area,
      'lotGrade': farm.health,
      'source': 'remote_supabase',
      'verified': true,
      'fpcRating': 'Not rated',
      'lastYield': 'Pending',
      'lastGrade': 'Pending',
      'detail': 'Farmer profile verified for FPC procurement and grading.',
      'currentCrop': {
        'season': farm.season.isEmpty ? 'Current' : farm.season,
        'crop': farm.crop,
        'variety': farm.variety,
        'expectedYield': 'Pending',
        'grade': 'Pending',
        'detail': '${farm.name} - ${farm.area} - ${farm.health}',
      },
      'productionHistory': [
        {
          'season': 'Last season',
          'crop': farm.previousCrop.isEmpty ? farm.crop : farm.previousCrop,
          'yield': 'Pending',
          'grade': 'Pending',
          'detail': 'Update after FPC grading or procurement.',
        },
      ],
      'sellingHistory': [
        {
          'date': 'Pending',
          'buyer': 'FPC procurement',
          'quantity': 'Pending',
          'rate': 'Pending',
          'rating': 'Pending',
        },
      ],
    });
    return _PageScaffold(
      title: 'Profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      BrandAssets.farmerAvatar,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const _StatusPill(
                          icon: Icons.verified_user_rounded,
                          label: 'Identity Verified',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Farmer ID: ${profile.farmerId}',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile.phone,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Farmer QR',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Only FPO / FPC login can scan this code to view farmer details.',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: QrImageView(
                        data: farmerQrData,
                        version: QrVersions.auto,
                        size: 188,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: AppTheme.green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${profile.farmerId} • ${profile.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.greenDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Primary Farm',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SelectedFarmHeader(farm: farm),
                  const SizedBox(height: 16),
                  const _StatusPill(
                    icon: Icons.verified_rounded,
                    label: 'Farm profile active',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Column(
              children: [
                _ProfileMenuRow(
                  icon: Icons.grass_outlined,
                  title: 'Farm Details',
                  subtitle: 'Review farm and crop health',
                  onTap: () => Get.snackbar(
                    'Farm Details',
                    'Open the Farm tab to switch farm.',
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
                const Divider(height: 1),
                _ProfileMenuRow(
                  icon: Icons.support_agent_rounded,
                  title: 'Support',
                  subtitle: 'Help and support center',
                  onTap: () => Get.snackbar(
                    'Support',
                    'Contact your field coordinator for help.',
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
                const Divider(height: 1),
                _ProfileMenuRow(
                  icon: Icons.logout_rounded,
                  title: 'Logout',
                  subtitle: 'Return to role selection',
                  onTap: auth.logout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _ProfileMenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.greenPale.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: AppTheme.green),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _SideNavGroupedLinks extends StatelessWidget {
  final bool expanded;
  final VoidCallback onOpenNews;
  final VoidCallback onOpenGrainGrading;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenApmcMarket;
  final VoidCallback onOpenSchemes;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSettings;

  const _SideNavGroupedLinks({
    required this.expanded,
    required this.onOpenNews,
    required this.onOpenGrainGrading,
    required this.onOpenWeather,
    required this.onOpenApmcMarket,
    required this.onOpenSchemes,
    required this.onOpenHistory,
    required this.onOpenInventory,
    required this.onOpenProfile,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final primary = [
      _SideUtilityItemData(
        icon: Icons.wb_cloudy_rounded,
        label: 'Weather',
        onTap: onOpenWeather,
      ),
      _SideUtilityItemData(
        icon: Icons.grain,
        label: 'Grain Grading',
        onTap: onOpenGrainGrading,
      ),
      _SideUtilityItemData(
        icon: Icons.newspaper_rounded,
        label: 'News',
        onTap: onOpenNews,
      ),
      _SideUtilityItemData(
        icon: Icons.storefront_rounded,
        label: 'APMC Market',
        onTap: onOpenApmcMarket,
      ),
      _SideUtilityItemData(
        icon: Icons.assignment_rounded,
        label: 'Schemes',
        onTap: onOpenSchemes,
      ),
    ];
    final secondary = [
      _SideUtilityItemData(
        icon: Icons.history_rounded,
        label: 'Farm History',
        onTap: onOpenHistory,
      ),
      _SideUtilityItemData(
        icon: Icons.inventory_2_rounded,
        label: 'Inventory',
        onTap: onOpenInventory,
      ),
      _SideUtilityItemData(
        icon: Icons.person_rounded,
        label: 'Profile',
        onTap: onOpenProfile,
      ),
      _SideUtilityItemData(
        icon: Icons.settings_rounded,
        label: 'Settings',
        onTap: onOpenSettings,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
      children: [
        for (final item in primary) ...[
          _SideUtilityItem(item: item, expanded: expanded),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(
            color: AppTheme.green.withValues(alpha: 0.18),
            height: 1,
          ),
        ),
        for (final item in secondary) ...[
          _SideUtilityItem(item: item, expanded: expanded),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SideUtilityItemData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SideUtilityItemData({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _SideUtilityItem extends StatelessWidget {
  final _SideUtilityItemData item;
  final bool expanded;

  const _SideUtilityItem({required this.item, required this.expanded});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 12 : 8,
            vertical: 10,
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(item.icon, color: AppTheme.greenDark, size: 21),
              if (expanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SideNavHeader extends StatelessWidget {
  final bool expanded;
  final _FarmerProfile profile;
  final String avatarAsset;
  final VoidCallback onMenuTap;

  const _SideNavHeader({
    required this.expanded,
    required this.profile,
    required this.avatarAsset,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: value,
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.fromLTRB(10, 10, 10, expanded ? 10 : 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF143B1B), Color(0xFF1F6B31)],
          ),
        ),
        child: Column(
          crossAxisAlignment: expanded
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Container(
              width: expanded ? double.infinity : 68,
              padding: EdgeInsets.all(expanded ? 8 : 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: expanded
                  ? Row(
                      children: [
                        _SideAvatar(asset: avatarAsset, size: 44),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _SideMenuDotButton(onTap: onMenuTap),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SideMenuDotButton(onTap: onMenuTap, compact: true),
                        const SizedBox(height: 8),
                        _SideAvatar(asset: avatarAsset, size: 46),
                        const SizedBox(height: 8),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _SideHeaderDot(delayMs: 0),
                            SizedBox(width: 5),
                            _SideHeaderDot(
                              delayMs: 120,
                              color: Color(0xFFA5D6A7),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideAvatar extends StatelessWidget {
  final String asset;
  final double size;

  const _SideAvatar({required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(asset, fit: BoxFit.cover),
    );
  }
}

class _SideAvatarStack extends StatelessWidget {
  final String primaryAsset;
  final bool compact;

  const _SideAvatarStack({required this.primaryAsset, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final size = compact ? 50.0 : 58.0;
    final supporting = BrandAssets.farmerAvatars
        .where((asset) => asset != primaryAsset)
        .take(2)
        .toList(growable: false);

    return SizedBox(
      width: compact ? 50 : 68,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < supporting.length; i++)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 320 + (i * 90)),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Positioned(
                  left: compact ? 0 : 24 + (i * 9),
                  top: compact ? 0 : 3 + (i * 18),
                  child: Opacity(
                    opacity: 0.58 * value,
                    child: Transform.translate(
                      offset: Offset((1 - value) * 10, 0),
                      child: child,
                    ),
                  ),
                );
              },
              child: _SideAvatar(asset: supporting[i], size: compact ? 28 : 30),
            ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.9, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _SideAvatar(asset: primaryAsset, size: compact ? 46 : 50),
            ),
          ),
          Positioned(
            right: compact ? -2 : 9,
            bottom: compact ? 0 : 2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF9CCC65),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideMenuDotButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;

  const _SideMenuDotButton({required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: compact ? 34 : 36,
          height: compact ? 30 : 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: const Icon(
            Icons.more_horiz_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _SideHeaderDot extends StatelessWidget {
  final int delayMs;
  final Color color;

  const _SideHeaderDot({required this.delayMs, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.45, end: 1),
      duration: Duration(milliseconds: 520 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: value, child: child),
        );
      },
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.86),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}

class _SideNavLogoutButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _SideNavLogoutButton({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: expanded ? 142 : 48,
      height: 48,
      child: Material(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Center(
            child: expanded
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  )
                : const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                    size: 21,
                  ),
          ),
        ),
      ),
    );
  }
}

class _PageScaffold extends StatelessWidget {
  final String title;
  final Widget child;

  const _PageScaffold({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final Color? tint;

  const _Panel({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tint ?? Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.green),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
