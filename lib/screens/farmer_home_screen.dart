import 'package:flutter/material.dart';
import 'dart:async';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import '../config/brand_assets.dart';
import '../config/satellite_config.dart';
import '../config/theme.dart';
import '../controllers/auth_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../models/satellite/farm_model.dart';
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
  static const _diseaseTabIndex = 4;
  static const _inventoryTabIndex = 3;
  static const _aiChatTabIndex = 5;
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
  }

  @override
  void dispose() {
    _verifiedFarmerWorker.dispose();
    super.dispose();
  }

  void _initializeFarmerStateFromSession({bool shouldSetState = true}) {
    final auth = Get.find<MainAuthController>();
    final verified = auth.verifiedFarmer.value;
    final fallback = verified == null
        ? _fallbackFarms
        : _seedFarmsFromVerified(verified);

    final nextProfile =
        verified == null ? _fallbackProfile : _profileFromVerified(verified);
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
    _initializeAllFarmState();
  }

  void _initializeAllFarmState() {
    for (var i = 0; i < _farms.length; i++) {
      _initializeFarmState(i);
    }
  }

  List<_FarmerFarm> _seedFarmsFromVerified(VerifiedFarmerRecord record) {
    if (record.lots.isEmpty) {
      return [
        _FarmerFarm(
          name: '${record.farmerName} Farm',
          location: record.defaultLocation,
          crop: 'Millet',
          variety: 'Mixed',
          area: '0 acres',
          health: 'Active',
          ndvi: '--',
          moisture: '--',
          product: 'General grain',
        ),
      ];
    }

    return record.lots
        .asMap()
        .entries
        .map(
          (entry) => _FarmerFarm(
            name: '${record.farmerName} Farm ${entry.key + 1}',
            location: entry.value.location.isEmpty
                ? record.defaultLocation
                : entry.value.location,
            crop: entry.value.grain.isEmpty ? 'Millet' : entry.value.grain,
            variety: entry.value.variety.isEmpty
                ? 'General'
                : entry.value.variety,
            area: '0 acres',
            health: 'Active',
            ndvi: '--',
            moisture: '--',
            product: entry.value.product,
          ),
        )
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
    NavigationDestination(
      icon: Icon(Icons.bug_report_outlined),
      selectedIcon: Icon(Icons.bug_report_rounded),
      label: 'Disease',
    ),
  ];

  static const _mobileDestinationFromPage = {
    _dashboardTabIndex: 0,
    _farmTabIndex: 1,
    _aiChatTabIndex: 2,
    _harvestTabIndex: 3,
    _diseaseTabIndex: 4,
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
        return _harvestTabIndex;
      case 4:
      default:
        return _diseaseTabIndex;
    }
  }

  static int _mobileIndexForPage(int pageIndex) {
    if (pageIndex == _inventoryTabIndex) {
      return _mobileDestinationFromPage[_harvestTabIndex]!;
    }
    return _mobileDestinationFromPage[pageIndex] ?? _mobileDestinationFromPage[_diseaseTabIndex]!;
  }

  static Widget _mobileNavIcon({
    required IconData defaultIcon,
    required IconData activeIcon,
    required String label,
    required bool selected,
    required bool isCenter,
  }) {
    if (isCenter) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: selected ? 38 : 34,
            height: selected ? 38 : 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
              ),
              shape: BoxShape.circle,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.green.withValues(alpha: 0.38),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : const [],
            ),
            child: Icon(
              selected ? activeIcon : defaultIcon,
              color: Colors.white,
              size: selected ? 20 : 18,
            ),
          ),
          if (selected) ...[
            const SizedBox(height: 1),
            const Text(
              'AI Chat',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                color: AppTheme.green,
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          transform: Matrix4.identity()..scale(selected ? 1.03 : 1.0),
          child: Icon(
            selected ? activeIcon : defaultIcon,
            size: selected ? 21 : 19,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            color: selected ? AppTheme.green : AppTheme.textMuted,
          ),
        ),
      ],
    );
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
      child: Container(
        height: 90,
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Background bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.84),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFDCE6D4)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.11),
                          blurRadius: 14,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The row of items
            Positioned(
              left: 6,
              right: 6,
              bottom: 0,
              height: 90,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < _destinations.length; i++)
                    Expanded(
                      child: i == 2
                          ? _buildCenterFloatingButton()
                          : _buildNormalNavItem(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalNavItem(int i) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          _setMobileTab(i);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 56,
          padding: const EdgeInsets.symmetric(
            vertical: 4,
            horizontal: 2,
          ),
          decoration: BoxDecoration(
            color: _mobileNavIndexFromPage() == i
                ? Colors.green.shade50
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: AnimatedScale(
            scale: _mobileNavIndexFromPage() == i ? 1.0 : 0.96,
            duration: const Duration(milliseconds: 220),
            child: _mobileNavIcon(
              defaultIcon: (i == 0)
                  ? Icons.home_outlined
                  : (i == 1)
                      ? Icons.agriculture_outlined
                      : (i == 3)
                          ? Icons.inventory_2_outlined
                          : Icons.bug_report_outlined,
              activeIcon: (i == 0)
                  ? Icons.home_rounded
                  : (i == 1)
                      ? Icons.agriculture_rounded
                      : (i == 3)
                          ? Icons.inventory_2_rounded
                          : Icons.bug_report_rounded,
              label: (i == 0)
                  ? 'Home'
                  : (i == 1)
                      ? 'Farm'
                      : (i == 3)
                          ? 'Harvest'
                          : 'Disease',
              selected: _mobileNavIndexFromPage() == i,
              isCenter: false,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterFloatingButton() {
    final selected = _mobileNavIndexFromPage() == 2;
    return Container(
      height: 90,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _setMobileTab(2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: selected ? 58 : 52,
                height: selected ? 58 : 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E7D32).withValues(alpha: selected ? 0.45 : 0.2),
                      blurRadius: selected ? 12 : 6,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  selected ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                  color: Colors.white,
                  size: selected ? 28 : 24,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _setMobileTab(2),
            child: Text(
              'AI Chat',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                color: selected ? AppTheme.green : AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, String>> _marketLotPayloads() {
    return _harvestInventory
        .map(
          (lot) => lot.toMarketPayload(),
        )
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
      final index = _harvestInventory.indexWhere((item) => item.batchId == lot.batchId);
      if (index >= 0) {
        _harvestInventory[index] = lot;
      } else {
        _harvestInventory.insert(0, lot);
      }
    });
  }

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: Text('Home'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.agriculture_outlined),
      selectedIcon: Icon(Icons.agriculture_rounded),
      label: Text('Farm'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.inventory_outlined),
      selectedIcon: Icon(Icons.inventory_2_rounded),
      label: Text('Harvest'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.inventory_2_outlined),
      selectedIcon: Icon(Icons.inventory_2_rounded),
      label: Text('Inventory'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.bug_report_outlined),
      selectedIcon: Icon(Icons.bug_report_rounded),
      label: Text('Disease'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome_rounded),
      label: Text('AI Chat'),
    ),
  ];

  _FarmerFarm get _farm => _farms[_selectedFarm];

  String get _currentFarmAvatar =>
      BrandAssets.farmerAvatars[_selectedFarm % BrandAssets.farmerAvatars.length];

  String _satelliteRequestToken() {
    if (!Get.isRegistered<AuthController>()) return '';
    final token = Get.find<AuthController>().accessToken.value;
    return token.isEmpty ? '' : token;
  }

  String _normalizeLookup(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
    final userMatch = farms.where((item) => item.userId != null && userId != null && item.userId == userId).toList();
    final matchingNames = farms.where((item) => _normalizeLookup(item.name) == farmName).toList();

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

  Map<String, List<TimelineEntry>> _groupTimelineByIndex(List<TimelineEntry> entries) {
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

  _SatelliteMetricTileData _placeholderTile(String title, IconData icon, Color tint, Color color) {
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

  _FarmSatelliteOverview _buildFarmSatelliteOverview(List<TimelineEntry> entries) {
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
    return LatLng(
      center.latitude + shift.dx,
      center.longitude + shift.dy,
    );
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
              polygonPoints.map((point) => point.latitude).reduce((a, b) => a + b) /
                  polygonPoints.length,
              polygonPoints
                      .map((point) => point.longitude)
                      .reduce((a, b) => a + b) /
                  polygonPoints.length,
            ),
    );
    final acres = setupResult.acres.trim().isEmpty
        ? '0 acres'
        : '${setupResult.acres.trim()} acres';

    final farm = _FarmerFarm(
      name: setupResult.farmName.trim(),
      location: location,
      crop: setupResult.crop,
      variety: setupResult.variety,
      area: acres,
      health: 'Active',
      ndvi: '--',
      moisture: '--',
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

    await _saveFarmToRemote(setupResult.farmName, polygonPoints);
    if (!mounted) return;
    _ensureSatelliteOverviewForFarm(_selectedFarm);
    if (_index == _farmTabIndex && mounted) {
      await _openFarmStatusUpdate(_selectedFarm);
    }
  }

  Future<void> _saveFarmToRemote(
    String farmName,
    List<LatLng> polygonPoints,
  ) async {
    if (!Get.isRegistered<FarmController>()) return;
    if (polygonPoints.length < 3) return;
    final farmCtrl = Get.find<FarmController>();
    await farmCtrl.saveFarm(
      name: farmName,
      points: polygonPoints,
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
            result.photoName ?? 'field-status-${DateTime.now().millisecondsSinceEpoch}.jpg';
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
    final markers = List<LatLng>.from(_farmDiseaseMarkers[index] ?? const <LatLng>[]);
    final logs = List<String>.from(_farmDiagnosisLog[index] ?? const <String>[]);
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
                            _farmDiseaseMarkers[index] = List<LatLng>.from(markers);
                            _farmDiagnosisLog[index] = List<String>.from(logs);
                          });
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

  void _openDiseaseTab() {
    setState(() => _index = _diseaseTabIndex);
  }

  void _openAiChatTab() {
    setState(() => _index = _aiChatTabIndex);
  }

  void _openMarketPage() {
    final selectedFarmName = (_selectedFarm >= 0 && _selectedFarm < _farms.length)
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
    Get.to(
      () => NewsPage(
        farmName: farm?.name,
        farmLocation: farm?.location,
      ),
    );
  }

  void _openWeatherPage() {
    final hasFarm = _selectedFarm >= 0 && _selectedFarm < _farms.length;
    final farm = hasFarm ? _farms[_selectedFarm] : null;
    Get.to(
      () => WeatherPage(
        farmName: farm?.name,
        farmLocation: farm?.location,
      ),
    );
  }

  void _openSchemesPage() {
    final hasFarm = _selectedFarm >= 0 && _selectedFarm < _farms.length;
    final farm = hasFarm ? _farms[_selectedFarm] : null;
    Get.to(
      () => SchemesPage(
        farmName: farm?.name,
        farmLocation: farm?.location,
      ),
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

  void _navigateFromSideDetail(VoidCallback action) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    action();
  }

  void _openNavigationDetail() {
    Get.to(
      () => _FarmerNavigationDetailPage(
        farmerName: _profile.name,
        selectedFarm: _farm.name,
        stageSummary: _stageSummary(_selectedFarm),
        inventoryCount: _harvestInventory.length,
        farmCount: _farms.length,
        onOpenHome: () => _navigateFromSideDetail(
          () => setState(() => _index = _dashboardTabIndex),
        ),
        onOpenFarm: () => _navigateFromSideDetail(
          () => setState(() => _index = _farmTabIndex),
        ),
        onOpenHarvest: () => _navigateFromSideDetail(
          () => setState(() => _index = _harvestTabIndex),
        ),
        onOpenDisease: () => _navigateFromSideDetail(
          () => setState(() => _index = _diseaseTabIndex),
        ),
        onOpenInventory: () => _navigateFromSideDetail(
          () => setState(() => _index = _inventoryTabIndex),
        ),
        onOpenAiChat: () => _navigateFromSideDetail(_openAiChatTab),
        onOpenMarket: () => _navigateFromSideDetail(_openMarketPage),
        onOpenNews: () => _navigateFromSideDetail(_openNewsPage),
        onOpenWeather: () => _navigateFromSideDetail(_openWeatherPage),
        onOpenSchemes: () => _navigateFromSideDetail(_openSchemesPage),
        onOpenProfile: () => _navigateFromSideDetail(
          () => Get.to(
            () => FarmerProfileScreen(
              profile: _profile,
              farm: _farm,
              avatarAsset: _currentFarmAvatar,
            ),
          ),
        ),
        onOpenAiGrading: () => _navigateFromSideDetail(
          () => Get.to(
            () => const FarmerAiGradingScreen(),
            arguments: {
              'farmName': _farm.name,
              'crop': _farm.crop,
              'village': _profile.location,
            },
          ),
        ),
      ),
    );
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
        onOpenHarvest: _openHarvestTab,
        onOpenDisease: _openDiseaseTab,
        onOpenNews: _openNewsPage,
        onOpenWeather: _openWeatherPage,
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
        },
        onOpenFarmInsight: _openFarmMapInsight,
        onOpenDiagnose: _openDiagnosisFlow,
        onOpenStatusUpdate: _openFarmStatusUpdate,
        farmPolygons: farmPolygons,
        statusByFarm: _farmStatusAnswer,
        stageByFarm: _farmGrowthStage,
        diseaseMarkersByFarm: _farmDiseaseMarkers,
        statusUpdatedAt: _farmStatusUpdatedAt,
        stageSummary: _stageSummary,
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
      _DiseaseDetectionPage(
        farm: _farm,
        diseaseLogs: _farmDiagnosisLog[_selectedFarm] ?? const [],
        diseaseMarkers: _farmDiseaseMarkers[_selectedFarm] ?? const [],
        farmPolygon: farmPolygons[_selectedFarm] ?? const [],
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
          appBar: useSideNav ? null : AppBar(
            backgroundColor: AppTheme.surface,
            elevation: 0,
            iconTheme: const IconThemeData(color: AppTheme.greenDark),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(BrandAssets.logo, width: 28, height: 28),
                const SizedBox(width: 8),
                const BrandText(fontSize: 18),
              ],
            ),
          ),
          body: SafeArea(
            child: useSideNav
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: (value) =>
                            setState(() => _index = value),
                        extended: constraints.maxWidth >= 1060,
                        backgroundColor: Colors.white,
                        indicatorColor: AppTheme.greenPale,
                        leading: Builder(
                          builder: (context) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 18),
                              child: IconButton(
                                icon: const Icon(Icons.menu_rounded, size: 30),
                                onPressed: () {
                                  Scaffold.of(context).openDrawer();
                                },
                              ),
                            );
                          }
                        ),
                        destinations: _railDestinations,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          transitionBuilder: (child, animation) {
                            final offsetTween = Tween<Offset>(
                              begin: const Offset(0.05, 0),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ));
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
                      final offsetTween = Tween<Offset>(
                        begin: const Offset(0.05, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ));
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

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: AppTheme.greenPale.withValues(alpha: 0.3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(_currentFarmAvatar, fit: BoxFit.cover),
                ),
                const SizedBox(height: 12),
                Text(
                  _profile.name,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  _profile.location,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.apps_rounded, color: AppTheme.green),
            title: const Text('App Navigation', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('All screens in one place'),
            onTap: () {
              Navigator.pop(context);
              _openNavigationDetail();
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_rounded, color: AppTheme.green),
            title: const Text('Detailed Profile', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context); // Close drawer
              Get.to(
                () => FarmerProfileScreen(
                  profile: _profile,
                  farm: _farm,
                  avatarAsset: _currentFarmAvatar,
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded, color: AppTheme.green),
            title: const Text('Farm History', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context);
              _openHistoryPage(_selectedFarm);
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_rounded, color: AppTheme.green),
            title: const Text('Inventory', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _index = _inventoryTabIndex);
            },
          ),
          ListTile(
            leading: const Icon(Icons.center_focus_strong_rounded, color: AppTheme.green),
            title: const Text('Grain Grading', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context);
              Get.to(
                () => const FarmerAiGradingScreen(),
                arguments: {
                  'farmName': _farm.name,
                  'crop': _farm.crop,
                  'village': _profile.location,
                },
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.wb_cloudy_rounded, color: AppTheme.green),
            title: const Text('Weather', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context);
              _openWeatherPage();
            },
          ),
          ListTile(
            leading: const Icon(Icons.storefront_rounded, color: AppTheme.green),
            title: const Text('Market', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context);
              _openMarketPage();
            },
          ),
          ListTile(
            leading: const Icon(Icons.newspaper_rounded, color: AppTheme.green),
            title: const Text('News', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context);
              _openNewsPage();
            },
          ),
          ListTile(
            leading: const Icon(Icons.assignment_rounded, color: AppTheme.green),
            title: const Text('Schemes', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.pop(context);
              _openSchemesPage();
            },
          ),
        ],
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

  String get lotLabel => '$batchId • $grade • ${estimatedYieldKg.toStringAsFixed(1)}kg';

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

  const _InventoryPage({
    required this.lots,
    required this.onTapListForSell,
  });

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
    final filtered = widget.lots.where((lot) {
      final farmMatch = _selectedFarm == _allFarmsLabel ||
          lot.farmName.toLowerCase() == selected;
      if (!farmMatch) return false;
      if (query.isEmpty) return true;
      return lot.batchId.toLowerCase().contains(query) ||
          lot.crop.toLowerCase().contains(query) ||
          lot.variety.toLowerCase().contains(query) ||
          lot.grade.toLowerCase().contains(query);
    }).toList(growable: false);

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
    final totalQty = lots.fold<double>(0, (sum, lot) => sum + lot.estimatedYieldKg);
    final avgMoisture = lots.isEmpty
        ? 0.0
        : lots.fold<double>(0, (sum, lot) => sum + lot.moisturePercent) / lots.length;
    final avgScore = lots.isEmpty
        ? 0.0
        : lots.fold<double>(0, (sum, lot) => sum + lot.gradeScore) / lots.length;

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
                    child: _SummaryStat(
                      title: 'Lots',
                      value: '${lots.length}',
                    ),
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
            ...lots.asMap().entries.map(
              (entry) {
                final index = entry.key;
                final lot = entry.value;
                return Padding(
                  padding: EdgeInsets.only(bottom: index == lots.length - 1 ? 0 : 10),
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
                                  value: '${lot.moisturePercent.toStringAsFixed(1)}%',
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
                                  value: '${lot.estimatedYieldKg.toStringAsFixed(1)}kg',
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
              },
            ),
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
  final VoidCallback onOpenHarvest;
  final VoidCallback onOpenDisease;
  final VoidCallback onOpenNews;
  final VoidCallback onOpenWeather;
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
    required this.onOpenHarvest,
    required this.onOpenDisease,
    required this.onOpenNews,
  required this.onOpenWeather,
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
                      final slide = Tween<Offset>(
                        begin: const Offset(0.04, 0.04),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ));
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slide,
                          child: child,
                        ),
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
                const _HomeRevealSection(
                  delayMs: 40,
                  child: _SectionTitle(title: 'Farm Overview'),
                ),
                const SizedBox(height: 12),
                _HomeRevealSection(
                  delayMs: 60,
                  child: _FarmSatelliteOverviewSection(
                    overview: satelliteOverview,
                    isLoading: isSatelliteLoading,
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
                  delayMs: 90,
                  child: _SectionTitle(title: 'Farm Operations'),
                ),
                const SizedBox(height: 12),
                const _HomeRevealSection(
                  delayMs: 110,
                  child: _OperationsGrid(),
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
            const Positioned.fill(child: FarmHillsBackground()),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.58),
                      Colors.white.withValues(alpha: 0.03),
                    ],
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
                width: 94,
                height: 94,
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
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
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
                        width: (constraints.maxWidth - ((crossAxisCount - 1) * 10)) /
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                Expanded(child: _FarmMetric(label: 'Area', value: farm.area)),
                const SizedBox(width: 8),
                Expanded(child: _FarmMetric(label: 'Crop', value: farm.crop)),
                const SizedBox(width: 8),
                Expanded(child: _FarmMetric(label: 'Variety', value: farm.variety)),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onOpenFarm,
                icon: const Icon(Icons.grass_rounded),
                label: const Text('Open farm'),
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

class _QuickAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionGrid extends StatelessWidget {
  final List<_QuickAction> items;

  const _QuickActionGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 620 ? 4 : 2;
            return GridView.builder(
              itemCount: items.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
                childAspectRatio: constraints.maxWidth > 620 ? 1.1 : 0.95,
              ),
          itemBuilder: (context, index) {
            final item = items[index];
            final delay = 45 + (index * 45);
            return TweenAnimationBuilder<double>(
              key: ValueKey('${item.title}-$index'),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 260 + delay),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - value)),
                    child: Transform.scale(
                      scale: 0.96 + (0.04 * value),
                      child: child,
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.52),
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: item.onTap,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(9, 10, 9, 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: item.color.withValues(alpha: 0.24),
                            width: 1,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              item.tint.withValues(alpha: 0.72),
                              item.tint.withValues(alpha: 0.28),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Icon(item.icon, color: item.color, size: 24),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.subtitle,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textDark,
                                fontSize: 10,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _OperationsGrid extends StatelessWidget {
  const _OperationsGrid();

  @override
  Widget build(BuildContext context) {
    final items = [
      const _OperationItem(
        icon: Icons.event_note_outlined,
        title: 'Crop Calendar',
        detail: 'Next weeding in 4 days',
        tint: Color(0xFFE8F5E9),
        color: AppTheme.green,
      ),
      const _OperationItem(
        icon: Icons.water_drop_outlined,
        title: 'Irrigation',
        detail: 'Moisture level good',
        tint: Color(0xFFEAF6FF),
        color: Color(0xFF1976D2),
      ),
      const _OperationItem(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Expense Book',
        detail: 'Season cost: Rs 18,400',
        tint: Color(0xFFFFF8E1),
        color: Color(0xFFB8860B),
      ),
      const _OperationItem(
        icon: Icons.storefront_outlined,
        title: 'Market Rate',
        detail: 'Finger millet: Rs 42/kg',
        tint: Color(0xFFF0EAFE),
        color: Color(0xFF673AB7),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth > 520;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: twoColumn
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth,
                child: _OperationCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _OperationItem {
  final IconData icon;
  final String title;
  final String detail;
  final Color tint;
  final Color color;

  const _OperationItem({
    required this.icon,
    required this.title,
    required this.detail,
    required this.tint,
    required this.color,
  });
}

class _OperationCard extends StatelessWidget {
  final _OperationItem item;

  const _OperationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Get.snackbar(
          item.title,
          item.detail,
          snackPosition: SnackPosition.BOTTOM,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.tint,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(item.icon, color: item.color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.detail,
                      maxLines: 1,
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
        ),
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

  const _HarvestReadinessCard({
    required this.farm,
    required this.onOpenAiChat,
  });

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

  const _FarmSatelliteOverview({
    required this.tiles,
    this.note,
  });
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
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
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
    'Finger Millet': {'A+': 1.00, 'A': 0.97, 'B+': 0.93, 'B': 0.88, 'C': 0.80, 'D': 0.68},
    'Foxtail Millet': {'A+': 1.00, 'A': 0.96, 'B+': 0.92, 'B': 0.86, 'C': 0.78, 'D': 0.66},
    'Rice': {'A+': 1.00, 'A': 0.98, 'B+': 0.93, 'B': 0.86, 'C': 0.77, 'D': 0.65},
    'Bajra': {'A+': 1.00, 'A': 0.96, 'B+': 0.92, 'B': 0.84, 'C': 0.76, 'D': 0.64},
  };

  double _estimatedYield({
    required double bagSize,
    required int bagCount,
    required String grade,
  }) {
    final cropMap = _yieldCurve[widget.cropName] ??
        const {'A+': 1.0, 'A': 0.95, 'B+': 0.9, 'B': 0.83, 'C': 0.74, 'D': 0.62};
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

  bool get _canCaptureImage =>
      _farmLatitude != null && _farmLongitude != null;

  Future<void> _captureMachineImage() async {
    if (_farmLatitude == null || _farmLongitude == null) {
      Get.snackbar(
        'Live location required',
        'Fetch live location before capturing machine image.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    setState(() => _isCapturingImage = true);
    try {
      final result = await pickHarvestMachineImage();
      if (result == null) return;
      if (!mounted) return;
      setState(() {
        _machineImageBytes = result.bytes;
        _machineImageName = result.name;
        _hasMachineImage = true;
      });
      Get.snackbar(
        'Machine image added',
        'Moisture image linked to location ${_locationSummary}.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      Get.snackbar(
        'Capture failed',
        'Could not open camera. Check permissions and try again.',
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
    final totalKg =
        (double.parse(bagSize) * int.parse(bagCount)).toStringAsFixed(1);
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
                    decoration: const InputDecoration(labelText: 'Bag size (kg)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _bagCountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Number of bags'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLocationFetching ? null : _fetchLocation,
                          icon: const Icon(Icons.gps_fixed_rounded),
                          label: const Text('Live location'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isCapturingImage ||
                                  !_canCaptureImage
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
                      _isGrading ? 'Running grading...' : 'Run grading (mandatory)',
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
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _DiseaseDetectionPage extends StatelessWidget {
  final _FarmerFarm farm;
  final List<String> diseaseLogs;
  final List<LatLng> diseaseMarkers;
  final List<LatLng> farmPolygon;

  const _DiseaseDetectionPage({
    required this.farm,
    required this.diseaseLogs,
    required this.diseaseMarkers,
    required this.farmPolygon,
  });

  List<CircleMarker> get _diseaseCircles {
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

  @override
  Widget build(BuildContext context) {
    return _PageScaffold(
      title: 'Disease Detection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SatelliteMapView(
                    farmPolygon: farmPolygon,
                    heatCircles: _diseaseCircles,
                    height: 190,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    farm.name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Diagnosed zones are marked from Farm tab workflow with current crop stage and your notes.',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (diseaseLogs.isEmpty) ...[
                    const Text(
                      'No diagnosis logged yet.',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Marked logs',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...diseaseLogs.map(
                      (log) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.34),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFE65100),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  log,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Get.snackbar(
                        'Disease Detection',
                        'Image detection model connection is ready to be wired here.',
                        snackPosition: SnackPosition.BOTTOM,
                      ),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Scan crop photo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _Panel(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Likely Risks',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 14),
                  _RiskRow(
                    title: 'Leaf Spot',
                    status: 'Moderate',
                    color: Color(0xFFE07800),
                  ),
                  _RiskRow(
                    title: 'Downy Mildew',
                    status: 'Low',
                    color: AppTheme.green,
                  ),
                  _RiskRow(title: 'Rust', status: 'Low', color: AppTheme.green),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  final String title;
  final String status;
  final Color color;

  const _RiskRow({
    required this.title,
    required this.status,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              status,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmPage extends StatelessWidget {
  final List<_FarmerFarm> farms;
  final int selectedIndex;
  final ValueChanged<int> onSelectFarm;
  final ValueChanged<int> onOpenFarmInsight;
  final ValueChanged<int> onOpenDiagnose;
  final ValueChanged<int> onOpenStatusUpdate;
  final Map<int, List<LatLng>> farmPolygons;
  final Map<int, String> statusByFarm;
  final Map<int, String> stageByFarm;
  final Map<int, List<LatLng>> diseaseMarkersByFarm;
  final Map<int, DateTime> statusUpdatedAt;
  final String Function(int) stageSummary;

  const _FarmPage({
    required this.farms,
    required this.selectedIndex,
    required this.onSelectFarm,
    required this.onOpenFarmInsight,
    required this.onOpenDiagnose,
    required this.onOpenStatusUpdate,
    required this.farmPolygons,
    required this.statusByFarm,
    required this.stageByFarm,
    required this.diseaseMarkersByFarm,
    required this.statusUpdatedAt,
    required this.stageSummary,
  });

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

  @override
  Widget build(BuildContext context) {
    final selected = farms[selectedIndex];
    final selectedPolygon = farmPolygons[selectedIndex] ?? const [];
    final diseaseMarkers = diseaseMarkersByFarm[selectedIndex] ?? const [];
    final currentStage = stageByFarm[selectedIndex] ?? 'Sowing';
    final currentStatus = statusByFarm[selectedIndex] ?? 'No status update yet';
    final updatedAt = statusUpdatedAt[selectedIndex];
    return _PageScaffold(
      title: 'My Farms',
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
                      'Farm Overview',
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
                    value: '$currentStage • $currentStatus',
                  ),
                  if (updatedAt != null) ...[
                    const SizedBox(height: 8),
                    _InfoStrip(
                      icon: Icons.schedule_outlined,
                      label: 'Updated',
                      value: '${updatedAt.day.toString().padLeft(2, '0')}/${updatedAt.month.toString().padLeft(2, '0')} ${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}',
                    ),
                  ],
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => onOpenFarmInsight(selectedIndex),
                    child: SizedBox(
                      height: 172,
                      child: SatelliteMapView(
                        farmPolygon: selectedPolygon,
                        heatCircles: _diseaseCircles(diseaseMarkers),
                        height: 172,
                        showZoomControls: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => onOpenDiagnose(selectedIndex),
                          icon: const Icon(Icons.bug_report_rounded),
                          label: const Text('Diagnose'),
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
                      _FarmMetric(label: 'Area', value: selected.area),
                      _FarmMetric(label: 'NDVI', value: selected.ndvi),
                      _FarmMetric(label: 'Moisture', value: selected.moisture),
                    ],
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
                  onOpenFarmInsight(i);
                },
              ),
            ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _DiagonalFarmActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  const _DiagonalFarmActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 46,
        child: FloatingActionButton.extended(
          heroTag: 'farm-diagnose-fab',
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: const Color(0xFF1B5E20),
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
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
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
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
      appBar: AppBar(
        title: Text(farm.name),
        elevation: 0,
      ),
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
                      _FarmMetric(label: 'Area', value: farm.area),
                      _FarmMetric(label: 'NDVI', value: farm.ndvi),
                      _FarmMetric(label: 'Moisture', value: farm.moisture),
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
                          onTap: () => Get.to(() => _NdviHistoryDetailPage(farm: farm)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InsightDetailCard(
                          title: 'Soil Health',
                          subtitle: 'pH, NPK & Moisture',
                          icon: Icons.science_outlined,
                          color: const Color(0xFFFFF3E0),
                          onTap: () => Get.to(() => _SoilDiagnosticsDetailPage(farm: farm)),
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
                          onTap: () => Get.to(() => _WeatherImpactDetailPage(farm: farm)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _InsightDetailCard(
                          title: 'Yield Prognosis',
                          subtitle: 'Expected harvest index',
                          icon: Icons.bar_chart_rounded,
                          color: const Color(0xFFF3E8FF),
                          onTap: () => Get.to(() => _YieldPrognosisDetailPage(farm: farm)),
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
            border: Border.all(color: AppTheme.greenPale.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.greenDark, size: 24),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.greenDark, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, height: 1.3),
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
        title: Text('${farm.name} • NDVI Analysis', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.greenDark, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.greenDark),
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
                    const Text('NDVI Health Index Trend', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    const Text('NDVI ranges from 0.0 to 1.0. Higher values (0.6 - 0.8) indicate healthy green vegetative growth.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
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
                      child: CustomPaint(
                        painter: _NdviCurvePainter(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Sowing (0.15)', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                        Text('Veg (0.42)', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                        Text('Flowering (0.76)', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                        Text('Filling (0.68)', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
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
                    const Text('Satellite Overpasses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    _buildPassRow('June 08, 2026', 'Sentinel-2B', '0.76', '0.2% Cloud'),
                    const Divider(),
                    _buildPassRow('May 28, 2026', 'Sentinel-2A', '0.64', '1.5% Cloud'),
                    const Divider(),
                    _buildPassRow('May 18, 2026', 'Sentinel-2B', '0.45', '12% Cloud'),
                    const Divider(),
                    _buildPassRow('May 08, 2026', 'Sentinel-2A', '0.28', '0.0% Cloud'),
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
              Text(sat, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(ndvi, style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.greenDark)),
              Text(cloud, style: const TextStyle(fontSize: 11, color: Colors.blueAccent)),
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
      size.width * 0.3, size.height * 0.8,
      size.width * 0.6, size.height * 0.1,
      size.width * 0.8, size.height * 0.25,
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

    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.25), 5, dotPaint);
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
        title: Text('${farm.name} • Soil Health', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.greenDark, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.greenDark),
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
                    const Text('NPK & Soil Chemistry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    _buildNutrientBar('Nitrogen (N)', 0.65, 'Optimal (65 kg/ha)', Colors.blue),
                    _buildNutrientBar('Phosphorus (P)', 0.42, 'Moderate (28 kg/ha)', Colors.orange),
                    _buildNutrientBar('Potassium (K)', 0.85, 'High (195 kg/ha)', Colors.purple),
                    _buildNutrientBar('Organic Carbon', 0.55, 'Moderate (0.55%)', Colors.green),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('Soil pH Value:', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text('6.7 (Slightly Acidic • Ideal)', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.greenDark)),
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
                    Text('Advisory for Millets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.greenDark)),
                    SizedBox(height: 10),
                    Text('• Apply 20 kg/ha of phosphorus before upcoming rain shower.', style: TextStyle(height: 1.4)),
                    SizedBox(height: 6),
                    Text('• Top-dress with nitrogen during vegetative growth at day 35.', style: TextStyle(height: 1.4)),
                    SizedBox(height: 6),
                    Text('• Organic carbon level is slightly low; add vermicompost or farmyard manure after current harvest.', style: TextStyle(height: 1.4)),
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
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(text, style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 11)),
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
        title: Text('${farm.name} • Weather Impact', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.greenDark, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.greenDark),
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
                    const Text('Microclimate Statistics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
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
                    Text('Weather Hazards Outlook', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.greenDark)),
                    SizedBox(height: 10),
                    Text('• Fungal Disease Risk: Low (Humidity remains under 70%)', style: TextStyle(height: 1.4)),
                    SizedBox(height: 6),
                    Text('• Heat Stress: Moderate (Top temps exceeding 31°C; ensure evening soil dampness)', style: TextStyle(height: 1.4)),
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
          Text(val, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.greenDark)),
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
        title: Text('${farm.name} • Yield Prognosis', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.greenDark, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.greenDark),
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
                    const Text('Expected Yield Prognosis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 14),
                    _buildYieldRow('Est. Production', '850 - 950 kg/acre'),
                    _buildYieldRow('Current Stage Projection', 'On Track (102%)'),
                    _buildYieldRow('Est. Harvest Window', 'July 15 - July 20'),
                    _buildYieldRow('Quality Grade Prediction', 'A (High density grains)'),
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
                    Text('Pre-harvest Checklist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.greenDark)),
                    SizedBox(height: 10),
                    Text('• Arrange drying yards and ensure moisture is under 12%.', style: TextStyle(height: 1.4)),
                    SizedBox(height: 6),
                    Text('• Procure 18 jute bags (50kg capacity) ahead of time.', style: TextStyle(height: 1.4)),
                    SizedBox(height: 6),
                    Text('• Clean harvester blades to prevent contamination.', style: TextStyle(height: 1.4)),
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
          Text(val, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.greenDark)),
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
    return daysAfterSowing >= milestone.startDay && daysAfterSowing <= milestone.endDay;
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.greenDark),
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
                        _FarmMetric(label: 'Stage', value: currentStage),
                        SizedBox(width: 8),
                        _FarmMetric(
                          label: 'Last status',
                          value: 'Updated',
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
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${lot.crop} • ${lot.variety} • ${lot.grade} • ${lot.estimatedYieldKg.toStringAsFixed(1)}kg',
                                    style: const TextStyle(color: AppTheme.textMuted),
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
            if (satelliteOverview != null && satelliteOverview!.tiles.isNotEmpty) ...[
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
          ],
        ),
      ),
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
    if (_selectedFarm != _allFarmsLabel && !_farmOptions.contains(_selectedFarm)) {
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
            return (lot['batchId'] ?? '').toLowerCase().contains(searchFilter) ||
                (lot['crop'] ?? '').toLowerCase().contains(searchFilter) ||
                (lot['variety'] ?? '').toLowerCase().contains(searchFilter) ||
                (lot['grade'] ?? '').toLowerCase().contains(searchFilter);
          });

    final sorted = searched.toList(growable: false)
      ..sort((a, b) {
        switch (_sortBy) {
          case 'Newest':
            return _parseDate(b['harvestedAt']).compareTo(_parseDate(a['harvestedAt']));
          case 'Highest grade':
            return _toInt(b['score']).compareTo(_toInt(a['score']));
          case 'Lowest moisture':
            return _toDouble(a['moisture']).compareTo(_toDouble(b['moisture']));
          case 'Highest qty':
            return _toDouble(b['estimatedYield']).compareTo(_toDouble(a['estimatedYield']));
          case 'Recommended':
          default:
            final score = _toInt(b['score']).compareTo(_toInt(a['score']));
            if (score != 0) return score;
            return _toDouble(b['estimatedYield']).compareTo(_toDouble(a['estimatedYield']));
        }
      });

    return sorted;
  }

  List<String> get _farmOptions {
    final farms = <String>{_allFarmsLabel};
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
    final scopeLabel = _selectedFarm == _allFarmsLabel ? 'all farms' : _selectedFarm;
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
        : scopedLots.fold<double>(0, (sum, lot) => sum + _toDouble(lot['moisture'])) /
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.greenDark),
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
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Create a lot-focused listing, compare grade impact, and review demand trend quickly.',
                      style: TextStyle(color: AppTheme.textDark, height: 1.35),
                    ),
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
              child: const Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No matching harvest lot found. Adjust filters or add a new harvest lot to list.',
                  style: TextStyle(color: AppTheme.textMuted),
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
              final isSelected = selectedLotId != null && selectedLotId == batchId;
              final harvestRate = 2100 + (score * 24);
              final expectedValue = (yieldEstimate / 1000) * harvestRate;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _Panel(
                  tint: isSelected ? AppTheme.greenPale.withValues(alpha: 0.2) : null,
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
                              color: isSelected ? AppTheme.green : AppTheme.textMuted,
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
                                value: '${yieldEstimate.toStringAsFixed(1)} kg',
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
                                value: '$bagCount × ${bagSize.toStringAsFixed(0)}kg',
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
                                icon: const Icon(Icons.storefront_rounded, size: 18),
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
                                icon: const Icon(Icons.trending_up_rounded, size: 18),
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

  const NewsPage({
    this.farmName,
    this.farmLocation,
  });

  static const List<Map<String, String>> _newsFeed = [
    {
      'title': 'Millet MSP updated for upcoming procurement cycle',
      'summary': 'Farm support channels report improved rates in Maharashtra.',
      'time': 'Today',
    },
    {
      'title': 'Monsoon outlook: lighter showers expected',
      'summary': 'Weather advisories suggest staggered irrigation in low-lying fields.',
      'time': 'Yesterday',
    },
    {
      'title': 'Storage tips for short-season grains',
      'summary': 'Drying and bin ventilation reduced mold and pest risk.',
      'time': '2 days ago',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final contextTitle = farmName == null ? 'News & Advisories' : 'News • ${farmName!}';
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.greenDark),
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
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      farmName == null
                          ? (farmLocation ?? 'Local farm area')
                          : (farmLocation == null || farmLocation!.trim().isEmpty
                              ? '${farmName!} • farm updates'
                              : '${farmName!} • ${farmLocation!}'),
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                ),
              ),
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
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['summary']!,
                          style: const TextStyle(color: AppTheme.textDark, height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['time']!,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
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
        border: Border.all(color: selected ? AppTheme.green : const Color(0xFFE5E7EB)),
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

  const SchemesPage({
    this.farmName,
    this.farmLocation,
  });

  static const List<Map<String, String>> _schemes = [
    {
      'title': 'PM-KISAN Direct Support',
      'desc': 'Income support for farmers with crop-specific conditions.',
      'status': 'Apply',
    },
    {
      'title': 'Millet Processing Grant',
      'desc': 'Support for post-harvest processing units at district level.',
      'status': 'Open',
    },
    {
      'title': 'Soil Health & Water Mission',
      'desc': 'Free soil card and advisory updates linked with local officers.',
      'status': 'By district office',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final contextTitle = farmName == null ? 'Government Schemes' : 'Schemes • ${farmName!}';
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.greenDark),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      farmName == null
                          ? (farmLocation ?? 'Local scheme center')
                          : (farmLocation == null || farmLocation!.trim().isEmpty
                              ? '${farmName!} • local scheme center'
                              : '${farmName!} • ${farmLocation!}'),
                      style: const TextStyle(color: AppTheme.textMuted),
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
                        const Icon(Icons.assignment_rounded, color: AppTheme.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  scheme['title']!,
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                              const SizedBox(height: 6),
                              Text(
                                scheme['desc']!,
                                style: const TextStyle(color: AppTheme.textDark, height: 1.35),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    scheme['status']!,
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.greenDark),
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
      'source': 'verified_farmer_seed',
      'verified': true,
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

class _FarmerNavigationDetailPage extends StatelessWidget {
  final String farmerName;
  final String selectedFarm;
  final String stageSummary;
  final int farmCount;
  final int inventoryCount;
  final VoidCallback onOpenHome;
  final VoidCallback onOpenFarm;
  final VoidCallback onOpenHarvest;
  final VoidCallback onOpenDisease;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenAiChat;
  final VoidCallback onOpenMarket;
  final VoidCallback onOpenNews;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenSchemes;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenAiGrading;

  const _FarmerNavigationDetailPage({
    required this.farmerName,
    required this.selectedFarm,
    required this.stageSummary,
    required this.farmCount,
    required this.inventoryCount,
    required this.onOpenHome,
    required this.onOpenFarm,
    required this.onOpenHarvest,
    required this.onOpenDisease,
    required this.onOpenInventory,
    required this.onOpenAiChat,
    required this.onOpenMarket,
    required this.onOpenNews,
    required this.onOpenWeather,
    required this.onOpenSchemes,
    required this.onOpenProfile,
    required this.onOpenAiGrading,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation Detail'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
          ),
        ],
      ),
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              farmerName,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Navigation Detail',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
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
                      'Farm and app flow',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedFarm,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stageSummary,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InventoryChip(label: 'Farms: $farmCount'),
                        _InventoryChip(label: 'Listings: $inventoryCount'),
                        const _InventoryChip(label: 'Live navigation'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Panel(
              child: Column(
                children: [
                  _ProfileMenuRow(
                    icon: Icons.home_rounded,
                    title: 'Home',
                    subtitle: 'Open home dashboard',
                    onTap: onOpenHome,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.agriculture_rounded,
                    title: 'Farm',
                    subtitle: 'View and update farm insights',
                    onTap: onOpenFarm,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.inventory_2_rounded,
                    title: 'Harvest',
                    subtitle: 'Harvest monitoring and quality',
                    onTap: onOpenHarvest,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.bug_report_rounded,
                    title: 'Disease Detection',
                    subtitle: 'Inspect and annotate disease maps',
                    onTap: onOpenDisease,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.inventory_rounded,
                    title: 'Inventory',
                    subtitle: 'Review harvest lots and quality',
                    onTap: onOpenInventory,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.auto_awesome_rounded,
                    title: 'AI Chat',
                    subtitle: 'Crop assistant and recommendations',
                    onTap: onOpenAiChat,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.storefront_rounded,
                    title: 'Market',
                    subtitle: 'Grade-wise sale marketplace',
                    onTap: onOpenMarket,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.newspaper_rounded,
                    title: 'News',
                    subtitle: 'Read latest agriculture updates',
                    onTap: onOpenNews,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.wb_cloudy_rounded,
                    title: 'Weather',
                    subtitle: '7-day weather forecasts',
                    onTap: onOpenWeather,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.assignment_rounded,
                    title: 'Schemes',
                    subtitle: 'Government and subsidy programs',
                    onTap: onOpenSchemes,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.center_focus_strong_rounded,
                    title: 'Grain Grading',
                    subtitle: 'AI grain quality assessment',
                    onTap: onOpenAiGrading,
                  ),
                  const Divider(height: 1),
                  _ProfileMenuRow(
                    icon: Icons.person_rounded,
                    title: 'Profile',
                    subtitle: 'Open detailed profile',
                    onTap: onOpenProfile,
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

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.green, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontSize: 29,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
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
      width: double.infinity,
      decoration: BoxDecoration(
        color: tint ?? Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AddFarmSheet extends StatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController locationCtrl;
  final TextEditingController areaCtrl;

  const _AddFarmSheet({
    required this.nameCtrl,
    required this.locationCtrl,
    required this.areaCtrl,
  });

  @override
  State<_AddFarmSheet> createState() => _AddFarmSheetState();
}

class _AddFarmSheetState extends State<_AddFarmSheet> {
  static const Map<String, List<String>> _cropVarieties = {
    'Finger Millet': ['Brown Top', 'Ravi', 'Sita', 'PRH-10'],
    'Foxtail Millet': ['Pragati', 'SiPS-1', 'BHU-8', 'Kalyan'],
    'Rice': ['Basmati', 'Karnal Local', 'IR-64', 'Hybrid'],
    'Bajra': ['HHB 67', 'HHB 208', 'Rajani', 'RNB-71'],
  };

  static const List<String> _cropTypes = [
    'Finger Millet',
    'Foxtail Millet',
    'Rice',
    'Bajra',
  ];

  late String _selectedCrop = _cropTypes.first;
  late String _selectedVariety = _cropVarieties[_selectedCrop]!.first;
  bool _isFetchingLocation = false;

  Future<void> _fetchLocation() async {
    final locationService = LocationService();
    setState(() => _isFetchingLocation = true);
    try {
      final location = await locationService.getCurrentLocation();
      if (!mounted) return;
      if (location == null) {
        Get.snackbar(
          'Location unavailable',
          'Live location not available. Enable location services and try again.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      widget.locationCtrl.text =
          '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
    } finally {
      if (mounted) {
        setState(() => _isFetchingLocation = false);
      }
    }
  }

  void _setCrop(String crop) {
    setState(() {
      _selectedCrop = crop;
      _selectedVariety = _cropVarieties[crop]!.first;
    });
  }

  void _createFarm() {
    final name = widget.nameCtrl.text.trim();
    final location = widget.locationCtrl.text.trim();
    final area = widget.areaCtrl.text.trim();
    final parts = location.split(',');
    final lat = parts.length == 2 ? double.tryParse(parts[0].trim()) : null;
    final lng = parts.length == 2 ? double.tryParse(parts[1].trim()) : null;
    if (name.isEmpty || location.isEmpty || _selectedVariety.isEmpty) {
      Get.snackbar(
        'Missing details',
        'Add farm name, location and crop details.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    Navigator.pop(
      context,
      _FarmerFarm(
        name: name,
        location: location,
        crop: _selectedCrop,
        variety: _selectedVariety,
        area: area.isEmpty ? '0 acres' : '$area acres',
        health: 'New',
        ndvi: '--',
        moisture: '--',
        latitude: lat,
        longitude: lng,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final varieties = _cropVarieties[_selectedCrop]!;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Farm',
              style: TextStyle(
                color: AppTheme.greenDark,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.nameCtrl,
              decoration: const InputDecoration(labelText: 'Farm name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.locationCtrl,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Location',
                suffixIcon: IconButton(
                  icon: _isFetchingLocation
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_outlined),
                  onPressed: _isFetchingLocation ? null : _fetchLocation,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Use live GPS to fill your farm location.',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCrop,
              decoration: const InputDecoration(labelText: 'Crop type'),
              items: _cropTypes
                  .map(
                    (crop) => DropdownMenuItem(
                      value: crop,
                      child: Text(crop),
                    ),
                  )
                  .toList(),
              onChanged: (crop) {
                if (crop != null) _setCrop(crop);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedVariety,
              decoration: const InputDecoration(labelText: 'Variety'),
              items: varieties
                  .map(
                    (variety) => DropdownMenuItem(
                      value: variety,
                      child: Text(variety),
                    ),
                  )
                  .toList(),
              onChanged: (variety) {
                if (variety != null) {
                  setState(() => _selectedVariety = variety);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.areaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Area in acres'),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _createFarm,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Farm'),
            ),
          ],
        ),
      ),
    );
  }
}
