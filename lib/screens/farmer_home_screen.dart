import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:get/get.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:latlong2/latlong.dart';
import '../config/brand_assets.dart';
import '../config/satellite_config.dart';
import '../config/theme.dart';
import '../config/locale_text.dart';
import '../config/ui_strings.dart';
import '../controllers/auth_controller.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../models/satellite/farm_model.dart';
import '../models/satellite/farm_alert_model.dart';
import '../models/satellite/farm_summary_model.dart';
import '../models/satellite/farm_timeline_event_model.dart';
import '../models/satellite/farm_weather_model.dart';
import '../models/satellite/timeline_entry_model.dart';
import '../models/verified_farmer_record.dart';
import '../widgets/app_back_button.dart';
import '../widgets/brand_text.dart';
import '../widgets/farm_hills_background.dart';
import '../widgets/farmer_floating_bottom_nav.dart';
import '../widgets/satellite/satellite_map_view.dart';
import '../widgets/language_selector_button.dart';
import '../services/location_service.dart';
import '../services/grain_grading_service.dart';
import '../services/farm_status_notification_service.dart';
import '../services/local_notification_service.dart';
import '../services/secure_app_storage.dart';
import '../services/backend_bridge_session.dart';
import '../services/policy_disclosure_service.dart';
import '../services/satellite_service.dart';
import '../services/survey_service.dart';
import '../controllers/farm_controller.dart';
import '../utils/harvest_machine_capture.dart';
import '../utils/polygon_geometry.dart';
import 'farmer_farm_setup_chat_screen.dart';
import 'farmer_ai_chat_screen.dart';
import 'farmer_ai_grading_screen.dart';
import 'farmer_status_chat_screen.dart';
import 'farmer_info_screens.dart';
import 'apmc_market_screen.dart';
import 'profile_screen.dart';

class FarmerHomeScreen extends StatefulWidget {
  const FarmerHomeScreen({super.key});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  int _selectedFarm = 0;
  static const _dashboardTabIndex = 0;
  static const _farmTabIndex = 1;
  static const _harvestTabIndex = 2;
  static const _inventoryTabIndex = 3;
  static const _aiChatTabIndex = 4;
  static const _farmPageRefreshMinimumDuration = Duration(seconds: 2);
  static const _farmSummaryFreshFor = Duration(minutes: 2);
  static const _liveWeatherFreshFor = Duration(minutes: 2);
  static const _diseaseRemoteFreshFor = Duration(minutes: 3);
  static const _cropLifecycleFreshFor = Duration(minutes: 1);
  static const _farmTimelineFreshFor = Duration(seconds: 20);
  static const _fallbackProfile = _FarmerProfile(
    name: 'Santosh Pawar',
    farmerId: 'FMR-2026-001',
    location: 'Rajur, Akole',
    phone: '+91 98765 43210',
  );
  static const List<_FarmerFarm> _fallbackFarms = [
    _FarmerFarm(
      name: 'opt_north_field',
      location: 'Rajur, Akole',
      crop: 'Finger Millet',
      variety: 'Brown Top',
      area: '2.4 acres',
      health: 'Healthy',
      ndvi: '0.68',
      moisture: 'Good',
      latitude: 19.6112,
      longitude: 73.7531,
    ),
    _FarmerFarm(
      name: 'opt_south_plot',
      location: 'Akole, Sangamner',
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
  Worker? _remoteFarmLoadingWorker;
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
  final FarmStatusNotificationService _farmerNotificationService =
      FarmStatusNotificationService();
  final Map<int, String> _satelliteFarmIdByFarmIndex = {};
  final Map<int, _FarmSatelliteOverview> _satelliteOverviewByFarmIndex = {};
  final Set<int> _satelliteOverviewLoading = {};
  final Set<int> _satelliteOverviewPendingAfterSummary = {};
  final Map<int, FarmerFarmSummary> _farmSummaryByFarmIndex = {};
  final Map<int, DateTime> _farmSummaryLoadedAt = {};
  final Set<int> _farmSummaryLoading = {};
  final Map<int, FarmWeatherSnapshot> _liveWeatherByFarmIndex = {};
  final Map<int, DateTime> _liveWeatherLoadedAt = {};
  final Set<int> _liveWeatherLoading = {};
  final Map<int, List<FarmTimelineEvent>> _farmTimelineByFarmIndex = {};
  final Map<int, DateTime> _farmTimelineLoadedAt = {};
  final Set<int> _farmTimelineLoading = {};
  final Map<int, List<Map<String, dynamic>>> _diseaseScoutZonesByFarmIndex = {};
  final Map<int, List<Map<String, dynamic>>> _diseaseRiskCellsByFarmIndex = {};
  final Map<int, DateTime> _diseaseRemoteLoadedAt = {};
  final Set<int> _diseaseRemoteLoading = {};
  final Map<int, DiseaseScreenResult> _diseaseScreenByFarmIndex = {};
  final Map<int, List<Map<String, dynamic>>> _currentScoutZonesByFarmIndex = {};
  final Map<int, List<Map<String, dynamic>>> _currentRiskCellsByFarmIndex = {};
  final Map<int, DiseaseScreenResult> _currentDiseaseScreenByFarmIndex = {};
  final Set<String> _riskScreenWarmupAttemptedFarmKeys = {};
  final Map<int, FarmAlertAdvice> _farmAlertAdviceByFarmIndex = {};
  final Map<int, String> _farmAlertErrorByFarmIndex = {};
  final Set<int> _farmAlertLoading = {};
  final Set<int> _farmPageRefreshLoading = {};
  final Set<String> _quietInitialAlertFarmIds = {};
  final Map<int, CropLifecycleAdvice> _cropLifecycleByFarmIndex = {};
  final Map<int, DateTime> _cropLifecycleLoadedAt = {};
  final Set<int> _cropLifecycleLoading = {};
  final SecureAppStorage _secureStorage = SecureAppStorage();
  bool _satelliteFarmCatalogLoaded = false;
  bool _satelliteFarmCatalogLoading = false;
  List<Farm> _satelliteFarmCatalog = [];
  bool _firstFarmGuideStateLoaded = true;
  bool _firstFarmGuideSeenForPhone = false;
  bool _firstFarmTutorialShown = false;
  bool _firstFarmTutorialOpen = false;
  String? _firstFarmTutorialPhone;
  String? _pendingFirstFarmTutorialPhone;
  bool _pendingFirstFarmTutorial = false;
  bool _forceFirstFarmGuideForRoute = false;
  bool _firstFarmLoadOverlayVisible = false;
  bool _firstFarmLoadOverlayError = false;
  String _firstFarmLoadOverlayTitle = '';
  String _firstFarmLoadOverlayMessage = '';
  bool _selectedFarmSnapshotEnsureScheduled = false;
  bool _initialFarmServiceSyncScheduled = false;
  bool _initialFarmServiceSyncing = false;
  bool _initialFarmServiceSyncError = false;
  String? _initialFarmServiceReadyKey;
  String? _initialFarmServiceActiveKey;
  bool _firstFarmTutorialCheckScheduled = false;
  String? _lastSelectedFarmSnapshotEnsureKey;
  bool _surveyFarmRecoveryInProgress = false;
  String? _surveyFarmRecoveryPhone;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyInitialTabArgument();
    _applyInitialFarmerRouteArguments();
    _farms
      ..clear()
      ..addAll(_fallbackFarms);
    _initializeFarmerStateFromSession(shouldSetState: false);
    _verifiedFarmerWorker = ever(
      Get.find<MainAuthController>().verifiedFarmer,
      (_) => _initializeFarmerStateFromSession(),
    );
    if (Get.isRegistered<FarmController>()) {
      final farmCtrl = Get.find<FarmController>();
      _remoteFarmsWorker = ever(
        farmCtrl.farms,
        (_) => _initializeFarmerStateFromSession(),
      );
      _remoteFarmLoadingWorker = ever(farmCtrl.isLoading, (_) {
        if (!farmCtrl.isLoading.value) {
          _initializeFarmerStateFromSession();
          _scheduleFirstFarmTutorialCheck();
        }
      });
      if (!farmCtrl.hasCurrentSessionFarmSnapshot) {
        unawaited(farmCtrl.loadFarms());
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openNotificationPanelFromSystemTray());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _verifiedFarmerWorker.dispose();
    _remoteFarmsWorker?.dispose();
    _remoteFarmLoadingWorker?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_openNotificationPanelFromSystemTray());
    }
  }

  void _applyInitialTabArgument() {
    final args = Get.arguments;
    final tab = args is Map ? '${args['farmerTab'] ?? ''}' : '';
    final index = _pageIndexFromRouteTab(tab);
    if (index != null) {
      _index = index;
    }
  }

  void _applyInitialFarmerRouteArguments() {
    final args = Get.arguments;
    if (args is! Map) return;
    final showFirstFarmGuide = args['showFirstFarmGuide'];
    final shouldForceFirstFarmGuide =
        showFirstFarmGuide is bool && showFirstFarmGuide;
    if (!shouldForceFirstFarmGuide) return;
    final rawPhone = args['newFarmerPhone'];
    final phone = rawPhone is String
        ? rawPhone.replaceAll(RegExp(r'\D'), '')
        : '${rawPhone ?? ''}'.replaceAll(RegExp(r'\D'), '');
    if (phone.length == 10) {
      _pendingFirstFarmTutorialPhone = phone;
      _pendingFirstFarmTutorial = true;
      _firstFarmTutorialPhone = phone;
      _firstFarmGuideSeenForPhone = false;
      _firstFarmGuideStateLoaded = true;
      _firstFarmTutorialShown = false;
      _firstFarmTutorialOpen = false;
      _forceFirstFarmGuideForRoute = true;
    }
  }

  static int? _pageIndexFromRouteTab(String tab) {
    switch (tab) {
      case 'home':
        return _dashboardTabIndex;
      case 'farm':
        return _farmTabIndex;
      case 'aiChat':
        return _aiChatTabIndex;
      case 'harvest':
        return _harvestTabIndex;
      default:
        return null;
    }
  }

  String _farmStateKey(_FarmerFarm farm) {
    final remoteId = farm.remoteFarmId.trim();
    if (remoteId.isNotEmpty) return 'id:$remoteId';
    return [
      _normalizeLookup(farm.name),
      _normalizeLookup(farm.crop),
      _normalizeLookup(farm.variety),
      _normalizeLookup(farm.location),
    ].join('|');
  }

  Map<String, int> _farmStateIndexByKey(List<_FarmerFarm> farms) {
    final indexByKey = <String, int>{};
    for (var i = 0; i < farms.length; i++) {
      indexByKey.putIfAbsent(_farmStateKey(farms[i]), () => i);
    }
    return indexByKey;
  }

  Map<int, T> _reindexFarmStateMap<T>(
    Map<int, T> source,
    Map<String, int> oldIndexByKey,
    List<_FarmerFarm> nextFarms,
  ) {
    if (source.isEmpty || oldIndexByKey.isEmpty || nextFarms.isEmpty) {
      return <int, T>{};
    }
    final next = <int, T>{};
    for (var nextIndex = 0; nextIndex < nextFarms.length; nextIndex++) {
      final oldIndex = oldIndexByKey[_farmStateKey(nextFarms[nextIndex])];
      if (oldIndex != null && source.containsKey(oldIndex)) {
        next[nextIndex] = source[oldIndex] as T;
      }
    }
    return next;
  }

  bool _isFarmCacheFresh(
    Map<int, DateTime> loadedAtByFarm,
    int index,
    Duration freshFor,
  ) {
    final loadedAt = loadedAtByFarm[index];
    if (loadedAt == null) return false;
    return DateTime.now().difference(loadedAt) < freshFor;
  }

  bool _hasRiskCellsForFarm(int index) {
    if (index < 0 || index >= _farms.length) return false;
    return (_diseaseRiskCellsByFarmIndex[index]?.isNotEmpty ?? false) ||
        (_currentRiskCellsByFarmIndex[index]?.isNotEmpty ?? false) ||
        (_displayDiseaseScreenForFarm(index)?.riskCells.isNotEmpty ?? false);
  }

  bool _shouldRunRiskScreenForEmptyFarm(int index) {
    if (index < 0 || index >= _farms.length) return false;
    if (_hasRiskCellsForFarm(index)) return false;
    return !_riskScreenWarmupAttemptedFarmKeys.contains(
      _farmStateKey(_farms[index]),
    );
  }

  bool _claimRiskScreenWarmup(int index, String farmKey) {
    if (index < 0 || index >= _farms.length) return false;
    if (_hasRiskCellsForFarm(index)) return false;
    return _riskScreenWarmupAttemptedFarmKeys.add(farmKey);
  }

  Future<void> _waitForFarmLoadToFinish(Set<int> loading, int index) async {
    var retries = 0;
    while (mounted && loading.contains(index) && retries < 20) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      retries++;
    }
  }

  String _cacheStateToken(
    bool hasValue,
    Map<int, DateTime> loadedAtByFarm,
    int index,
    Duration freshFor,
  ) {
    if (!hasValue) return '0';
    return _isFarmCacheFresh(loadedAtByFarm, index, freshFor) ? '1' : 'stale';
  }

  int _selectedIndexForFarms(
    List<_FarmerFarm> nextFarms, {
    required String? preferredRemoteFarmId,
    required int fallbackIndex,
  }) {
    final remoteId = preferredRemoteFarmId?.trim();
    if (remoteId != null && remoteId.isNotEmpty) {
      final index = nextFarms.indexWhere(
        (farm) => farm.remoteFarmId == remoteId,
      );
      if (index >= 0) return index;
    }
    if (nextFarms.isEmpty) return 0;
    if (fallbackIndex >= 0 && fallbackIndex < nextFarms.length) {
      return fallbackIndex;
    }
    return 0;
  }

  int? _indexForRemoteFarmId(String? farmId) {
    final id = farmId?.trim();
    if (id == null || id.isEmpty) return null;
    final index = _farms.indexWhere((farm) => farm.remoteFarmId == id);
    return index >= 0 ? index : null;
  }

  void _syncSelectedRemoteFarmFromIndex() {
    if (!Get.isRegistered<FarmController>()) return;
    if (_farms.isEmpty || _selectedFarm < 0 || _selectedFarm >= _farms.length) {
      return;
    }
    final farmId = _farms[_selectedFarm].remoteFarmId.trim();
    if (farmId.isEmpty) return;
    final farmCtrl = Get.find<FarmController>();
    Farm? remoteFarm;
    for (final farm in farmCtrl.farms) {
      if (farm.id == farmId) {
        remoteFarm = farm;
        break;
      }
    }
    if (remoteFarm == null) return;
    if (farmCtrl.selectedFarm.value?.id != remoteFarm.id) {
      farmCtrl.selectFarm(remoteFarm);
    }
  }

  void _applyRemoteFarmStatusFields(int index) {
    if (index < 0 || index >= _farms.length) return;
    final farm = _farms[index];
    final remoteStage = farm.currentStatusStage?.trim();
    if (remoteStage != null && remoteStage.isNotEmpty) {
      _farmGrowthStage[index] = remoteStage;
    }
    final remoteStatus = farm.currentStatus?.trim();
    if (remoteStatus != null && remoteStatus.isNotEmpty) {
      _farmStatusAnswer[index] = remoteStatus;
    }
    final updatedAt = farm.currentStatusUpdatedAt;
    if (updatedAt != null) {
      _farmStatusUpdatedAt[index] = updatedAt;
    }
  }

  FarmTimelineEvent? _latestStatusTimelineEvent(
    int index, [
    List<FarmTimelineEvent>? events,
  ]) {
    final source = events ?? _farmTimelineByFarmIndex[index] ?? const [];
    FarmTimelineEvent? latest;
    for (final event in source) {
      if (event.eventType != 'farm_status_update') continue;
      final statusText = _statusTextFromTimelineEvent(event);
      if (statusText.isEmpty) continue;
      if (latest == null || event.createdAt.isAfter(latest.createdAt)) {
        latest = event;
      }
    }
    return latest;
  }

  String _statusTextFromTimelineEvent(FarmTimelineEvent event) {
    for (final key in const ['status_text', 'status', 'current_status']) {
      final text = '${event.payload[key] ?? ''}'.trim();
      if (text.isNotEmpty) return text;
    }
    return event.message.trim();
  }

  String _stageFromTimelineEvent(FarmTimelineEvent event) {
    final direct = event.stage.trim();
    if (direct.isNotEmpty) return direct;
    for (final key in const ['growth_stage', 'stage', 'current_status_stage']) {
      final text = '${event.payload[key] ?? ''}'.trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  void _applyTimelineStatusFields(int index, List<FarmTimelineEvent> events) {
    if (index < 0 || index >= _farms.length) return;
    final latest = _latestStatusTimelineEvent(index, events);
    if (latest == null) return;
    final currentUpdatedAt =
        _farmStatusUpdatedAt[index] ?? _farms[index].currentStatusUpdatedAt;
    if (currentUpdatedAt != null &&
        currentUpdatedAt.isAfter(latest.createdAt)) {
      return;
    }
    final status = _statusTextFromTimelineEvent(latest);
    if (status.isEmpty) return;
    final stage = _stageFromTimelineEvent(latest);
    final nextStage = stage.isEmpty
        ? (_farmGrowthStage[index] ?? _growthStageForFarm(index))
        : stage;
    _farmStatusAnswer[index] = status;
    _farmGrowthStage[index] = nextStage;
    _farmStatusUpdatedAt[index] = latest.createdAt;
    _farms[index] = _farms[index].copyWithStatus(
      currentStatus: status,
      currentStatusStage: nextStage,
      currentStatusUpdatedAt: latest.createdAt,
    );
  }

  bool _isFarmerVisibleTimelineEvent(FarmTimelineEvent event) {
    switch (event.eventType) {
      case 'farm_alert_refresh':
      case 'crop_lifecycle_advice':
        return false;
      default:
        return true;
    }
  }

  void _applyRemoteFarmStatusFieldsForAll() {
    for (var i = 0; i < _farms.length; i++) {
      _applyRemoteFarmStatusFields(i);
    }
  }

  String _firstFarmGuideSeenKey(String phone) =>
      'farmer_first_farm_guide_seen_$phone';

  Future<void> _loadFirstFarmGuideSeenState(String phone) async {
    final value = await _secureStorage.readString(
      _firstFarmGuideSeenKey(phone),
    );
    if (!mounted || _firstFarmTutorialPhone != phone) return;
    setState(() {
      _firstFarmGuideSeenForPhone = value == 'true';
      _firstFarmGuideStateLoaded = true;
    });
    _scheduleFirstFarmTutorialCheck();
  }

  Future<void> _markFirstFarmGuideSeen() async {
    final phone = _firstFarmTutorialPhone;
    if (phone == null || phone.isEmpty) return;
    _forceFirstFarmGuideForRoute = false;
    _firstFarmGuideSeenForPhone = true;
    await _secureStorage.writeString(_firstFarmGuideSeenKey(phone), 'true');
  }

  void _initializeFarmerStateFromSession({bool shouldSetState = true}) {
    final auth = Get.find<MainAuthController>();
    final verified = auth.verifiedFarmer.value;
    final verifiedPhone = verified?.phone.replaceAll(RegExp(r'\D'), '');
    if (_pendingFirstFarmTutorial && _pendingFirstFarmTutorialPhone != null) {
      _firstFarmTutorialPhone = _pendingFirstFarmTutorialPhone;
      _firstFarmTutorialShown = false;
      _firstFarmTutorialOpen = false;
      _firstFarmGuideSeenForPhone = false;
      _firstFarmGuideStateLoaded = true;
      _pendingFirstFarmTutorial = false;
      _pendingFirstFarmTutorialPhone = null;
      _forceFirstFarmGuideForRoute = true;
    } else if (_firstFarmTutorialPhone != verifiedPhone) {
      _firstFarmTutorialPhone = verifiedPhone;
      _firstFarmTutorialShown = false;
      _firstFarmTutorialOpen = false;
      _firstFarmGuideSeenForPhone = false;
      _firstFarmGuideStateLoaded = verifiedPhone == null;
      _forceFirstFarmGuideForRoute = false;
      if (verifiedPhone != null) {
        unawaited(_loadFirstFarmGuideSeenState(verifiedPhone));
      }
    }
    final fallback = verified == null
        ? _fallbackFarms
        : _remoteFarmsFromController(verified);

    final nextProfile = verified == null
        ? _fallbackProfile
        : _profileFromVerified(verified);
    final nextFarms = List<_FarmerFarm>.from(fallback, growable: true);
    if (verified == null && nextFarms.isEmpty) {
      nextFarms.add(_fallbackFarms.first);
    }

    final previousFarms = List<_FarmerFarm>.from(_farms);
    final oldIndexByKey = _farmStateIndexByKey(previousFarms);
    final previousSelectedFarmId =
        previousFarms.isNotEmpty &&
            _selectedFarm >= 0 &&
            _selectedFarm < previousFarms.length
        ? previousFarms[_selectedFarm].remoteFarmId
        : null;
    final controllerSelectedFarmId = Get.isRegistered<FarmController>()
        ? Get.find<FarmController>().selectedFarm.value?.id
        : null;
    final preferredSelectedFarmId =
        controllerSelectedFarmId?.trim().isNotEmpty == true
        ? controllerSelectedFarmId
        : previousSelectedFarmId;
    final nextSelectedFarm = _selectedIndexForFarms(
      nextFarms,
      preferredRemoteFarmId: preferredSelectedFarmId,
      fallbackIndex: _selectedFarm,
    );
    final nextSatelliteFarmIds = <int, String>{
      for (var i = 0; i < nextFarms.length; i++)
        if (nextFarms[i].remoteFarmId.trim().isNotEmpty)
          i: nextFarms[i].remoteFarmId.trim(),
    };
    final nextGrowthStage = _reindexFarmStateMap(
      _farmGrowthStage,
      oldIndexByKey,
      nextFarms,
    );
    final nextStatusAnswer = _reindexFarmStateMap(
      _farmStatusAnswer,
      oldIndexByKey,
      nextFarms,
    );
    final nextSowingDate = _reindexFarmStateMap(
      _farmSowingDate,
      oldIndexByKey,
      nextFarms,
    );
    final nextStatusUpdatedAt = _reindexFarmStateMap(
      _farmStatusUpdatedAt,
      oldIndexByKey,
      nextFarms,
    );
    final nextStatusPhotoBytes = _reindexFarmStateMap(
      _farmStatusPhotoBytes,
      oldIndexByKey,
      nextFarms,
    );
    final nextStatusPhotoName = _reindexFarmStateMap(
      _farmStatusPhotoName,
      oldIndexByKey,
      nextFarms,
    );
    final nextDiagnosisLog = _reindexFarmStateMap(
      _farmDiagnosisLog,
      oldIndexByKey,
      nextFarms,
    );
    final nextDiseaseMarkers = _reindexFarmStateMap(
      _farmDiseaseMarkers,
      oldIndexByKey,
      nextFarms,
    );
    final nextSatelliteOverview = _reindexFarmStateMap(
      _satelliteOverviewByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextFarmSummary = _reindexFarmStateMap(
      _farmSummaryByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextFarmSummaryLoadedAt = _reindexFarmStateMap(
      _farmSummaryLoadedAt,
      oldIndexByKey,
      nextFarms,
    );
    final nextLiveWeather = _reindexFarmStateMap(
      _liveWeatherByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextLiveWeatherLoadedAt = _reindexFarmStateMap(
      _liveWeatherLoadedAt,
      oldIndexByKey,
      nextFarms,
    );
    final nextFarmTimeline = _reindexFarmStateMap(
      _farmTimelineByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextFarmTimelineLoadedAt = _reindexFarmStateMap(
      _farmTimelineLoadedAt,
      oldIndexByKey,
      nextFarms,
    );
    final nextDiseaseScoutZones = _reindexFarmStateMap(
      _diseaseScoutZonesByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextDiseaseRiskCells = _reindexFarmStateMap(
      _diseaseRiskCellsByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextDiseaseRemoteLoadedAt = _reindexFarmStateMap(
      _diseaseRemoteLoadedAt,
      oldIndexByKey,
      nextFarms,
    );
    final nextDiseaseScreen = _reindexFarmStateMap(
      _diseaseScreenByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextCurrentScoutZones = _reindexFarmStateMap(
      _currentScoutZonesByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextCurrentRiskCells = _reindexFarmStateMap(
      _currentRiskCellsByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextCurrentDiseaseScreen = _reindexFarmStateMap(
      _currentDiseaseScreenByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextAlertAdvice = _reindexFarmStateMap(
      _farmAlertAdviceByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextAlertError = _reindexFarmStateMap(
      _farmAlertErrorByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextLifecycleAdvice = _reindexFarmStateMap(
      _cropLifecycleByFarmIndex,
      oldIndexByKey,
      nextFarms,
    );
    final nextLifecycleLoadedAt = _reindexFarmStateMap(
      _cropLifecycleLoadedAt,
      oldIndexByKey,
      nextFarms,
    );

    void applySessionState() {
      _profile = nextProfile;
      _farms
        ..clear()
        ..addAll(nextFarms);
      _selectedFarm = nextSelectedFarm;
      _farmGrowthStage
        ..clear()
        ..addAll(nextGrowthStage);
      _farmStatusAnswer
        ..clear()
        ..addAll(nextStatusAnswer);
      _farmSowingDate
        ..clear()
        ..addAll(nextSowingDate);
      _farmStatusUpdatedAt
        ..clear()
        ..addAll(nextStatusUpdatedAt);
      _farmStatusPhotoBytes
        ..clear()
        ..addAll(nextStatusPhotoBytes);
      _farmStatusPhotoName
        ..clear()
        ..addAll(nextStatusPhotoName);
      _farmDiagnosisLog
        ..clear()
        ..addAll(nextDiagnosisLog);
      _farmDiseaseMarkers
        ..clear()
        ..addAll(nextDiseaseMarkers);
      _satelliteFarmIdByFarmIndex
        ..clear()
        ..addAll(nextSatelliteFarmIds);
      _satelliteOverviewByFarmIndex
        ..clear()
        ..addAll(nextSatelliteOverview);
      _satelliteOverviewLoading.clear();
      _satelliteOverviewPendingAfterSummary.clear();
      _farmSummaryByFarmIndex
        ..clear()
        ..addAll(nextFarmSummary);
      _farmSummaryLoadedAt
        ..clear()
        ..addAll(nextFarmSummaryLoadedAt);
      _farmSummaryLoading.clear();
      _liveWeatherByFarmIndex
        ..clear()
        ..addAll(nextLiveWeather);
      _liveWeatherLoadedAt
        ..clear()
        ..addAll(nextLiveWeatherLoadedAt);
      _liveWeatherLoading.clear();
      _farmTimelineByFarmIndex
        ..clear()
        ..addAll(nextFarmTimeline);
      _farmTimelineLoadedAt
        ..clear()
        ..addAll(nextFarmTimelineLoadedAt);
      _farmTimelineLoading.clear();
      _diseaseScoutZonesByFarmIndex
        ..clear()
        ..addAll(nextDiseaseScoutZones);
      _diseaseRiskCellsByFarmIndex
        ..clear()
        ..addAll(nextDiseaseRiskCells);
      _diseaseRemoteLoadedAt
        ..clear()
        ..addAll(nextDiseaseRemoteLoadedAt);
      _diseaseRemoteLoading.clear();
      _diseaseScreenByFarmIndex
        ..clear()
        ..addAll(nextDiseaseScreen);
      _currentScoutZonesByFarmIndex
        ..clear()
        ..addAll(nextCurrentScoutZones);
      _currentRiskCellsByFarmIndex
        ..clear()
        ..addAll(nextCurrentRiskCells);
      _currentDiseaseScreenByFarmIndex
        ..clear()
        ..addAll(nextCurrentDiseaseScreen);
      _farmAlertAdviceByFarmIndex
        ..clear()
        ..addAll(nextAlertAdvice);
      _farmAlertErrorByFarmIndex
        ..clear()
        ..addAll(nextAlertError);
      _farmAlertLoading.clear();
      _farmPageRefreshLoading.clear();
      _cropLifecycleByFarmIndex
        ..clear()
        ..addAll(nextLifecycleAdvice);
      _cropLifecycleLoadedAt
        ..clear()
        ..addAll(nextLifecycleLoadedAt);
      _cropLifecycleLoading.clear();
      _lastSelectedFarmSnapshotEnsureKey = null;
      if (verified == null || nextFarms.isEmpty) {
        _initialFarmServiceReadyKey = null;
        _initialFarmServiceActiveKey = null;
        _initialFarmServiceSyncing = false;
        _initialFarmServiceSyncError = false;
      }
      if (verified != null && Get.isRegistered<FarmController>()) {
        _satelliteFarmCatalog = List<Farm>.from(
          Get.find<FarmController>().farms,
        );
        _satelliteFarmCatalogLoaded = _satelliteFarmCatalog.isNotEmpty;
      } else {
        _satelliteFarmCatalogLoaded = false;
        _satelliteFarmCatalog.clear();
      }
      _initializeAllFarmState();
      _applyRemoteFarmStatusFieldsForAll();
    }

    if (shouldSetState && mounted) {
      setState(applySessionState);
    } else {
      applySessionState();
    }
    _syncSelectedRemoteFarmFromIndex();

    if (verified != null && _farms.isNotEmpty) {
      _forceFirstFarmGuideForRoute = false;
      _firstFarmTutorialShown = true;
      _firstFarmTutorialOpen = false;
      if (!_firstFarmGuideSeenForPhone) {
        unawaited(_markFirstFarmGuideSeen());
      }
    }
  }

  bool get _requiresFirstFarmSetup {
    final auth = Get.find<MainAuthController>();
    if (auth.verifiedFarmer.value == null) {
      return false;
    }

    final syncCode = auth.farmerLoginSyncStatusCode.value;
    final syncedCount = auth.farmerLoginSyncedFarmCount.value;

    if (syncCode == 'farms_synced') {
      return false;
    }
    if (auth.isLoading.value || syncCode != 'farms_not_found') {
      return false;
    }
    if (syncedCount != 0) {
      return false;
    }

    if (!Get.isRegistered<FarmController>()) return false;
    final farmCtrl = Get.find<FarmController>();

    if (farmCtrl.farms.isNotEmpty) {
      return false;
    }

    return !farmCtrl.isLoading.value &&
        !farmCtrl.hasError.value &&
        farmCtrl.farms.isEmpty;
  }

  bool get _needsFirstFarmTutorial {
    if (!_firstFarmGuideStateLoaded || _firstFarmTutorialShown) {
      return false;
    }
    if (_firstFarmGuideSeenForPhone && !_forceFirstFarmGuideForRoute) {
      return false;
    }
    return _requiresFirstFarmSetup;
  }

  bool get _isFarmSyncingForVerifiedFarmer {
    if (Get.find<MainAuthController>().verifiedFarmer.value == null) {
      return false;
    }
    if (!Get.isRegistered<FarmController>()) return false;
    final farmCtrl = Get.find<FarmController>();
    return farmCtrl.isLoading.value && farmCtrl.farms.isEmpty;
  }

  bool _guardFirstFarmSetup() {
    if (_isFarmSyncingForVerifiedFarmer) {
      Get.snackbar(
        UiStrings.t('syncing_farms'),
        UiStrings.t('checking_farms_for_mobile'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return true;
    }
    if (_requiresFirstFarmSetup) {
      if (!_firstFarmTutorialOpen) {
        unawaited(_recoverSurveyFarmThenContinueFirstFarmGate());
      }
      return true;
    }
    return false;
  }

  Future<void> _recoverSurveyFarmThenContinueFirstFarmGate() async {
    final recovered = await _recoverLatestSurveyPolygonAsFarm();
    if (!mounted || recovered || !_requiresFirstFarmSetup) return;
    if (_firstFarmTutorialOpen) return;
    if (_needsFirstFarmTutorial) {
      unawaited(_maybeShowFirstFarmTutorial());
    } else {
      unawaited(_openAddFarmSheet(silentAutoSync: true));
    }
  }

  Future<bool> _recoverLatestSurveyPolygonAsFarm() async {
    if (_surveyFarmRecoveryInProgress) return false;
    final auth = Get.find<MainAuthController>();
    final verified = auth.verifiedFarmer.value;
    final phone = verified?.phone.replaceAll(RegExp(r'\D'), '');
    if (verified == null || phone == null || phone.isEmpty) return false;

    _surveyFarmRecoveryInProgress = true;
    _surveyFarmRecoveryPhone = phone;
    try {
      final survey = await SurveyService().fetchLatestWithPolygonForPhone(
        phone,
      );
      if (!mounted || survey == null || _surveyFarmRecoveryPhone != phone) {
        return false;
      }
      final points = _surveyPolygonPoints(survey['farm_polygon']);
      if (points.length < 3) return false;

      final farmCtrl = Get.isRegistered<FarmController>()
          ? Get.find<FarmController>()
          : Get.put(FarmController());
      final farmerName = _surveyText(survey['farmer_name']).isNotEmpty
          ? _surveyText(survey['farmer_name'])
          : verified.farmerName;
      final village = _surveyText(survey['village']);
      final crop = _surveyText(survey['main_crop_other']).isNotEmpty
          ? _surveyText(survey['main_crop_other'])
          : _surveyText(survey['main_crop']);
      final farmName = [
        if (farmerName.isNotEmpty) farmerName,
        if (crop.isNotEmpty) crop,
        if (village.isNotEmpty) village,
      ].join(' - ');
      final savedFarm = await farmCtrl.saveFarmRecord(
        name: farmName.isEmpty ? 'Recorded farm' : farmName,
        points: points,
        showSnackbars: false,
        waitForRemoteConfirmation: false,
        metadata: {
          if (_surveyText(survey['id']).isNotEmpty)
            'survey_id': _surveyText(survey['id']),
          if (crop.isNotEmpty) 'crop': crop,
          if (village.isNotEmpty) 'village': village,
        },
      );
      if (!mounted || savedFarm == null) {
        final message = farmCtrl.lastSaveErrorMessage.value.trim();
        if (message.isNotEmpty) {
          Get.snackbar(
            UiStrings.t('could_not_save_farm'),
            message,
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        return false;
      }

      await farmCtrl.loadFarms(
        forceRefresh: true,
        preferredFarmId: savedFarm.id,
      );
      auth.farmerLoginSyncedFarmCount.value = farmCtrl.farms.length;
      auth.farmerLoginLastSyncAt.value = DateTime.now().toUtc();
      auth.farmerLoginSyncStatusCode.value = farmCtrl.farms.isEmpty
          ? 'farms_not_found'
          : 'farms_synced';
      _initializeFarmerStateFromSession();
      return farmCtrl.farms.isNotEmpty;
    } catch (error) {
      Get.log('Survey polygon farm recovery failed: $error');
      return false;
    } finally {
      _surveyFarmRecoveryInProgress = false;
    }
  }

  List<LatLng> _surveyPolygonPoints(dynamic polygon) {
    if (polygon is! Map) return const [];
    final coordinates = polygon['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) return const [];
    final ring = coordinates.first;
    if (ring is! List) return const [];
    final points = <LatLng>[];
    for (final point in ring) {
      if (point is! List || point.length < 2) continue;
      final lng = _surveyToDouble(point[0]);
      final lat = _surveyToDouble(point[1]);
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  String _surveyText(dynamic value) => value?.toString().trim() ?? '';

  double? _surveyToDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  void _openInventoryTab() {
    if (_guardFirstFarmSetup()) return;
    setState(() => _index = _inventoryTabIndex);
  }

  void _showFirstFarmLoadOverlay({
    required String title,
    required String message,
    bool isError = false,
  }) {
    if (!mounted) return;
    setState(() {
      _firstFarmLoadOverlayVisible = true;
      _firstFarmLoadOverlayError = isError;
      _firstFarmLoadOverlayTitle = title;
      _firstFarmLoadOverlayMessage = message;
    });
  }

  void _hideFirstFarmLoadOverlay() {
    if (!mounted || !_firstFarmLoadOverlayVisible) return;
    setState(() {
      _firstFarmLoadOverlayVisible = false;
      _firstFarmLoadOverlayError = false;
      _firstFarmLoadOverlayTitle = '';
      _firstFarmLoadOverlayMessage = '';
    });
  }

  Future<void> _showFirstFarmLoadFailure([String? message]) async {
    _showFirstFarmLoadOverlay(
      title: UiStrings.t('farm_sync_required'),
      message: message ?? UiStrings.t('first_farm_remote_required'),
      isError: true,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    _hideFirstFarmLoadOverlay();
  }

  Future<void> _openAddFarmFromFirstFarmGate({
    bool silentAutoSync = true,
  }) async {
    await _openAddFarmSheet(silentAutoSync: silentAutoSync);
    if (!mounted) return;
    _scheduleFirstFarmTutorialCheck();
  }

  Future<void> _showFirstFarmTutorial() async {
    if (_firstFarmTutorialOpen || !mounted || !_requiresFirstFarmSetup) {
      return;
    }
    _firstFarmTutorialShown = true;
    _firstFarmTutorialOpen = true;
    final startSetup = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFFFFF), Color(0xFFF2FAEC)],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.add_location_alt_rounded,
                      color: AppTheme.greenDark,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    UiStrings.t('add_first_farm'),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    UiStrings.t('first_farm_dialog_body'),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FirstFarmGuideStep(
                    icon: Icons.map_rounded,
                    title: UiStrings.t('mark_boundary'),
                    subtitle: UiStrings.t('draw_farm_area'),
                  ),
                  const SizedBox(height: 10),
                  _FirstFarmGuideStep(
                    icon: Icons.grass_rounded,
                    title: UiStrings.t('add_crop_details'),
                    subtitle: UiStrings.t('confirm_crop_details'),
                  ),
                  const SizedBox(height: 10),
                  _FirstFarmGuideStep(
                    icon: Icons.cloud_sync_rounded,
                    title: UiStrings.t('sync_farmer_data'),
                    subtitle: UiStrings.t('save_phone_linked_profile'),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(UiStrings.t('start_farm_setup')),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _firstFarmTutorialOpen = false;
    if (!mounted) return;
    if (startSetup == true) {
      await _openAddFarmFromFirstFarmGate();
    }
  }

  Future<void> _maybeShowFirstFarmTutorial() async {
    if (!_needsFirstFarmTutorial) {
      return;
    }
    if (_forceFirstFarmGuideForRoute) {
      _forceFirstFarmGuideForRoute = false;
      _firstFarmTutorialShown = true;
      _firstFarmTutorialOpen = true;
      await _openAddFarmFromFirstFarmGate();
      if (mounted) {
        _firstFarmTutorialOpen = false;
      }
      return;
    }
    await _showFirstFarmTutorial();
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
      return const [];
    }

    return remoteFarms.map(_farmerFarmFromRemoteRecord).toList(growable: false);
  }

  _FarmerFarm _farmerFarmFromRemoteRecord(Farm farm) {
    final center = _centerFromGeometry(farm.geometry);
    return _FarmerFarm(
      remoteFarmId: farm.id,
      name: farm.name,
      location: _formatLocationFromPoints(center),
      crop: (farm.crop == null || farm.crop!.trim().isEmpty)
          ? 'Millet'
          : farm.crop!,
      variety: (farm.variety == null || farm.variety!.trim().isEmpty)
          ? 'General'
          : farm.variety!,
      area: farm.areaAcres == null
          ? _formatLocalizedAcres(
              (farm.areaHectares ?? 0) * 2.47105,
              fractionDigits: 2,
            )
          : _formatLocalizedAcres(
              farm.areaAcres!,
              fractionDigits: farm.areaAcres! >= 10 ? 1 : 2,
            ),
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
      currentStatus: farm.currentStatus,
      currentStatusStage: farm.currentStatusStage,
      currentStatusUpdatedAt: DateTime.tryParse(
        farm.currentStatusUpdatedAt ?? '',
      ),
      sowingDate: DateTime.tryParse(farm.sowingDate ?? ''),
      createdAt: DateTime.tryParse(farm.createdAt),
      latitude: center?.latitude,
      longitude: center?.longitude,
      polygon: _ringFromGeometry(farm.geometry),
    );
  }

  _FarmerFarm _farmerFarmWithSetupMetadata(
    _FarmerFarm farm,
    FarmSetupChatResult setup,
  ) {
    return _FarmerFarm(
      remoteFarmId: farm.remoteFarmId,
      name: farm.name,
      location: farm.location,
      crop: setup.crop.trim().isEmpty ? farm.crop : setup.crop,
      variety: setup.variety.trim().isEmpty ? farm.variety : setup.variety,
      area: farm.area,
      health: farm.health,
      ndvi: farm.ndvi,
      moisture: farm.moisture,
      product: farm.product,
      previousCrop: setup.previousCrop.trim().isEmpty
          ? farm.previousCrop
          : setup.previousCrop,
      season: setup.season.trim().isEmpty ? farm.season : setup.season,
      irrigation: setup.irrigation.trim().isEmpty
          ? farm.irrigation
          : setup.irrigation,
      soilType: setup.soilType.trim().isEmpty ? farm.soilType : setup.soilType,
      ownershipType: setup.ownershipType.trim().isEmpty
          ? farm.ownershipType
          : setup.ownershipType,
      seedSource: setup.seedSource.trim().isEmpty
          ? farm.seedSource
          : setup.seedSource,
      harvestIntent: setup.harvestIntent.trim().isEmpty
          ? farm.harvestIntent
          : setup.harvestIntent,
      currentStatus: farm.currentStatus,
      currentStatusStage: farm.currentStatusStage,
      currentStatusUpdatedAt: farm.currentStatusUpdatedAt,
      sowingDate: setup.sowingDate,
      createdAt: farm.createdAt,
      latitude: farm.latitude,
      longitude: farm.longitude,
      polygon: farm.polygon,
    );
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

  bool _remoteFarmHasMarkedBoundary(Farm farm) {
    return _ringFromGeometry(farm.geometry).length >= 3;
  }

  bool _farmerFarmHasMarkedBoundary(_FarmerFarm farm) {
    final ring = farm.polygon;
    if (ring == null) return false;
    return ring.where((point) => point.length >= 2).length >= 3;
  }

  _FarmerProfile _profileFromVerified(VerifiedFarmerRecord record) {
    return _FarmerProfile(
      name: record.farmerName,
      farmerId: record.farmerId,
      location: record.defaultLocation,
      phone: '+91 ${record.phone}',
    );
  }

  static const _mobileDestinationFromPage = {
    _dashboardTabIndex: FarmerBottomNavItem.home,
    _farmTabIndex: FarmerBottomNavItem.farm,
    _aiChatTabIndex: FarmerBottomNavItem.aiChat,
    _harvestTabIndex: FarmerBottomNavItem.harvest,
  };

  static int _pageIndexForMobile(FarmerBottomNavItem item) {
    switch (item) {
      case FarmerBottomNavItem.home:
        return _dashboardTabIndex;
      case FarmerBottomNavItem.farm:
        return _farmTabIndex;
      case FarmerBottomNavItem.aiChat:
        return _aiChatTabIndex;
      case FarmerBottomNavItem.harvest:
      case FarmerBottomNavItem.apmc:
        return _harvestTabIndex;
    }
  }

  static FarmerBottomNavItem _mobileIndexForPage(int pageIndex) {
    if (pageIndex == _inventoryTabIndex) {
      return _mobileDestinationFromPage[_harvestTabIndex]!;
    }
    return _mobileDestinationFromPage[pageIndex] ??
        _mobileDestinationFromPage[_farmTabIndex]!;
  }

  FarmerBottomNavItem _mobileNavIndexFromPage() {
    return _mobileIndexForPage(_index);
  }

  void _handleMobileNavTap(FarmerBottomNavItem item) {
    if (_guardFirstFarmSetup()) return;
    if (item == FarmerBottomNavItem.apmc) {
      _openMarketPage();
      return;
    }
    final pageIndex = _pageIndexForMobile(item);
    if (_index == pageIndex) return;
    setState(() => _index = pageIndex);
  }

  Widget _buildMobileBottomNavigationBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: FarmerFloatingBottomNav(
        selectedItem: _mobileNavIndexFromPage(),
        onSelected: _handleMobileNavTap,
      ),
    );
  }

  Widget _buildLanguageSelector({bool compact = false}) {
    if (!Get.isRegistered<LanguageController>()) {
      return const SizedBox.shrink();
    }
    final languageCtrl = Get.find<LanguageController>();
    return Obx(
      () => LanguageSelectorButton(
        code: languageCtrl.language.value,
        compact: compact,
        onChanged: languageCtrl.setLanguage,
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

  _FarmerFarm get _firstFarmPlaceholder => _FarmerFarm(
    name: UiStrings.t('add_first_farm'),
    location: _profile.location,
    crop: UiStrings.t('millet'),
    variety: UiStrings.t('select_variety'),
    area: UiStrings.t('zero_acres'),
    health: UiStrings.t('setup_required'),
    ndvi: '--',
    moisture: '--',
    product: '',
  );

  int get _safeSelectedFarmIndex {
    if (_farms.isEmpty) return 0;
    return _selectedFarm.clamp(0, _farms.length - 1).toInt();
  }

  _FarmerFarm get _farm =>
      _farms.isEmpty ? _firstFarmPlaceholder : _farms[_safeSelectedFarmIndex];

  _FarmStatusSnapshot _statusSnapshotForFarm(int index) {
    final farm = index >= 0 && index < _farms.length ? _farms[index] : null;
    final farmStatus = farm?.currentStatus?.trim();
    final localStatus = _farmStatusAnswer[index]?.trim();
    final farmUpdatedAt = farm?.currentStatusUpdatedAt;
    final localUpdatedAt = _farmStatusUpdatedAt[index];
    final useLocal =
        localUpdatedAt != null &&
        (farmUpdatedAt == null || localUpdatedAt.isAfter(farmUpdatedAt));
    final status = useLocal && localStatus != null && localStatus.isNotEmpty
        ? localStatus
        : farmStatus != null && farmStatus.isNotEmpty
        ? farmStatus
        : (localStatus != null && localStatus.isNotEmpty
              ? localStatus
              : UiStrings.t('not_updated'));
    final farmStage = farm?.currentStatusStage?.trim();
    final localStage = _farmGrowthStage[index]?.trim();
    final stage = useLocal && localStage != null && localStage.isNotEmpty
        ? localStage
        : farmStage != null && farmStage.isNotEmpty
        ? farmStage
        : (localStage != null && localStage.isNotEmpty
              ? localStage
              : _growthStageForFarm(index));
    final updatedAt = useLocal
        ? localUpdatedAt
        : farmUpdatedAt ?? localUpdatedAt;
    return _FarmStatusSnapshot(
      status: status,
      stage: stage,
      updatedAt: updatedAt,
    );
  }

  String get _currentFarmAvatar =>
      BrandAssets.farmerAvatars[_safeSelectedFarmIndex %
          BrandAssets.farmerAvatars.length];

  String _satelliteRequestToken() {
    if (!Get.isRegistered<AuthController>()) return '';
    final token = Get.find<AuthController>().accessToken.value;
    return token.isEmpty ? '' : token;
  }

  String? _verifiedFarmerPhone() {
    if (!Get.isRegistered<MainAuthController>()) return null;
    final phone = Get.find<MainAuthController>().verifiedFarmer.value?.phone
        .replaceAll(RegExp(r'\D'), '');
    return phone == null || phone.isEmpty ? null : phone;
  }

  String? _verifiedFarmerId() {
    if (!Get.isRegistered<MainAuthController>()) return null;
    final farmerId = Get.find<MainAuthController>()
        .verifiedFarmer
        .value
        ?.farmerId
        .trim();
    return farmerId == null || farmerId.isEmpty ? null : farmerId;
  }

  String _notificationFarmerId() {
    return (_verifiedFarmerId() ?? _profile.farmerId).trim();
  }

  String _notificationFarmerPhone() {
    return (_verifiedFarmerPhone() ??
            _profile.phone.replaceAll(RegExp(r'\D'), ''))
        .trim();
  }

  String _normalizeLookup(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<List<Farm>> _getSatelliteFarmCatalog() async {
    final auth = Get.find<MainAuthController>();
    if (auth.verifiedFarmer.value != null &&
        Get.isRegistered<FarmController>()) {
      final farmCtrl = Get.find<FarmController>();
      if (farmCtrl.farms.isEmpty && !farmCtrl.isLoading.value) {
        await farmCtrl.loadFarms();
      }
      if (farmCtrl.isLoading.value) {
        var retries = 0;
        while (farmCtrl.isLoading.value && retries < 24) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          retries++;
        }
      }
      _satelliteFarmCatalog = List<Farm>.from(farmCtrl.farms);
      _satelliteFarmCatalogLoaded = true;
      return _satelliteFarmCatalog;
    }

    if (_satelliteFarmCatalogLoaded && _satelliteFarmCatalog.isNotEmpty) {
      return _satelliteFarmCatalog;
    }
    if (_satelliteFarmCatalogLoading) {
      return _satelliteFarmCatalog;
    }

    _satelliteFarmCatalogLoading = true;
    try {
      final token = _satelliteRequestToken();
      if (token.isEmpty) return _satelliteFarmCatalog;
      final ownerUserId = Get.isRegistered<AuthController>()
          ? Get.find<AuthController>().currentUser.value?.id
          : null;
      if (ownerUserId == null || ownerUserId.trim().isEmpty) {
        return _satelliteFarmCatalog;
      }
      final farms = await _satelliteService.getFarms(
        token,
        ownerUserId: ownerUserId,
      );
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
    if (farm.remoteFarmId.trim().isNotEmpty) {
      _satelliteFarmIdByFarmIndex[index] = farm.remoteFarmId.trim();
      return farm.remoteFarmId.trim();
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

    final resolved = matched?.id.isNotEmpty == true ? matched!.id : '';
    _satelliteFarmIdByFarmIndex[index] = resolved;
    return resolved;
  }

  bool _isSameFarmAtIndex(int index, String farmKey) {
    return index >= 0 &&
        index < _farms.length &&
        _farmStateKey(_farms[index]) == farmKey;
  }

  void _selectFarmIndex(int index, {bool forceRefresh = true}) {
    if (index < 0 || index >= _farms.length) return;
    final farmId = _farms[index].remoteFarmId.trim();
    if (mounted && _selectedFarm != index) {
      setState(() => _selectedFarm = index);
    } else {
      _selectedFarm = index;
    }
    _syncSelectedRemoteFarmFromIndex();
    if (forceRefresh && farmId.isNotEmpty) {
      unawaited(
        _refreshFarmsFromCloudAndSelect(
          farmId: farmId,
          fallbackIndex: index,
          refreshSnapshot: false,
          timeout: const Duration(seconds: 1),
          retryHttpErrors: false,
        ),
      );
    }
    _ensureSelectedFarmSnapshotForFarm(index, forceRefresh: forceRefresh);
  }

  Future<int> _refreshFarmsFromCloudAndSelect({
    required String farmId,
    required int fallbackIndex,
    bool refreshSnapshot = true,
    Duration timeout = const Duration(seconds: 4),
    bool retryHttpErrors = true,
  }) async {
    if (Get.isRegistered<FarmController>()) {
      final farmCtrl = Get.find<FarmController>();
      if (farmId.trim().isEmpty) {
        await farmCtrl.loadFarms(forceRefresh: true);
      } else {
        await farmCtrl.syncSavedFarmFromRemote(
          farmId,
          timeout: timeout,
          retryHttpErrors: retryHttpErrors,
        );
      }
    }
    if (mounted) {
      _initializeFarmerStateFromSession();
    }
    final refreshedIndex = _indexForRemoteFarmId(farmId) ?? fallbackIndex;
    final safeIndex = _farms.isEmpty
        ? 0
        : refreshedIndex.clamp(0, _farms.length - 1).toInt();
    if (_farms.isNotEmpty && refreshSnapshot) {
      _selectFarmIndex(safeIndex, forceRefresh: true);
    } else if (_farms.isNotEmpty) {
      if (mounted && _selectedFarm != safeIndex) {
        setState(() => _selectedFarm = safeIndex);
      } else {
        _selectedFarm = safeIndex;
      }
      _syncSelectedRemoteFarmFromIndex();
    }
    return safeIndex;
  }

  void _ensureSelectedFarmSnapshotForFarm(
    int index, {
    bool forceRefresh = false,
  }) {
    if (index < 0 || index >= _farms.length) return;
    _initializeFarmState(index);
    _applyRemoteFarmStatusFields(index);
    final remoteFarmId = _farms[index].remoteFarmId.trim();
    final showAlertErrors = !_quietInitialAlertFarmIds.contains(remoteFarmId);
    if (forceRefresh) {
      unawaited(_loadFarmSummaryForFarm(index, forceRefresh: true));
      unawaited(_loadLiveWeatherForFarm(index, forceRefresh: true));
      unawaited(
        _ensureDiseaseRemoteForFarm(
          index,
          forceRefresh: true,
          runScreenIfEmpty: true,
          showAlertErrors: showAlertErrors,
        ),
      );
      unawaited(_loadCropLifecycleAdviceForFarm(index, forceRefresh: true));
      unawaited(_loadFarmTimelineForFarm(index, forceRefresh: true));
      return;
    }
    _ensureSatelliteOverviewForFarm(index);
    unawaited(_loadLiveWeatherForFarm(index));
    final shouldRunInitialRiskScreen = _shouldRunRiskScreenForEmptyFarm(index);
    unawaited(
      _ensureDiseaseRemoteForFarm(
        index,
        runScreenIfEmpty: shouldRunInitialRiskScreen,
        showAlertErrors: showAlertErrors,
      ),
    );
    if (_cropLifecycleByFarmIndex[index] == null) {
      unawaited(_loadCropLifecycleAdviceForFarm(index));
    }
    if (_farmTimelineByFarmIndex[index] == null) {
      unawaited(_loadFarmTimelineForFarm(index));
    }
  }

  Future<void> _refreshSelectedFarmSnapshotForFarm(
    int index, {
    bool runRiskScreenIfEmpty = false,
  }) async {
    if (index < 0 || index >= _farms.length) return;
    _initializeFarmState(index);
    _applyRemoteFarmStatusFields(index);
    await Future.wait<void>([
      _loadFarmSummaryForFarm(index, cascade: false, forceRefresh: true),
      _loadLiveWeatherForFarm(index, forceRefresh: true),
      _ensureDiseaseRemoteForFarm(
        index,
        forceRefresh: true,
        runScreenIfEmpty: runRiskScreenIfEmpty,
      ),
      _loadCropLifecycleAdviceForFarm(index, forceRefresh: true),
      _loadFarmTimelineForFarm(index, forceRefresh: true),
    ]);
  }

  void _clearMonitoringStateForFarmIndex(int index) {
    if (index >= 0 && index < _farms.length) {
      _riskScreenWarmupAttemptedFarmKeys.remove(_farmStateKey(_farms[index]));
    }
    _satelliteOverviewByFarmIndex.remove(index);
    _satelliteOverviewLoading.remove(index);
    _satelliteOverviewPendingAfterSummary.remove(index);
    _farmSummaryByFarmIndex.remove(index);
    _farmSummaryLoadedAt.remove(index);
    _farmSummaryLoading.remove(index);
    _liveWeatherByFarmIndex.remove(index);
    _liveWeatherLoadedAt.remove(index);
    _liveWeatherLoading.remove(index);
    _farmTimelineByFarmIndex.remove(index);
    _farmTimelineLoadedAt.remove(index);
    _farmTimelineLoading.remove(index);
    _diseaseScoutZonesByFarmIndex.remove(index);
    _diseaseRiskCellsByFarmIndex.remove(index);
    _diseaseRemoteLoadedAt.remove(index);
    _diseaseRemoteLoading.remove(index);
    _diseaseScreenByFarmIndex.remove(index);
    _currentScoutZonesByFarmIndex.remove(index);
    _currentRiskCellsByFarmIndex.remove(index);
    _currentDiseaseScreenByFarmIndex.remove(index);
    _farmAlertAdviceByFarmIndex.remove(index);
    _farmAlertErrorByFarmIndex.remove(index);
    _farmAlertLoading.remove(index);
    _farmPageRefreshLoading.remove(index);
    _cropLifecycleByFarmIndex.remove(index);
    _cropLifecycleLoadedAt.remove(index);
    _cropLifecycleLoading.remove(index);
    _lastSelectedFarmSnapshotEnsureKey = null;
  }

  Future<void> _warmNewFarmMonitoring({
    required int index,
    required String farmId,
    bool clearFirst = true,
    bool showAlertErrors = true,
  }) async {
    final normalizedFarmId = farmId.trim();
    if (normalizedFarmId.isEmpty || index < 0 || index >= _farms.length) {
      return;
    }

    final farmKey = _farmStateKey(_farms[index]);
    if (clearFirst) {
      if (mounted) {
        setState(() {
          _clearMonitoringStateForFarmIndex(index);
          _satelliteFarmIdByFarmIndex[index] = normalizedFarmId;
          _initializeFarmState(index);
          _applyRemoteFarmStatusFields(index);
        });
      } else {
        _clearMonitoringStateForFarmIndex(index);
        _satelliteFarmIdByFarmIndex[index] = normalizedFarmId;
        _initializeFarmState(index);
        _applyRemoteFarmStatusFields(index);
      }
    } else {
      _satelliteFarmIdByFarmIndex[index] = normalizedFarmId;
      _initializeFarmState(index);
      _applyRemoteFarmStatusFields(index);
    }

    _syncSelectedRemoteFarmFromIndex();
    if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
    try {
      await Future.wait<void>([
        _loadFarmSummaryForFarm(index, cascade: false, forceRefresh: true),
        _loadLiveWeatherForFarm(index, forceRefresh: true),
        _ensureDiseaseRemoteForFarm(
          index,
          forceRefresh: true,
          runScreenIfEmpty: true,
          showAlertErrors: showAlertErrors,
        ),
        _loadCropLifecycleAdviceForFarm(index, forceRefresh: true),
        _loadFarmTimelineForFarm(index, forceRefresh: true),
      ]);
    } catch (_) {
      // Each monitoring panel keeps its own empty/error state; adding a farm
      // should not reopen the setup flow because one service is temporarily down.
    }

    if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
    unawaited(
      _saveFarmDataSnapshotForFarm(index, source: 'new_farm_monitoring_warmup'),
    );
  }

  String _selectedFarmSnapshotEnsureKey(int index) {
    if (index < 0 || index >= _farms.length) return 'none';
    final farm = _farms[index];
    final hasDisease =
        _diseaseScoutZonesByFarmIndex.containsKey(index) &&
        _diseaseRiskCellsByFarmIndex.containsKey(index);
    return [
      _farmStateKey(farm),
      's${_cacheStateToken(_satelliteOverviewByFarmIndex.containsKey(index), _farmSummaryLoadedAt, index, _farmSummaryFreshFor)}',
      'w${_cacheStateToken(_liveWeatherByFarmIndex.containsKey(index), _liveWeatherLoadedAt, index, _liveWeatherFreshFor)}',
      'd${_cacheStateToken(hasDisease, _diseaseRemoteLoadedAt, index, _diseaseRemoteFreshFor)}',
      'c${_cacheStateToken(_cropLifecycleByFarmIndex.containsKey(index), _cropLifecycleLoadedAt, index, _cropLifecycleFreshFor)}',
      't${_cacheStateToken(_farmTimelineByFarmIndex.containsKey(index), _farmTimelineLoadedAt, index, _farmTimelineFreshFor)}',
    ].join('|');
  }

  void _scheduleSelectedFarmSnapshotEnsure(int index) {
    if (index < 0 || index >= _farms.length) return;
    final key = _selectedFarmSnapshotEnsureKey(index);
    if (_selectedFarmSnapshotEnsureScheduled ||
        _lastSelectedFarmSnapshotEnsureKey == key) {
      return;
    }
    _selectedFarmSnapshotEnsureScheduled = true;
    _lastSelectedFarmSnapshotEnsureKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectedFarmSnapshotEnsureScheduled = false;
      if (!mounted) return;
      if (index < 0 || index >= _farms.length) {
        _lastSelectedFarmSnapshotEnsureKey = null;
        return;
      }
      _ensureSelectedFarmSnapshotForFarm(index);
    });
  }

  void _scheduleFirstFarmTutorialCheck() {
    if (_firstFarmTutorialCheckScheduled) return;
    _firstFarmTutorialCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFarmTutorialCheckScheduled = false;
      if (!mounted) return;
      _maybeShowFirstFarmTutorial();
    });
  }

  String? _initialFarmServiceSyncKey(int index) {
    if (index < 0 || index >= _farms.length) return null;
    final phone = _verifiedFarmerPhone();
    if (phone == null) return null;
    return [
      phone,
      _verifiedFarmerId() ?? '',
      _farmStateKey(_farms[index]),
    ].join('|');
  }

  void _scheduleInitialFarmServiceSync(int index) {
    final key = _initialFarmServiceSyncKey(index);
    if (key == null || _initialFarmServiceReadyKey == key) return;
    if (_initialFarmServiceSyncing && _initialFarmServiceActiveKey == key) {
      return;
    }
    if (_initialFarmServiceSyncScheduled &&
        _initialFarmServiceActiveKey == key) {
      return;
    }
    _initialFarmServiceSyncScheduled = true;
    _initialFarmServiceActiveKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialFarmServiceSyncScheduled = false;
      if (!mounted) return;
      unawaited(_syncInitialFarmServicesForFarm(index, key).then((_) {}));
    });
  }

  Future<bool> _syncInitialFarmServicesForFarm(
    int index,
    String key, {
    bool requireDiseaseScan = true,
  }) async {
    if (index < 0 || index >= _farms.length) return false;
    if (_initialFarmServiceReadyKey == key) return true;
    setState(() {
      _initialFarmServiceSyncing = true;
      _initialFarmServiceSyncError = false;
      _initialFarmServiceActiveKey = key;
    });
    try {
      final servicesReady = await _confirmFarmServicesReadyForFarm(
        index,
        requireDiseaseScan: requireDiseaseScan,
      );
      if (!servicesReady) {
        if (mounted && _initialFarmServiceActiveKey == key) {
          setState(() {
            _initialFarmServiceSyncError = true;
          });
        }
        return false;
      }
      await _saveFarmDataSnapshotForFarm(
        index,
        source: 'initial_farmer_home_sync',
      );
      if (!mounted || _initialFarmServiceActiveKey != key) return false;
      setState(() {
        _initialFarmServiceReadyKey = key;
        _initialFarmServiceSyncError = false;
      });
      return true;
    } catch (error) {
      Get.log('Initial farm service sync failed: $error');
      if (!mounted || _initialFarmServiceActiveKey != key) return false;
      setState(() {
        _initialFarmServiceSyncError = true;
      });
      return false;
    } finally {
      if (mounted && _initialFarmServiceActiveKey == key) {
        setState(() {
          _initialFarmServiceSyncing = false;
        });
      }
    }
  }

  Future<bool> _confirmFarmServicesReadyForFarm(
    int index, {
    required bool requireDiseaseScan,
  }) async {
    if (index < 0 || index >= _farms.length) return false;
    final farm = _farms[index];
    final farmKey = _farmStateKey(farm);
    final farmerPhone = _verifiedFarmerPhone();
    if (farmerPhone == null || farmerPhone.isEmpty) return false;
    if (!_farmerFarmHasMarkedBoundary(farm)) return false;
    final farmId = await _resolveSatelliteFarmId(farm, index);
    if (farmId.trim().isEmpty) return false;
    final center = _selectedFarmWeatherCenter(farm);
    if (center == null) return false;

    final token = _satelliteRequestToken();
    final farmerId = _verifiedFarmerId();
    final summary = await _satelliteService.getFarmerFarmSummary(
      farmId: farmId,
      jwt: token,
      farmerPhone: farmerPhone,
      farmerId: farmerId,
    );
    if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return false;
    final summaryZones = _normalizeIssueRowsForMap(summary.scoutZoneRows);
    final summaryCells = _normalizeIssueRowsForMap(summary.riskCellRows);
    setState(() {
      _farmSummaryByFarmIndex[index] = summary;
      _satelliteOverviewByFarmIndex[index] = _overviewFromFarmSummary(summary);
      _farmSummaryLoadedAt[index] = DateTime.now();
      _diseaseScreenByFarmIndex[index] = summary.diseaseScreen;
      _diseaseScoutZonesByFarmIndex[index] = summaryZones;
      _diseaseRiskCellsByFarmIndex[index] = summaryCells;
      _diseaseRemoteLoadedAt[index] = DateTime.now();
      if (summary.advice != null) {
        _farmAlertAdviceByFarmIndex[index] = summary.advice!;
      }
    });

    final weather = await _satelliteService.getLiveWeather(
      latitude: center.latitude,
      longitude: center.longitude,
      crop: farm.crop,
      growthStage: _farmGrowthStage[index] ?? _growthStageForFarm(index),
      daysAfterSowing: _daysAfterSowing(index),
      satelliteMoisture: _satelliteOverviewByFarmIndex[index]?.moisture,
      jwt: token,
    );
    if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return false;
    setState(() {
      _liveWeatherByFarmIndex[index] = weather;
      _liveWeatherLoadedAt[index] = DateTime.now();
    });

    if (!_hasDiseaseScanStateForFarm(index)) {
      await _loadConfirmedDiseaseRowsForFarm(
        index,
        farmId: farmId,
        farmKey: farmKey,
        farmerPhone: farmerPhone,
        farmerId: farmerId,
        jwt: token,
      );
    }

    if (!_hasDiseaseScanStateForFarm(index)) {
      final scanReady = await _runDiseaseScreenForFarm(
        index,
        showFailureSnack: false,
        showInlineError: true,
        refreshSummaryAfter: false,
      );
      if (!scanReady && requireDiseaseScan) return false;
      await _loadConfirmedDiseaseRowsForFarm(
        index,
        farmId: farmId,
        farmKey: farmKey,
        farmerPhone: farmerPhone,
        farmerId: farmerId,
        jwt: token,
      );
    }

    if (requireDiseaseScan && !_hasDiseaseScanStateForFarm(index)) {
      return false;
    }

    await Future.wait<void>([
      _loadCropLifecycleAdviceForFarm(index, forceRefresh: true),
      _loadFarmTimelineForFarm(index, forceRefresh: true),
    ]);
    return mounted && _isSameFarmAtIndex(index, farmKey);
  }

  Future<bool> _loadConfirmedDiseaseRowsForFarm(
    int index, {
    required String farmId,
    required String farmKey,
    required String farmerPhone,
    required String? farmerId,
    required String? jwt,
  }) async {
    for (final delay in const [
      Duration.zero,
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
      Duration(milliseconds: 1500),
    ]) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return false;
      try {
        final diseaseData = await _satelliteService.getFarmerDiseaseData(
          farmId: farmId,
          jwt: jwt,
          farmerPhone: farmerPhone,
          farmerId: farmerId,
        );
        final zones = _latestIssueRowsForMap(
          _normalizeIssueRowsForMap(diseaseData.scoutZones),
        );
        final cells = _latestIssueRowsForMap(
          _normalizeIssueRowsForMap(diseaseData.riskCells),
        );
        if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return false;
        setState(() {
          _diseaseScoutZonesByFarmIndex[index] = zones;
          _diseaseRiskCellsByFarmIndex[index] = cells;
          _diseaseRemoteLoadedAt[index] = DateTime.now();
        });
        if (_hasDiseaseScanStateForFarm(index)) return true;
      } catch (error) {
        Get.log('Confirmed disease row load failed: $error');
      }
    }
    return _hasDiseaseScanStateForFarm(index);
  }

  Map<String, dynamic>? _weatherContextForFarm(int index) {
    if (index < 0 || index >= _farms.length) return null;
    final context = <String, dynamic>{
      ...?_displayDiseaseScreenForFarm(index)?.weatherContext,
      ...?_farmSummaryByFarmIndex[index]?.weatherContext,
    };
    final snapshot = _liveWeatherByFarmIndex[index];
    if (snapshot == null) {
      return context.isEmpty ? null : context;
    }
    double? read(Map<String, dynamic> row, String key) {
      return FarmWeatherSnapshot.readDouble(row, key);
    }

    final rainTotal = snapshot.daily7d.fold<double>(
      0,
      (sum, row) => sum + (read(row, 'rain_mm') ?? 0),
    );
    final waterStressScore = read(snapshot.waterStress, 'score');
    final cropWeatherScore = read(snapshot.cropHealthWeather, 'score');
    final weatherRisk =
        [
          waterStressScore,
          cropWeatherScore,
          if (rainTotal > 0) (rainTotal / 80).clamp(0.0, 1.0).toDouble(),
        ].whereType<double>().fold<double>(
          0,
          (max, value) => value > max ? value : max,
        );

    return {
      ...context,
      'current': snapshot.current,
      'live_current': snapshot.current,
      'hourly_24h': snapshot.hourly24h,
      'daily_7d': snapshot.daily7d,
      'agro_weather': snapshot.agroWeather,
      'water_stress': snapshot.waterStress,
      'crop_health_weather': snapshot.cropHealthWeather,
      'temperature_c': read(snapshot.current, 'temperature_c'),
      'humidity_percent': read(snapshot.current, 'humidity_percent'),
      'rain_mm': read(snapshot.current, 'rain_mm'),
      'wind_kmh': read(snapshot.current, 'wind_kmh'),
      'total_rain_mm': rainTotal,
      'weather_risk': weatherRisk,
      'source': snapshot.source,
      'updated_at': snapshot.updatedAt,
    };
  }

  Map<String, dynamic> _snapshotMap(dynamic raw) {
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  double? _snapshotDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  Map<String, dynamic> _farmDataSnapshotPayload(
    int index, {
    required String source,
  }) {
    final farm = _farms[index];
    final status = _statusSnapshotForFarm(index);
    final weather = _weatherContextForFarm(index) ?? const <String, dynamic>{};
    final current = _snapshotMap(weather['live_current']).isNotEmpty
        ? _snapshotMap(weather['live_current'])
        : _snapshotMap(weather['current']);
    final waterStress = _snapshotMap(weather['water_stress']);
    final cropWeather = _snapshotMap(weather['crop_health_weather']);
    final advice = _cropLifecycleByFarmIndex[index];
    final diseaseScreen = _displayDiseaseScreenForFarm(index);
    final topDiseaseRisks =
        diseaseScreen?.topDiseaseRisks.entries.toList(growable: false) ??
        const <MapEntry<String, double>>[];
    final sortedTopDiseaseRisks = [...topDiseaseRisks]
      ..sort((a, b) => b.value.compareTo(a.value));
    final latestStatusEvent = _latestStatusTimelineEvent(index);

    return {
      'source': source,
      'farm': {
        'name': farm.name,
        'location': farm.location,
        'area': farm.area,
        if (farm.remoteFarmId.trim().isNotEmpty)
          'remote_farm_id': farm.remoteFarmId.trim(),
      },
      'crop': {
        'name': farm.crop,
        'variety': farm.variety,
        'days_after_sowing': _daysAfterSowing(index),
        'growth_stage': status.stage,
      },
      'status': {
        'current': status.status,
        'stage': status.stage,
        if (status.updatedAt != null)
          'updated_at': status.updatedAt!.toIso8601String(),
      },
      'weather': {
        'temperature_c':
            _snapshotDouble(weather['temperature_c']) ??
            _snapshotDouble(current['temperature_c']),
        'humidity_percent':
            _snapshotDouble(weather['humidity_percent']) ??
            _snapshotDouble(current['humidity_percent']),
        'rain_mm':
            _snapshotDouble(weather['rain_mm']) ??
            _snapshotDouble(current['rain_mm']),
        'total_rain_mm': _snapshotDouble(weather['total_rain_mm']),
        'wind_kmh':
            _snapshotDouble(weather['wind_kmh']) ??
            _snapshotDouble(current['wind_kmh']),
        'weather_risk': _snapshotDouble(weather['weather_risk']),
        'water_stress_label': '${waterStress['label'] ?? ''}'.trim(),
        'water_stress_score': _snapshotDouble(waterStress['score']),
        'water_stress_recommendation': '${waterStress['recommendation'] ?? ''}'
            .trim(),
        'crop_weather_label': '${cropWeather['label'] ?? ''}'.trim(),
        'crop_weather_score': _snapshotDouble(cropWeather['score']),
        'crop_weather_summary': '${cropWeather['summary'] ?? ''}'.trim(),
        'source': '${weather['source'] ?? ''}'.trim(),
        'updated_at': '${weather['updated_at'] ?? ''}'.trim(),
      },
      'disease': {
        'max_risk': _diseaseMaxRiskForFarm(index),
        'risk_cells_count':
            diseaseScreen?.riskCellsCount ??
            _displayRiskCellsForFarm(index).length,
        'scout_zones_count': _displayScoutZonesForFarm(index).length,
        'top_risks': [
          for (final risk in sortedTopDiseaseRisks.take(5))
            {'name': risk.key, 'score': risk.value},
        ],
      },
      'lifecycle': advice == null
          ? null
          : {
              'crop': advice.crop,
              'growth_stage': advice.growthStage,
              'stage_window': advice.stageWindow,
              'water_need': advice.waterNeed,
              'disease_watch': advice.diseaseWatch,
              'scout_task': advice.scoutTask,
              'next_action': advice.nextAction,
              'timeline_stage_count': advice.timeline.length,
            },
      'timeline': {
        'visible_event_count': _farmTimelineByFarmIndex[index]?.length ?? 0,
        if (latestStatusEvent != null) ...{
          'latest_status_event_at': latestStatusEvent.createdAt
              .toIso8601String(),
          'latest_status_stage': _stageFromTimelineEvent(latestStatusEvent),
          'latest_status': _statusTextFromTimelineEvent(latestStatusEvent),
        },
      },
    };
  }

  Future<void> _saveFarmDataSnapshotForFarm(
    int index, {
    required String source,
  }) async {
    if (index < 0 || index >= _farms.length) return;
    final farmerPhone = _verifiedFarmerPhone();
    if (farmerPhone == null) return;
    final farm = _farms[index];
    final farmKey = _farmStateKey(farm);
    try {
      final farmId = await _resolveSatelliteFarmId(farm, index);
      if (farmId.isEmpty) return;
      if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
      await _satelliteService.saveFarmDataSnapshot(
        farmId: farmId,
        farmerPhone: farmerPhone,
        jwt: _satelliteRequestToken(),
        farmerId: _verifiedFarmerId(),
        source: source,
        snapshot: _farmDataSnapshotPayload(index, source: source),
      );
    } catch (_) {
      // Daily analytics snapshots are hidden from the farmer timeline.
    }
  }

  Future<void> _loadLiveWeatherForFarm(
    int index, {
    bool forceRefresh = false,
  }) async {
    if (index < 0 || index >= _farms.length) return;
    if (_liveWeatherLoading.contains(index)) return;
    if (!forceRefresh &&
        _liveWeatherByFarmIndex.containsKey(index) &&
        _isFarmCacheFresh(_liveWeatherLoadedAt, index, _liveWeatherFreshFor)) {
      return;
    }

    final farm = _farms[index];
    final farmKey = _farmStateKey(farm);
    final center = _selectedFarmWeatherCenter(farm);
    if (center == null) return;
    setState(() => _liveWeatherLoading.add(index));
    try {
      final snapshot = await _satelliteService.getLiveWeather(
        latitude: center.latitude,
        longitude: center.longitude,
        crop: farm.crop,
        growthStage: _farmGrowthStage[index] ?? _growthStageForFarm(index),
        daysAfterSowing: _daysAfterSowing(index),
        satelliteMoisture: _satelliteOverviewByFarmIndex[index]?.moisture,
        jwt: _satelliteRequestToken(),
      );
      if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
      setState(() {
        _liveWeatherByFarmIndex[index] = snapshot;
        _liveWeatherLoadedAt[index] = DateTime.now();
      });
    } catch (_) {
      // Keep the previous weather snapshot on transient network errors.
    } finally {
      if (mounted) {
        setState(() => _liveWeatherLoading.remove(index));
      }
    }
  }

  void _ensureSatelliteOverviewForFarm(int index) {
    if (index < 0 || index >= _farms.length) return;
    if (_satelliteOverviewLoading.contains(index)) return;
    if (_satelliteOverviewByFarmIndex.containsKey(index) &&
        _isFarmCacheFresh(_farmSummaryLoadedAt, index, _farmSummaryFreshFor)) {
      return;
    }
    if (_farmSummaryLoading.contains(index)) {
      if (_satelliteOverviewPendingAfterSummary.add(index)) {
        unawaited(_loadSatelliteOverviewAfterSummary(index));
      }
      return;
    }
    unawaited(_loadFarmSummaryForFarm(index));
  }

  Future<void> _loadSatelliteOverviewAfterSummary(int index) async {
    try {
      await _waitForFarmLoadToFinish(_farmSummaryLoading, index);
      if (!mounted || index < 0 || index >= _farms.length) return;
      if (_satelliteOverviewByFarmIndex.containsKey(index) &&
          _isFarmCacheFresh(
            _farmSummaryLoadedAt,
            index,
            _farmSummaryFreshFor,
          )) {
        return;
      }
      await _loadSatelliteOverviewForFarm(index);
    } finally {
      _satelliteOverviewPendingAfterSummary.remove(index);
    }
  }

  Future<void> _loadFarmSummaryForFarm(
    int index, {
    bool cascade = true,
    bool forceRefresh = false,
    bool updateDiseaseRows = true,
  }) async {
    if (index < 0 || index >= _farms.length) return;
    if (_farmSummaryLoading.contains(index)) {
      await _waitForFarmLoadToFinish(_farmSummaryLoading, index);
      if (!mounted || _farmSummaryLoading.contains(index)) return;
    }
    if (!forceRefresh &&
        _farmSummaryByFarmIndex.containsKey(index) &&
        _isFarmCacheFresh(_farmSummaryLoadedAt, index, _farmSummaryFreshFor)) {
      return;
    }
    final farmerPhone = _verifiedFarmerPhone();
    if (farmerPhone == null) {
      await _loadSatelliteOverviewForFarm(index, forceRefresh: forceRefresh);
      return;
    }

    setState(() => _farmSummaryLoading.add(index));
    try {
      final farm = _farms[index];
      final farmKey = _farmStateKey(farm);
      final farmId = await _resolveSatelliteFarmId(farm, index);
      if (farmId.isEmpty) {
        if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
        _satelliteOverviewByFarmIndex[index] = _fallbackSatelliteOverview(
          UiStrings.t('no_satellite_index_farm'),
        );
        _farmSummaryLoadedAt[index] = DateTime.now();
        return;
      }
      final summary = await _satelliteService.getFarmerFarmSummary(
        farmId: farmId,
        jwt: _satelliteRequestToken(),
        farmerPhone: farmerPhone,
        farmerId: _verifiedFarmerId(),
      );
      final zones = _normalizeIssueRowsForMap(summary.scoutZoneRows);
      final cells = _normalizeIssueRowsForMap(summary.riskCellRows);
      if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
      _farmSummaryByFarmIndex[index] = summary;
      _satelliteOverviewByFarmIndex[index] = _overviewFromFarmSummary(summary);
      _farmSummaryLoadedAt[index] = DateTime.now();
      if (updateDiseaseRows) {
        _diseaseScreenByFarmIndex[index] = summary.diseaseScreen;
        _diseaseScoutZonesByFarmIndex[index] = zones;
        _diseaseRiskCellsByFarmIndex[index] = cells;
        _diseaseRemoteLoadedAt[index] = DateTime.now();
      }
      if (summary.advice != null) {
        _farmAlertAdviceByFarmIndex[index] = summary.advice!;
      }
      if (cascade) {
        unawaited(_loadLiveWeatherForFarm(index));
        unawaited(_loadCropLifecycleAdviceForFarm(index));
      }
    } catch (_) {
      await _loadSatelliteOverviewForFarm(index, forceRefresh: forceRefresh);
    } finally {
      if (mounted) {
        setState(() => _farmSummaryLoading.remove(index));
      }
    }
  }

  Future<void> _loadCropLifecycleAdviceForFarm(
    int index, {
    bool forceRefresh = false,
  }) async {
    if (index < 0 || index >= _farms.length) return;
    if (_cropLifecycleLoading.contains(index)) {
      await _waitForFarmLoadToFinish(_cropLifecycleLoading, index);
      if (!mounted || _cropLifecycleLoading.contains(index)) return;
    }
    if (!forceRefresh &&
        _cropLifecycleByFarmIndex.containsKey(index) &&
        _isFarmCacheFresh(
          _cropLifecycleLoadedAt,
          index,
          _cropLifecycleFreshFor,
        )) {
      return;
    }
    final farmerPhone = _verifiedFarmerPhone();
    if (farmerPhone == null) return;

    setState(() => _cropLifecycleLoading.add(index));
    try {
      final farm = _farms[index];
      final farmKey = _farmStateKey(farm);
      final farmId = await _resolveSatelliteFarmId(farm, index);
      if (farmId.isEmpty) return;
      final advice = await _satelliteService.getCropLifecycleAdvice(
        farmId: farmId,
        farmerPhone: farmerPhone,
        jwt: _satelliteRequestToken(),
        farmerId: _verifiedFarmerId(),
        crop: farm.crop,
        growthStage: _farmGrowthStage[index] ?? _growthStageForFarm(index),
        daysAfterSowing: _daysAfterSowing(index),
        variety: farm.variety,
        district: farm.location,
      );
      if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
      _cropLifecycleByFarmIndex[index] = advice;
      _cropLifecycleLoadedAt[index] = DateTime.now();
    } catch (_) {
      // Lifecycle advice should not block farm summary or alert loading.
    } finally {
      if (mounted) {
        setState(() => _cropLifecycleLoading.remove(index));
      }
    }
  }

  Future<void> _loadSatelliteOverviewForFarm(
    int index, {
    bool forceRefresh = false,
  }) async {
    if (index < 0 || index >= _farms.length) return;
    if (_satelliteOverviewLoading.contains(index)) return;
    if (!forceRefresh &&
        _satelliteOverviewByFarmIndex.containsKey(index) &&
        _isFarmCacheFresh(_farmSummaryLoadedAt, index, _farmSummaryFreshFor)) {
      return;
    }
    setState(() => _satelliteOverviewLoading.add(index));

    final farmKey = _farmStateKey(_farms[index]);
    try {
      final farm = _farms[index];
      final farmId = await _resolveSatelliteFarmId(farm, index);
      if (farmId.isEmpty) {
        if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
        _satelliteOverviewByFarmIndex[index] = _fallbackSatelliteOverview(
          UiStrings.t('no_satellite_index_farm'),
        );
        _farmSummaryLoadedAt[index] = DateTime.now();
        return;
      }
      final timeline = await _satelliteService.getFarmTimeline(
        farmId,
        _satelliteRequestToken(),
      );
      final overview = _buildFarmSatelliteOverview(timeline);
      if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
      _satelliteOverviewByFarmIndex[index] = overview;
      _farmSummaryLoadedAt[index] = DateTime.now();
    } catch (_) {
      if (!_isSameFarmAtIndex(index, farmKey)) return;
      _satelliteOverviewByFarmIndex[index] = _fallbackSatelliteOverview(
        UiStrings.t('no_satellite_index_farm'),
      );
      _farmSummaryLoadedAt[index] = DateTime.now();
    } finally {
      if (mounted) {
        setState(() {
          _satelliteOverviewLoading.remove(index);
        });
      }
    }
  }

  _FarmSatelliteOverview _fallbackSatelliteOverview(String message) {
    return _FarmSatelliteOverview(
      tiles: [
        _SatelliteMetricTileData(
          title: UiStrings.t('water_level'),
          value: '--',
          subtitle: UiStrings.t('waiting_for_data'),
          icon: Icons.water_drop_rounded,
          tint: Color(0xFFE3F2FD),
          color: Color(0xFF1976D2),
        ),
        _SatelliteMetricTileData(
          title: UiStrings.t('crop_health'),
          value: '--',
          subtitle: UiStrings.t('waiting_for_data'),
          icon: Icons.satellite_alt_rounded,
          tint: Color(0xFFE8F5E9),
          color: Color(0xFF2E7D32),
        ),
        _SatelliteMetricTileData(
          title: UiStrings.t('canopy_ground_structure'),
          value: '--',
          subtitle: UiStrings.t('waiting_for_data'),
          icon: Icons.park_rounded,
          tint: Color(0xFFE8F5E9),
          color: Color(0xFF2E7D32),
        ),
        _SatelliteMetricTileData(
          title: UiStrings.t('crop_trend'),
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

  _FarmSatelliteOverview _overviewFromFarmSummary(FarmerFarmSummary summary) {
    final weather = summary.weatherContext ?? const <String, dynamic>{};
    final waterStress = _snapshotMap(weather['water_stress']);
    final cropWeather = _snapshotMap(weather['crop_health_weather']);
    final waterStressScore = _snapshotDouble(waterStress['score']);
    final cropWeatherScore = _snapshotDouble(cropWeather['score']);
    final weatherWaterLevel = waterStressScore == null
        ? null
        : (1 - waterStressScore).clamp(0.0, 1.0).toDouble();
    final weatherCropHealth = cropWeatherScore?.clamp(0.0, 1.0).toDouble();

    String? weatherSubtitle(Map<String, dynamic> source) {
      for (final key in const ['label', 'summary', 'recommendation']) {
        final text = '${source[key] ?? ''}'.trim();
        if (text.isNotEmpty) return UiStrings.option(text);
      }
      return source.isEmpty ? null : UiStrings.t('current_conditions');
    }

    _SatelliteMetricTileData tile(
      FarmSummaryMetric? metric, {
      required String title,
      required IconData icon,
      required Color tint,
      required Color color,
      double? fallbackValue,
      String? fallbackSubtitle,
      int decimals = 3,
    }) {
      if (metric == null || !metric.hasValue) {
        if (fallbackValue != null) {
          return _SatelliteMetricTileData(
            title: title,
            value: LocaleText.number(fallbackValue, fractionDigits: decimals),
            subtitle: fallbackSubtitle ?? UiStrings.t('current_conditions'),
            icon: icon,
            tint: tint,
            color: color,
          );
        }
        return _placeholderTile(title, icon, tint, color);
      }
      final index = metric.index?.trim();
      final date = metric.date?.trim();
      final subtitle = index != null && index.isNotEmpty
          ? '${index.toUpperCase()}${date != null && date.isNotEmpty ? ' • ${LocaleText.digits(date)}' : ''}'
          : metric.source ?? UiStrings.t('last_update');
      return _SatelliteMetricTileData(
        title: title,
        value: LocaleText.number(metric.value!, fractionDigits: decimals),
        subtitle: subtitle,
        icon: icon,
        tint: tint,
        color: color,
      );
    }

    return _FarmSatelliteOverview(
      tiles: [
        tile(
          summary.waterLevel,
          title: UiStrings.t('water_level'),
          icon: Icons.water_drop_rounded,
          tint: const Color(0xFFE3F2FD),
          color: const Color(0xFF1976D2),
          fallbackValue: weatherWaterLevel,
          fallbackSubtitle: weatherSubtitle(waterStress),
        ),
        tile(
          summary.cropHealth,
          title: UiStrings.t('crop_health'),
          icon: Icons.satellite_alt_rounded,
          tint: const Color(0xFFE8F5E9),
          color: const Color(0xFF2E7D32),
          fallbackValue: weatherCropHealth,
          fallbackSubtitle: weatherSubtitle(cropWeather),
        ),
        tile(
          summary.canopy,
          title: UiStrings.t('canopy_ground_structure'),
          icon: Icons.park_rounded,
          tint: const Color(0xFFE8F5E9),
          color: const Color(0xFF2E7D32),
        ),
        tile(
          summary.cropTrend,
          title: UiStrings.t('crop_trend'),
          icon: Icons.trending_up_rounded,
          tint: const Color(0xFFE8EAF6),
          color: const Color(0xFF3949AB),
        ),
      ],
      note: summary.lastUpdate == null
          ? null
          : '${UiStrings.t('last_update')}: ${LocaleText.digits(summary.lastUpdate!)}',
      ndvi: summary.cropHealth?.value ?? weatherCropHealth,
      moisture: summary.waterLevel?.value ?? weatherWaterLevel,
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
    return LocaleText.number(value, fractionDigits: decimals);
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
      subtitle: UiStrings.t('no_data'),
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
      subtitle:
          '${_indexLabel(selectedIndex)} • ${LocaleText.digits(entry.date)}',
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
      subtitle: UiStrings.f('index_trend_delta', {
        'direction': direction,
        'delta': _formatIndexValue(delta, 3),
        'date': LocaleText.digits(previous.date),
        'value': _formatIndexValue(previous.meanValue, 3),
      }),
      icon: icon,
      tint: tint,
      color: color,
    );
  }

  _FarmSatelliteOverview _buildFarmSatelliteOverview(
    List<TimelineEntry> entries,
  ) {
    if (entries.isEmpty) {
      return _fallbackSatelliteOverview(UiStrings.t('no_remote_index_records'));
    }

    final grouped = _groupTimelineByIndex(entries);
    final water = _buildMetricTile(
      UiStrings.t('water_level'),
      const ['ndwi'],
      grouped,
      decimals: 3,
      icon: Icons.water_drop_rounded,
      tint: const Color(0xFFE3F2FD),
      color: const Color(0xFF1976D2),
    );
    final crop = _buildMetricTile(
      UiStrings.t('crop_health'),
      const ['ndvi'],
      grouped,
      decimals: 3,
      icon: Icons.satellite_alt_rounded,
      tint: const Color(0xFFE8F5E9),
      color: const Color(0xFF2E7D32),
    );
    final canopy = _buildMetricTile(
      UiStrings.t('canopy_ground_structure'),
      const ['ndre', 'gndvi', 'savi'],
      grouped,
      decimals: 3,
      icon: Icons.park_rounded,
      tint: const Color(0xFFE8F5E9),
      color: const Color(0xFF2E7D32),
    );
    final trend = _buildTrendTile(
      UiStrings.t('crop_trend'),
      'ndvi',
      grouped,
      icon: Icons.trending_up_rounded,
      tint: const Color(0xFFE8EAF6),
      color: const Color(0xFF3949AB),
    );

    return _FarmSatelliteOverview(
      tiles: [water, crop, canopy, trend],
      note: entries.isNotEmpty
          ? '${UiStrings.t('last_update')}: ${LocaleText.digits(entries.last.date)}'
          : null,
      ndvi: _latestGroupedValue(grouped, const ['ndvi']),
      moisture: _latestGroupedValue(grouped, const ['ndwi', 'moisture']),
    );
  }

  double? _latestGroupedValue(
    Map<String, List<TimelineEntry>> grouped,
    List<String> candidates,
  ) {
    for (final index in candidates) {
      final list = grouped[index];
      if (list != null && list.isNotEmpty) {
        return list.last.meanValue;
      }
    }
    return null;
  }

  void _initializeFarmState(int index) {
    _farmSowingDate.putIfAbsent(
      index,
      () => _farmRecordSowingDate(index) ?? _dateOnly(DateTime.now()),
    );
    _farmStatusPhotoBytes.putIfAbsent(index, () => null);
    _farmStatusPhotoName.putIfAbsent(index, () => '');
    _farmGrowthStage.putIfAbsent(index, () {
      final stage = index >= 0 && index < _farms.length
          ? _farms[index].currentStatusStage
          : null;
      return stage == null || stage.trim().isEmpty
          ? _farmLifecycleStages.first
          : stage.trim();
    });
    _farmStatusAnswer.putIfAbsent(index, () {
      final status = index >= 0 && index < _farms.length
          ? _farms[index].currentStatus
          : null;
      return status == null || status.trim().isEmpty
          ? UiStrings.t('not_updated')
          : status.trim();
    });
    final remoteStatusUpdatedAt = index >= 0 && index < _farms.length
        ? _farms[index].currentStatusUpdatedAt
        : null;
    if (remoteStatusUpdatedAt != null) {
      _farmStatusUpdatedAt.putIfAbsent(index, () => remoteStatusUpdatedAt);
    }
    _farmDiagnosisLog.putIfAbsent(index, () => const <String>[]);
    _farmDiseaseMarkers.putIfAbsent(index, () => const <LatLng>[]);
  }

  DateTime _dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _dateOnlyIso(DateTime value) {
    return _dateOnly(value).toIso8601String().split('T').first;
  }

  DateTime? _farmRecordSowingDate(int index) {
    if (index < 0 || index >= _farms.length) return null;
    final farm = _farms[index];
    for (final raw in [farm.sowingDate, farm.createdAt]) {
      final parsed = DateTime.tryParse('${raw ?? ''}'.trim());
      if (parsed != null) return _dateOnly(parsed);
    }
    return null;
  }

  int _daysAfterSowing(int index) {
    final sowingDate = _farmSowingDate[index] ?? _farmRecordSowingDate(index);
    if (sowingDate == null) return 0;
    final now = _dateOnly(DateTime.now());
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
    final remoteStage = index >= 0 && index < _farms.length
        ? _farms[index].currentStatusStage?.trim()
        : null;
    _farmGrowthStage[index] = remoteStage == null || remoteStage.isEmpty
        ? _growthStageForFarm(index)
        : remoteStage;
  }

  CropLifecycleStage? _currentLifecycleStageForFarm(int index) {
    final advice = _cropLifecycleByFarmIndex[index];
    if (advice == null) return null;
    final day = _daysAfterSowing(index);
    final timeline =
        advice.timeline
            .where(
              (stage) =>
                  stage.stage.trim().isNotEmpty ||
                  stage.detail.trim().isNotEmpty,
            )
            .toList(growable: true)
          ..sort((a, b) => a.startDay.compareTo(b.startDay));
    for (final stage in timeline) {
      if (day >= stage.startDay && day <= stage.endDay) return stage;
    }
    return null;
  }

  String? _lifecycleContextForFarm(int index) {
    final advice = _cropLifecycleByFarmIndex[index];
    if (advice == null) return null;
    final farm = index >= 0 && index < _farms.length ? _farms[index] : null;
    final cropContext = [
      if (farm != null && farm.crop.trim().isNotEmpty)
        UiStrings.option(farm.crop),
      if (farm != null && farm.variety.trim().isNotEmpty)
        UiStrings.option(farm.variety),
    ].join(' • ');
    final activeStage = _currentLifecycleStageForFarm(index);
    final dayText = UiStrings.f('days_after_sowing_value', {
      'days': LocaleText.number(_daysAfterSowing(index)),
    });
    final stageName = activeStage?.stage.trim().isNotEmpty == true
        ? activeStage!.stage
        : (advice.growthStage.trim().isNotEmpty
              ? advice.growthStage
              : (_farmGrowthStage[index] ?? _growthStageForFarm(index)));
    final detail = activeStage?.detail.trim().isNotEmpty == true
        ? activeStage!.detail.trim()
        : advice.nextAction.trim();
    final lines = <String>[
      '${UiStrings.t('crop_cycle_timeline')}: ${cropContext.isEmpty ? UiStrings.option(advice.crop) : cropContext}',
      '${UiStrings.t('growth')}: $dayText • ${UiStrings.option(stageName.replaceAll('-', ' '))}',
      if (activeStage != null)
        UiStrings.f('active_now_range', {
          'start': LocaleText.number(activeStage.startDay),
          'end': LocaleText.number(activeStage.endDay),
        }),
      if (detail.isNotEmpty) detail,
    ];
    return lines.join('\n');
  }

  String _statusQuestionForFarm(int index, String stage) {
    final farm = index >= 0 && index < _farms.length ? _farms[index] : null;
    final crop = farm == null ? '' : UiStrings.option(farm.crop);
    final variety = farm == null ? '' : UiStrings.option(farm.variety);
    final activeStage = _currentLifecycleStageForFarm(index);
    final activeDetail = activeStage?.detail.trim();
    final base =
        _farmStatusQuestions[stage] ??
        'What is the field activity in current crop stage?';
    final lifecycleTask = _cropLifecycleByFarmIndex[index]?.scoutTask.trim();
    final focus = lifecycleTask == null || lifecycleTask.isEmpty
        ? (activeDetail == null || activeDetail.isEmpty ? base : activeDetail)
        : lifecycleTask;
    final cropContext = [
      crop,
      variety,
    ].where((item) => item.trim().isNotEmpty).join(' ');
    final dayText = UiStrings.f('days_after_sowing_value', {
      'days': LocaleText.number(_daysAfterSowing(index)),
    });
    final stageLabel = activeStage?.stage.trim().isNotEmpty == true
        ? activeStage!.stage
        : stage;
    return cropContext.isEmpty
        ? '$dayText • ${UiStrings.option(stageLabel.replaceAll('-', ' '))}: $focus'
        : '$cropContext • $dayText • ${UiStrings.option(stageLabel.replaceAll('-', ' '))}: $focus';
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
    final selectedCenter = _selectedFarmWeatherCenter(farm);
    if (selectedCenter != null) return selectedCenter;
    return const LatLng(12.3919, 77.7736);
  }

  LatLng? _selectedFarmWeatherCenter(_FarmerFarm farm) {
    final polygon = farm.polygon
        ?.where((point) => point.length >= 2)
        .map((point) => LatLng(point[1], point[0]))
        .toList(growable: false);
    if (polygon != null && polygon.length >= 3) {
      final lat =
          polygon.fold<double>(0, (sum, point) => sum + point.latitude) /
          polygon.length;
      final lng =
          polygon.fold<double>(0, (sum, point) => sum + point.longitude) /
          polygon.length;
      return LatLng(lat, lng);
    }
    if (farm.latitude != null && farm.longitude != null) {
      return LatLng(farm.latitude!, farm.longitude!);
    }
    return _parseCoordinates(farm.location);
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
    return '${LocaleText.date(value, pattern: 'dd/MM')} ${LocaleText.time(value)}';
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

  double? _readCoordinate(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  LatLng? _parseCoordinatePair(num? maybeLat, num? maybeLng) {
    if (maybeLat == null || maybeLng == null) return null;
    final first = maybeLat.toDouble();
    final second = maybeLng.toDouble();
    if (first.abs() <= 90 && second.abs() <= 180) {
      return LatLng(first, second);
    }
    if (first.abs() <= 180 && second.abs() <= 90) {
      return LatLng(second, first);
    }
    return null;
  }

  LatLng? _parsePointObject(dynamic value) {
    if (value == null) return null;
    if (value is LatLng) return value;
    if (value is List) {
      if (value.length >= 2) {
        final first = _readCoordinate(value[0]);
        final second = _readCoordinate(value[1]);
        if (first == null || second == null) return null;
        return _parseCoordinatePair(first, second);
      }
      return null;
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final directLat = _readCoordinate(
        map['lat'] ?? map['latitude'] ?? map['y'],
      );
      final directLng = _readCoordinate(
        map['lng'] ?? map['lon'] ?? map['long'] ?? map['x'],
      );
      if (directLat != null && directLng != null) {
        return _parseCoordinatePair(directLat, directLng);
      }
      return _parsePointFromMap(map);
    }

    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      if (text.startsWith('{') || text.startsWith('[')) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map) {
            return _parsePointObject(Map<String, dynamic>.from(decoded));
          }
          if (decoded is List) {
            return _parsePointObject(decoded);
          }
        } catch (_) {
          // Fallback to regex parse for POINT and comma notation.
        }
      }

      final pointMatch = RegExp(
        r'POINT\\s*\\(\\s*([+-]?\\d*\\.?\\d+)\\s+([+-]?\\d*\\.?\\d+)\\s*\\)',
        caseSensitive: false,
      ).firstMatch(text);
      if (pointMatch != null) {
        final a = double.tryParse(pointMatch.group(1) ?? '');
        final b = double.tryParse(pointMatch.group(2) ?? '');
        if (a == null || b == null) return null;
        return _parseCoordinatePair(a, b);
      }

      if (text.contains(',')) {
        final parts = text.split(',');
        if (parts.length >= 2) {
          final first = double.tryParse(parts[0].trim());
          final second = double.tryParse(parts[1].trim());
          return _parseCoordinatePair(first, second);
        }
      }
      final spaceSplit = text.trim().split(RegExp(r'\\s+'));
      if (spaceSplit.length >= 2) {
        final first = double.tryParse(spaceSplit[0]);
        final second = double.tryParse(spaceSplit[1]);
        return _parseCoordinatePair(first, second);
      }
    }

    return null;
  }

  LatLng? _parsePointFromMap(Map<String, dynamic> map) {
    final centroid = _parsePointObject(map['centroid']);
    if (centroid != null) return centroid;
    final geometry = _parsePointObject(map['geometry']);
    if (geometry != null) return geometry;
    final point = _parsePointObject(map['point']);
    if (point != null) return point;
    final coordinates = _parsePointObject(map['coordinates']);
    if (coordinates != null) return coordinates;
    if (map.containsKey('coordinates') && map['coordinates'] is List) {
      final coordinates = map['coordinates'] as List;
      if (coordinates.isNotEmpty && coordinates[0] is List) {
        final ring = coordinates[0] as List;
        return _parsePointFromRing(ring);
      }
    }
    return null;
  }

  LatLng? _parsePointFromRing(List<dynamic> ring) {
    if (ring.isEmpty) return null;
    double latSum = 0;
    double lngSum = 0;
    var pointCount = 0;
    for (final point in ring) {
      if (point is! List || point.length < 2) continue;
      final lat = _readCoordinate(point[0]);
      final lng = _readCoordinate(point[1]);
      if (lat == null || lng == null) continue;
      final parsed = _parseCoordinatePair(lat, lng);
      if (parsed == null) continue;
      latSum += parsed.latitude;
      lngSum += parsed.longitude;
      pointCount++;
    }
    if (pointCount == 0) return null;
    return LatLng(latSum / pointCount, lngSum / pointCount);
  }

  LatLng? _readIssuePoint(Map<String, dynamic> row) {
    final latLng = _parsePointFromMap(row);
    if (latLng != null) return latLng;

    final direct = _parseCoordinatePair(
      _readCoordinate(row['lat']) ?? _readCoordinate(row['cell_lat']),
      _readCoordinate(row['lng']) ?? _readCoordinate(row['cell_lng']),
    );
    if (direct != null) return direct;

    final centroid = _parseCoordinatePair(
      _readCoordinate(row['centroid_lat']),
      _readCoordinate(row['centroid_lng']),
    );
    if (centroid != null) return centroid;

    return null;
  }

  List<Map<String, dynamic>> _normalizeIssueRowsForMap(
    List<Map<String, dynamic>> rows,
  ) {
    return rows
        .map((row) {
          final normalized = Map<String, dynamic>.from(row);
          final point = _readIssuePoint(normalized);
          if (point == null) return normalized;
          normalized['lat'] = point.latitude;
          normalized['lng'] = point.longitude;
          return normalized;
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _latestIssueRowsForMap(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return const [];

    DateTime toMinute(DateTime date) =>
        DateTime(date.year, date.month, date.day, date.hour, date.minute);

    final latestScanDate = rows
        .map((row) => DateTime.tryParse('${row['scan_date']}'))
        .whereType<DateTime>()
        .fold<DateTime?>(null, (acc, date) {
          if (acc == null || date.isAfter(acc)) return date;
          return acc;
        });
    if (latestScanDate == null) return rows;

    final latestScanMinute = toMinute(latestScanDate);
    final latestRows = rows
        .where((row) {
          final parsed = DateTime.tryParse('${row['scan_date']}');
          return parsed != null && toMinute(parsed) == latestScanMinute;
        })
        .toList(growable: false);
    return latestRows.isEmpty ? rows : latestRows;
  }

  Future<void> _ensureDiseaseRemoteForFarm(
    int index, {
    bool forceRefresh = false,
    bool runScreenIfEmpty = false,
    bool showAlertErrors = true,
  }) async {
    if (index < 0 || index >= _farms.length) return;
    if (_diseaseRemoteLoading.contains(index)) return;
    if (!forceRefresh &&
        _diseaseScoutZonesByFarmIndex.containsKey(index) &&
        _diseaseRiskCellsByFarmIndex.containsKey(index) &&
        _isFarmCacheFresh(
          _diseaseRemoteLoadedAt,
          index,
          _diseaseRemoteFreshFor,
        ) &&
        (!runScreenIfEmpty || !_shouldRunRiskScreenForEmptyFarm(index))) {
      return;
    }

    final farm = _farms[index];
    final farmKey = _farmStateKey(farm);
    setState(() => _diseaseRemoteLoading.add(index));
    try {
      final farmId = await _resolveSatelliteFarmId(farm, index);
      if (farmId.isEmpty) return;
      final token = _satelliteRequestToken();
      final farmerPhone = _verifiedFarmerPhone();
      final farmerId = _verifiedFarmerId();
      late List<Map<String, dynamic>> zones;
      late List<Map<String, dynamic>> cells;
      if (farmerPhone != null) {
        final diseaseData = await _satelliteService.getFarmerDiseaseData(
          farmId: farmId,
          jwt: token,
          farmerPhone: farmerPhone,
          farmerId: farmerId,
        );
        zones = _normalizeIssueRowsForMap(diseaseData.scoutZones);
        cells = _normalizeIssueRowsForMap(diseaseData.riskCells);
      } else {
        zones = await _satelliteService.getDiseaseScoutZones(
          farmId: farmId,
          jwt: token,
        );
        cells = await _satelliteService.getDiseaseRiskCells(
          farmId: farmId,
          jwt: token,
        );
        zones = _normalizeIssueRowsForMap(zones);
        cells = _normalizeIssueRowsForMap(cells);
      }
      if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
      setState(() {
        _diseaseScoutZonesByFarmIndex[index] = zones;
        _diseaseRiskCellsByFarmIndex[index] = cells;
        _diseaseRemoteLoadedAt[index] = DateTime.now();
      });
      if (runScreenIfEmpty &&
          cells.isEmpty &&
          _claimRiskScreenWarmup(index, farmKey)) {
        await _runDiseaseScreenForFarm(
          index,
          showFailureSnack: false,
          showInlineError: showAlertErrors,
        );
      }
    } catch (_) {
      if (!mounted) return;
      // Keep cached values on transient remote failures so the map keeps showing
      // the latest known disease result instead of dropping to an empty view.
      if (runScreenIfEmpty && _claimRiskScreenWarmup(index, farmKey)) {
        await _runDiseaseScreenForFarm(
          index,
          showFailureSnack: false,
          showInlineError: showAlertErrors,
        );
      }
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
        farmerPhone: _verifiedFarmerPhone(),
        farmerId: _verifiedFarmerId(),
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

  /// Issue locations for the farm map. After a refresh, use only the current
  /// screening cells; otherwise fall back to saved history rows.
  List<Map<String, dynamic>> _displayScoutZonesForFarm(int index) {
    if (_currentScoutZonesByFarmIndex.containsKey(index)) {
      return _currentScoutZonesByFarmIndex[index] ?? const [];
    }
    final rows = _diseaseScoutZonesByFarmIndex[index] ?? const [];
    return _latestIssueRowsForMap(rows);
  }

  List<Map<String, dynamic>> _displayRiskCellsForFarm(int index) {
    if (_currentRiskCellsByFarmIndex.containsKey(index)) {
      return _currentRiskCellsByFarmIndex[index] ?? const [];
    }
    final rows = _diseaseRiskCellsByFarmIndex[index] ?? const [];
    return _latestIssueRowsForMap(rows);
  }

  DiseaseScreenResult? _displayDiseaseScreenForFarm(int index) {
    return _currentDiseaseScreenByFarmIndex[index] ??
        _diseaseScreenByFarmIndex[index];
  }

  List<FarmIssueCell> _issueCellsForFarm(int index) {
    final rows = _displayRiskCellsForFarm(index);
    final normalizedRows = _normalizeIssueRowsForMap(rows);
    if (normalizedRows.isEmpty) {
      return _displayDiseaseScreenForFarm(index)?.riskCells ??
          const <FarmIssueCell>[];
    }

    var parsedCells = _latestIssueRowsForMap(normalizedRows)
        .map(FarmIssueCell.fromJson)
        .where((cell) => cell.hasLocation)
        .toList(growable: false);
    if (parsedCells.isNotEmpty) return parsedCells;

    return _displayDiseaseScreenForFarm(index)?.riskCells ??
        const <FarmIssueCell>[];
  }

  double _diseaseMaxRiskForFarm(int index) {
    final summaryRisk = _farmSummaryByFarmIndex[index]?.maxDiseaseRisk;
    final screen = _displayDiseaseScreenForFarm(index);
    if (!_currentDiseaseScreenByFarmIndex.containsKey(index) &&
        summaryRisk != null &&
        summaryRisk > 0) {
      return summaryRisk;
    }
    if (screen == null) return 0;
    var maxRisk = 0.0;
    for (final value in screen.topDiseaseRisks.values) {
      maxRisk = math.max(maxRisk, value);
    }
    for (final cell in screen.riskCells) {
      maxRisk = math.max(maxRisk, cell.compositeRisk);
    }
    return maxRisk;
  }

  bool _hasRiskSignalData(FarmIssueCell issue) {
    return issue.ndvi != null ||
        issue.moisture != null ||
        issue.weatherRisk != null ||
        issue.perDisease.isNotEmpty;
  }

  double? _scoutZoneRadiusMetersForIssue(int index, FarmIssueCell issue) {
    if (!issue.hasLocation) return null;
    final origin = LatLng(issue.lat, issue.lng);
    for (final row in _displayScoutZonesForFarm(index)) {
      final point = _readIssuePoint(row);
      if (point == null) continue;
      final distance = const Distance().as(LengthUnit.Meter, origin, point);
      if (distance > 8) continue;
      return _snapshotDouble(row['radius_meters']) ??
          _snapshotDouble(row['radius']) ??
          _snapshotDouble(row['radius_m']);
    }
    return null;
  }

  FarmIssueCell? _nearestSignalCellForIssue(int index, FarmIssueCell issue) {
    if (!issue.hasLocation) return null;
    final candidates = <FarmIssueCell>[];

    void addCandidate(FarmIssueCell cell) {
      if (!cell.hasLocation || !_hasRiskSignalData(cell)) return;
      candidates.add(cell);
    }

    for (final row in _displayRiskCellsForFarm(index)) {
      addCandidate(FarmIssueCell.fromJson(row));
    }
    for (final cell
        in _displayDiseaseScreenForFarm(index)?.riskCells ??
            const <FarmIssueCell>[]) {
      addCandidate(cell);
    }
    if (candidates.isEmpty) return null;

    final origin = LatLng(issue.lat, issue.lng);
    final maxDistance = issue.isScoutZone
        ? (_scoutZoneRadiusMetersForIssue(index, issue) ?? 120) + 45
        : 20.0;
    FarmIssueCell? nearest;
    var nearestDistance = double.infinity;
    for (final candidate in candidates) {
      final distance = const Distance().as(
        LengthUnit.Meter,
        origin,
        LatLng(candidate.lat, candidate.lng),
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = candidate;
      }
    }
    return nearestDistance <= maxDistance ? nearest : null;
  }

  FarmIssueCell _issueWithFarmSignalFallback(int index, FarmIssueCell issue) {
    final fallback = _nearestSignalCellForIssue(index, issue);
    if (fallback == null) return issue;
    return FarmIssueCell(
      lat: issue.lat,
      lng: issue.lng,
      compositeRisk: math.max(issue.compositeRisk, fallback.compositeRisk),
      diseaseCandidates: issue.diseaseCandidates.isNotEmpty
          ? issue.diseaseCandidates
          : fallback.diseaseCandidates,
      likelyAbiotic:
          issue.likelyAbiotic ||
          (issue.diseaseCandidates.isEmpty && fallback.likelyAbiotic),
      perDisease: issue.perDisease.isNotEmpty
          ? issue.perDisease
          : fallback.perDisease,
      ndvi: issue.ndvi ?? fallback.ndvi,
      moisture: issue.moisture ?? fallback.moisture,
      weatherRisk: issue.weatherRisk ?? fallback.weatherRisk,
      isScoutZone: issue.isScoutZone,
    );
  }

  void _openFarmIssue(int index, FarmIssueCell issue) {
    if (index < 0 || index >= _farms.length) return;
    _initializeFarmState(index);
    _refreshFarmStage(index);
    final farm = _farms[index];
    final displayIssue = _issueWithFarmSignalFallback(index, issue);
    _FarmIssueSheet issuePage({required bool fullScreen}) => _FarmIssueSheet(
      farmName: farm.name,
      issue: displayIssue,
      farmCenter: _farmCenter(farm),
      daysAfterSowing: _daysAfterSowing(index),
      growthStage: _farmGrowthStage[index] ?? _farmLifecycleStages.first,
      weatherContext:
          _farmSummaryByFarmIndex[index]?.weatherContext ??
          _displayDiseaseScreenForFarm(index)?.weatherContext,
      fetchGuidance: () => _fetchIssueGuidance(index, displayIssue),
      captureAndDiagnose: (source) =>
          _captureAndDiagnoseIssuePhoto(index, displayIssue, source),
      recordAction:
          ({
            required FarmIssueCell issue,
            required String action,
            FarmPhotoDiagnosis? diagnosis,
          }) => _recordFarmIssueAction(
            index: index,
            issue: issue,
            action: action,
            diagnosis: diagnosis,
          ),
      fullScreen: fullScreen,
    );

    if (displayIssue.compositeRisk >= 0.55) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/FarmIssueDetailPage'),
          builder: (_) => issuePage(fullScreen: true),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => issuePage(fullScreen: false),
    );
  }

  Future<FarmAlertAdvice> _fetchIssueGuidance(
    int index,
    FarmIssueCell issue,
  ) async {
    final farm = _farms[index];
    final farmId = await _resolveSatelliteFarmId(farm, index);
    final diseaseScreen = _displayDiseaseScreenForFarm(index);
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
    final canUsePhoto = await PolicyDisclosureService.confirmPhotoUse(context);
    if (!canUsePhoto) return null;

    final shot = await pickHarvestMachineImage(source: source);
    if (shot == null) return null;
    final farm = _farms[index];
    final farmId = await _resolveSatelliteFarmId(farm, index);
    if (farmId.isEmpty) {
      throw SatelliteApiException(UiStrings.t('farm_not_synced_satellite'));
    }
    final diseaseSpotted = issue.diseaseCandidates.isEmpty
        ? UiStrings.t('suspected_disease')
        : issue.diseaseCandidates
              .map((item) => UiStrings.option(item.replaceAll('_', ' ')))
              .join(', ');
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
        'growth_stage': _farmGrowthStage[index] ?? _growthStageForFarm(index),
        'disease_spotted': diseaseSpotted,
        'description':
            '$diseaseSpotted near ${LocaleText.number(issue.lat, fractionDigits: 5)}, ${LocaleText.number(issue.lng, fractionDigits: 5)}',
        'satellite_context': issue.toJson(),
        'satellite_monitoring': {
          'composite_risk': issue.compositeRisk,
          if (issue.ndvi != null) 'ndvi': issue.ndvi,
          if (issue.moisture != null) 'moisture': issue.moisture,
          if (issue.weatherRisk != null) 'weather_risk': issue.weatherRisk,
        },
      },
    );
  }

  Future<void> _recordFarmIssueAction({
    required int index,
    required FarmIssueCell issue,
    required String action,
    FarmPhotoDiagnosis? diagnosis,
  }) async {
    final farm = _farms[index];
    final farmId = await _resolveSatelliteFarmId(farm, index);
    if (farmId.isEmpty) {
      throw SatelliteApiException(UiStrings.t('farm_not_synced_satellite'));
    }
    await _satelliteService.insertFarmIssueAction(
      jwt: _satelliteRequestToken(),
      farmerPhone: _verifiedFarmerPhone(),
      farmerId: _verifiedFarmerId(),
      payload: {
        'farm_id': farmId,
        'action': action,
        'status': action == 'visited' ? 'visited' : 'photo_checked',
        'issue_lat': issue.lat,
        'issue_lng': issue.lng,
        'risk_score': issue.compositeRisk,
        'crop': _diseaseCropForFarm(farm),
        'growth_stage': _farmGrowthStage[index] ?? _growthStageForFarm(index),
        'issue_snapshot': issue.toJson(),
        if (diagnosis != null)
          'photo_diagnosis_result': {
            'diagnosis': diagnosis.diagnosis,
            'confidence': diagnosis.confidence,
            'severity': diagnosis.severity,
            'differential': diagnosis.differential,
            'evidence': diagnosis.evidence,
            'scout_action': diagnosis.scoutAction,
            if (diagnosis.model != null) 'model': diagnosis.model,
          },
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

  String _alertRefreshMessage(Object error) {
    final raw = error.toString().replaceFirst('SatelliteApiException: ', '');
    final normalized = raw.toLowerCase();
    if (_looksLikeNetworkRefreshError(error)) {
      return UiStrings.t('network_issue_error');
    }
    if (normalized.contains('farm geometry required') ||
        normalized.contains('geometry')) {
      return UiStrings.t('farm_boundary_required_refresh');
    }
    if (normalized.contains('remote farm id') ||
        normalized.contains('farm_id')) {
      return UiStrings.t('farm_sync_incomplete_retry');
    }
    if (normalized.contains('farm not found for this farmer') ||
        normalized.contains('not linked to that farmer number') ||
        normalized.contains('farm is not synced')) {
      return UiStrings.t('farm_sync_incomplete_retry');
    }
    if (normalized.contains('auth token') || normalized.contains('401')) {
      return UiStrings.t('farmer_session_expired_refresh');
    }
    if (normalized.contains('disease-risk-screen failed') ||
        normalized.contains('disease risk scan failed')) {
      return UiStrings.t('disease_screening_failed_retry');
    }
    return raw.isEmpty ? UiStrings.t('alert_refresh_failed_retry') : raw;
  }

  bool _looksLikeNetworkRefreshError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socket') ||
        text.contains('network') ||
        text.contains('connection') ||
        text.contains('failed host lookup') ||
        text.contains('clientexception') ||
        text.contains('xmlhttprequest') ||
        text.contains('timeout') ||
        text.contains('connection closed') ||
        text.contains('network is unreachable');
  }

  bool _hasDiseaseRefreshCache(int index) {
    if (index < 0 || index >= _farms.length) return false;
    return (_diseaseRiskCellsByFarmIndex[index]?.isNotEmpty ?? false) ||
        (_currentRiskCellsByFarmIndex[index]?.isNotEmpty ?? false) ||
        (_diseaseScoutZonesByFarmIndex[index]?.isNotEmpty ?? false) ||
        (_currentScoutZonesByFarmIndex[index]?.isNotEmpty ?? false) ||
        _displayDiseaseScreenForFarm(index) != null ||
        _farmAlertAdviceByFarmIndex[index] != null;
  }

  bool _hasDiseaseScanStateForFarm(int index) {
    if (index < 0 || index >= _farms.length) return false;
    final screen = _displayDiseaseScreenForFarm(index);
    if (screen != null &&
        (screen.scanDate.trim().isNotEmpty ||
            screen.imagesAnalyzed > 0 ||
            screen.riskCellsCount > 0 ||
            screen.riskCells.isNotEmpty ||
            screen.scoutZones.isNotEmpty)) {
      return true;
    }
    return (_displayRiskCellsForFarm(index).isNotEmpty ||
        _displayScoutZonesForFarm(index).isNotEmpty);
  }

  Map<String, dynamic>? _farmGeometryJson(_FarmerFarm farm) {
    final ring = farm.polygon;
    if (ring == null || ring.length < 3) return null;
    return {
      'type': 'Polygon',
      'coordinates': [ring],
    };
  }

  Future<bool> _runDiseaseScreenForFarm(
    int index, {
    bool showFailureSnack = true,
    bool showInlineError = true,
    bool refreshSummaryAfter = true,
  }) async {
    if (index < 0 || index >= _farms.length) return false;
    if (_farmAlertLoading.contains(index)) return false;

    _initializeFarmState(index);
    _refreshFarmStage(index);
    setState(() {
      _farmAlertLoading.add(index);
      _farmAlertErrorByFarmIndex.remove(index);
    });

    try {
      final farm = _farms[index];
      final token = _satelliteRequestToken();
      final farmerPhone = _verifiedFarmerPhone();
      final farmerId = _verifiedFarmerId();
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
        jwt: token,
        farmerPhone: farmerPhone,
        farmerId: farmerId,
      );

      var zones = _normalizeIssueRowsForMap(diseaseScreen.scoutZones);
      var cells = _normalizeIssueRowsForMap(
        diseaseScreen.riskCells
            .map((cell) => cell.toJson())
            .toList(growable: false),
      );
      if (cells.isEmpty && diseaseScreen.riskCellsCount > 0) {
        try {
          late List<Map<String, dynamic>> fallbackCells;
          if (farmerPhone != null) {
            final diseaseData = await _satelliteService.getFarmerDiseaseData(
              farmId: farmId,
              jwt: token,
              farmerPhone: farmerPhone,
              farmerId: farmerId,
            );
            if (zones.isEmpty) {
              zones = _latestIssueRowsForMap(
                _normalizeIssueRowsForMap(diseaseData.scoutZones),
              );
            }
            fallbackCells = diseaseData.riskCells;
          } else {
            fallbackCells = await _satelliteService.getDiseaseRiskCells(
              farmId: farmId,
              jwt: token,
            );
          }
          final latestCells = _latestIssueRowsForMap(
            _normalizeIssueRowsForMap(fallbackCells),
          );
          if (latestCells.isNotEmpty) {
            cells = latestCells;
          }
        } catch (_) {
          // Keep the current scan count even if the saved-cell read is delayed.
        }
      }

      var advisorWeatherContext = diseaseScreen.weatherContext;
      try {
        final center = _farmCenter(farm);
        final liveWeather = await _satelliteService.getLiveWeather(
          latitude: center.latitude,
          longitude: center.longitude,
          crop: crop,
          growthStage: growthStage,
          daysAfterSowing: _daysAfterSowing(index),
          satelliteMoisture: _satelliteOverviewByFarmIndex[index]?.moisture,
          jwt: token,
        );
        advisorWeatherContext = {
          ...?diseaseScreen.weatherContext,
          'live_current': liveWeather.current,
          'water_stress': liveWeather.waterStress,
          'crop_health_weather': liveWeather.cropHealthWeather,
          'agro_weather': liveWeather.agroWeather,
          'source': liveWeather.source,
          'updated_at': liveWeather.updatedAt,
        };
      } catch (_) {
        // Advisor can still use disease-screen weather context.
      }

      FarmAlertAdvice? advice;
      Object? advisorError;
      try {
        advice = await _satelliteService.getFarmAlertAdvice(
          jwt: token,
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
            'risk_cells': cells.take(20).toList(growable: false),
            'weather_context': advisorWeatherContext,
          },
        );
      } catch (e) {
        advisorError = e;
      }

      if (!mounted) return false;
      setState(() {
        _farmSummaryByFarmIndex.remove(index);
        _satelliteOverviewByFarmIndex.remove(index);
        _diseaseScreenByFarmIndex[index] = diseaseScreen;
        _diseaseScoutZonesByFarmIndex[index] = zones;
        _diseaseRiskCellsByFarmIndex[index] = cells;
        _diseaseRemoteLoadedAt[index] = DateTime.now();
        _currentDiseaseScreenByFarmIndex[index] = diseaseScreen;
        _currentScoutZonesByFarmIndex[index] = zones;
        _currentRiskCellsByFarmIndex[index] = cells;
        if (advice != null) {
          _farmAlertAdviceByFarmIndex[index] = advice;
        }
        _farmAlertErrorByFarmIndex.remove(index);
      });
      if (refreshSummaryAfter) {
        unawaited(_loadFarmSummaryForFarm(index, updateDiseaseRows: false));
      }
      final currentRiskCellCount =
          diseaseScreen.riskCellsCount > 0 || cells.isEmpty
          ? diseaseScreen.riskCellsCount
          : cells.length;
      final refreshMessage = advisorError == null
          ? UiStrings.f('issue_cells_available', {
              'farm': farm.name,
              'count': currentRiskCellCount,
              'label': UiStrings.t(
                currentRiskCellCount == 1 ? 'cell' : 'cells',
              ),
            })
          : UiStrings.t('advisor_refresh_failed_preserved');
      final maxRisk = cells.fold<double>(0, (current, row) {
        final raw =
            row['composite_risk'] ?? row['max_risk_score'] ?? row['risk_score'];
        final value = raw is num
            ? raw.toDouble()
            : (double.tryParse('$raw') ?? 0);
        return math.max(current, value);
      });
      unawaited(
        _saveFarmDataSnapshotForFarm(index, source: 'farm_alert_refresh'),
      );
      if (maxRisk >= 0.55) {
        unawaited(
          _createSelectedFarmNotification(
            index: index,
            type: 'high_disease_risk',
            title: UiStrings.t('disease_risk'),
            message: refreshMessage,
            stage: growthStage,
            source: 'farm_alert_advisor',
            payload: {
              'farm_name': farm.name,
              'crop': crop,
              'growth_stage': growthStage,
              'risk_cells': currentRiskCellCount,
              'scout_zones': zones.length,
              'max_risk': maxRisk,
              'advisor_status': advisorError == null
                  ? 'available'
                  : 'preserved',
            },
            showPopup: false,
          ),
        );
      }
      FarmAlertItem? urgentAlert;
      if (advice != null) {
        for (final alert in [
          ...advice.importantAlerts,
          ...advice.weatherAlerts,
        ]) {
          final severity = alert.severity.trim().toLowerCase();
          if (severity == 'high' ||
              severity == 'urgent' ||
              severity == 'critical') {
            urgentAlert = alert;
            break;
          }
        }
      }
      if (urgentAlert != null) {
        final detail = [
          urgentAlert.detail,
          urgentAlert.action,
        ].where((part) => part.trim().isNotEmpty).join(' ');
        unawaited(
          _createSelectedFarmNotification(
            index: index,
            type: 'urgent_farm_alert',
            title: urgentAlert.title,
            message: detail.isEmpty ? urgentAlert.title : detail,
            stage: growthStage,
            source: 'farm_alert_advisor',
            payload: {
              'farm_name': farm.name,
              'crop': crop,
              'growth_stage': growthStage,
              'max_risk': maxRisk,
              'alert': urgentAlert.toJson(),
            },
            showPopup: false,
          ),
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      if (_looksLikeNetworkRefreshError(e) && _hasDiseaseRefreshCache(index)) {
        if (showInlineError) {
          setState(() => _farmAlertErrorByFarmIndex.remove(index));
        }
        return true;
      }
      final message = _alertRefreshMessage(e);
      if (showInlineError) {
        setState(() {
          _farmAlertErrorByFarmIndex[index] = message;
        });
      }
      if (showFailureSnack) {
        Get.snackbar(
          UiStrings.t('alert_refresh_failed'),
          message,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _farmAlertLoading.remove(index));
      }
    }
  }

  String _stageSummary(int index) {
    _refreshFarmStage(index);
    final stage = _farmGrowthStage[index] ?? _farmLifecycleStages.first;
    final days = _daysAfterSowing(index);
    final note = _farmStatusAnswer[index] ?? UiStrings.t('not_updated');
    final updatedAt = _farmStatusUpdatedAt[index];
    if (updatedAt == null) return '${UiStrings.option(stage)} • $note';
    return '${UiStrings.f('cycle_summary_day', {'day': days})} • ${UiStrings.option(stage)} • $note • ${_formatTime(updatedAt)}';
  }

  Future<void> _openAddFarmSheet({bool silentAutoSync = false}) async {
    final setupResult = await Get.to<FarmSetupChatResult>(
      () => const FarmerFarmSetupChatScreen(),
    );
    if (setupResult == null) return;

    final polygonPoints = _polygonPointsFromRing(setupResult.polygon);
    _showFirstFarmLoadOverlay(
      title: UiStrings.t('first_farm_loading_title'),
      message: UiStrings.t('first_farm_saving_remote'),
    );
    final savedFarm = await _saveFarmToRemote(
      setupResult,
      polygonPoints,
      showSnackbars: false,
      waitForRemoteConfirmation: true,
    );
    if (savedFarm == null) {
      final farmCtrl = Get.isRegistered<FarmController>()
          ? Get.find<FarmController>()
          : null;
      final reason = farmCtrl?.lastSaveErrorMessage.value.trim();
      final debugReason = [
        if (reason != null && reason.isNotEmpty) reason,
        if (reason == null || reason.isEmpty)
          'No farm row was returned. Points: ${polygonPoints.length}. Area: ${PolygonGeometry.areaHectares(polygonPoints).toStringAsFixed(4)} ha.',
      ].join('\n');
      await _showFirstFarmLoadFailure(debugReason);
      return;
    }

    if (!mounted) return;
    _showFirstFarmLoadOverlay(
      title: UiStrings.t('first_farm_loading_title'),
      message: UiStrings.t('first_farm_loading_remote'),
    );
    final quietFarmId = savedFarm.id.trim();
    if (quietFarmId.isNotEmpty) {
      _quietInitialAlertFarmIds.add(quietFarmId);
    }
    final activeIndex = await _loadSavedFirstFarmIntoApp(
      savedFarm: savedFarm,
      setupResult: setupResult,
    );
    var visibleFarmIndex = activeIndex;
    if (visibleFarmIndex == null) {
      _quietInitialAlertFarmIds.remove(quietFarmId);
      visibleFarmIndex = _activateSavedFarmImmediately(
        savedFarm,
        setupResult,
        warmMonitoring: false,
      );
    }
    if (visibleFarmIndex == null) {
      _hideFirstFarmLoadOverlay();
      await _markFirstFarmGuideSeen();
      _firstFarmTutorialShown = true;
      _firstFarmTutorialOpen = false;
      return;
    }

    _showFirstFarmLoadOverlay(
      title: UiStrings.t('initial_farm_sync_title'),
      message: UiStrings.t('initial_farm_sync_message'),
    );
    final servicesReady = await _syncNewFarmServicesBeforeOpen(
      index: visibleFarmIndex,
      farmId: savedFarm.id,
    );
    if (!servicesReady) {
      _quietInitialAlertFarmIds.remove(quietFarmId);
      _hideFirstFarmLoadOverlay();
      await _markFirstFarmGuideSeen();
      _firstFarmTutorialShown = true;
      _firstFarmTutorialOpen = false;
      unawaited(
        _warmNewFarmMonitoring(
          index: visibleFarmIndex,
          farmId: savedFarm.id,
          clearFirst: false,
          showAlertErrors: false,
        ),
      );
      return;
    }
    _hideFirstFarmLoadOverlay();
    await _markFirstFarmGuideSeen();
    _firstFarmTutorialShown = true;
    _firstFarmTutorialOpen = false;
    unawaited(
      _sendFarmAddedNotification(
        visibleFarmIndex,
        showPopup: !silentAutoSync,
        mirrorLocalNotification: !silentAutoSync,
      ),
    );
  }

  int? _activateSavedFarmImmediately(
    Farm savedFarm,
    FarmSetupChatResult setupResult, {
    bool warmMonitoring = true,
  }) {
    if (!mounted) return null;
    _initializeFarmerStateFromSession(shouldSetState: false);

    var activeIndex = _indexForRemoteFarmId(savedFarm.id);
    if (activeIndex == null) {
      final localFarm = _farmerFarmWithSetupMetadata(
        _farmerFarmFromRemoteRecord(savedFarm),
        setupResult,
      );
      final existingIndex = _farms.indexWhere(
        (farm) => farm.remoteFarmId == savedFarm.id,
      );
      if (existingIndex >= 0) {
        _farms[existingIndex] = localFarm;
        activeIndex = existingIndex;
      } else {
        _farms.add(localFarm);
        activeIndex = _farms.length - 1;
      }
    } else if (activeIndex >= 0 && activeIndex < _farms.length) {
      _farms[activeIndex] = _farmerFarmWithSetupMetadata(
        _farms[activeIndex],
        setupResult,
      );
    }

    final selectedIndex = activeIndex;
    if (selectedIndex < 0 || selectedIndex >= _farms.length) {
      return null;
    }
    _satelliteFarmIdByFarmIndex[selectedIndex] = savedFarm.id;
    _upsertSatelliteFarmCatalog(savedFarm);
    setState(() {
      _selectedFarm = selectedIndex;
      _clearMonitoringStateForFarmIndex(selectedIndex);
      _initializeFarmState(selectedIndex);
      _farmSowingDate[selectedIndex] = setupResult.sowingDate;
      _refreshFarmStage(selectedIndex);
      _index = _farmTabIndex;
    });
    _syncSelectedRemoteFarmFromIndex();
    if (warmMonitoring) {
      unawaited(
        _warmNewFarmMonitoring(
          index: selectedIndex,
          farmId: savedFarm.id,
          clearFirst: false,
        ),
      );
    }
    return selectedIndex;
  }

  Future<int?> _loadSavedFirstFarmIntoApp({
    required Farm savedFarm,
    required FarmSetupChatResult setupResult,
  }) async {
    final farmId = savedFarm.id.trim();
    if (farmId.isEmpty || !Get.isRegistered<FarmController>()) return null;

    Farm? confirmedFarm;
    try {
      confirmedFarm = await Get.find<FarmController>().syncSavedFarmFromRemote(
        farmId,
        timeout: const Duration(seconds: 6),
        retryHttpErrors: true,
        requireRemoteConfirmation: true,
      );
    } catch (error) {
      Get.log('Saved farm reload before opening failed: $error');
      return null;
    }
    if (!mounted || confirmedFarm == null) return null;
    if (confirmedFarm.id.trim() != farmId ||
        !_remoteFarmHasMarkedBoundary(confirmedFarm)) {
      Get.log('Saved farm remote confirmation missing boundary: $farmId');
      return null;
    }

    _initializeFarmerStateFromSession(shouldSetState: false);
    var selectedIndex = _indexForRemoteFarmId(farmId);
    if (selectedIndex == null) {
      selectedIndex = _activateSavedFarmImmediately(
        confirmedFarm,
        setupResult,
        warmMonitoring: false,
      );
    } else if (selectedIndex >= 0 && selectedIndex < _farms.length) {
      _farms[selectedIndex] = _farmerFarmWithSetupMetadata(
        _farms[selectedIndex],
        setupResult,
      );
    }
    if (!mounted || selectedIndex == null) return null;
    if (selectedIndex < 0 || selectedIndex >= _farms.length) return null;
    final confirmedIndex = selectedIndex;
    if (_farms[confirmedIndex].remoteFarmId.trim() != farmId ||
        !_farmerFarmHasMarkedBoundary(_farms[confirmedIndex])) {
      Get.log('Saved farm local selection missing boundary: $farmId');
      return null;
    }

    _satelliteFarmIdByFarmIndex[confirmedIndex] = farmId;
    _upsertSatelliteFarmCatalog(confirmedFarm);
    setState(() {
      _selectedFarm = confirmedIndex;
      _clearMonitoringStateForFarmIndex(confirmedIndex);
      _index = _farmTabIndex;
      _initializeFarmState(confirmedIndex);
      _farmSowingDate[confirmedIndex] = setupResult.sowingDate;
      _refreshFarmStage(confirmedIndex);
      _applyRemoteFarmStatusFields(confirmedIndex);
    });
    _syncSelectedRemoteFarmFromIndex();
    return confirmedIndex;
  }

  Future<bool> _syncNewFarmServicesBeforeOpen({
    required int index,
    required String farmId,
  }) async {
    if (!mounted || _farms.isEmpty) return false;
    final normalizedFarmId = farmId.trim();
    if (normalizedFarmId.isEmpty) return false;
    final activeIndex = _indexForRemoteFarmId(normalizedFarmId) ?? index;
    if (activeIndex < 0 || activeIndex >= _farms.length) return false;
    final activeFarm = _farms[activeIndex];
    if (activeFarm.remoteFarmId.trim() != normalizedFarmId ||
        !_farmerFarmHasMarkedBoundary(activeFarm)) {
      Get.log('New farm service sync blocked until farm boundary is synced.');
      return false;
    }
    setState(() {
      _selectedFarm = activeIndex;
      _clearMonitoringStateForFarmIndex(activeIndex);
      _satelliteFarmIdByFarmIndex[activeIndex] = normalizedFarmId;
      _initializeFarmState(activeIndex);
      _applyRemoteFarmStatusFields(activeIndex);
      _initialFarmServiceReadyKey = null;
      _initialFarmServiceSyncError = false;
      _index = _farmTabIndex;
    });
    _syncSelectedRemoteFarmFromIndex();
    final key = _initialFarmServiceSyncKey(activeIndex);
    if (key == null) return false;
    final ready = await _syncInitialFarmServicesForFarm(
      activeIndex,
      key,
      requireDiseaseScan: true,
    );
    if (ready) {
      _quietInitialAlertFarmIds.remove(normalizedFarmId);
    }
    return ready;
  }

  void _upsertSatelliteFarmCatalog(Farm savedFarm) {
    final existingIndex = _satelliteFarmCatalog.indexWhere(
      (farm) => farm.id == savedFarm.id,
    );
    if (existingIndex >= 0) {
      _satelliteFarmCatalog[existingIndex] = savedFarm;
    } else {
      _satelliteFarmCatalog.insert(0, savedFarm);
    }
    _satelliteFarmCatalogLoaded = true;
  }

  Future<Farm?> _saveFarmToRemote(
    FarmSetupChatResult setupResult,
    List<LatLng> polygonPoints, {
    bool showSnackbars = true,
    bool waitForRemoteConfirmation = false,
  }) async {
    if (!Get.isRegistered<FarmController>()) {
      final message =
          'Farm service is not ready. Reopen farmer home and try again.';
      if (showSnackbars) {
        Get.snackbar(
          UiStrings.t('could_not_save_farm'),
          message,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      Get.put(FarmController()).lastSaveErrorMessage.value = message;
      return null;
    }
    if (polygonPoints.length < 3) {
      final message =
          'Farm boundary did not return enough points. Points: ${polygonPoints.length}. Draw at least 3 corners and tap Confirm.';
      if (showSnackbars) {
        Get.snackbar(
          UiStrings.t('too_few_points'),
          message,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      Get.find<FarmController>().lastSaveErrorMessage.value = message;
      return null;
    }
    final farmCtrl = Get.find<FarmController>();
    final savedFarm = await farmCtrl.saveFarmRecord(
      name: setupResult.farmName,
      points: polygonPoints,
      showSnackbars: showSnackbars,
      waitForRemoteConfirmation: waitForRemoteConfirmation,
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
        'sowing_date': _dateOnlyIso(setupResult.sowingDate),
      },
    );
    if (savedFarm != null) {
      farmCtrl.selectFarm(savedFarm);
    }
    return savedFarm;
  }

  List<LatLng> _polygonPointsFromRing(List<List<double>> ring) {
    return ring
        .where((point) => point.length >= 2)
        .map((point) => LatLng(point[1], point[0]))
        .toList();
  }

  String _formatLocationFromPoints(LatLng? point) {
    if (point == null) return UiStrings.t('map_marked_farm');
    return '${LocaleText.number(point.latitude, fractionDigits: 5)}, ${LocaleText.number(point.longitude, fractionDigits: 5)}';
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
        stageQuestion: _statusQuestionForFarm(index, currentStage),
        lifecycleContext: _lifecycleContextForFarm(index),
        priorStatus: _farmStatusAnswer[index],
        requiresPhoto: requiresPhoto,
      ),
    );

    if (result == null) return;

    final previousStatus = _farmStatusAnswer[index];
    final farmerPhone = _verifiedFarmerPhone();
    final farmerId = _verifiedFarmerId();
    if (farmerPhone == null || farmerPhone.trim().isEmpty) {
      Get.snackbar(
        UiStrings.t('login_required'),
        UiStrings.t('farm_link_login_required'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    var syncedAt = result.updatedAt;
    var activeIndex = index;
    var activeFarm = farm;
    FarmTimelineEvent? savedTimelineEvent;
    var savedFarmId = '';
    try {
      final farmId = await _resolveSatelliteFarmId(farm, index);
      if (farmId.isEmpty) {
        throw SatelliteApiException('Remote farm id not found');
      }
      savedFarmId = farmId;
      final response = await _satelliteService.saveFarmStatusUpdate(
        farmId: farmId,
        farmerPhone: farmerPhone,
        jwt: _satelliteRequestToken(),
        farmerId: farmerId,
        farmerName: _profile.name,
        farmName: farm.name,
        crop: farm.crop,
        variety: farm.variety,
        stage: currentStage,
        stageQuestion: result.question,
        daysAfterSowing: daysAfterSowing,
        statusText: result.message,
        priorStatus: previousStatus,
      );
      final farmStatus = response['farm'];
      final updatedAt = farmStatus is Map
          ? DateTime.tryParse(
              '${farmStatus['current_status_updated_at'] ?? ''}',
            )
          : null;
      if (updatedAt != null) {
        syncedAt = updatedAt;
      }
      final timelineRaw = response['timeline_event'];
      if (timelineRaw is Map) {
        savedTimelineEvent = FarmTimelineEvent.fromJson(
          Map<String, dynamic>.from(timelineRaw),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        UiStrings.t('error'),
        _statusSaveErrorMessage(e),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      if (Get.isRegistered<FarmController>()) {
        Get.find<FarmController>().invalidateFarmCache();
      }
      activeIndex = await _refreshFarmsFromCloudAndSelect(
        farmId: savedFarmId,
        fallbackIndex: index,
      );
      if (_farms.isEmpty) {
        throw SatelliteApiException('Farm list refresh returned no farms');
      }
      if (activeIndex < 0 || activeIndex >= _farms.length) {
        activeIndex = index.clamp(0, _farms.length - 1).toInt();
      }
      activeFarm = _farms[activeIndex];
    } catch (e) {
      activeIndex = _indexForRemoteFarmId(savedFarmId) ?? index;
      if (_farms.isNotEmpty) {
        activeIndex = activeIndex.clamp(0, _farms.length - 1).toInt();
        activeFarm = _farms[activeIndex];
      }
      if (mounted) {
        Get.snackbar(
          UiStrings.t('status_updated'),
          UiStrings.t('status_saved_sync_pending'),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }

    setState(() {
      _farms[activeIndex] = activeFarm.copyWithStatus(
        currentStatus: result.message,
        currentStatusStage: currentStage,
        currentStatusUpdatedAt: syncedAt,
      );
      _farmGrowthStage[activeIndex] = currentStage;
      _farmStatusAnswer[activeIndex] = result.message;
      _farmStatusUpdatedAt[activeIndex] = syncedAt;
      if (savedTimelineEvent != null) {
        final event = savedTimelineEvent;
        final existing =
            _farmTimelineByFarmIndex[activeIndex] ??
            const <FarmTimelineEvent>[];
        _farmTimelineByFarmIndex[activeIndex] = [
          event,
          ...existing.where((item) => item.id != event.id),
        ];
      }
      if (result.photoBytes == null) {
        _farmStatusPhotoBytes.remove(activeIndex);
        _farmStatusPhotoName[activeIndex] = '';
      } else {
        _farmStatusPhotoBytes[activeIndex] = result.photoBytes;
        _farmStatusPhotoName[activeIndex] =
            result.photoName ??
            'field-status-${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
    });

    _ensureSelectedFarmSnapshotForFarm(activeIndex, forceRefresh: true);
    unawaited(_loadFarmTimelineForFarm(activeIndex));

    unawaited(
      _sendFarmStatusNotification(
        farm: activeFarm,
        index: activeIndex,
        stage: currentStage,
        statusText: result.message,
      ),
    );
  }

  String _statusSaveErrorMessage(Object error) {
    final raw = error.toString().replaceFirst('SatelliteApiException: ', '');
    final normalized = raw.toLowerCase();
    if (normalized.contains('remote farm id') ||
        normalized.contains('farm_id') ||
        normalized.contains('farm not found') ||
        normalized.contains('not linked to that farmer number') ||
        normalized.contains('not linked to this farm owner')) {
      return UiStrings.t('farm_sync_incomplete_retry');
    }
    if (normalized.contains('auth token') ||
        normalized.contains('invalid auth') ||
        normalized.contains('401')) {
      return UiStrings.t('farmer_session_expired_refresh');
    }
    if (normalized.contains('internet') ||
        normalized.contains('network') ||
        normalized.contains('connection') ||
        normalized.contains('timeout')) {
      return UiStrings.t('status_saved_sync_pending_body');
    }
    return raw.trim().isEmpty
        ? UiStrings.t('status_saved_sync_pending_body')
        : raw.trim();
  }

  Future<FarmerNotification?> _createSelectedFarmNotification({
    required int index,
    required String type,
    required String title,
    required String message,
    String? stage,
    String? stageQuestion,
    int? daysAfterSowing,
    String? statusText,
    String? priorStatus,
    String source = 'farmer_dashboard_alert',
    Map<String, dynamic> payload = const {},
    bool showPopup = true,
    bool mirrorLocalNotification = true,
  }) async {
    if (index < 0 || index >= _farms.length) return null;
    final farmerId = _notificationFarmerId();
    if (farmerId.isEmpty) return null;
    final farmerPhone = _notificationFarmerPhone();
    final farm = _farms[index];
    try {
      final farmId = await _resolveSatelliteFarmId(farm, index);
      if (farmId.isEmpty) return null;
      final notification = await _farmerNotificationService
          .sendFarmAlertNotification(
            farmerId: farmerId,
            farmerName: _profile.name,
            farmerPhone: farmerPhone.isEmpty ? null : farmerPhone,
            farmId: farmId,
            farmName: farm.name,
            crop: farm.crop,
            variety: farm.variety,
            location: farm.location,
            type: type,
            title: title,
            message: message,
            stage: stage,
            stageQuestion: stageQuestion,
            daysAfterSowing: daysAfterSowing ?? _daysAfterSowing(index),
            statusText: statusText,
            priorStatus: priorStatus,
            source: source,
            payload: {
              'farm_id': farmId,
              'farm_name': farm.name,
              'crop': farm.crop,
              'variety': farm.variety,
              ...payload,
            },
            authToken: _satelliteRequestToken(),
          );
      if (notification == null) return null;
      if (mounted && showPopup) {
        Get.snackbar(
          notification.title,
          notification.message,
          snackPosition: SnackPosition.TOP,
        );
      }
      if (mirrorLocalNotification) {
        unawaited(
          LocalNotificationService.instance.showFarmerNotification(
            notification,
            fallbackTitle: title,
          ),
        );
      }
      return notification;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendFarmStatusNotification({
    required _FarmerFarm farm,
    required int index,
    required String stage,
    required String statusText,
  }) async {
    final title = UiStrings.f('farm_status_notification_title', {
      'farm': farm.name,
    });
    final stageLabel = UiStrings.option(stage);
    final message = statusText.trim().isEmpty
        ? UiStrings.f('farm_status_notification_message', {'stage': stageLabel})
        : '$stageLabel: $statusText';
    await _createSelectedFarmNotification(
      index: index,
      type: 'farm_status_update',
      title: title,
      message: message,
      stage: stage,
      stageQuestion: _statusQuestionForFarm(index, stage),
      daysAfterSowing: _daysAfterSowing(index),
      statusText: statusText,
      source: 'farmer_dashboard_status_chat',
      payload: {
        'farm_name': farm.name,
        'status_text': statusText,
        'growth_stage': stage,
      },
    );
  }

  Future<void> _sendFarmAddedNotification(
    int index, {
    bool showPopup = true,
    bool mirrorLocalNotification = true,
  }) async {
    if (index < 0 || index >= _farms.length) return;
    final farm = _farms[index];
    await _createSelectedFarmNotification(
      index: index,
      type: 'farm_added',
      title: UiStrings.f('farm_added_notification_title', {'farm': farm.name}),
      message: UiStrings.f('farm_added_notification_message', {
        'farm': farm.name,
      }),
      source: 'farmer_dashboard_add_farm',
      payload: {
        'farm_name': farm.name,
        'crop': farm.crop,
        'variety': farm.variety,
        'season': farm.season,
        'sowing_date': _farmSowingDate[index]?.toIso8601String(),
      },
      showPopup: showPopup,
      mirrorLocalNotification: mirrorLocalNotification,
    );
  }

  Future<void> _loadFarmTimelineForFarm(
    int index, {
    bool forceRefresh = false,
  }) async {
    if (index < 0 || index >= _farms.length) return;
    if (_farmTimelineLoading.contains(index)) {
      await _waitForFarmLoadToFinish(_farmTimelineLoading, index);
      if (!mounted || _farmTimelineLoading.contains(index)) return;
    }
    if (!forceRefresh &&
        _farmTimelineByFarmIndex.containsKey(index) &&
        _isFarmCacheFresh(
          _farmTimelineLoadedAt,
          index,
          _farmTimelineFreshFor,
        )) {
      return;
    }
    final farmerPhone = _verifiedFarmerPhone();
    if (farmerPhone == null) return;

    final farm = _farms[index];
    final farmKey = _farmStateKey(farm);
    setState(() => _farmTimelineLoading.add(index));
    try {
      final farmId = await _resolveSatelliteFarmId(farm, index);
      if (farmId.isEmpty) return;
      final events = await _satelliteService.listFarmTimelineEvents(
        farmId: farmId,
        farmerPhone: farmerPhone,
        jwt: _satelliteRequestToken(),
        farmerId: _verifiedFarmerId(),
      );
      if (!mounted || !_isSameFarmAtIndex(index, farmKey)) return;
      final visibleEvents = events
          .where(_isFarmerVisibleTimelineEvent)
          .toList(growable: false);
      setState(() {
        _farmTimelineByFarmIndex[index] = visibleEvents;
        _farmTimelineLoadedAt[index] = DateTime.now();
        _applyTimelineStatusFields(index, events);
      });
    } catch (_) {
      // Timeline refresh should not block the farm page.
    } finally {
      if (mounted) {
        setState(() => _farmTimelineLoading.remove(index));
      }
    }
  }

  Future<void> _openDiagnosisFlow(int index) async {
    _initializeFarmState(index);
    _refreshFarmStage(index);
    final farm = _farms[index];
    final issueCells = _issueCellsForFarm(index).toList(growable: false)
      ..sort((a, b) => b.compositeRisk.compareTo(a.compositeRisk));
    if (issueCells.isNotEmpty) {
      _openFarmIssue(index, issueCells.first);
      return;
    }
    final polygons = _farmBoundary(farm);
    final markers = List<LatLng>.from(
      _farmDiseaseMarkers[index] ?? const <LatLng>[],
    );
    final logs = List<String>.from(
      _farmDiagnosisLog[index] ?? const <String>[],
    );
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    String noteText = '';
    final question = _statusQuestionForFarm(index, _farmGrowthStage[index]!);
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        UiStrings.f('diagnose_farm', {'farm': farm.name}),
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
                        decoration: InputDecoration(
                          labelText: UiStrings.t('zone_note_label'),
                        ),
                        onChanged: (value) => noteText = value,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          final label = noteText.trim().isEmpty
                              ? UiStrings.t('suspected_disease')
                              : noteText.trim();
                          setSheet(() {
                            final marker = _nextDiseaseMarker(index, markers);
                            markers.add(marker);
                            logs.insert(
                              0,
                              '${_formatTime(DateTime.now())} • ${UiStrings.option(_farmGrowthStage[index] ?? '')} • $label',
                            );
                          });
                        },
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: Text(UiStrings.t('mark_disease_zone')),
                      ),
                      if (markers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          UiStrings.t('marked_zones'),
                          style: const TextStyle(
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
                              UiStrings.t('no_disease_zone_title'),
                              UiStrings.t('add_disease_marker_before_save'),
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
                                note: noteText.trim(),
                              ),
                            );
                          }
                          Navigator.pop(context, true);
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: Text(UiStrings.t('save_diagnosis')),
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
    if (result == true) {
      Get.snackbar(
        UiStrings.t('diagnosis_saved'),
        UiStrings.f('disease_zones_updated', {'farm': farm.name}),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _openFarmTab() {
    if (_guardFirstFarmSetup()) return;
    setState(() => _index = _farmTabIndex);
  }

  void _openAiChatTab() {
    if (_guardFirstFarmSetup()) return;
    setState(() => _index = _aiChatTabIndex);
  }

  void _openMarketPage() {
    if (_guardFirstFarmSetup()) return;
    final selectedFarmName =
        (_selectedFarm >= 0 && _selectedFarm < _farms.length)
        ? _farms[_selectedFarm].name
        : null;
    Get.to(
      () => ApmcMarketPage(
        inventoryLots: _marketLotPayloads(),
        farmName: selectedFarmName,
        onBottomNavSelected: _handleApmcBottomNav,
      ),
    );
  }

  void _handleApmcBottomNav(FarmerBottomNavItem item) {
    if (item == FarmerBottomNavItem.apmc) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleMobileNavTap(item);
    });
  }

  void _openNewsPage() {
    if (_guardFirstFarmSetup()) return;
    final hasFarm = _selectedFarm >= 0 && _selectedFarm < _farms.length;
    final farm = hasFarm ? _farms[_selectedFarm] : null;
    Get.to(() => NewsPage(farmName: farm?.name, farmLocation: farm?.location));
  }

  void _openWeatherPage() {
    if (_guardFirstFarmSetup()) return;
    final hasFarm = _selectedFarm >= 0 && _selectedFarm < _farms.length;
    final farm = hasFarm ? _farms[_selectedFarm] : null;
    final selectedIndex = _safeSelectedFarmIndex;
    final center = farm == null ? null : _selectedFarmWeatherCenter(farm);
    final overview = _satelliteOverviewByFarmIndex[selectedIndex];
    Get.to(
      () => WeatherPage(
        farmId: farm?.remoteFarmId,
        farmName: farm?.name,
        farmLocation: center == null
            ? farm?.location
            : _formatLocationFromPoints(center),
        crop: farm?.crop,
        growthStage: _farmGrowthStage[selectedIndex],
        daysAfterSowing: _daysAfterSowing(selectedIndex),
        latitude: center?.latitude,
        longitude: center?.longitude,
        satelliteMoisture: overview?.moisture,
        fallbackWeatherContext: _weatherContextForFarm(selectedIndex),
        initialSnapshot: _liveWeatherByFarmIndex[selectedIndex],
        onSnapshotLoaded: (snapshot) {
          if (!mounted || selectedIndex >= _farms.length) return;
          if (farm == null ||
              _farms[selectedIndex].remoteFarmId != farm.remoteFarmId) {
            return;
          }
          setState(() => _liveWeatherByFarmIndex[selectedIndex] = snapshot);
        },
      ),
    );
  }

  void _openSchemesPage() {
    if (_guardFirstFarmSetup()) return;
    final hasFarm = _selectedFarm >= 0 && _selectedFarm < _farms.length;
    final farm = hasFarm ? _farms[_selectedFarm] : null;
    Get.to(
      () => SchemesPage(farmName: farm?.name, farmLocation: farm?.location),
    );
  }

  Future<void> _openFarmMapInsight(int index) async {
    if (_guardFirstFarmSetup()) return;
    if (index < 0 || index >= _farms.length) return;
    _initializeFarmState(index);
    _refreshFarmStage(index);
    final farm = _farms[index];
    if (mounted && _selectedFarm != index) {
      setState(() => _selectedFarm = index);
    } else {
      _selectedFarm = index;
    }
    _syncSelectedRemoteFarmFromIndex();
    _applyRemoteFarmStatusFields(index);
    try {
      await _refreshSelectedFarmSnapshotForFarm(
        index,
        runRiskScreenIfEmpty: true,
      );
    } catch (_) {
      await _loadFarmTimelineForFarm(index, forceRefresh: true);
    }
    if (!mounted) return;
    final statusSnapshot = _statusSnapshotForFarm(index);
    final overview = _satelliteOverviewByFarmIndex[index];
    final isSatelliteLoading =
        _satelliteOverviewLoading.contains(index) ||
        _farmSummaryLoading.contains(index);
    Get.to(
      () => _FarmMapInsightPage(
        farm: farm,
        farmPolygon: _farmBoundary(farm),
        diseaseMarkers: _farmDiseaseMarkers[index] ?? const [],
        diseaseRiskCells: _issueCellsForFarm(index),
        currentStage: statusSnapshot.stage,
        stageSummary: _stageSummary(index),
        daysAfterSowing: _daysAfterSowing(index),
        harvestHistory: _harvestHistoryForFarm(index),
        diagnosisNotes: _farmNotesForFarm(index),
        lastUpdated: statusSnapshot.updatedAt,
        status: statusSnapshot.status,
        satelliteOverview: overview,
        isSatelliteLoading: isSatelliteLoading,
        lifecycleAdvice: _cropLifecycleByFarmIndex[index],
        onOpenDiagnose: () => _openDiagnosisFlow(index),
        onOpenStatusUpdate: () => _openFarmStatusUpdate(index),
      ),
    );
  }

  Future<void> _openHistoryPage([int? index]) async {
    if (_guardFirstFarmSetup()) return;
    final farmIndex = index ?? _selectedFarm;
    if (farmIndex < 0 || farmIndex >= _farms.length) return;
    _initializeFarmState(farmIndex);
    _refreshFarmStage(farmIndex);
    if (farmIndex != _selectedFarm) {
      if (mounted) {
        setState(() => _selectedFarm = farmIndex);
      } else {
        _selectedFarm = farmIndex;
      }
      _syncSelectedRemoteFarmFromIndex();
    }
    await _refreshSelectedFarmSnapshotForFarm(farmIndex);
    if (!mounted) return;
    _applyRemoteFarmStatusFields(farmIndex);
    final farm = _farms[farmIndex];
    final statusSnapshot = _statusSnapshotForFarm(farmIndex);
    Get.to(
      () => _HistoryPage(
        farm: farm,
        daysAfterSowing: _daysAfterSowing(farmIndex),
        currentStage: statusSnapshot.stage,
        status: statusSnapshot.status,
        statusUpdatedAt: statusSnapshot.updatedAt,
        harvestHistory: _harvestHistoryForFarm(farmIndex),
        diagnosisNotes: _farmNotesForFarm(farmIndex),
        satelliteOverview: _satelliteOverviewByFarmIndex[farmIndex],
      ),
    );
  }

  void _openHistoryIndexPage() {
    if (_guardFirstFarmSetup()) return;
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
          unawaited(_openHistoryPage(index));
        },
      ),
    );
  }

  Future<void> _refreshFirstFarmSync() async {
    await _refreshFarmerHomeData();
  }

  Future<void> _refreshFarmerHomeData() async {
    final auth = Get.find<MainAuthController>();
    await auth.syncFarmerData(forceRefresh: true);
    if (!Get.isRegistered<FarmController>()) return;
    if (!mounted) return;
    _initializeFarmerStateFromSession();
    if (_farms.isNotEmpty) {
      await _refreshSelectedFarmSnapshotForFarm(_safeSelectedFarmIndex);
      unawaited(
        _saveFarmDataSnapshotForFarm(
          _safeSelectedFarmIndex,
          source: 'home_refresh',
        ),
      );
    }
    _scheduleFirstFarmTutorialCheck();
  }

  Future<void> _refreshFarmPageData(int index) async {
    if (index < 0 || index >= _farms.length) return;
    if (_farmPageRefreshLoading.contains(index) ||
        _farmAlertLoading.contains(index)) {
      return;
    }
    var activeIndex = index;
    final farm = _farms[index];
    final minimumLoadingVisible = Future<void>.delayed(
      _farmPageRefreshMinimumDuration,
    );
    String? refreshErrorMessage;
    setState(() {
      _farmPageRefreshLoading.add(index);
      _farmAlertErrorByFarmIndex.remove(index);
    });
    try {
      final farmId = await _resolveSatelliteFarmId(farm, index);
      if (farmId.isEmpty) {
        throw SatelliteApiException('Remote farm id not found');
      }
      if (Get.isRegistered<FarmController>()) {
        Get.find<FarmController>().invalidateFarmCache();
      }
      try {
        final refreshedIndex = await _refreshFarmsFromCloudAndSelect(
          farmId: farmId,
          fallbackIndex: index,
          refreshSnapshot: false,
        );
        activeIndex = refreshedIndex;
      } catch (error) {
        Get.log('Farm list refresh skipped before alert refresh: $error');
        activeIndex = _indexForRemoteFarmId(farmId) ?? index;
      }
      if (!mounted || _farms.isEmpty) return;
      _initializeFarmState(activeIndex);
      _applyRemoteFarmStatusFields(activeIndex);
      await Future.wait<void>([
        _loadLiveWeatherForFarm(activeIndex, forceRefresh: true),
        _loadCropLifecycleAdviceForFarm(activeIndex, forceRefresh: true),
      ]);
      final scanReady = await _runDiseaseScreenForFarm(
        activeIndex,
        showFailureSnack: false,
        refreshSummaryAfter: false,
      );
      if (!scanReady && !_hasDiseaseRefreshCache(activeIndex)) {
        throw SatelliteApiException('Disease risk scan failed');
      }
      if (!mounted || _farms.isEmpty) return;
      await _ensureDiseaseRemoteForFarm(
        activeIndex,
        forceRefresh: true,
        showAlertErrors: false,
      );
      await _loadFarmSummaryForFarm(
        activeIndex,
        cascade: false,
        forceRefresh: true,
      );
      await _loadFarmTimelineForFarm(activeIndex, forceRefresh: true);
      unawaited(
        _saveFarmDataSnapshotForFarm(activeIndex, source: 'farm_page_refresh'),
      );
    } catch (e) {
      refreshErrorMessage = _alertRefreshMessage(e);
    } finally {
      await minimumLoadingVisible;
      if (mounted) {
        setState(() {
          if (refreshErrorMessage != null) {
            _farmAlertErrorByFarmIndex[activeIndex] = refreshErrorMessage;
          }
          _farmPageRefreshLoading.remove(index);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    for (var i = 0; i < _farms.length; i++) {
      _initializeFarmState(i);
      _refreshFarmStage(i);
    }
    final selectedFarmIndex = _safeSelectedFarmIndex;
    if (_farms.isNotEmpty) {
      _scheduleSelectedFarmSnapshotEnsure(selectedFarmIndex);
    }
    _scheduleFirstFarmTutorialCheck();

    final farmPolygons = {
      for (var i = 0; i < _farms.length; i++) i: _farmBoundary(_farms[i]),
    };
    final displayScoutZonesByFarm = {
      for (var i = 0; i < _farms.length; i++) i: _displayScoutZonesForFarm(i),
    };
    final displayRiskCellsByFarm = {
      for (var i = 0; i < _farms.length; i++) i: _displayRiskCellsForFarm(i),
    };
    final displayDiseaseScreenByFarm = <int, DiseaseScreenResult>{};
    for (var i = 0; i < _farms.length; i++) {
      final screen = _displayDiseaseScreenForFarm(i);
      if (screen != null) {
        displayDiseaseScreenByFarm[i] = screen;
      }
    }
    final farmCtrl = Get.isRegistered<FarmController>()
        ? Get.find<FarmController>()
        : null;
    final verifiedFarmer =
        Get.find<MainAuthController>().verifiedFarmer.value != null;
    final farmSyncing =
        verifiedFarmer &&
        (farmCtrl?.isLoading.value ?? false) &&
        _farms.isEmpty;
    final initialFarmServiceKey = _initialFarmServiceSyncKey(selectedFarmIndex);
    final initialFarmServicesPending =
        verifiedFarmer &&
        _farms.isNotEmpty &&
        initialFarmServiceKey != null &&
        _initialFarmServiceReadyKey != initialFarmServiceKey;
    if (initialFarmServicesPending) {
      _scheduleInitialFarmServiceSync(selectedFarmIndex);
    }
    final selectedStatusSnapshot = _statusSnapshotForFarm(selectedFarmIndex);
    final pageIndex = _index.clamp(_dashboardTabIndex, _aiChatTabIndex).toInt();

    Widget buildCurrentPage() {
      switch (pageIndex) {
        case _farmTabIndex:
          return _FarmPage(
            farms: _farms,
            selectedIndex: selectedFarmIndex,
            isFarmSyncing: farmSyncing,
            farmSyncError: farmCtrl?.hasError.value == true
                ? farmCtrl?.errorMessage.value ?? ''
                : '',
            onRetryFarmSync: () {
              unawaited(_refreshFirstFarmSync());
            },
            onAddFarm: () {
              unawaited(_openAddFarmSheet());
            },
            onOpenFarmInsight: _openFarmMapInsight,
            onOpenStatusUpdate: _openFarmStatusUpdate,
            onRefreshAlerts: _refreshFarmPageData,
            onOpenIssue: _openFarmIssue,
            farmPolygons: farmPolygons,
            statusSnapshotForFarm: _statusSnapshotForFarm,
            diseaseMarkersByFarm: _farmDiseaseMarkers,
            scoutZonesByFarm: displayScoutZonesByFarm,
            riskCellsByFarm: displayRiskCellsByFarm,
            issueCells: _issueCellsForFarm(selectedFarmIndex),
            diseaseScreenByFarm: displayDiseaseScreenByFarm,
            alertAdviceByFarm: _farmAlertAdviceByFarmIndex,
            alertErrorByFarm: _farmAlertErrorByFarmIndex,
            alertLoading: {..._farmAlertLoading, ..._farmPageRefreshLoading},
            timelineByFarm: _farmTimelineByFarmIndex,
            timelineLoading: _farmTimelineLoading,
            stageSummary: _stageSummary,
            daysAfterSowing: _daysAfterSowing,
          );
        case _harvestTabIndex:
          return _HarvestHomePage(
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
            onOpenInventory: _openInventoryTab,
            onHarvestCompleted: _onHarvestCompleted,
          );
        case _inventoryTabIndex:
          return _InventoryPage(
            lots: _harvestInventory,
            onTapListForSell: (lot) => Get.to(
              () => MarketPage(
                inventoryLots: _marketLotPayloads(),
                farmName: lot.farmName,
                initialSelectedLot: lot.toMarketPayload(),
              ),
            ),
          );
        case _aiChatTabIndex:
          return FarmerAiChatScreen(
            farmId: _farm.remoteFarmId,
            farmName: _farm.name,
            crop: _farm.crop,
            variety: _farm.variety,
            location: _farm.location,
            farmerPhone: _verifiedFarmerPhone(),
            farmerId: _verifiedFarmerId() ?? _profile.farmerId,
            growthStage: _farm.currentStatusStage?.trim().isNotEmpty == true
                ? _farm.currentStatusStage
                : _growthStageForFarm(selectedFarmIndex),
            daysAfterSowing: _daysAfterSowing(selectedFarmIndex),
            bottomContentInset: 106,
          );
        case _dashboardTabIndex:
        default:
          return _FarmerDashboard(
            profile: _profile,
            farm: _farm,
            farms: _farms,
            selectedFarmIndex: selectedFarmIndex,
            avatarAsset: _currentFarmAvatar,
            stageSummary: _stageSummary(selectedFarmIndex),
            onOpenAiChat: _openAiChatTab,
            onOpenFarm: _openFarmTab,
            onOpenDisease: _openFarmTab,
            onOpenMarket: _openMarketPage,
            onRefresh: _refreshFarmerHomeData,
            satelliteOverview: _satelliteOverviewByFarmIndex[selectedFarmIndex],
            isSatelliteLoading:
                _satelliteOverviewLoading.contains(selectedFarmIndex) ||
                _farmSummaryLoading.contains(selectedFarmIndex) ||
                _liveWeatherLoading.contains(selectedFarmIndex),
            weatherContext: _weatherContextForFarm(selectedFarmIndex),
            diseaseMaxRisk: _diseaseMaxRiskForFarm(selectedFarmIndex),
            lifecycleAdvice: _cropLifecycleByFarmIndex[selectedFarmIndex],
            currentStage: selectedStatusSnapshot.stage,
            currentStatus: selectedStatusSnapshot.status,
            statusUpdatedAt: selectedStatusSnapshot.updatedAt,
            diseaseScreen: _displayDiseaseScreenForFarm(selectedFarmIndex),
            onSelectFarm: (value) {
              if (value < 0 || value >= _farms.length) return;
              _selectFarmIndex(value, forceRefresh: true);
            },
          );
      }
    }

    final currentPage = buildCurrentPage();

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideNav = constraints.maxWidth >= 760;
        return Scaffold(
          extendBody: !useSideNav,
          backgroundColor: AppTheme.surface,
          drawer: _buildDrawer(context),
          appBar: useSideNav
              ? null
              : AppBar(
                  backgroundColor: AppTheme.surface,
                  elevation: 0,
                  toolbarHeight: appHeaderToolbarHeight,
                  centerTitle: true,
                  iconTheme: const IconThemeData(color: AppTheme.greenDark),
                  leadingWidth: appBackButtonLeadingWidth,
                  leading: Builder(
                    builder: (context) => appMenuButtonLeading(context),
                  ),
                  title: const BrandText(fontSize: 21),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                        child: _buildLanguageSelector(compact: true),
                      ),
                    ),
                  ],
                ),
          body: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
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
                                  key: ValueKey(pageIndex),
                                  child: currentPage,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Stack(
                          children: [
                            Positioned.fill(
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
                                  key: ValueKey('mobile-$pageIndex'),
                                  child: currentPage,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _buildMobileBottomNavigationBar(),
                            ),
                          ],
                        ),
                ),
              ),
              if (_firstFarmLoadOverlayVisible)
                Positioned.fill(
                  child: _FirstFarmLoadOverlay(
                    title: _firstFarmLoadOverlayTitle,
                    message: _firstFarmLoadOverlayMessage,
                    isError: _firstFarmLoadOverlayError,
                  ),
                )
              else if (initialFarmServicesPending)
                Positioned.fill(
                  child: _FirstFarmLoadOverlay(
                    title: UiStrings.t('initial_farm_sync_title'),
                    message: UiStrings.t('initial_farm_sync_message'),
                    isError: _initialFarmServiceSyncError,
                  ),
                ),
            ],
          ),
          floatingActionButton:
              (_firstFarmLoadOverlayVisible || initialFarmServicesPending)
              ? null
              : pageIndex == _dashboardTabIndex
              ? Padding(
                  padding: EdgeInsets.only(bottom: useSideNav ? 0 : 92),
                  child: FloatingActionButton.extended(
                    onPressed: _openAddFarmSheet,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(UiStrings.t('farm_label')),
                  ),
                )
              : null,
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
            onMenuTap: () => Scaffold.maybeOf(context)?.openDrawer(),
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
              onOpenInventory: _openInventoryTab,
              onOpenOfflineMaps: _openOfflineMapsPage,
              onOpenProfile: _openProfilePage,
              onOpenSettings: _openSettingsPage,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 18),
            child: Column(
              children: [
                Center(child: _buildLanguageSelector(compact: !expanded)),
                const SizedBox(height: 10),
                Center(
                  child: _SideNavLogoutButton(
                    expanded: expanded,
                    onTap: () => Get.find<MainAuthController>().logout(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openGrainGradingPage() async {
    if (_guardFirstFarmSetup()) return;
    final selectedIndex = _safeSelectedFarmIndex;
    final selectedFarm = _farms[selectedIndex];
    final farmId = await _resolveSatelliteFarmId(selectedFarm, selectedIndex);
    final result = await Get.to<Map<String, dynamic>>(
      () => const FarmerAiGradingScreen(),
      arguments: {
        if (farmId.trim().isNotEmpty) 'farmId': farmId,
        'farmName': selectedFarm.name,
        'farmLocation': selectedFarm.location,
        'farmerId': _profile.farmerId,
        'farmerName': _profile.name,
        'crop': selectedFarm.crop,
        'variety': selectedFarm.variety,
        'product': selectedFarm.product,
        'village': selectedFarm.location,
      },
    );
    if (result == null || result['action'] != 'add_inventory') return;
    final bagSize = (result['bagSizeKg'] as num?)?.toDouble() ?? 0;
    final bagCount = (result['bagCount'] as num?)?.toInt() ?? 0;
    final moisture = (result['moisturePercent'] as num?)?.toDouble() ?? 0;
    final score = (result['gradeScore'] as num?)?.toInt() ?? 0;
    if (bagSize <= 0 || bagCount <= 0) return;
    final center = _farmCenter(selectedFarm);
    _onHarvestCompleted(
      _HarvestInventoryLot(
        batchId: '${result['batchId'] ?? _createFallbackBatchId()}',
        farmName: selectedFarm.name,
        crop: '${result['crop'] ?? selectedFarm.crop}',
        variety: '${result['variety'] ?? selectedFarm.variety}',
        bagCount: bagCount,
        bagSizeKg: bagSize,
        moisturePercent: moisture,
        grade: '${result['grade'] ?? '--'}',
        gradeScore: score,
        gradeBasis: '${result['gradeBasis'] ?? 'AI grain grading'}',
        estimatedYieldKg: bagSize * bagCount,
        harvestedAt: DateTime.now(),
        latitude: center.latitude,
        longitude: center.longitude,
        machineImageName: '${result['imageName'] ?? 'grain-grading'}',
      ),
    );
    setState(() => _index = _inventoryTabIndex);
    Get.snackbar(
      UiStrings.t('inventory'),
      UiStrings.f('product_added_inventory', {
        'batch': '${result['batchId'] ?? ''}',
      }),
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  String _createFallbackBatchId() {
    final now = DateTime.now();
    return 'KF-HV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch % 10000}';
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

  void _openOfflineMapsPage() {
    Get.toNamed('/offline-maps');
  }

  void _openSettingsPage() {
    Get.to(
      () => _SettingsPage(
        profile: _profile,
        onOpenAddFarm: () => unawaited(_openAddFarmSheet()),
        onOpenNotifications: () => _openNotificationsPanel(),
      ),
    );
  }

  Future<void> _openNotificationPanelFromSystemTray() async {
    final notificationId = await LocalNotificationService.instance
        .consumeNotificationPayload();
    if (!mounted || notificationId == null) return;
    _openNotificationsPanel(initialNotificationId: notificationId);
  }

  void _openNotificationsPanel({String? initialNotificationId}) {
    Get.to(
      () => _FarmerNotificationsPage(
        farmerId: _notificationFarmerId(),
        farmerPhone: _notificationFarmerPhone(),
        service: _farmerNotificationService,
        authToken: _satelliteRequestToken(),
        initialNotificationId: initialNotificationId,
      ),
    );
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
                      Icons.wb_cloudy_rounded,
                      color: AppTheme.green,
                    ),
                    title: Text(
                      UiStrings.t('weather'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                    title: Text(
                      UiStrings.t('apmc_market'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                    title: Text(
                      UiStrings.t('news'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                    title: Text(
                      UiStrings.t('schemes'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openSchemesPage();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.grain, color: AppTheme.green),
                    title: Text(
                      UiStrings.t('grain_grading'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openGrainGradingPage();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.offline_pin_rounded,
                      color: AppTheme.green,
                    ),
                    title: Text(
                      UiStrings.t('offline_maps'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openOfflineMapsPage();
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.history_rounded,
                      color: AppTheme.green,
                    ),
                    title: Text(
                      UiStrings.t('farm_history'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                    title: Text(
                      UiStrings.t('inventory'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openInventoryTab();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.person_rounded,
                      color: AppTheme.green,
                    ),
                    title: Text(
                      UiStrings.t('profile'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openProfilePage();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.settings_rounded,
                      color: AppTheme.green,
                    ),
                    title: Text(
                      UiStrings.t('settings'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openSettingsPage();
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

String _formatLocalizedAcres(num value, {required int fractionDigits}) {
  return UiStrings.f('acres_value', {
    'value': LocaleText.number(value, fractionDigits: fractionDigits),
  });
}

String _formatLocalizedKg(num value, {int fractionDigits = 1}) {
  return UiStrings.f('kg_value', {
    'value': LocaleText.number(value, fractionDigits: fractionDigits),
  });
}

String _formatLocalizedPercent(num value, {int fractionDigits = 1}) {
  return '${LocaleText.number(value, fractionDigits: fractionDigits)}%';
}

String _formatLocalizedBagSize(int count, num sizeKg) {
  return UiStrings.f('bags_size_value', {
    'count': count,
    'size': LocaleText.number(sizeKg, fractionDigits: 0),
  });
}

String _localizedHarvestLotLabel(_HarvestInventoryLot lot) {
  return UiStrings.f('harvest_lot_label', {
    'batch': lot.batchId,
    'grade': lot.grade,
    'qty': LocaleText.number(lot.estimatedYieldKg, fractionDigits: 1),
  });
}

String _localizedHarvestLotDetail(_HarvestInventoryLot lot) {
  return UiStrings.f('harvest_lot_detail', {
    'crop': UiStrings.option(lot.crop),
    'variety': UiStrings.option(lot.variety),
    'grade': lot.grade,
    'qty': LocaleText.number(lot.estimatedYieldKg, fractionDigits: 1),
  });
}

class _FarmerFarm {
  final String remoteFarmId;
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
  final String? currentStatus;
  final String? currentStatusStage;
  final DateTime? currentStatusUpdatedAt;
  final DateTime? sowingDate;
  final DateTime? createdAt;
  final double? latitude;
  final double? longitude;
  final List<List<double>>? polygon;

  const _FarmerFarm({
    this.remoteFarmId = '',
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
    this.currentStatus,
    this.currentStatusStage,
    this.currentStatusUpdatedAt,
    this.sowingDate,
    this.createdAt,
    this.polygon,
    this.latitude,
    this.longitude,
  });

  _FarmerFarm copyWithStatus({
    String? currentStatus,
    String? currentStatusStage,
    DateTime? currentStatusUpdatedAt,
  }) {
    return _FarmerFarm(
      remoteFarmId: remoteFarmId,
      name: name,
      location: location,
      crop: crop,
      variety: variety,
      area: area,
      health: health,
      ndvi: ndvi,
      moisture: moisture,
      product: product,
      previousCrop: previousCrop,
      season: season,
      irrigation: irrigation,
      soilType: soilType,
      ownershipType: ownershipType,
      seedSource: seedSource,
      harvestIntent: harvestIntent,
      currentStatus: currentStatus ?? this.currentStatus,
      currentStatusStage: currentStatusStage ?? this.currentStatusStage,
      currentStatusUpdatedAt:
          currentStatusUpdatedAt ?? this.currentStatusUpdatedAt,
      sowingDate: sowingDate,
      createdAt: createdAt,
      polygon: polygon,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class _FarmStatusSnapshot {
  final String status;
  final String stage;
  final DateTime? updatedAt;

  const _FarmStatusSnapshot({
    required this.status,
    required this.stage,
    required this.updatedAt,
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

  String get lotLabel => _localizedHarvestLotLabel(this);

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
    return '${LocaleText.date(dateTime, pattern: 'dd/MM')} ${LocaleText.time(dateTime)}';
  }

  String _localizedSortOption(String option) {
    return switch (option) {
      'Highest grade' => UiStrings.t('sort_highest_grade'),
      'Lowest moisture' => UiStrings.t('sort_lowest_moisture'),
      'Most yield' => UiStrings.t('sort_most_yield'),
      _ => UiStrings.t('sort_newest'),
    };
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
      title: UiStrings.t('inventory'),
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
                      title: UiStrings.t('lots'),
                      value: LocaleText.number(lots.length),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryStat(
                      title: UiStrings.t('total_bags'),
                      value: LocaleText.number(totalBags),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryStat(
                      title: UiStrings.t('qty'),
                      value: _formatLocalizedKg(totalQty),
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
                      hintText: UiStrings.t('search_inventory_hint'),
                      suffixIcon: _searchText.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _searchText = '';
                                _searchController.clear();
                              }),
                              tooltip: UiStrings.t('clear_search'),
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
                                  child: Text(_localizedSortOption(item)),
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
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final farm = _farmOptions[index];
                          return ChoiceChip(
                            label: Text(UiStrings.option(farm)),
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  UiStrings.t('no_lot_found_inventory'),
                  style: const TextStyle(color: AppTheme.textMuted),
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
                          UiStrings.f('harvested_at', {
                            'time': _formatDateTime(lot.harvestedAt),
                          }),
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
                            _InventoryChip(
                              label: UiStrings.label(lot.farmName),
                            ),
                            _InventoryChip(label: UiStrings.option(lot.crop)),
                            _InventoryChip(
                              label: UiStrings.option(lot.variety),
                            ),
                            _InventoryChip(
                              label: UiStrings.f('grade_value', {
                                'grade': lot.grade,
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryStat(
                                title: UiStrings.t('bags'),
                                value: _formatLocalizedBagSize(
                                  lot.bagCount,
                                  lot.bagSizeKg,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SummaryStat(
                                title: UiStrings.t('moisture_label'),
                                value: _formatLocalizedPercent(
                                  lot.moisturePercent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryStat(
                                title: UiStrings.t('quality_score'),
                                value: LocaleText.number(lot.gradeScore),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SummaryStat(
                                title: UiStrings.t('estimated_qty'),
                                value: _formatLocalizedKg(lot.estimatedYieldKg),
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
                                label: Text(UiStrings.t('list_for_sale')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Get.snackbar(
                                    UiStrings.t('inventory'),
                                    UiStrings.f('coordinates_value', {
                                      'lat': LocaleText.number(
                                        lot.latitude,
                                        fractionDigits: 4,
                                      ),
                                      'lng': LocaleText.number(
                                        lot.longitude,
                                        fractionDigits: 4,
                                      ),
                                    }),
                                    snackPosition: SnackPosition.BOTTOM,
                                  );
                                },
                                icon: const Icon(Icons.location_on_outlined),
                                label: Text(UiStrings.t('view_lot')),
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
                  Text(
                    UiStrings.t('farm_inventory_snapshot'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryStat(
                          title: UiStrings.t('avg_moisture'),
                          value: _formatLocalizedPercent(avgMoisture),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryStat(
                          title: UiStrings.t('avg_grade_score'),
                          value: LocaleText.number(avgScore, fractionDigits: 1),
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
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E9DC)),
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
  final List<_FarmerFarm> farms;
  final int selectedFarmIndex;
  final String avatarAsset;
  final String stageSummary;
  final VoidCallback onOpenAiChat;
  final VoidCallback onOpenFarm;
  final VoidCallback onOpenDisease;
  final VoidCallback onOpenMarket;
  final RefreshCallback onRefresh;
  final _FarmSatelliteOverview? satelliteOverview;
  final bool isSatelliteLoading;
  final Map<String, dynamic>? weatherContext;
  final double diseaseMaxRisk;
  final CropLifecycleAdvice? lifecycleAdvice;
  final String currentStage;
  final String currentStatus;
  final DateTime? statusUpdatedAt;
  final DiseaseScreenResult? diseaseScreen;
  final ValueChanged<int> onSelectFarm;

  const _FarmerDashboard({
    required this.profile,
    required this.farm,
    required this.farms,
    required this.selectedFarmIndex,
    required this.avatarAsset,
    required this.stageSummary,
    required this.onOpenAiChat,
    required this.onOpenFarm,
    required this.onOpenDisease,
    required this.onOpenMarket,
    required this.onRefresh,
    required this.satelliteOverview,
    required this.isSatelliteLoading,
    required this.weatherContext,
    required this.diseaseMaxRisk,
    required this.lifecycleAdvice,
    required this.currentStage,
    required this.currentStatus,
    required this.statusUpdatedAt,
    required this.diseaseScreen,
    required this.onSelectFarm,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: 20,
      color: AppTheme.green,
      backgroundColor: Colors.white,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 150),
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
                      farmName: farm.name,
                      metrics: _overviewMetricsFromSatellite(
                        satelliteOverview,
                        weatherContext,
                        diseaseMaxRisk,
                        isSatelliteLoading,
                      ),
                      onDetailsTap: onOpenFarm,
                    ),
                  ),
                  if (farms.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _HomeRevealSection(
                      delayMs: 60,
                      child: _FarmQuickSwitchStrip(
                        farms: farms,
                        selectedIndex: selectedFarmIndex,
                        onSelectFarm: onSelectFarm,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _HomeRevealSection(
                    delayMs: 130,
                    child: _SectionTitle(title: UiStrings.t('farm_insight')),
                  ),
                  const SizedBox(height: 12),
                  _HomeRevealSection(
                    delayMs: 150,
                    child: _FarmSnapshotCard(
                      farm: farm,
                      satelliteOverview: satelliteOverview,
                      diseaseMaxRisk: diseaseMaxRisk,
                      isLoading: isSatelliteLoading,
                      lifecycleAdvice: lifecycleAdvice,
                      currentStage: currentStage,
                      currentStatus: currentStatus,
                      statusUpdatedAt: statusUpdatedAt,
                      diseaseScreen: diseaseScreen,
                      onOpenFarm: onOpenFarm,
                    ),
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
                  _HomeRevealSection(
                    delayMs: 190,
                    child: _SectionTitle(title: UiStrings.t('recent_activity')),
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
      ),
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
  Map<String, dynamic>? weatherContext,
  double diseaseMaxRisk,
  bool isLoading,
) {
  FarmMetricData placeholder(String label, IconData icon) => FarmMetricData(
    label: label,
    icon: icon,
    progress: 0,
    color: const Color(0xFF9AA0A6),
    status: isLoading ? UiStrings.t('loading') : UiStrings.t('no_data'),
    valueText: '--',
  );

  double? readWeatherValue(String key) {
    final raw = weatherContext?[key];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  Map<String, dynamic> readWeatherMap(String key) {
    final raw = weatherContext?[key];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  double? readMapValue(Map<String, dynamic> map, String key) {
    final raw = map[key];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  String? readMapText(Map<String, dynamic> map, String key) {
    final text = '${map[key] ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  final currentWeather = readWeatherMap('live_current').isNotEmpty
      ? readWeatherMap('live_current')
      : readWeatherMap('current');
  final waterStress = readWeatherMap('water_stress');
  final cropWeather = readWeatherMap('crop_health_weather');
  final currentTemp =
      readMapValue(currentWeather, 'temperature_c') ??
      readWeatherValue('temperature_c');
  final rainNow =
      readMapValue(currentWeather, 'rain_mm') ?? readWeatherValue('rain_mm');
  final windKmh =
      readMapValue(currentWeather, 'wind_kmh') ?? readWeatherValue('wind_kmh');
  final humidity =
      readMapValue(currentWeather, 'humidity_percent') ??
      readWeatherValue('humidity_percent');
  final waterStressScore = readMapValue(waterStress, 'score');
  final cropWeatherScore = readMapValue(cropWeather, 'score');
  final weatherCondition = readMapText(currentWeather, 'condition');

  final wetness = readWeatherValue('leaf_wetness_hours');
  final rain = readWeatherValue('total_rain_mm');
  final weatherRisk =
      readWeatherValue('weather_risk') ?? readWeatherValue('weather_risk_max');
  final liveScore =
      [
        waterStressScore,
        cropWeatherScore,
        if (rainNow != null) (rainNow / 20).clamp(0.0, 1.0).toDouble(),
        if (windKmh != null) (windKmh / 45).clamp(0.0, 1.0).toDouble(),
        if (humidity != null && humidity >= 90) 0.55,
      ].whereType<double>().fold<double>(
        0,
        (max, value) => value > max ? value : max,
      );
  final hasLiveWeather =
      currentWeather.isNotEmpty ||
      waterStress.isNotEmpty ||
      cropWeather.isNotEmpty;
  final FarmMetricData weatherCard;
  if (wetness == null &&
      rain == null &&
      weatherRisk == null &&
      !hasLiveWeather) {
    weatherCard = placeholder(
      UiStrings.t('weather_alerts'),
      Icons.cloud_rounded,
    );
  } else {
    final wetScore = ((wetness ?? 0) / 12).clamp(0.0, 1.0).toDouble();
    final rainScore = ((rain ?? 0) / 50).clamp(0.0, 1.0).toDouble();
    final riskScore = (weatherRisk ?? 0).clamp(0.0, 1.0).toDouble();
    final alert = math.max(
      math.max(math.max(wetScore, rainScore), riskScore),
      liveScore,
    );
    weatherCard = FarmMetricData(
      label: UiStrings.t('weather_alerts'),
      icon: Icons.cloud_rounded,
      progress: alert,
      color: alert >= 0.66
          ? const Color(0xFFD32F2F)
          : alert >= 0.4
          ? const Color(0xFFF57C00)
          : const Color(0xFF2EAF4A),
      status: alert >= 0.66
          ? UiStrings.t('high')
          : alert >= 0.4
          ? UiStrings.t('watch')
          : (weatherCondition == null
                ? UiStrings.t('good')
                : UiStrings.option(weatherCondition)),
      valueText: currentTemp == null
          ? _formatLocalizedPercent((alert * 100).round(), fractionDigits: 0)
          : '${LocaleText.number(currentTemp, fractionDigits: 0)} C',
    );
  }

  final moisture =
      overview?.moisture ??
      (waterStressScore == null
          ? null
          : (1 - waterStressScore).clamp(0.0, 1.0).toDouble());
  final FarmMetricData waterCard;
  if (moisture == null) {
    waterCard = placeholder(
      UiStrings.t('water_level'),
      Icons.water_drop_rounded,
    );
  } else {
    final level = moisture.clamp(0.0, 1.0).toDouble();
    waterCard = FarmMetricData(
      label: UiStrings.t('water_level'),
      icon: Icons.water_drop_rounded,
      progress: level,
      color: waterStressScore != null && waterStressScore >= 0.66
          ? const Color(0xFFD32F2F)
          : const Color(0xFF3498DB),
      status: waterStressScore == null
          ? (level >= 0.4 ? UiStrings.t('good') : UiStrings.t('low'))
          : (waterStressScore >= 0.66
                ? UiStrings.t('low')
                : waterStressScore >= 0.4
                ? UiStrings.t('watch')
                : UiStrings.t('good')),
      valueText: overview?.moisture == null
          ? _formatLocalizedPercent((level * 100).round(), fractionDigits: 0)
          : LocaleText.number(moisture, fractionDigits: 3),
    );
  }

  final ndvi = overview?.ndvi ?? cropWeatherScore;
  final FarmMetricData cropCard;
  if (ndvi == null) {
    cropCard = placeholder(UiStrings.t('crop_health'), Icons.eco_rounded);
  } else {
    final level = ndvi.clamp(0.0, 1.0).toDouble();
    cropCard = FarmMetricData(
      label: UiStrings.t('crop_health'),
      icon: Icons.eco_rounded,
      progress: level,
      color: level >= 0.6
          ? const Color(0xFF2EAF4A)
          : level >= 0.4
          ? const Color(0xFFF5B21D)
          : const Color(0xFFD32F2F),
      status: level >= 0.6
          ? UiStrings.t('healthy')
          : level >= 0.4
          ? UiStrings.t('fair')
          : UiStrings.t('low'),
      valueText: overview?.ndvi == null
          ? _formatLocalizedPercent((level * 100).round(), fractionDigits: 0)
          : LocaleText.number(ndvi, fractionDigits: 3),
    );
  }

  final diseaseCard = diseaseMaxRisk <= 0
      ? placeholder(UiStrings.t('disease_risk'), Icons.shield_rounded)
      : FarmMetricData(
          label: UiStrings.t('disease_risk'),
          icon: Icons.shield_rounded,
          progress: diseaseMaxRisk.clamp(0.0, 1.0).toDouble(),
          color: _FarmPage._riskColor(diseaseMaxRisk),
          status: diseaseMaxRisk >= 0.72
              ? UiStrings.t('high')
              : diseaseMaxRisk >= 0.55
              ? UiStrings.t('watch')
              : UiStrings.t('low'),
          valueText: _formatLocalizedPercent(
            (diseaseMaxRisk * 100).round(),
            fractionDigits: 0,
          ),
        );

  return [weatherCard, waterCard, cropCard, diseaseCard];
}

class FarmMetricData {
  final String label;
  final IconData icon;
  final double progress;
  final Color color;
  final String status;
  final String? valueText;

  const FarmMetricData({
    required this.label,
    required this.icon,
    required this.progress,
    required this.color,
    required this.status,
    this.valueText,
  });
}

class FarmOverviewSection extends StatelessWidget {
  final String farmName;
  final List<FarmMetricData> metrics;
  final VoidCallback? onDetailsTap;

  const FarmOverviewSection({
    super.key,
    required this.farmName,
    required this.metrics,
    this.onDetailsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          UiStrings.t('farm_overview'),
                          style: const TextStyle(
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                UiStrings.t('details'),
                                style: const TextStyle(
                                  color: Color(0xFF2EAF4A),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
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
                  const SizedBox(height: 6),
                  Text(
                    UiStrings.label(farmName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
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
                  if (availableWidth >= 720) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          for (var index = 0; index < metrics.length; index++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: index == 0 ? 0 : 6,
                                  right: index == metrics.length - 1 ? 0 : 6,
                                ),
                                child: FarmMetricCard(metric: metrics[index]),
                              ),
                            ),
                        ],
                      ),
                    );
                  }
                  final cardWidth = availableWidth >= 420 ? 178.0 : 172.0;
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

class _FarmQuickSwitchStrip extends StatelessWidget {
  final List<_FarmerFarm> farms;
  final int selectedIndex;
  final ValueChanged<int> onSelectFarm;

  const _FarmQuickSwitchStrip({
    required this.farms,
    required this.selectedIndex,
    required this.onSelectFarm,
  });

  @override
  Widget build(BuildContext context) {
    final safeSelected = farms.isEmpty
        ? 0
        : selectedIndex.clamp(0, farms.length - 1).toInt();
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: farms.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final farm = farms[index];
          final selected = index == safeSelected;
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onSelectFarm(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 190,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFE8F5E9) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? AppTheme.green : const Color(0xFFE5E7EB),
                  width: selected ? 1.4 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF1B5E20,
                    ).withValues(alpha: selected ? 0.12 : 0.05),
                    blurRadius: selected ? 18 : 10,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.green : AppTheme.greenPale,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          selected
                              ? Icons.check_rounded
                              : Icons.photo_library_outlined,
                          color: selected ? Colors.white : AppTheme.greenDark,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          UiStrings.label(farm.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? AppTheme.greenDark
                                : AppTheme.textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    UiStrings.option(farm.crop),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    UiStrings.label(farm.area),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
    final valueText = metric.valueText ?? '$percent%';
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
                valueText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          UiStrings.t('apmc_bulletin_title'),
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          UiStrings.t('apmc_bulletin_subtitle'),
                          style: const TextStyle(
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
              _MarketBullet(text: UiStrings.t('apmc_bulletin_1')),
              const SizedBox(height: 8),
              _MarketBullet(text: UiStrings.t('apmc_bulletin_2')),
              const SizedBox(height: 8),
              _MarketBullet(text: UiStrings.t('apmc_bulletin_3')),
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
    final seed = Object.hash(profile.farmerId, farm.name, farm.crop).abs();
    final palettes = const [
      [Color(0xFF123619), Color(0xFFE6F4D8), Color(0xFFFFF7D6)],
      [Color(0xFF244C28), Color(0xFFF2E1B8), Color(0xFFE7F5EF)],
      [Color(0xFF5D3D12), Color(0xFFFFF0C7), Color(0xFFEAF5D7)],
      [Color(0xFF173D45), Color(0xFFDFF2EC), Color(0xFFFFE8BF)],
    ];
    final alignments = const [
      Alignment.center,
      Alignment.centerLeft,
      Alignment.centerRight,
      Alignment.topCenter,
    ];
    final palette = palettes[seed % palettes.length];
    final imageAlignment = alignments[seed % alignments.length];

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
        height: 208,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
          boxShadow: [
            BoxShadow(
              color: palette.first.withValues(alpha: 0.17),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/farm_home_Top_widget.jpg',
                fit: BoxFit.cover,
                alignment: imageAlignment,
                errorBuilder: (context, error, stackTrace) {
                  return const FarmHillsBackground();
                },
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.95),
                      palette[1].withValues(alpha: 0.84),
                      palette[2].withValues(alpha: 0.56),
                      palette.first.withValues(alpha: 0.34),
                    ],
                    stops: const [0, 0.46, 0.76, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              top: 20,
              right: 120,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    UiStrings.timeGreeting(),
                    style: TextStyle(
                      color: palette.first,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 13),
                  _MiniInfo(
                    icon: Icons.grass_outlined,
                    text: UiStrings.f('farm_value', {'value': farm.name}),
                  ),
                  const SizedBox(height: 7),
                  _MiniInfo(
                    icon: Icons.location_on_outlined,
                    text:
                        '${UiStrings.label(farm.location)} • ${UiStrings.option(farm.crop)} • ${UiStrings.option(farm.variety)}',
                  ),
                ],
              ),
            ),
            Positioned(
              right: 18,
              top: 0,
              bottom: 0,
              child: Center(
                child: SizedBox(
                  width: 96,
                  height: 108,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 92,
                          height: 92,
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.96),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: palette.first.withValues(alpha: 0.22),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              avatarAsset,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  BrandAssets.farmerAvatar,
                                  fit: BoxFit.cover,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: 4,
                        child: Container(
                          width: 34,
                          height: 34,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: palette[1], width: 2),
                          ),
                          child: Image.asset(
                            BrandAssets.kalsubaiLogo,
                            fit: BoxFit.contain,
                            cacheWidth: 96,
                          ),
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

class _CropLifecycleAdviceCard extends StatelessWidget {
  final CropLifecycleAdvice advice;
  final bool compact;
  final String? crop;
  final String? variety;
  final String? currentStage;
  final int? daysAfterSowing;
  final String? currentStatus;
  final DateTime? statusUpdatedAt;

  const _CropLifecycleAdviceCard({
    required this.advice,
    this.compact = false,
    this.crop,
    this.variety,
    this.currentStage,
    this.daysAfterSowing,
    this.currentStatus,
    this.statusUpdatedAt,
  });

  String _stageLabel(String value) {
    final label = value.trim().isEmpty ? currentStage ?? '' : value;
    return UiStrings.option(label.replaceAll('-', ' '));
  }

  bool _isCurrent(CropLifecycleStage stage) {
    final day = daysAfterSowing;
    return day != null && day >= stage.startDay && day <= stage.endDay;
  }

  bool _isComplete(CropLifecycleStage stage) {
    final day = daysAfterSowing;
    return day != null && day > stage.endDay;
  }

  String _statusText(CropLifecycleStage stage) {
    if (_isCurrent(stage)) return UiStrings.t('active_now');
    if (_isComplete(stage)) return UiStrings.t('completed');
    return UiStrings.f('starts_at_day', {
      'day': LocaleText.number(stage.startDay),
    });
  }

  CropLifecycleStage? _activeTimelineStage(List<CropLifecycleStage> timeline) {
    for (final stage in timeline) {
      if (_isCurrent(stage)) return stage;
    }
    return null;
  }

  List<CropLifecycleStage> _visibleTimeline() {
    final timeline =
        advice.timeline
            .where(
              (stage) =>
                  stage.stage.trim().isNotEmpty ||
                  stage.detail.trim().isNotEmpty,
            )
            .toList(growable: true)
          ..sort((a, b) => a.startDay.compareTo(b.startDay));
    if (timeline.length <= 3) return timeline;
    final activeIndex = timeline.indexWhere(_isCurrent);
    const windowSize = 3;
    if (activeIndex < 0) {
      return timeline.take(windowSize).toList(growable: false);
    }
    var start = math.max(0, activeIndex - 1);
    final end = math.min(timeline.length, start + windowSize);
    if (end - start < windowSize) {
      start = math.max(0, end - windowSize);
    }
    return timeline.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final rows = compact
        ? const <MapEntry<IconData, String>>[]
        : [
            MapEntry(Icons.water_drop_outlined, advice.waterNeed),
            MapEntry(Icons.search_rounded, advice.scoutTask),
            MapEntry(Icons.task_alt_rounded, advice.nextAction),
          ].where((row) => row.value.trim().isNotEmpty).toList(growable: false);
    final timeline = _visibleTimeline();
    final activeStage = _activeTimelineStage(timeline);
    final cropContext = [
      if (crop?.trim().isNotEmpty == true) UiStrings.option(crop!.trim()),
      if (variety?.trim().isNotEmpty == true) UiStrings.option(variety!.trim()),
    ].join(' • ');
    final dayText = daysAfterSowing == null
        ? ''
        : UiStrings.f('days_after_sowing_value', {
            'days': LocaleText.number(daysAfterSowing!),
          });
    final rawNowStage = activeStage?.stage.trim().isNotEmpty == true
        ? activeStage!.stage
        : (currentStage?.trim().isNotEmpty == true
              ? currentStage!
              : advice.growthStage);
    final nowDetail = activeStage?.detail.trim().isNotEmpty == true
        ? activeStage!.detail.trim()
        : advice.nextAction.trim();
    final statusText = currentStatus?.trim() ?? '';
    final hasStatus =
        statusText.isNotEmpty && statusText != UiStrings.t('not_updated');
    final statusTimeText = statusUpdatedAt == null
        ? ''
        : '${LocaleText.date(statusUpdatedAt!, pattern: 'dd/MM')} ${LocaleText.time(statusUpdatedAt!)}';

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 16 : 18),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.16)),
        boxShadow: compact
            ? const []
            : [
                BoxShadow(
                  color: AppTheme.greenDark.withValues(alpha: 0.06),
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
              Container(
                width: compact ? 32 : 38,
                height: compact ? 32 : 38,
                decoration: BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.timeline_rounded,
                  color: AppTheme.greenDark,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  UiStrings.t('crop_lifecycle_guidance'),
                  style: TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (advice.stageWindow.trim().isNotEmpty)
                Text(
                  advice.stageWindow,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          if (cropContext.isNotEmpty || dayText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                cropContext,
                dayText,
              ].where((item) => item.trim().isNotEmpty).join(' • '),
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (dayText.isNotEmpty || rawNowStage.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 10 : 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    UiStrings.t('active_now'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      dayText,
                      _stageLabel(rawNowStage),
                    ].where((item) => item.trim().isNotEmpty).join(' • '),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (nowDetail.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      nowDetail,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFEAF5E8),
                        height: 1.3,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (hasStatus) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UiStrings.t('current_status'),
                            style: const TextStyle(
                              color: Color(0xFFEAF5E8),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            UiStrings.option(statusText),
                            maxLines: compact ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              height: 1.25,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (statusTimeText.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              statusTimeText,
                              style: const TextStyle(
                                color: Color(0xFFDDEED8),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (timeline.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              UiStrings.t('crop_cycle_timeline'),
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < timeline.length; index++)
              _LifecycleTimelineTile(
                stage: timeline[index],
                index: index,
                compact: compact,
                isCurrent: _isCurrent(timeline[index]),
                isComplete: _isComplete(timeline[index]),
                stageLabel: _stageLabel(timeline[index].stage),
                statusText: _statusText(timeline[index]),
              ),
          ],
          if (!compact && advice.diseaseWatch.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              advice.diseaseWatch,
              maxLines: compact ? 3 : 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textDark,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(row.key, size: 16, color: AppTheme.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.value,
                      maxLines: compact ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

class _LifecycleTimelineTile extends StatelessWidget {
  final CropLifecycleStage stage;
  final int index;
  final bool compact;
  final bool isCurrent;
  final bool isComplete;
  final String stageLabel;
  final String statusText;

  const _LifecycleTimelineTile({
    required this.stage,
    required this.index,
    required this.compact,
    required this.isCurrent,
    required this.isComplete,
    required this.stageLabel,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isCurrent
        ? AppTheme.green
        : isComplete
        ? AppTheme.greenDark.withValues(alpha: 0.58)
        : AppTheme.textMuted.withValues(alpha: 0.38);
    final background = isCurrent
        ? const Color(0xFFEAF6E8)
        : isComplete
        ? const Color(0xFFF4F8F1)
        : const Color(0xFFF9FBF7);
    final icon = isCurrent
        ? Icons.play_arrow_rounded
        : isComplete
        ? Icons.check_rounded
        : Icons.more_horiz_rounded;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? AppTheme.green : const Color(0xFFDCEBD9),
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppTheme.green.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: Colors.white),
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                Container(
                  width: 2,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stageLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.greenDark,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.greenDark,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  UiStrings.f('day_range_value', {
                    'start': stage.startDay,
                    'end': stage.endDay,
                  }),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    height: 1.3,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (stage.detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    stage.detail,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      height: 1.25,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: content,
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
              _localizedSatelliteTileTitle(tile.title),
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

String _localizedSatelliteTileTitle(String title) {
  final value = title.toLowerCase();
  if (value.contains('water')) return UiStrings.t('water_level');
  if (value.contains('crop health')) return UiStrings.t('crop_health');
  if (value.contains('canopy')) return UiStrings.t('canopy_ground_structure');
  if (value.contains('trend')) return UiStrings.t('crop_trend');
  return title;
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
  final _FarmSatelliteOverview? satelliteOverview;
  final double diseaseMaxRisk;
  final bool isLoading;
  final CropLifecycleAdvice? lifecycleAdvice;
  final String currentStage;
  final String currentStatus;
  final DateTime? statusUpdatedAt;
  final DiseaseScreenResult? diseaseScreen;
  final VoidCallback onOpenFarm;

  const _FarmSnapshotCard({
    required this.farm,
    required this.satelliteOverview,
    required this.diseaseMaxRisk,
    required this.isLoading,
    required this.lifecycleAdvice,
    required this.currentStage,
    required this.currentStatus,
    required this.statusUpdatedAt,
    required this.diseaseScreen,
    required this.onOpenFarm,
  });

  @override
  Widget build(BuildContext context) {
    final ndvi = satelliteOverview?.ndvi;
    final moisture = satelliteOverview?.moisture;
    final condition = _conditionLabel(ndvi, moisture);
    final conditionDetail = _conditionDetail(ndvi, moisture);
    final lifecycleAction = lifecycleAdvice?.nextAction.trim() ?? '';
    final actionText = lifecycleAction.isNotEmpty
        ? lifecycleAction
        : _fallbackAction(ndvi, moisture);
    final conditionColor = _conditionColor(ndvi, moisture);
    final statusText = currentStatus.trim().isEmpty
        ? UiStrings.t('not_updated')
        : currentStatus.trim();
    final stageText = currentStage.trim().isEmpty
        ? ''
        : UiStrings.option(currentStage.trim().replaceAll('-', ' '));
    final statusValue = stageText.isEmpty
        ? UiStrings.option(statusText)
        : '$stageText • ${UiStrings.option(statusText)}';
    final updatedText = statusUpdatedAt == null
        ? UiStrings.t('not_updated')
        : '${LocaleText.date(statusUpdatedAt!, pattern: 'dd/MM')} ${LocaleText.time(statusUpdatedAt!)}';

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
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        conditionColor.withValues(alpha: 0.88),
                        AppTheme.greenDark,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.health_and_safety_outlined,
                    color: Colors.white,
                    size: 29,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        UiStrings.label(farm.name),
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
                        '${UiStrings.label(farm.area)} • ${UiStrings.option(farm.crop)} • ${UiStrings.option(farm.variety)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: onOpenFarm,
                  child: Text(UiStrings.t('open')),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _InfoStrip(
              icon: Icons.track_changes_rounded,
              label: UiStrings.t('current_status'),
              value: statusValue,
            ),
            _InfoStrip(
              icon: Icons.biotech_outlined,
              label: UiStrings.t('disease_detection'),
              value: _diseaseDetectionText(),
            ),
            _InfoStrip(
              icon: Icons.schedule_outlined,
              label: UiStrings.t('last_update'),
              value: updatedText,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: conditionColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: conditionColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: conditionColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${UiStrings.t('farm_condition')}: $condition',
                          style: TextStyle(
                            color: conditionColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    conditionDetail,
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.task_alt_rounded,
                        color: conditionColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          actionText,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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

  String _diseaseDetectionText() {
    final screen = diseaseScreen;
    if (isLoading && screen == null) {
      return UiStrings.t('disease_detection_loading_desc');
    }
    if (screen == null) {
      return UiStrings.t('disease_detection_missing_desc');
    }
    final topRisks = screen.topDiseaseRisks.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    if (topRisks.isNotEmpty && topRisks.first.value > 0) {
      final disease = UiStrings.option(topRisks.first.key.replaceAll('_', ' '));
      final risk = _formatLocalizedPercent(
        (topRisks.first.value * 100).round(),
      );
      if (topRisks.first.value >= 0.55 || screen.highRiskCells > 0) {
        return UiStrings.f('disease_detection_high_desc', {
          'disease': disease,
          'risk': risk,
          'cells': LocaleText.number(screen.highRiskCells),
        });
      }
      return UiStrings.f('disease_detection_watch_desc', {
        'disease': disease,
        'risk': risk,
      });
    }
    final message = screen.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    return UiStrings.t('disease_detection_clear_desc');
  }

  String _conditionLabel(double? ndvi, double? moisture) {
    if (isLoading && ndvi == null && moisture == null && diseaseMaxRisk <= 0) {
      return UiStrings.t('loading');
    }
    if (diseaseMaxRisk >= 0.72 || (ndvi != null && ndvi < 0.35)) {
      return UiStrings.t('high');
    }
    if (diseaseMaxRisk >= 0.55 ||
        (ndvi != null && ndvi < 0.50) ||
        (moisture != null && moisture < 0.32)) {
      return UiStrings.t('watch');
    }
    return UiStrings.t('good');
  }

  String _conditionDetail(double? ndvi, double? moisture) {
    if (isLoading && ndvi == null && moisture == null && diseaseMaxRisk <= 0) {
      return UiStrings.t('farm_condition_loading_desc');
    }
    if (diseaseMaxRisk >= 0.72 || (ndvi != null && ndvi < 0.35)) {
      return UiStrings.t('farm_condition_high_desc');
    }
    if (diseaseMaxRisk >= 0.55 ||
        (ndvi != null && ndvi < 0.50) ||
        (moisture != null && moisture < 0.32)) {
      return UiStrings.t('farm_condition_watch_desc');
    }
    return UiStrings.t('farm_condition_good_desc');
  }

  String _fallbackAction(double? ndvi, double? moisture) {
    if (diseaseMaxRisk >= 0.72 || (ndvi != null && ndvi < 0.35)) {
      return UiStrings.t('farm_action_high');
    }
    if (moisture != null && moisture < 0.32) {
      return UiStrings.t('farm_action_water');
    }
    if (diseaseMaxRisk >= 0.55 || (ndvi != null && ndvi < 0.50)) {
      return UiStrings.t('farm_action_watch');
    }
    return UiStrings.t('farm_action_good');
  }

  Color _conditionColor(double? ndvi, double? moisture) {
    if (diseaseMaxRisk >= 0.72 || (ndvi != null && ndvi < 0.35)) {
      return const Color(0xFFD32F2F);
    }
    if (diseaseMaxRisk >= 0.55 ||
        (ndvi != null && ndvi < 0.50) ||
        (moisture != null && moisture < 0.32)) {
      return const Color(0xFFF57C00);
    }
    return AppTheme.green;
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
                      Text(
                        UiStrings.t('harvest_readiness'),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        UiStrings.f('crop_batch_grade_ready', {
                          'crop': UiStrings.option(farm.crop),
                        }),
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
                _HarvestMetric(
                  label: UiStrings.t('estimated_bags'),
                  value: '12',
                ),
                _HarvestMetric(
                  label: UiStrings.t('quality'),
                  value: UiStrings.t('ready'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: onOpenAiChat,
                  child: Text(UiStrings.t('harvest')),
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
  final double? ndvi;
  final double? moisture;

  const _FarmSatelliteOverview({
    required this.tiles,
    this.note,
    this.ndvi,
    this.moisture,
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
            title: UiStrings.t('disease_risk_checked'),
            detail: UiStrings.f('farm_activity_detail', {
              'farm': farm.name,
              'detail': UiStrings.t('leaf_spot_moderate'),
            }),
            onTap: onOpenDisease,
          ),
          const Divider(height: 1),
          _ActivityRow(
            icon: Icons.auto_awesome_outlined,
            iconColor: const Color(0xFF1976D2),
            title: UiStrings.t('ai_guidance'),
            detail: UiStrings.f('farm_activity_detail', {
              'farm': farm.crop,
              'detail': UiStrings.f('grade_value', {'grade': 'A'}),
            }),
            onTap: onOpenAiChat,
          ),
          const Divider(height: 1),
          _ActivityRow(
            icon: Icons.qr_code_2_outlined,
            iconColor: AppTheme.green,
            title: UiStrings.t('need_ai_check'),
            detail: UiStrings.t('create_bag_plan_quickly'),
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
          OutlinedButton(onPressed: onTap, child: Text(UiStrings.t('view'))),
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
  final VoidCallback onOpenInventory;
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
    required this.onOpenInventory,
    required this.onHarvestCompleted,
  });

  @override
  State<_HarvestHomePage> createState() => _HarvestHomePageState();
}

class _HarvestHomePageState extends State<_HarvestHomePage> {
  final _moistureCtrl = TextEditingController();
  final _bagSizeCtrl = TextEditingController(text: '50');
  final _bagCountCtrl = TextEditingController(text: '12');
  final GrainGradingService _service = GrainGradingService();
  bool _readingMoisture = false;
  bool _hasMoistureImage = false;
  bool _isLocationFetching = false;
  bool _isCapturingImage = false;
  bool _isCapturingGrainImage = false;
  bool _isGrading = false;
  bool _hasGrade = false;
  String _batchId = '';
  double? _farmLatitude;
  double? _farmLongitude;
  MoistureOcrResult? _moistureReading;
  Uint8List? _moistureImageBytes;
  String? _moistureImageName;
  Uint8List? _grainImageBytes;
  String? _grainImageName;
  String _grade = '--';
  int _gradeScore = 0;
  String _gradingMessage = UiStrings.t('run_grading_message');
  _HarvestInventoryLot? _pendingInventoryLot;
  bool _inventoryAdded = false;

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

  int _fallbackScoreForGrade(String grade) {
    switch (grade.trim().toUpperCase()) {
      case 'A+':
        return 94;
      case 'A':
        return 88;
      case 'B+':
        return 80;
      case 'B':
        return 74;
      case 'C':
        return 62;
      default:
        return 50;
    }
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
    _service.dispose();
    super.dispose();
  }

  String get _locationSummary {
    if (_farmLatitude == null || _farmLongitude == null) {
      return '';
    }
    return '${LocaleText.number(_farmLatitude!, fractionDigits: 5)}, ${LocaleText.number(_farmLongitude!, fractionDigits: 5)}';
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
        _hasMoistureImage &&
        _moistureImageBytes != null &&
        _grainImageBytes != null &&
        _farmLatitude != null &&
        _farmLongitude != null;
  }

  bool get _canCaptureMoistureImage =>
      _farmLatitude != null && _farmLongitude != null;

  Future<HarvestMachineImageSource?> _chooseHarvestImageSource(
    String title, {
    required String cameraSubtitle,
    required String gallerySubtitle,
  }) {
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
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: Text(UiStrings.t('open_camera')),
                  subtitle: Text(cameraSubtitle),
                  onTap: () =>
                      Navigator.pop(context, HarvestMachineImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: Text(UiStrings.t('select_from_gallery')),
                  subtitle: Text(gallerySubtitle),
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

  Future<HarvestMachineImageSource?> _chooseMoistureImageSource() {
    return _chooseHarvestImageSource(
      UiStrings.t('add_moisture_meter_photo'),
      cameraSubtitle: UiStrings.t('click_new_machine_photo'),
      gallerySubtitle: UiStrings.t('use_existing_machine_image'),
    );
  }

  Future<HarvestMachineImageSource?> _chooseGrainImageSource() {
    return _chooseHarvestImageSource(
      UiStrings.t('grain_image_section'),
      cameraSubtitle: UiStrings.t('capture_grain_image'),
      gallerySubtitle: UiStrings.t('grain_image_section'),
    );
  }

  Future<void> _captureMoistureImage() async {
    if (_farmLatitude == null || _farmLongitude == null) {
      Get.snackbar(
        UiStrings.t('live_location_required'),
        UiStrings.t('capture_moisture_after_location'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final source = await _chooseMoistureImageSource();
    if (source == null) return;
    if (!mounted) return;
    final canUsePhoto = await PolicyDisclosureService.confirmPhotoUse(context);
    if (!canUsePhoto) return;

    setState(() => _isCapturingImage = true);
    try {
      final result = await pickHarvestMachineImage(source: source);
      if (result == null) return;
      if (!mounted) return;
      setState(() {
        _moistureImageBytes = result.bytes;
        _moistureImageName = result.name;
        _hasMoistureImage = true;
        _moistureReading = null;
        _hasGrade = false;
        _grade = '--';
        _gradeScore = 0;
        _gradingMessage = UiStrings.t('run_grading_message');
        _pendingInventoryLot = null;
        _inventoryAdded = false;
      });
      Get.snackbar(
        UiStrings.t('moisture_photo_added'),
        UiStrings.f('meter_photo_linked_to_location', {
          'location': _locationSummary,
        }),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      Get.snackbar(
        UiStrings.t('image_capture_error'),
        UiStrings.t('image_capture_retry'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isCapturingImage = false);
    }
  }

  Future<void> _captureGrainImage() async {
    final source = await _chooseGrainImageSource();
    if (source == null) return;
    if (!mounted) return;
    final canUsePhoto = await PolicyDisclosureService.confirmPhotoUse(context);
    if (!canUsePhoto) return;

    setState(() => _isCapturingGrainImage = true);
    try {
      final result = await pickHarvestMachineImage(source: source);
      if (result == null) return;
      if (!mounted) return;
      setState(() {
        _grainImageBytes = result.bytes;
        _grainImageName = result.name;
        _hasGrade = false;
        _grade = '--';
        _gradeScore = 0;
        _gradingMessage = UiStrings.t('run_grading_message');
        _pendingInventoryLot = null;
        _inventoryAdded = false;
      });
      Get.snackbar(
        UiStrings.t('grain_image_added'),
        UiStrings.t('grain_image_ready'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      Get.snackbar(
        UiStrings.t('image_capture_error'),
        UiStrings.t('image_capture_retry'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isCapturingGrainImage = false);
    }
  }

  Future<void> _readMoisture() async {
    if (_moistureImageBytes == null) {
      Get.snackbar(
        UiStrings.t('moisture_photo_required'),
        UiStrings.t('capture_meter_photo_first'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    setState(() => _readingMoisture = true);
    try {
      final reading = await _service.readMoisture(
        moistureImageBytes: _moistureImageBytes,
        moistureImageName: _moistureImageName ?? 'moisture-meter.jpg',
      );
      if (!mounted) return;
      setState(() {
        _readingMoisture = false;
        _moistureReading = reading;
        if (reading.percent != null) {
          _moistureCtrl.text = reading.percent!.toStringAsFixed(1);
        }
      });
    } on GradingException catch (e) {
      if (!mounted) return;
      setState(() => _readingMoisture = false);
      Get.snackbar(
        UiStrings.t('moisture_read_failed_title'),
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _readingMoisture = false);
      Get.snackbar(
        UiStrings.t('moisture_read_failed_title'),
        UiStrings.t('moisture_read_retry'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _readingMoisture = false);
    }
  }

  Future<void> _fetchLocation() async {
    setState(() => _isLocationFetching = true);
    try {
      final service = LocationService();
      final location = await service.getCurrentLocation();
      if (location == null || !mounted) {
        Get.snackbar(
          UiStrings.t('location_unavailable_title'),
          UiStrings.t('location_unavailable_body'),
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
        UiStrings.t('location_error_title'),
        UiStrings.t('location_error_body'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      if (mounted) setState(() => _isLocationFetching = false);
    }
  }

  Future<void> _runHarvestGrade() async {
    if (_grainImageBytes == null) {
      Get.snackbar(
        UiStrings.t('grain_image_required'),
        UiStrings.t('capture_grain_image_first'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    if (!_canRunGrading || _isGrading) return;
    final moisture = double.parse(_moistureCtrl.text.trim());
    final bagSize = double.parse(_bagSizeCtrl.text.trim());
    final bagCount = int.parse(_bagCountCtrl.text.trim());
    final batchId = _createBatchId();

    setState(() {
      _isGrading = true;
    });
    try {
      final result = await _service.analyze(
        grainImageBytes: _grainImageBytes!,
        grainImageName: _grainImageName ?? 'grain.jpg',
        moistureImageBytes: _moistureImageBytes,
        moistureImageName: _moistureImageName ?? 'moisture-meter.jpg',
        manualMoisturePercent: moisture,
        cropType: widget.cropName,
        cropVariety: widget.variety,
        farmerId: widget.farmerId,
        batchId: batchId,
        bagSizeKg: bagSize,
        bagCount: bagCount,
        source: 'farmer_harvest_page',
      );
      if (!mounted) return;

      final grade = result.grade.trim().isEmpty ? '--' : result.grade;
      final rawScore =
          result.finalScore?.round() ?? _fallbackScoreForGrade(grade);
      final score = math.max(0, math.min(100, rawScore));
      final moisturePercent = result.moisturePercent ?? moisture;
      final gradeBasis = result.operatorSummary.trim().isNotEmpty
          ? result.operatorSummary.trim()
          : UiStrings.t('moisture_grade_message');
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
        _gradingMessage = gradeBasis;
        _pendingInventoryLot = _HarvestInventoryLot(
          batchId: batchId,
          farmName: widget.farmName,
          crop: widget.cropName,
          variety: widget.variety,
          bagCount: bagCount,
          bagSizeKg: bagSize,
          moisturePercent: moisturePercent,
          grade: grade,
          gradeScore: score,
          gradeBasis: gradeBasis,
          estimatedYieldKg: estimatedYield,
          harvestedAt: DateTime.now(),
          latitude: _farmLatitude!,
          longitude: _farmLongitude!,
          machineImageName:
              _grainImageName ?? _moistureImageName ?? 'grain-grading',
        );
        _inventoryAdded = false;
      });

      Get.snackbar(
        UiStrings.t('harvest_grading_complete'),
        UiStrings.f('harvest_grading_complete_body', {
          'grade': _grade,
          'score': _gradeScore,
        }),
        snackPosition: SnackPosition.BOTTOM,
      );
    } on GradingException catch (e) {
      if (!mounted) return;
      setState(() => _isGrading = false);
      Get.snackbar(
        UiStrings.t('image_capture_error'),
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isGrading = false);
      Get.snackbar(
        UiStrings.t('image_capture_error'),
        UiStrings.t('image_capture_retry'),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _addGradedProductToInventory() {
    final lot = _pendingInventoryLot;
    if (!_hasGrade || lot == null) {
      Get.snackbar(
        UiStrings.t('harvest_grade_required'),
        UiStrings.t('harvest_grade_required_body'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    widget.onHarvestCompleted(lot);
    setState(() => _inventoryAdded = true);
    Get.snackbar(
      UiStrings.t('inventory'),
      UiStrings.f('product_added_inventory', {'batch': lot.batchId}),
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void _openHarvestQr() {
    if (!_hasGrade) {
      Get.snackbar(
        UiStrings.t('harvest_grade_required'),
        UiStrings.t('harvest_grade_required_body'),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    if (!_canRunGrading) {
      Get.snackbar(
        UiStrings.t('harvest_qr_inputs_required_title'),
        UiStrings.t('harvest_qr_inputs_required_body'),
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
        'machineImage': _grainImageName ?? _moistureImageName ?? 'captured',
        'bagSizeKg': bagSize,
        'bagCount': bagCount,
        'totalKg': totalKg,
        'moisture': moisture,
        'moistureSource': _moistureReading?.source ?? 'manual-meter',
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
      title: UiStrings.t('harvest_hub'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HarvestChecklistHero(
                    farmName: widget.farmName,
                    area: widget.area,
                    cropName: widget.cropName,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusPill(
                        icon: Icons.spa_rounded,
                        label: UiStrings.option(widget.harvestHealth),
                      ),
                      _StatusPill(
                        icon: Icons.wb_twilight,
                        label: UiStrings.f('seven_days_range', {
                          'start': 5,
                          'end': 7,
                        }),
                      ),
                      _StatusPill(
                        icon: Icons.inventory_2_outlined,
                        label: UiStrings.f('bags_range', {
                          'start': 12,
                          'end': 16,
                        }),
                      ),
                      if (_farmLatitude != null && _farmLongitude != null)
                        _StatusPill(
                          icon: Icons.gps_fixed_rounded,
                          label: UiStrings.t('harvest_location_captured'),
                        ),
                      if (_hasMoistureImage)
                        _StatusPill(
                          icon: Icons.photo_camera_front_rounded,
                          label: UiStrings.t('harvest_photo_ready'),
                        ),
                      if (_grainImageBytes != null)
                        _StatusPill(
                          icon: Icons.grain_rounded,
                          label: UiStrings.t('grain_image_ready'),
                        ),
                      if (_hasGrade)
                        _StatusPill(
                          icon: Icons.verified_rounded,
                          label: UiStrings.t('grade_result'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _HarvestSectionTitle(
                    icon: Icons.my_location_rounded,
                    title: UiStrings.t('live_location'),
                  ),
                  const SizedBox(height: 10),
                  _CompactActionSlot(
                    child: OutlinedButton.icon(
                      onPressed: _isLocationFetching ? null : _fetchLocation,
                      icon: _isLocationFetching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.green,
                              ),
                            )
                          : const Icon(Icons.my_location_rounded),
                      label: Text(
                        UiStrings.t('live_location'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_farmLatitude != null && _farmLongitude != null) ...[
                    const SizedBox(height: 8),
                    _InlineNotice(
                      icon: Icons.gps_fixed_rounded,
                      text: UiStrings.f('live_location_value', {
                        'value': _locationSummary,
                      }),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _HarvestSectionTitle(
                    icon: Icons.water_drop_rounded,
                    title: UiStrings.t('moisture_capture_section'),
                  ),
                  const SizedBox(height: 10),
                  _CompactActionSlot(
                    child: OutlinedButton.icon(
                      onPressed: _isCapturingImage || !_canCaptureMoistureImage
                          ? null
                          : _captureMoistureImage,
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
                              _hasMoistureImage
                                  ? Icons.check_circle_rounded
                                  : Icons.photo_camera_front_rounded,
                            ),
                      label: Text(
                        _hasMoistureImage
                            ? UiStrings.t('retake_moisture_photo')
                            : UiStrings.t('capture_moisture_photo'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_moistureImageBytes != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.memory(
                          _moistureImageBytes!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _CompactActionSlot(
                      child: OutlinedButton.icon(
                        onPressed: _readingMoisture ? null : _readMoisture,
                        icon: _readingMoisture
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.green,
                                ),
                              )
                            : const Icon(Icons.speed_rounded),
                        label: Text(
                          UiStrings.t('read_meter_moisture'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  if (_moistureReading != null) ...[
                    const SizedBox(height: 10),
                    _HarvestMoistureReadingCard(reading: _moistureReading!),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _moistureCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: UiStrings.t('moisture_input_label'),
                      suffixText: '%',
                      prefixIcon: Icon(Icons.percent_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _HarvestSectionTitle(
                    icon: Icons.grain_rounded,
                    title: UiStrings.t('grain_image_section'),
                  ),
                  const SizedBox(height: 10),
                  _CompactActionSlot(
                    child: OutlinedButton.icon(
                      onPressed: _isCapturingGrainImage || !_hasMoistureImage
                          ? null
                          : _captureGrainImage,
                      icon: _isCapturingGrainImage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.green,
                              ),
                            )
                          : Icon(
                              _grainImageBytes != null
                                  ? Icons.check_circle_rounded
                                  : Icons.grain_rounded,
                            ),
                      label: Text(
                        _grainImageBytes != null
                            ? UiStrings.t('retake_grain_image')
                            : UiStrings.t('capture_grain_image'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_grainImageBytes != null) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.memory(
                          _grainImageBytes!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _HarvestSectionTitle(
                    icon: Icons.inventory_2_rounded,
                    title: UiStrings.t('bag_details'),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 360;
                      final bagSize = TextField(
                        controller: _bagSizeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: UiStrings.t('bag_size_label'),
                        ),
                      );
                      final bagCount = TextField(
                        controller: _bagCountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: UiStrings.t('bag_count_label'),
                        ),
                      );
                      if (compact) {
                        return Column(
                          children: [
                            bagSize,
                            const SizedBox(height: 10),
                            bagCount,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: bagSize),
                          const SizedBox(width: 10),
                          Expanded(child: bagCount),
                        ],
                      );
                    },
                  ),
                  if (_farmLatitude != null && _farmLongitude != null) ...[
                    const SizedBox(height: 10),
                    _InlineNotice(
                      icon: Icons.location_on_rounded,
                      text: UiStrings.f('live_location_value', {
                        'value': _locationSummary,
                      }),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _CompactActionSlot(
                    maxWidth: 300,
                    child: ElevatedButton.icon(
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
                            ? UiStrings.t('running_grading')
                            : UiStrings.t('grade_grain_action'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                                    Text(
                                      UiStrings.t('grade_result'),
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _hasGrade
                                          ? UiStrings.f('grade_summary_line', {
                                              'grade': _grade,
                                              'score': '$_gradeScore',
                                              'message': _gradingMessage,
                                            })
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
                              UiStrings.f('harvest_verified_with_standard', {
                                'crop': widget.cropName,
                              }),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _CompactActionSlot(
                              maxWidth: 300,
                              child: FilledButton.icon(
                                onPressed: _inventoryAdded
                                    ? widget.onOpenInventory
                                    : _addGradedProductToInventory,
                                icon: Icon(
                                  _inventoryAdded
                                      ? Icons.inventory_2_rounded
                                      : Icons.add_business_rounded,
                                ),
                                label: Text(
                                  _inventoryAdded
                                      ? UiStrings.t('view_inventory')
                                      : UiStrings.t('add_product_inventory'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
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
                          ? UiStrings.t('generate_harvest_qr')
                          : UiStrings.t('grade_first_unlock_qr'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: widget.onOpenAiChat,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(UiStrings.t('ask_ai_harvest_action')),
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

class _HarvestChecklistHero extends StatelessWidget {
  final String farmName;
  final String area;
  final String cropName;

  const _HarvestChecklistHero({
    required this.farmName,
    required this.area,
    required this.cropName,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 16 / 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/Farm_home_top_widget_images/harvesting.webp',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Image.asset(BrandAssets.kalsubaiFarms, fit: BoxFit.cover),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.06),
                    Colors.black.withValues(alpha: 0.58),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    UiStrings.t('harvest_checklist'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${UiStrings.label(farmName)} • ${UiStrings.label(area)} • ${UiStrings.option(cropName)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
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

class _CompactActionSlot extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const _CompactActionSlot({required this.child, this.maxWidth = 280});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: math.min(maxWidth, constraints.maxWidth).toDouble(),
            child: child,
          );
        },
      ),
    );
  }
}

class _HarvestSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _HarvestSectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.greenPale,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.green, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 17,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineNotice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.green, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
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
  final bool isFarmSyncing;
  final String farmSyncError;
  final VoidCallback onRetryFarmSync;
  final VoidCallback onAddFarm;
  final ValueChanged<int> onOpenFarmInsight;
  final ValueChanged<int> onOpenStatusUpdate;
  final Future<void> Function(int index) onRefreshAlerts;
  final void Function(int, FarmIssueCell) onOpenIssue;
  final Map<int, List<LatLng>> farmPolygons;
  final _FarmStatusSnapshot Function(int index) statusSnapshotForFarm;
  final Map<int, List<LatLng>> diseaseMarkersByFarm;
  final Map<int, List<Map<String, dynamic>>> scoutZonesByFarm;
  final Map<int, List<Map<String, dynamic>>> riskCellsByFarm;
  final List<FarmIssueCell> issueCells;
  final Map<int, DiseaseScreenResult> diseaseScreenByFarm;
  final Map<int, FarmAlertAdvice> alertAdviceByFarm;
  final Map<int, String> alertErrorByFarm;
  final Set<int> alertLoading;
  final Map<int, List<FarmTimelineEvent>> timelineByFarm;
  final Set<int> timelineLoading;
  final String Function(int) stageSummary;
  final int Function(int) daysAfterSowing;

  const _FarmPage({
    required this.farms,
    required this.selectedIndex,
    required this.isFarmSyncing,
    required this.farmSyncError,
    required this.onRetryFarmSync,
    required this.onAddFarm,
    required this.onOpenFarmInsight,
    required this.onOpenStatusUpdate,
    required this.onRefreshAlerts,
    required this.onOpenIssue,
    required this.farmPolygons,
    required this.statusSnapshotForFarm,
    required this.diseaseMarkersByFarm,
    required this.scoutZonesByFarm,
    required this.riskCellsByFarm,
    required this.issueCells,
    required this.diseaseScreenByFarm,
    required this.alertAdviceByFarm,
    required this.alertErrorByFarm,
    required this.alertLoading,
    required this.timelineByFarm,
    required this.timelineLoading,
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

  static double? _readCoordinate(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static LatLng? _parseCoordinatePair(num? maybeLat, num? maybeLng) {
    if (maybeLat == null || maybeLng == null) return null;
    final first = maybeLat.toDouble();
    final second = maybeLng.toDouble();
    if (first.abs() <= 90 && second.abs() <= 180) {
      return LatLng(first, second);
    }
    if (first.abs() <= 180 && second.abs() <= 90) {
      return LatLng(second, first);
    }
    return null;
  }

  static LatLng? _parsePointObject(dynamic value) {
    if (value == null) return null;
    if (value is LatLng) return value;
    if (value is List) {
      if (value.length >= 2) {
        final first = _readCoordinate(value[0]);
        final second = _readCoordinate(value[1]);
        if (first == null || second == null) return null;
        return _parseCoordinatePair(first, second);
      }
      return null;
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final directLat = _readCoordinate(
        map['lat'] ?? map['latitude'] ?? map['y'],
      );
      final directLng = _readCoordinate(
        map['lng'] ?? map['lon'] ?? map['long'] ?? map['x'],
      );
      if (directLat != null && directLng != null) {
        return _parseCoordinatePair(directLat, directLng);
      }
      return _parsePointFromMap(map);
    }

    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      if (text.startsWith('{') || text.startsWith('[')) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map) {
            return _parsePointObject(Map<String, dynamic>.from(decoded));
          }
          if (decoded is List) {
            return _parsePointObject(decoded);
          }
        } catch (_) {
          // Fallback to regex parse for POINT and comma notation.
        }
      }

      final pointMatch = RegExp(
        r'POINT\s*\(\s*([+-]?\d*\.?\d+)\s+([+-]?\d*\.?\d+)\s*\)',
        caseSensitive: false,
      ).firstMatch(text);
      if (pointMatch != null) {
        final a = double.tryParse(pointMatch.group(1) ?? '');
        final b = double.tryParse(pointMatch.group(2) ?? '');
        if (a == null || b == null) return null;
        return _parseCoordinatePair(a, b);
      }

      if (text.contains(',')) {
        final parts = text.split(',');
        if (parts.length >= 2) {
          final first = double.tryParse(parts[0].trim());
          final second = double.tryParse(parts[1].trim());
          return _parseCoordinatePair(first, second);
        }
      }
      final spaceSplit = text.trim().split(RegExp(r'\s+'));
      if (spaceSplit.length >= 2) {
        final first = double.tryParse(spaceSplit[0]);
        final second = double.tryParse(spaceSplit[1]);
        return _parseCoordinatePair(first, second);
      }
    }

    return null;
  }

  static LatLng? _parsePointFromMap(Map<String, dynamic> map) {
    final centroid = _parsePointObject(map['centroid']);
    if (centroid != null) return centroid;
    final geometry = _parsePointObject(map['geometry']);
    if (geometry != null) return geometry;
    final point = _parsePointObject(map['point']);
    if (point != null) return point;
    final coordinates = _parsePointObject(map['coordinates']);
    if (coordinates != null) return coordinates;
    if (map.containsKey('coordinates') && map['coordinates'] is List) {
      final coordinates = map['coordinates'] as List;
      if (coordinates.isNotEmpty && coordinates[0] is List) {
        final ring = coordinates[0] as List;
        return _parsePointFromRing(ring);
      }
    }
    return null;
  }

  static LatLng? _parsePointFromRing(List<dynamic> ring) {
    if (ring.isEmpty) return null;
    double latSum = 0;
    double lngSum = 0;
    var pointCount = 0;
    for (final point in ring) {
      if (point is! List || point.length < 2) continue;
      final lat = _readCoordinate(point[0]);
      final lng = _readCoordinate(point[1]);
      if (lat == null || lng == null) continue;
      final parsed = _parseCoordinatePair(lat, lng);
      if (parsed == null) continue;
      latSum += parsed.latitude;
      lngSum += parsed.longitude;
      pointCount++;
    }
    if (pointCount == 0) return null;
    return LatLng(latSum / pointCount, lngSum / pointCount);
  }

  static LatLng? _readIssuePoint(Map<String, dynamic> row) {
    final latLng = _parsePointFromMap(row);
    if (latLng != null) return latLng;

    final direct = _parseCoordinatePair(
      _readCoordinate(row['lat']) ?? _readCoordinate(row['cell_lat']),
      _readCoordinate(row['lng']) ?? _readCoordinate(row['cell_lng']),
    );
    if (direct != null) return direct;

    final centroid = _parseCoordinatePair(
      _readCoordinate(row['centroid_lat']),
      _readCoordinate(row['centroid_lng']),
    );
    if (centroid != null) return centroid;

    return null;
  }

  static String _issueCoordinateKey(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)}|${point.longitude.toStringAsFixed(6)}';
  }

  static bool _isVisibleIssue(FarmIssueCell issue) {
    if (issue.compositeRisk > 0.0) return true;
    if (issue.isDisease) {
      return issue.compositeRisk > 0.0 ||
          issue.diseaseCandidates.isNotEmpty ||
          issue.weatherRisk != null;
    }
    if (issue.likelyAbiotic) return true;
    final weatherRisk = issue.weatherRisk;
    return weatherRisk != null && weatherRisk > 0.0;
  }

  List<Map<String, dynamic>> _riskRowsForMap(
    List<Map<String, dynamic>> riskCells,
    List<FarmIssueCell> issueCells,
  ) {
    final rows = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addRow(Map<String, dynamic> row) {
      final normalized = Map<String, dynamic>.from(row);
      final point = _readIssuePoint(normalized);
      if (point == null) return;
      final key = _issueCoordinateKey(point);
      if (!seen.add(key)) return;
      normalized['lat'] = point.latitude;
      normalized['lng'] = point.longitude;
      rows.add(normalized);
    }

    for (final row in riskCells) {
      addRow(row);
    }
    for (final cell in issueCells) {
      if (cell.hasLocation) addRow(cell.toJson());
    }

    return rows;
  }

  static Color _riskColor(double risk) {
    if (risk >= 0.72) return const Color(0xFFD32F2F);
    if (risk >= 0.55) return const Color(0xFFF57C00);
    if (risk >= 0.35) return const Color(0xFFFBC02D);
    return AppTheme.green;
  }

  static String _riskLabel(double risk) {
    if (risk >= 0.72) return UiStrings.t('high');
    if (risk >= 0.55) return UiStrings.t('watch');
    if (risk > 0) return UiStrings.t('low');
    return UiStrings.t('pending');
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
    if (raw.isEmpty) return UiStrings.t('not_screened_yet');
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return LocaleText.date(parsed, pattern: 'dd/MM/yyyy');
  }

  static String _formatWeatherValue(Object? raw, String suffix) {
    if (raw is num) {
      return '${LocaleText.number(raw, fractionDigits: raw >= 10 ? 0 : 1)}$suffix';
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return '${LocaleText.digits(raw)}$suffix';
    }
    return '--';
  }

  static const Color _abioticColor = Color(0xFF1976D2);
  static const Color _zoneColor = Color(0xFF7B1FA2);

  static Color _issueColor(FarmIssueCell issue) {
    if (issue.isScoutZone) return _zoneColor;
    if (!issue.isDisease) {
      if (issue.likelyAbiotic) return _abioticColor;
      if (issue.compositeRisk > 0) {
        return _riskColor(math.max(issue.compositeRisk, 0.35));
      }
      return _abioticColor;
    }
    // Disease candidates never render green: floor at the amber band.
    return _riskColor(math.max(issue.compositeRisk, 0.35));
  }

  static IconData _issueIcon(FarmIssueCell issue) {
    if (issue.isScoutZone) return Icons.travel_explore_rounded;
    if (!issue.isDisease) {
      return issue.likelyAbiotic
          ? Icons.water_drop_rounded
          : Icons.warning_amber_rounded;
    }
    return Icons.coronavirus_rounded;
  }

  static String _issueTitle(FarmIssueCell issue) {
    if (issue.isScoutZone) return UiStrings.t('scout_zone_title');
    if (!issue.isDisease) {
      return issue.likelyAbiotic
          ? UiStrings.t('crop_stress_title')
          : UiStrings.t('satellite_risk_cell');
    }
    final names = issue.diseaseCandidates
        .map((name) => name.replaceAll('_', ' '))
        .join(', ');
    return UiStrings.f('possible_names', {'names': names});
  }

  /// Issue locations worth a walk: disease cells only when symptoms are strong
  /// Keep visibility stable but not overly strict.
  static List<FarmIssueCell> _visibleIssues(List<FarmIssueCell> cells) {
    final ranked = List<FarmIssueCell>.from(cells)
      ..sort((a, b) => b.compositeRisk.compareTo(a.compositeRisk));
    return ranked.where(_isVisibleIssue).take(80).toList(growable: false);
  }

  static double _issueLevel(FarmIssueCell issue) {
    if (issue.isScoutZone) return 1.0;
    final raw = issue.isDisease
        ? issue.compositeRisk
        : (issue.weatherRisk ?? issue.compositeRisk);
    final t = ((raw - 0.25) / 0.75).clamp(0.0, 1.0).toDouble();
    return issue.isDisease ? t : math.max(t, 0.35);
  }

  static double _issueDiameter(FarmIssueCell issue) {
    if (issue.isScoutZone) return 80;
    return 34 + (70 - 34) * _issueLevel(issue);
  }

  static double _issueCenterAlpha(FarmIssueCell issue) {
    final t = issue.isScoutZone ? 0.6 : _issueLevel(issue);
    return 0.45 + (0.85 - 0.45) * t;
  }

  List<Marker> _issueMarkers({
    required List<FarmIssueCell> cells,
    required List<Map<String, dynamic>> scoutZones,
    required List<Map<String, dynamic>> riskCells,
    required void Function(FarmIssueCell) onTap,
  }) {
    final seen = <String>{};
    final issues = <FarmIssueCell>[];

    void addIssue(FarmIssueCell issue) {
      if (!_isVisibleIssue(issue) || !issue.hasLocation) return;
      final point = LatLng(issue.lat, issue.lng);
      final key = _issueCoordinateKey(point);
      if (!seen.add(key)) return;
      issues.add(issue);
    }

    for (final issue in _visibleIssues(cells)) {
      addIssue(issue);
    }

    for (final zone in scoutZones) {
      final point = _readIssuePoint(zone);
      if (point == null) continue;
      final normalizedZone = Map<String, dynamic>.from(zone)
        ..['lat'] = point.latitude
        ..['lng'] = point.longitude;
      addIssue(FarmIssueCell.fromScoutZone(normalizedZone));
    }

    for (final row in riskCells) {
      final point = _readIssuePoint(row);
      if (point == null) continue;
      final normalizedRow = Map<String, dynamic>.from(row)
        ..['lat'] = point.latitude
        ..['lng'] = point.longitude;
      addIssue(FarmIssueCell.fromJson(normalizedRow));
    }

    return [
      for (final issue in issues)
        () {
          final base = _issueColor(issue);
          final diameter = _issueDiameter(issue);
          return Marker(
            point: LatLng(issue.lat, issue.lng),
            width: diameter,
            height: diameter,
            child: GestureDetector(
              onTap: () => onTap(issue),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      base.withValues(alpha: _issueCenterAlpha(issue)),
                      base.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: base,
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
                    size: issue.isScoutZone ? 14 : 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        }(),
    ];
  }

  List<CircleMarker> _alertCircles({
    required List<LatLng> localMarkers,
    required List<FarmIssueCell> issueCells,
    required List<Map<String, dynamic>> scoutZones,
    required List<Map<String, dynamic>> riskCells,
  }) {
    bool isAbiotic(Map<String, dynamic> row) {
      final value = row['likely_abiotic'];
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      if (value is num) return value != 0;
      return false;
    }

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
      final point = _readIssuePoint(zone);
      if (point == null) continue;
      final lat = point.latitude;
      final lng = point.longitude;
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

    final rows = riskCells.isNotEmpty
        ? riskCells
        : issueCells.map((cell) => cell.toJson()).toList(growable: false);
    for (final row in rows.take(80)) {
      final point = _readIssuePoint(row);
      final lat = point?.latitude;
      final lng = point?.longitude;
      if (lat == null || lng == null) continue;

      final risk =
          _readDouble(row, const [
            'composite_risk',
            'max_risk_score',
            'risk_score',
          ]) ??
          0.0;
      final base = isAbiotic(row) ? _abioticColor : _riskColor(risk);
      final radius = math.max(5.0, 14.0 * risk.clamp(0.15, 1.0));
      circles.add(
        CircleMarker(
          point: LatLng(lat, lng),
          radius: radius,
          useRadiusInMeter: false,
          borderColor: Colors.white,
          borderStrokeWidth: 1.2,
          color: base.withValues(alpha: 0.36),
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
    if (farms.isEmpty) {
      final hasSyncError = farmSyncError.trim().isNotEmpty;
      final title = isFarmSyncing
          ? UiStrings.t('syncing_farms')
          : hasSyncError
          ? UiStrings.t('farm_data_sync')
          : UiStrings.t('add_first_farm');
      final detail = isFarmSyncing
          ? UiStrings.t('checking_farms_for_mobile')
          : hasSyncError
          ? farmSyncError
          : UiStrings.t('add_sync_first_farm_before_use');
      return _PageScaffold(
        title: UiStrings.t('nav_farm'),
        child: _Panel(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppTheme.green.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isFarmSyncing
                            ? Icons.cloud_sync_rounded
                            : hasSyncError
                            ? Icons.cloud_off_rounded
                            : Icons.add_location_alt_rounded,
                        color: AppTheme.green,
                      ),
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
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
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
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: isFarmSyncing ? null : onRetryFarmSync,
                      icon: isFarmSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(UiStrings.t('try_again')),
                    ),
                    OutlinedButton.icon(
                      onPressed: isFarmSyncing ? null : onAddFarm,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(UiStrings.t('add_first_farm')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final safeIndex = selectedIndex.clamp(0, farms.length - 1).toInt();
    final selected = farms[safeIndex];
    final selectedPolygon = farmPolygons[safeIndex] ?? const [];
    final diseaseMarkers = diseaseMarkersByFarm[safeIndex] ?? const [];
    final scoutZones =
        scoutZonesByFarm[safeIndex] ?? const <Map<String, dynamic>>[];
    final riskCells =
        riskCellsByFarm[safeIndex] ?? const <Map<String, dynamic>>[];
    final visibleRiskCells = _riskRowsForMap(riskCells, issueCells);
    final diseaseScreen = diseaseScreenByFarm[safeIndex];
    final advice = alertAdviceByFarm[safeIndex];
    final alertError = alertErrorByFarm[safeIndex];
    final timelineEvents = timelineByFarm[safeIndex] ?? const [];
    final isTimelineLoading = timelineLoading.contains(safeIndex);
    final isLoading = alertLoading.contains(safeIndex);
    final statusSnapshot = statusSnapshotForFarm(safeIndex);
    final currentStage = statusSnapshot.stage;
    final currentStatus = statusSnapshot.status;
    final updatedAt = statusSnapshot.updatedAt;
    final maxRisk = _maxRisk(scoutZones, visibleRiskCells, issueCells);
    final weather = diseaseScreen?.weatherContext;
    final issueMarkers = _issueMarkers(
      cells: issueCells,
      scoutZones: scoutZones,
      riskCells: visibleRiskCells,
      onTap: (issue) => onOpenIssue(safeIndex, issue),
    );
    return _PageScaffold(
      title: UiStrings.t('nav_farm'),
      onRefresh: () => onRefreshAlerts(safeIndex),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SelectedFarmHeader(farm: selected),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 252,
                      child: SatelliteMapView(
                        farmPolygon: selectedPolygon,
                        center:
                            selected.latitude != null &&
                                selected.longitude != null
                            ? LatLng(selected.latitude!, selected.longitude!)
                            : null,
                        heatCircles: _alertCircles(
                          localMarkers: diseaseMarkers,
                          issueCells: issueCells,
                          scoutZones: scoutZones,
                          riskCells: visibleRiskCells,
                        ),
                        markers: issueMarkers,
                        height: 252,
                        showZoomControls: true,
                      ),
                    ),
                  ),
                  if (issueMarkers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _IssueLegendItem(
                          color: const Color(0xFFF57C00),
                          label: UiStrings.t('disease_risk'),
                        ),
                        _IssueLegendItem(
                          color: _abioticColor,
                          label: UiStrings.t('water_heat_stress'),
                        ),
                        _IssueLegendItem(
                          color: _zoneColor,
                          label: UiStrings.t('scout_zone'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      UiStrings.t('map_tap_guidance'),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final canFitOneRow = constraints.maxWidth >= 430;
                      final statusWidth = math
                          .min(
                            constraints.maxWidth,
                            canFitOneRow ? 112.0 : 116.0,
                          )
                          .toDouble();
                      final actionWidth = canFitOneRow
                          ? ((constraints.maxWidth - statusWidth - 16) / 2)
                                .clamp(136.0, 176.0)
                                .toDouble()
                          : ((constraints.maxWidth - 8) / 2)
                                .clamp(128.0, 180.0)
                                .toDouble();
                      final compactButtonStyle = OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                      );
                      return SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          runAlignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            SizedBox(
                              width: actionWidth,
                              child: FilledButton.icon(
                                onPressed: isLoading
                                    ? null
                                    : () => onRefreshAlerts(safeIndex),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 42),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
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
                                  isLoading
                                      ? UiStrings.t('refreshing')
                                      : UiStrings.t('refresh_risk'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: actionWidth,
                              child: OutlinedButton.icon(
                                onPressed: () => onOpenFarmInsight(safeIndex),
                                style: compactButtonStyle,
                                icon: const Icon(Icons.open_in_full_rounded),
                                label: Text(
                                  UiStrings.t('full_view'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: statusWidth,
                              child: OutlinedButton.icon(
                                onPressed: () => onOpenStatusUpdate(safeIndex),
                                style: compactButtonStyle,
                                icon: const Icon(Icons.track_changes_rounded),
                                label: Text(
                                  UiStrings.t('status'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 8),
                    _InfoStrip(
                      icon: Icons.sync_rounded,
                      label: UiStrings.t('initial_farm_sync_title'),
                      value: UiStrings.t('farm_page_sync_message'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryStat(
                          title: UiStrings.t('scout_zones'),
                          value: scoutZones.length.toString(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryStat(
                          title: UiStrings.t('risk_cells'),
                          value:
                              diseaseScreen?.riskCellsCount.toString() ??
                              visibleRiskCells.length.toString(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryStat(
                          title: UiStrings.t('max_risk'),
                          value: _riskLabel(maxRisk),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoStrip(
                    icon: Icons.track_changes_rounded,
                    label: UiStrings.t('current_status'),
                    value:
                        '${UiStrings.option(currentStage)} - ${UiStrings.option(currentStatus)}',
                  ),
                  if (updatedAt != null) ...[
                    const SizedBox(height: 8),
                    _InfoStrip(
                      icon: Icons.schedule_outlined,
                      label: UiStrings.t('updated'),
                      value:
                          '${LocaleText.date(updatedAt, pattern: 'dd/MM')} ${LocaleText.time(updatedAt)}',
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    stageSummary(safeIndex),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (timelineEvents.isNotEmpty || isTimelineLoading) ...[
            _FarmTimelineEventPanel(
              events: timelineEvents,
              loading: isTimelineLoading,
              maxItems: 5,
              showEmptyState: false,
            ),
            const SizedBox(height: 16),
          ],
          if (alertError != null) ...[
            _FarmAlertCard(
              alert: FarmAlertItem(
                title: UiStrings.t('alert_refresh_failed'),
                detail: alertError,
                severity: 'high',
                action: UiStrings.t('alert_refresh_retry_detail'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _Panel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.notification_important_rounded,
                        color: AppTheme.greenDark,
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SectionTitle(
                          title: UiStrings.t('important_alerts'),
                        ),
                      ),
                      if (advice != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${advice.importantAlerts.length}',
                            style: const TextStyle(
                              color: AppTheme.greenDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (advice?.importantAlerts.isNotEmpty == true)
                    for (final alert in advice!.importantAlerts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FarmAlertCard(alert: alert),
                      )
                  else
                    _FarmAlertEmptyState(
                      icon: Icons.notifications_active_outlined,
                      title: UiStrings.t('no_important_alerts'),
                      detail: alertError != null
                          ? UiStrings.t('advisor_recommendation_missing')
                          : UiStrings.t('no_important_alerts_desc'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle(title: UiStrings.t('weather')),
          const SizedBox(height: 10),
          if (weather != null) ...[
            _SowingWeekWeatherCard(
              daysAfterSowing: daysAfterSowing(safeIndex),
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
            _FarmAlertEmptyState(
              icon: Icons.cloud_outlined,
              title: UiStrings.t('no_weather_alert'),
              detail: UiStrings.t('refresh_farm_weather_risk'),
            ),
          if (advice?.nextActions.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UiStrings.t('next_actions'),
                      style: const TextStyle(
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
                    label: UiStrings.f('last_screen_value', {
                      'value': _formatScanDate(diseaseScreen?.scanDate ?? ''),
                    }),
                  ),
                  _InventoryChip(
                    label: UiStrings.f('confidence_value', {
                      'value': advice?.confidence ?? UiStrings.t('pending'),
                    }),
                  ),
                  _InventoryChip(
                    label: UiStrings.f('images_value', {
                      'value': diseaseScreen?.imagesAnalyzed ?? 0,
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

class _FarmTimelineEventPanel extends StatelessWidget {
  final List<FarmTimelineEvent> events;
  final bool loading;
  final int maxItems;
  final bool showEmptyState;

  const _FarmTimelineEventPanel({
    required this.events,
    required this.loading,
    this.maxItems = 5,
    this.showEmptyState = false,
  });

  @override
  Widget build(BuildContext context) {
    final visible = events
        .where(
          (event) =>
              event.eventType != 'farm_alert_refresh' &&
              event.eventType != 'crop_lifecycle_advice',
        )
        .take(maxItems)
        .toList(growable: false);
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline_rounded, color: AppTheme.greenDark),
                const SizedBox(width: 8),
                Expanded(
                  child: _SectionTitle(title: UiStrings.t('recent_activity')),
                ),
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty && !loading && showEmptyState)
              Text(
                UiStrings.t('no_data'),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              for (final event in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FarmTimelineEventTile(event: event),
                ),
          ],
        ),
      ),
    );
  }
}

class _FarmTimelineEventTile extends StatelessWidget {
  final FarmTimelineEvent event;

  const _FarmTimelineEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = _color(event.severity);
    final timeText =
        '${LocaleText.date(event.createdAt, pattern: 'dd/MM')} ${LocaleText.time(event.createdAt)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon(event.eventType), color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title.isEmpty
                      ? UiStrings.t('new_notification')
                      : event.title,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (event.stage.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    UiStrings.option(event.stage),
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  event.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  timeText,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _icon(String type) {
    switch (type) {
      case 'farm_alert_refresh':
        return Icons.health_and_safety_rounded;
      case 'crop_lifecycle_advice':
        return Icons.eco_rounded;
      case 'farm_status_update':
        return Icons.track_changes_rounded;
      default:
        return Icons.timeline_rounded;
    }
  }

  static Color _color(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return const Color(0xFFB71C1C);
      case 'medium':
      case 'watch':
        return const Color(0xFFF57F17);
      default:
        return AppTheme.greenDark;
    }
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        alert.severity.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
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
              child: _SummaryStat(title: UiStrings.t('rain'), value: rain),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryStat(
                title: UiStrings.t('wetness'),
                value: wetness,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryStat(
                title: UiStrings.t('temp'),
                value: temperature,
              ),
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
  final stageLabel = UiStrings.option(stage);
  if (daysAfterSowing <= 25) {
    if (rain >= 40) {
      note = UiStrings.f('weather_heavy_rain_week', {'week': week});
    } else if (rain < 5) {
      note = UiStrings.f('weather_low_rain_week', {'week': week});
    } else {
      note = UiStrings.f('weather_manageable_week', {
        'stage': stageLabel,
        'week': week,
      });
    }
  } else if (daysAfterSowing <= 55) {
    note = fungalWeather
        ? UiStrings.f('leaf_wetness_week', {
            'hours': wetness.round(),
            'week': week,
            'stage': stageLabel,
          })
        : UiStrings.f('no_weather_trigger_week', {
            'week': week,
            'stage': stageLabel,
          });
  } else {
    note = (fungalWeather || rain >= 40)
        ? UiStrings.f('wet_weather_stage_risk', {
            'week': week,
            'stage': stageLabel,
          })
        : UiStrings.f('stable_weather_week', {
            'week': week,
            'stage': stageLabel,
          });
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
                  UiStrings.f('week_after_sowing_stage', {
                    'week': week,
                    'stage': UiStrings.option(stage),
                  }),
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
  final Future<void> Function({
    required FarmIssueCell issue,
    required String action,
    FarmPhotoDiagnosis? diagnosis,
  })
  recordAction;
  final bool fullScreen;

  const _FarmIssueSheet({
    required this.farmName,
    required this.issue,
    required this.farmCenter,
    required this.daysAfterSowing,
    required this.growthStage,
    required this.weatherContext,
    required this.fetchGuidance,
    required this.captureAndDiagnose,
    required this.recordAction,
    this.fullScreen = false,
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
  bool _visited = false;
  bool _visitSaving = false;
  String? _trackingError;

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
        _adviceError = _cleanError(e);
        _adviceLoading = false;
      });
    }
  }

  Future<void> _takePhoto(HarvestMachineImageSource source) async {
    if (_photoBusy) return;
    setState(() {
      _photoBusy = true;
      _diagnosisError = null;
      _trackingError = null;
    });
    try {
      final diagnosis = await widget.captureAndDiagnose(source);
      String? trackingError;
      if (diagnosis != null) {
        try {
          await widget.recordAction(
            issue: widget.issue,
            action: 'photo_diagnosis',
            diagnosis: diagnosis,
          );
        } catch (e) {
          trackingError = _cleanError(e);
        }
      }
      if (!mounted) return;
      setState(() {
        _diagnosis = diagnosis ?? _diagnosis;
        _trackingError = trackingError;
        _photoBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _diagnosisError = _cleanError(e);
        _photoBusy = false;
      });
    }
  }

  Future<void> _markVisited() async {
    if (_visitSaving || _visited) return;
    setState(() {
      _visitSaving = true;
      _trackingError = null;
    });
    try {
      await widget.recordAction(
        issue: widget.issue,
        action: 'visited',
        diagnosis: _diagnosis,
      );
      if (!mounted) return;
      setState(() {
        _visited = true;
        _visitSaving = false;
      });
      Get.snackbar(
        UiStrings.t('risk_visit_saved_title'),
        UiStrings.f('risk_visit_saved_desc', {'farm': widget.farmName}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trackingError = _cleanError(e);
        _visitSaving = false;
      });
    }
  }

  String _cleanError(Object error) {
    final raw = error.toString().replaceFirst('SatelliteApiException: ', '');
    final normalized = raw.toLowerCase();
    if (normalized.contains('farm is not synced') ||
        normalized.contains('remote farm id') ||
        normalized.contains('farm_id')) {
      return UiStrings.t('farm_not_synced_satellite');
    }
    return raw;
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

  String get _riskPercent => _formatLocalizedPercent(
    (widget.issue.compositeRisk * 100).round(),
    fractionDigits: 0,
  );

  String get _guidanceStatusText {
    if (_adviceLoading) return UiStrings.t('guidance_loading');
    if (_adviceError != null) return UiStrings.t('guidance_failed');
    return UiStrings.t('guidance_ready');
  }

  Color get _guidanceStatusColor {
    if (_adviceLoading) return const Color(0xFFF57C00);
    if (_adviceError != null) return const Color(0xFFD32F2F);
    return AppTheme.green;
  }

  String get _photoStatusText {
    if (_photoBusy) return UiStrings.t('guidance_loading');
    if (_diagnosisError != null) return UiStrings.t('photo_failed_status');
    if (_diagnosis != null) return UiStrings.t('photo_ready');
    return UiStrings.t('photo_needed');
  }

  Color get _photoStatusColor {
    if (_photoBusy) return const Color(0xFFF57C00);
    if (_diagnosisError != null) return const Color(0xFFD32F2F);
    if (_diagnosis != null) return AppTheme.green;
    return AppTheme.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fullScreen) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F8F4),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF6F8F4),
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
          ),
          title: Text(
            UiStrings.t('risk_detail_title'),
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _adviceLoading ? null : _loadGuidance,
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.green),
              tooltip: UiStrings.t('refresh_advice'),
            ),
          ],
        ),
        body: SafeArea(child: _buildIssueContent(context)),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.58,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF6F8F4),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: _buildIssueContent(
            context,
            controller: controller,
            showHandle: true,
          ),
        );
      },
    );
  }

  Widget _buildIssueContent(
    BuildContext context, {
    ScrollController? controller,
    bool showHandle = false,
  }) {
    final bottomPadding = 28 + MediaQuery.paddingOf(context).bottom;
    final issue = widget.issue;
    final color = _FarmPage._issueColor(issue);
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, showHandle ? 12 : 16, 16, bottomPadding),
      children: [
        if (showHandle) ...[_sheetHandle(), const SizedBox(height: 14)],
        _topSummary(issue, color),
        const SizedBox(height: 12),
        _quickActions(),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.report_problem_rounded,
          title: UiStrings.t('problem'),
          color: color,
          child: _problemSection(issue),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.psychology_alt_rounded,
          title: UiStrings.t('why_it_happened'),
          color: const Color(0xFFF57C00),
          child: _whySection(issue, color),
        ),
        if (_showBackendStatusSection) ...[
          const SizedBox(height: 12),
          _sectionCard(
            icon: Icons.cloud_sync_rounded,
            title: UiStrings.t('backend_status'),
            color: AppTheme.green,
            child: _backendStatusSection(issue),
          ),
        ],
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.task_alt_rounded,
          title: UiStrings.t('what_to_do_now'),
          color: AppTheme.green,
          child: _guidanceSection(),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.add_a_photo_rounded,
          title: UiStrings.t('photo_check'),
          color: const Color(0xFF1565C0),
          child: _photoSection(),
        ),
      ],
    );
  }

  bool get _showBackendStatusSection => false;

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  Widget _topSummary(FarmIssueCell issue, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.16), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _FarmPage._issueIcon(issue),
                  color: color,
                  size: 25,
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
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.farmName,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _riskPill(color),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryChip(
                Icons.directions_walk_rounded,
                UiStrings.f('distance_from_field_center', {
                  'distance': LocaleText.number(_distanceMeters),
                }),
              ),
              _summaryChip(
                Icons.spa_rounded,
                UiStrings.f('risk_growth_stage_value', {
                  'stage': UiStrings.option(widget.growthStage),
                }),
              ),
              _summaryChip(
                Icons.calendar_today_rounded,
                UiStrings.f('days_after_sowing_value', {
                  'days': LocaleText.number(widget.daysAfterSowing),
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _riskPill(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '${_FarmPage._riskLabel(widget.issue.compositeRisk)} • $_riskPercent',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _summaryChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.greenDark),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _adviceLoading ? null : _loadGuidance,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(UiStrings.t('refresh_advice')),
        ),
        OutlinedButton.icon(
          onPressed: _photoBusy
              ? null
              : () => _takePhoto(HarvestMachineImageSource.camera),
          icon: const Icon(Icons.photo_camera_rounded),
          label: Text(UiStrings.t('open_camera')),
        ),
        FilledButton.icon(
          onPressed: _visitSaving || _visited ? null : _markVisited,
          icon: Icon(_visited ? Icons.verified_rounded : Icons.place_rounded),
          label: Text(
            _visitSaving
                ? UiStrings.t('guidance_loading')
                : _visited
                ? UiStrings.t('visited')
                : UiStrings.t('mark_visited'),
          ),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _problemSection(FarmIssueCell issue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          issue.isDisease
              ? UiStrings.t('scout_zone_desc')
              : UiStrings.t('crop_stress_desc'),
          style: const TextStyle(
            color: AppTheme.textMuted,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (issue.diseaseCandidates.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: issue.diseaseCandidates
                .map(
                  (item) => Chip(
                    label: Text(UiStrings.option(item.replaceAll('_', ' '))),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppTheme.greenPale,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _whySection(FarmIssueCell issue, Color color) {
    final signalRows = <Widget>[
      _statusLine(
        icon: Icons.speed_rounded,
        label: UiStrings.t('risk_score'),
        value: _riskPercent,
        color: color,
      ),
    ];
    if (issue.ndvi != null) {
      signalRows.add(
        _statusLine(
          icon: Icons.eco_rounded,
          label: UiStrings.t('ndvi_signal'),
          value: LocaleText.number(issue.ndvi!, fractionDigits: 2),
          color: AppTheme.green,
        ),
      );
    }
    if (issue.moisture != null) {
      signalRows.add(
        _statusLine(
          icon: Icons.water_drop_rounded,
          label: UiStrings.t('moisture_signal'),
          value: LocaleText.number(issue.moisture!, fractionDigits: 2),
          color: const Color(0xFF1565C0),
        ),
      );
    }
    if (issue.weatherRisk != null) {
      signalRows.add(
        _statusLine(
          icon: Icons.cloud_rounded,
          label: UiStrings.t('weather_risk_signal'),
          value: _formatLocalizedPercent(
            (issue.weatherRisk! * 100).round(),
            fractionDigits: 0,
          ),
          color: const Color(0xFFF57C00),
        ),
      );
    }
    for (final entry in issue.perDisease.entries.take(3)) {
      signalRows.add(
        _statusLine(
          icon: Icons.coronavirus_rounded,
          label: UiStrings.option(entry.key.replaceAll('_', ' ')),
          value: _formatLocalizedPercent(
            (entry.value * 100).round(),
            fractionDigits: 0,
          ),
          color: const Color(0xFFD32F2F),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          UiStrings.t('risk_signals'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        ...signalRows,
        if (signalRows.length == 1 &&
            issue.ndvi == null &&
            issue.moisture == null &&
            issue.weatherRisk == null &&
            issue.perDisease.isEmpty) ...[
          const SizedBox(height: 8),
          _FarmAlertEmptyState(
            icon: Icons.info_outline_rounded,
            title: UiStrings.t('no_signal_data'),
            detail: UiStrings.t('no_signal_data_detail'),
          ),
        ],
        if (widget.weatherContext != null) ...[
          const SizedBox(height: 12),
          _SowingWeekWeatherCard(
            daysAfterSowing: widget.daysAfterSowing,
            stage: widget.growthStage,
            weather: widget.weatherContext!,
          ),
        ],
      ],
    );
  }

  Widget _backendStatusSection(FarmIssueCell issue) {
    return Column(
      children: [
        _statusLine(
          icon: Icons.psychology_rounded,
          label: UiStrings.t('guidance_status'),
          value: _guidanceStatusText,
          color: _guidanceStatusColor,
        ),
        _statusLine(
          icon: Icons.cloud_queue_rounded,
          label: UiStrings.t('weather_status'),
          value: widget.weatherContext == null
              ? UiStrings.t('weather_missing')
              : UiStrings.t('weather_available'),
          color: widget.weatherContext == null
              ? const Color(0xFFF57C00)
              : AppTheme.green,
        ),
        _statusLine(
          icon: Icons.satellite_alt_rounded,
          label: UiStrings.t('backend_source'),
          value: issue.isScoutZone
              ? UiStrings.t('scout_zone')
              : UiStrings.t('satellite_risk_cell'),
          color: AppTheme.greenDark,
        ),
        _statusLine(
          icon: Icons.schedule_rounded,
          label: UiStrings.t('last_risk_scan'),
          value: UiStrings.t('risk_scan_time_not_available'),
          color: AppTheme.textMuted,
        ),
        _statusLine(
          icon: Icons.add_a_photo_rounded,
          label: UiStrings.t('photo_status'),
          value: _photoStatusText,
          color: _photoStatusColor,
        ),
        if (_trackingError != null) ...[
          const SizedBox(height: 8),
          Text(
            UiStrings.f('tracking_sync_failed', {
              'error': _trackingError ?? '',
            }),
            style: const TextStyle(
              color: Color(0xFFD32F2F),
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusLine({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guidanceSection() {
    if (_adviceLoading) {
      return _loadingBlock(UiStrings.t('asking_advisor'));
    }
    if (_adviceError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FarmAlertEmptyState(
            icon: Icons.warning_amber_rounded,
            title: UiStrings.t('risk_found_guidance_unavailable'),
            detail: _adviceError ?? '',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loadGuidance,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(UiStrings.t('try_again')),
          ),
        ],
      );
    }
    final advice = _advice;
    if (advice == null ||
        (advice.importantAlerts.isEmpty && advice.nextActions.isEmpty)) {
      return _FarmAlertEmptyState(
        icon: Icons.info_outline_rounded,
        title: UiStrings.t('advice_empty_title'),
        detail: UiStrings.t('advice_empty_detail'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final alert in advice.importantAlerts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FarmAlertCard(alert: alert),
          ),
        if (advice.nextActions.isNotEmpty) ...[
          for (final action in advice.nextActions)
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
    );
  }

  Widget _photoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          UiStrings.t('confirm_photo_desc'),
          style: const TextStyle(
            color: AppTheme.textMuted,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (_photoBusy)
          _loadingBlock(UiStrings.t('uploading_diagnosing'))
        else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _takePhoto(HarvestMachineImageSource.camera),
              icon: const Icon(Icons.photo_camera_rounded),
              label: Text(UiStrings.t('take_photo')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _takePhoto(HarvestMachineImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(UiStrings.t('from_gallery')),
            ),
          ),
        ],
        if (_diagnosisError != null) ...[
          const SizedBox(height: 10),
          _FarmAlertEmptyState(
            icon: Icons.error_outline_rounded,
            title: UiStrings.t('photo_failed_status'),
            detail: UiStrings.f('photo_diagnosis_failed', {
              'error': _diagnosisError ?? '',
            }),
          ),
        ],
        if (_diagnosis != null) ...[
          const SizedBox(height: 12),
          _PhotoDiagnosisCard(diagnosis: _diagnosis!),
        ],
      ],
    );
  }

  Widget _loadingBlock(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
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
                _formatLocalizedPercent(
                  (diagnosis.confidence * 100).round(),
                  fractionDigits: 0,
                ),
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
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E9DC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.greenDark, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
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

class _SelectedFarmHeader extends StatelessWidget {
  final _FarmerFarm farm;

  const _SelectedFarmHeader({required this.farm});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.greenDark, AppTheme.green],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.greenDark.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.grass_outlined, color: Colors.white),
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
                '${UiStrings.label(farm.location)} • ${UiStrings.option(farm.crop)} • ${UiStrings.option(farm.variety)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
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

class _FarmMetricWrap extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;

  const _FarmMetricWrap({required this.children, this.minItemWidth = 118});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = (maxWidth / minItemWidth)
            .floor()
            .clamp(1, children.length)
            .toInt();
        const spacing = 8.0;
        final itemWidth = (maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _FarmMapInsightPage extends StatelessWidget {
  final _FarmerFarm farm;
  final List<LatLng> farmPolygon;
  final List<LatLng> diseaseMarkers;
  final List<FarmIssueCell> diseaseRiskCells;
  final String currentStage;
  final String stageSummary;
  final int daysAfterSowing;
  final List<_HarvestInventoryLot> harvestHistory;
  final List<String> diagnosisNotes;
  final DateTime? lastUpdated;
  final String status;
  final _FarmSatelliteOverview? satelliteOverview;
  final bool isSatelliteLoading;
  final CropLifecycleAdvice? lifecycleAdvice;
  final VoidCallback onOpenDiagnose;
  final VoidCallback onOpenStatusUpdate;

  const _FarmMapInsightPage({
    required this.farm,
    required this.farmPolygon,
    required this.diseaseMarkers,
    required this.diseaseRiskCells,
    required this.currentStage,
    required this.stageSummary,
    required this.daysAfterSowing,
    required this.harvestHistory,
    required this.diagnosisNotes,
    required this.lastUpdated,
    required this.status,
    required this.satelliteOverview,
    required this.isSatelliteLoading,
    required this.lifecycleAdvice,
    required this.onOpenDiagnose,
    required this.onOpenStatusUpdate,
  });

  List<CircleMarker> _diseaseCircles() {
    final circles = <CircleMarker>[
      for (final point in diseaseMarkers)
        CircleMarker(
          point: point,
          radius: 9,
          useRadiusInMeter: false,
          borderColor: Colors.white,
          borderStrokeWidth: 1.5,
          color: Colors.redAccent.withValues(alpha: 0.62),
        ),
    ];

    for (final issue
        in diseaseRiskCells.where((cell) => cell.hasLocation).take(80)) {
      final risk = issue.compositeRisk;
      final radius = math.max(5.0, 14.0 * risk.clamp(0.12, 1.0));
      circles.add(
        CircleMarker(
          point: LatLng(issue.lat, issue.lng),
          radius: radius,
          useRadiusInMeter: false,
          borderColor: Colors.white,
          borderStrokeWidth: 1.2,
          color: _FarmPage._issueColor(issue).withValues(alpha: 0.34),
        ),
      );
    }

    return circles;
  }

  @override
  Widget build(BuildContext context) {
    final updatedText = lastUpdated == null
        ? UiStrings.t('not_updated')
        : '${LocaleText.date(lastUpdated!, pattern: 'dd/MM')} ${LocaleText.time(lastUpdated!)}';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(farm.name),
        elevation: 0,
      ),
      backgroundColor: AppTheme.surface,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _FarmInsightActionBar(
        onOpenDiagnose: onOpenDiagnose,
        onOpenStatusUpdate: onOpenStatusUpdate,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 132),
          children: [
            _Panel(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UiStrings.t('farm_insight'),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SelectedFarmHeader(farm: farm),
                    const SizedBox(height: 10),
                    _FarmMetricWrap(
                      minItemWidth: 118,
                      children: [
                        _FarmMetric(
                          label: UiStrings.t('area'),
                          value: UiStrings.label(farm.area),
                        ),
                        _FarmMetric(
                          label: UiStrings.t('ndvi'),
                          value: farm.ndvi,
                        ),
                        _FarmMetric(
                          label: UiStrings.t('moisture_label'),
                          value: UiStrings.option(farm.moisture),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      UiStrings.t('satellite_field_map'),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SatelliteMapView(
                        farmPolygon: farmPolygon,
                        heatCircles: _diseaseCircles(),
                        height: 280,
                        showZoomControls: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (lifecycleAdvice != null)
                      _CropLifecycleAdviceCard(
                        advice: lifecycleAdvice!,
                        compact: false,
                        crop: farm.crop,
                        variety: farm.variety,
                        currentStage: currentStage,
                        daysAfterSowing: daysAfterSowing,
                        currentStatus: status,
                        statusUpdatedAt: lastUpdated,
                      )
                    else ...[
                      _InfoStrip(
                        icon: Icons.timeline,
                        label: UiStrings.t('growth'),
                        value: UiStrings.f('day_stage', {
                          'day': daysAfterSowing,
                          'stage': UiStrings.option(currentStage),
                        }),
                      ),
                      const SizedBox(height: 8),
                      _InfoStrip(
                        icon: Icons.note_alt_outlined,
                        label: UiStrings.t('status_note'),
                        value: status,
                      ),
                      const SizedBox(height: 8),
                      _InfoStrip(
                        icon: Icons.info_outline,
                        label: UiStrings.t('last_update'),
                        value: updatedText,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        stageSummary,
                        style: const TextStyle(color: AppTheme.textDark),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      UiStrings.t('detailed_analysis_diagnostics'),
                      style: const TextStyle(
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
                            title: UiStrings.t('ndvi_history'),
                            subtitle: UiStrings.t('satellite_index_graphs'),
                            icon: Icons.trending_up_rounded,
                            color: const Color(0xFFECF6E8),
                            onTap: () => Get.to(
                              () => _NdviHistoryDetailPage(farm: farm),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InsightDetailCard(
                            title: UiStrings.t('soil_health_card'),
                            subtitle: UiStrings.t('soil_health_subtitle'),
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
                            title: UiStrings.t('weather_impact'),
                            subtitle: UiStrings.t('humidity_rainfall_logs'),
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
                            title: UiStrings.t('yield_prognosis'),
                            subtitle: UiStrings.t('expected_harvest_index'),
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
                      Text(
                        UiStrings.t('recent_harvest_history'),
                        style: const TextStyle(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lot.lotLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _localizedHarvestLotDetail(lot),
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
                      Text(
                        UiStrings.t('latest_field_notes'),
                        style: const TextStyle(
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
      ),
    );
  }
}

class _FarmInsightActionBar extends StatelessWidget {
  final VoidCallback onOpenDiagnose;
  final VoidCallback onOpenStatusUpdate;

  const _FarmInsightActionBar({
    required this.onOpenDiagnose,
    required this.onOpenStatusUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final width = math
        .min(MediaQuery.sizeOf(context).width - 36, 360.0)
        .toDouble();
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDDE9D5)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.greenDark.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpenDiagnose,
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: Text(
                    UiStrings.t('diagnose'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenStatusUpdate,
                  icon: const Icon(Icons.track_changes_rounded, size: 18),
                  label: Text(
                    UiStrings.t('status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
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
          constraints: const BoxConstraints(minHeight: 128),
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
          UiStrings.f('ndvi_analysis_title', {'farm': farm.name}),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.greenDark,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
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
                    Text(
                      UiStrings.t('ndvi_health_index_trend'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      UiStrings.t('ndvi_explanation'),
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
                      children: [
                        Text(
                          '${UiStrings.option('Sowing')} (${LocaleText.number(0.15, fractionDigits: 2)})',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        Text(
                          '${UiStrings.option('Vegetative')} (${LocaleText.number(0.42, fractionDigits: 2)})',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        Text(
                          '${UiStrings.option('Flowering')} (${LocaleText.number(0.76, fractionDigits: 2)})',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        Text(
                          '${UiStrings.option('Grain filling')} (${LocaleText.number(0.68, fractionDigits: 2)})',
                          style: const TextStyle(
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
                    Text(
                      UiStrings.t('satellite_overpasses'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildPassRow(
                      LocaleText.date(
                        DateTime(2026, 6, 8),
                        pattern: 'MMMM dd, yyyy',
                      ),
                      'Sentinel-2B',
                      LocaleText.number(0.76, fractionDigits: 2),
                      UiStrings.f('cloud_percent', {'value': 0.2}),
                    ),
                    const Divider(),
                    _buildPassRow(
                      LocaleText.date(
                        DateTime(2026, 5, 28),
                        pattern: 'MMMM dd, yyyy',
                      ),
                      'Sentinel-2A',
                      LocaleText.number(0.64, fractionDigits: 2),
                      UiStrings.f('cloud_percent', {'value': 1.5}),
                    ),
                    const Divider(),
                    _buildPassRow(
                      LocaleText.date(
                        DateTime(2026, 5, 18),
                        pattern: 'MMMM dd, yyyy',
                      ),
                      'Sentinel-2B',
                      LocaleText.number(0.45, fractionDigits: 2),
                      UiStrings.f('cloud_percent', {'value': 12}),
                    ),
                    const Divider(),
                    _buildPassRow(
                      LocaleText.date(
                        DateTime(2026, 5, 8),
                        pattern: 'MMMM dd, yyyy',
                      ),
                      'Sentinel-2A',
                      LocaleText.number(0.28, fractionDigits: 2),
                      UiStrings.f('cloud_percent', {'value': 0.0}),
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
          UiStrings.f('soil_health_farm_title', {'farm': farm.name}),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.greenDark,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
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
                    Text(
                      UiStrings.t('npk_soil_chemistry'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildNutrientBar(
                      UiStrings.t('nitrogen_n'),
                      0.65,
                      UiStrings.t('optimal_65_kg_ha'),
                      Colors.blue,
                    ),
                    _buildNutrientBar(
                      UiStrings.t('phosphorus_p'),
                      0.42,
                      UiStrings.t('moderate_28_kg_ha'),
                      Colors.orange,
                    ),
                    _buildNutrientBar(
                      UiStrings.t('potassium_k'),
                      0.85,
                      UiStrings.t('high_195_kg_ha'),
                      Colors.purple,
                    ),
                    _buildNutrientBar(
                      UiStrings.t('organic_carbon'),
                      0.55,
                      UiStrings.t('moderate_055_percent'),
                      Colors.green,
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          UiStrings.t('soil_ph_value'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          UiStrings.t('soil_ph_ideal'),
                          style: const TextStyle(
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
                  children: [
                    Text(
                      UiStrings.t('millet_advisor_title'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.greenDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      UiStrings.t('phosphorus_advisory'),
                      style: const TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      UiStrings.t('nitrogen_advisory'),
                      style: const TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      UiStrings.t('carbon_advisory'),
                      style: const TextStyle(height: 1.4),
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
          UiStrings.f('weather_impact_farm_title', {'farm': farm.name}),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.greenDark,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
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
                    Text(
                      UiStrings.t('microclimate_statistics'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildStatRow(
                      UiStrings.t('avg_moisture'),
                      UiStrings.option(farm.moisture),
                    ),
                    _buildStatRow(
                      UiStrings.t('solar_radiation'),
                      LocaleText.digits('820 W/m²'),
                    ),
                    _buildStatRow(
                      UiStrings.t('daily_evapotranspiration'),
                      LocaleText.digits('4.2 mm/day'),
                    ),
                    _buildStatRow(
                      UiStrings.t('dew_point'),
                      LocaleText.digits('18.4°C'),
                    ),
                    _buildStatRow(UiStrings.t('relative_humidity'), '45%'),
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
                    Text(
                      UiStrings.t('weather_hazards_outlook'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.greenDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      UiStrings.t('fungal_disease_low_humidity'),
                      style: const TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      UiStrings.t('heat_stress_advisory'),
                      style: const TextStyle(height: 1.4),
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
          UiStrings.f('yield_prognosis_farm_title', {'farm': farm.name}),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.greenDark,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
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
                    Text(
                      UiStrings.t('expected_yield_prognosis'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildYieldRow(
                      UiStrings.t('est_production'),
                      UiStrings.f('kg_value', {
                        'value':
                            '${LocaleText.number(850)} - ${LocaleText.number(950)}',
                      }),
                    ),
                    _buildYieldRow(
                      UiStrings.t('current_stage_projection'),
                      UiStrings.t('on_track_percent'),
                    ),
                    _buildYieldRow(
                      UiStrings.t('est_harvest_window'),
                      UiStrings.t('harvest_window_demo'),
                    ),
                    _buildYieldRow(
                      UiStrings.t('quality_grade_prediction'),
                      UiStrings.t('grade_a_high_density'),
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
                    Text(
                      UiStrings.t('pre_harvest_checklist'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.greenDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      UiStrings.t('drying_yard_advisory'),
                      style: const TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      UiStrings.t('bag_procurement_advisory'),
                      style: const TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      UiStrings.t('harvester_cleaning_advisory'),
                      style: const TextStyle(height: 1.4),
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
        title: Text(
          UiStrings.t('farm_history'),
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
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
                    Text(
                      UiStrings.t('select_farm'),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      UiStrings.f('farm_count_history_message', {
                        'count': farms.length,
                        'plural': farms.length == 1 ? '' : 's',
                      }),
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
                                  label: UiStrings.f('previous_value', {
                                    'value': UiStrings.option(
                                      farms[i].previousCrop,
                                    ),
                                  }),
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
    if (statusUpdatedAt == null) return UiStrings.t('not_updated');
    return '${LocaleText.date(statusUpdatedAt!, pattern: 'dd/MM')} ${LocaleText.time(statusUpdatedAt!)}';
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
        title: Text(
          UiStrings.t('farm_history'),
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
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
                          child: Text(
                            UiStrings.t('live'),
                            style: const TextStyle(
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
                      '${UiStrings.option(farm.crop)} • ${UiStrings.option(farm.variety)} • ${UiStrings.label(farm.area)}',
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      UiStrings.f('cycle_summary_day', {
                        'day': daysAfterSowing,
                      }),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _FarmMetricWrap(
                      minItemWidth: 118,
                      children: [
                        _FarmMetric(
                          label: UiStrings.t('stage'),
                          value: UiStrings.option(currentStage),
                        ),
                        _FarmMetric(
                          label: UiStrings.t('status'),
                          value: _statusTimeText,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F8EE),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFDCEBD9)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            UiStrings.t('current_status'),
                            style: const TextStyle(
                              color: AppTheme.greenDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            status.trim().isEmpty
                                ? UiStrings.t('not_updated')
                                : status,
                            style: const TextStyle(
                              color: AppTheme.textDark,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InventoryChip(label: UiStrings.label(farm.location)),
                        _InventoryChip(
                          label: UiStrings.f('health_value', {
                            'value': UiStrings.option(farm.health),
                          }),
                        ),
                        _InventoryChip(
                          label:
                              '${UiStrings.t('moisture_label')} ${UiStrings.option(farm.moisture)}',
                        ),
                        if (farm.previousCrop.isNotEmpty)
                          _InventoryChip(
                            label: UiStrings.f('previous_value', {
                              'value': UiStrings.option(farm.previousCrop),
                            }),
                          ),
                        if (farm.season.isNotEmpty)
                          _InventoryChip(label: UiStrings.option(farm.season)),
                        if (farm.irrigation.isNotEmpty)
                          _InventoryChip(
                            label: UiStrings.option(farm.irrigation),
                          ),
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
                      Text(
                        UiStrings.t('farm_questionnaire_details'),
                        style: const TextStyle(
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
                              label: UiStrings.f('previous_crop_value', {
                                'value': UiStrings.option(farm.previousCrop),
                              }),
                            ),
                          if (farm.soilType.isNotEmpty)
                            _InventoryChip(
                              label: UiStrings.f('soil_value', {
                                'value': UiStrings.option(farm.soilType),
                              }),
                            ),
                          if (farm.ownershipType.isNotEmpty)
                            _InventoryChip(
                              label: UiStrings.f('land_value', {
                                'value': UiStrings.option(farm.ownershipType),
                              }),
                            ),
                          if (farm.seedSource.isNotEmpty)
                            _InventoryChip(
                              label: UiStrings.f('seed_value', {
                                'value': UiStrings.option(farm.seedSource),
                              }),
                            ),
                          if (farm.harvestIntent.isNotEmpty)
                            _InventoryChip(
                              label: UiStrings.f('use_value', {
                                'value': UiStrings.option(farm.harvestIntent),
                              }),
                            ),
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
                      UiStrings.t('crop_cycle_timeline'),
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
                        title: UiStrings.option(milestone.stage),
                        detail: _isCurrent(milestone)
                            ? UiStrings.f('active_now_range', {
                                'start': milestone.startDay,
                                'end': milestone.endDay,
                              })
                            : _isCompleted(milestone)
                            ? UiStrings.t('completed')
                            : UiStrings.f('starts_at_day', {
                                'day': milestone.startDay,
                              }),
                        active: _isCurrent(milestone),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      UiStrings.f('current_status_value', {'value': status}),
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      UiStrings.f('last_update_value', {
                        'value': _statusTimeText,
                      }),
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
                      Text(
                        UiStrings.t('harvest_history'),
                        style: const TextStyle(
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
                                    _localizedHarvestLotDetail(lot),
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
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: _HistoryEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: UiStrings.t('no_harvest_history'),
                    detail: UiStrings.t('selected_farm_harvest_empty_detail'),
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
                      Text(
                        UiStrings.t('field_notes'),
                        style: const TextStyle(
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
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: _HistoryEmptyState(
                    icon: Icons.note_alt_outlined,
                    title: UiStrings.t('no_field_notes'),
                    detail: UiStrings.t('field_notes_desc'),
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
                      Text(
                        UiStrings.t('weather_index_trend'),
                        style: const TextStyle(
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
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: _HistoryEmptyState(
                    icon: Icons.satellite_alt_outlined,
                    title: UiStrings.t('remote_index_pending'),
                    detail: UiStrings.t('remote_index_pending'),
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
    super.key,
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

  String _localizedMarketSortOption(String option) {
    return switch (option) {
      'Newest' => UiStrings.t('sort_newest'),
      'Highest grade' => UiStrings.t('sort_highest_grade'),
      'Lowest moisture' => UiStrings.t('sort_lowest_moisture'),
      'Highest qty' => UiStrings.t('sort_highest_qty'),
      _ => UiStrings.t('sort_recommended'),
    };
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
    final allFarmsSelected = _selectedFarm == _allFarmsLabel;
    final scopeLabel = allFarmsSelected
        ? UiStrings.t('all_farms')
        : UiStrings.label(_selectedFarm);
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
        title: Text(
          UiStrings.t('market_desk'),
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
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
                      allFarmsSelected
                          ? UiStrings.t('market_desk')
                          : UiStrings.f('market_desk_farm', {
                              'farm': scopeLabel,
                            }),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      UiStrings.t('market_desk_desc'),
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MarketSyncStrip(scopeLabel: scopeLabel),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MarketTrendStat(
                            label: UiStrings.t('active_lots'),
                            value: LocaleText.number(totalLots),
                            icon: Icons.inventory_2_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MarketTrendStat(
                            label: UiStrings.t('qty_kg'),
                            value: LocaleText.number(
                              totalQty,
                              fractionDigits: 1,
                            ),
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
                            label: UiStrings.t('avg_score'),
                            value: LocaleText.number(
                              avgScore,
                              fractionDigits: 1,
                            ),
                            icon: Icons.assessment_outlined,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MarketTrendStat(
                            label: UiStrings.t('avg_moisture'),
                            value: _formatLocalizedPercent(avgMoisture),
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
                        hintText: UiStrings.t('search_lot_hint'),
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
                            initialValue: _sortBy,
                            decoration: InputDecoration(
                              labelText: UiStrings.t('sort_by'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: _sortOptions
                                .map(
                                  (opt) => DropdownMenuItem(
                                    value: opt,
                                    child: Text(
                                      _localizedMarketSortOption(opt),
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
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final farm = _farmOptions[index];
                            final selected = farm == _selectedFarm;
                            return ChoiceChip(
                              label: Text(UiStrings.option(farm)),
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
                      Row(
                        children: [
                          const Icon(
                            Icons.inventory_2_outlined,
                            color: AppTheme.green,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            UiStrings.t('no_active_market_lots'),
                            style: const TextStyle(
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
                            ? UiStrings.t('market_empty_all_farms')
                            : UiStrings.f('market_empty_farm', {
                                'farm': _selectedFarm,
                              }),
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InventoryChip(
                            label: UiStrings.t('awaiting_harvest'),
                          ),
                          _InventoryChip(label: UiStrings.t('grade_required')),
                          _InventoryChip(label: UiStrings.t('remote_ready')),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              ...scopedLots.map((lot) {
                final batchId = lot['batchId'] ?? UiStrings.t('lot');
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
                                  LocaleText.digits(batchId),
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
                              _InventoryChip(label: UiStrings.option(crop)),
                              _InventoryChip(label: UiStrings.option(variety)),
                              _InventoryChip(
                                label: UiStrings.f('grade_value', {
                                  'grade': grade,
                                }),
                              ),
                              _InventoryChip(
                                label: UiStrings.f('score_value', {
                                  'score': score,
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _SummaryStat(
                                  title: UiStrings.t('qty'),
                                  value: _formatLocalizedKg(yieldEstimate),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SummaryStat(
                                  title: UiStrings.t('moisture_label'),
                                  value: _formatLocalizedPercent(moisture),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SummaryStat(
                                  title: UiStrings.t('bags'),
                                  value: _formatLocalizedBagSize(
                                    bagCount,
                                    bagSize,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            UiStrings.f('expected_lot_value', {
                              'value': LocaleText.number(
                                expectedValue,
                                fractionDigits: 0,
                              ),
                            }),
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
                                    UiStrings.t('market'),
                                    UiStrings.f('prepare_listing_for', {
                                      'batch': batchId,
                                    }),
                                    snackPosition: SnackPosition.BOTTOM,
                                  ),
                                  icon: const Icon(
                                    Icons.storefront_rounded,
                                    size: 18,
                                  ),
                                  label: Text(UiStrings.t('create_listing')),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Get.snackbar(
                                      UiStrings.t('market'),
                                      UiStrings.f('opening_demand_trend_for', {
                                        'batch': batchId,
                                      }),
                                      snackPosition: SnackPosition.BOTTOM,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.trending_up_rounded,
                                    size: 18,
                                  ),
                                  label: Text(UiStrings.t('demand_trend')),
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
              UiStrings.f('market_sync_context', {'scope': scopeLabel}),
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

  const NewsPage({super.key, this.farmName, this.farmLocation});

  static const List<Map<String, String>> _newsFeed = [
    {
      'title': 'news_msp_title',
      'summary': 'news_msp_summary',
      'time': 'opt_today',
      'tag': 'market',
      'impact': 'news_msp_impact',
    },
    {
      'title': 'news_monsoon_title',
      'summary': 'news_monsoon_summary',
      'time': 'yesterday',
      'tag': 'weather',
      'impact': 'news_monsoon_impact',
    },
    {
      'title': 'news_storage_title',
      'summary': 'news_storage_summary',
      'time': 'two_days_ago',
      'tag': 'storage',
      'impact': 'news_storage_impact',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final contextTitle = farmName == null
        ? UiStrings.t('news_advisories')
        : UiStrings.f('news_farm_title', {'farm': farmName!});
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
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _NewsCategoryChip(
                    label: UiStrings.t('all_news'),
                    selected: true,
                  ),
                  const SizedBox(width: 8),
                  _NewsCategoryChip(
                    label: UiStrings.t('msp_markets'),
                    selected: false,
                  ),
                  const SizedBox(width: 8),
                  _NewsCategoryChip(
                    label: UiStrings.t('weather_alerts'),
                    selected: false,
                  ),
                  const SizedBox(width: 8),
                  _NewsCategoryChip(
                    label: UiStrings.t('farming_tips'),
                    selected: false,
                  ),
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
                                ? (farmLocation ??
                                      UiStrings.t('local_farm_area'))
                                : (farmLocation == null ||
                                          farmLocation!.trim().isEmpty
                                      ? UiStrings.f('farm_updates', {
                                          'farm': farmName!,
                                        })
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
                        UiStrings.f('millet_field_tips', {
                          'farm': farmName ?? UiStrings.t('all_farms'),
                        }),
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
                          UiStrings.t(item['title']!),
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
                            _InventoryChip(label: UiStrings.t(item['tag']!)),
                            _InventoryChip(label: UiStrings.t(item['time']!)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          UiStrings.t(item['summary']!),
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          UiStrings.f('farm_impact_value', {
                            'value': UiStrings.t(item['impact']!),
                          }),
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

  const SchemesPage({super.key, this.farmName, this.farmLocation});

  static const List<Map<String, String>> _schemes = [
    {
      'title': 'scheme_pm_kisan_title',
      'desc': 'scheme_pm_kisan_desc',
      'status': 'apply',
      'fit': 'scheme_pm_kisan_fit',
    },
    {
      'title': 'scheme_processing_title',
      'desc': 'scheme_processing_desc',
      'status': 'open',
      'fit': 'scheme_processing_fit',
    },
    {
      'title': 'scheme_soil_title',
      'desc': 'scheme_soil_desc',
      'status': 'by_district_office',
      'fit': 'scheme_soil_fit',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final contextTitle = farmName == null
        ? UiStrings.t('government_schemes')
        : UiStrings.f('schemes_farm_title', {'farm': farmName!});
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
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: UiStrings.t('search_schemes_hint'),
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
                                ? (farmLocation ??
                                      UiStrings.t('local_scheme_center'))
                                : (farmLocation == null ||
                                          farmLocation!.trim().isEmpty
                                      ? UiStrings.f(
                                          'local_scheme_center_farm',
                                          {'farm': farmName!},
                                        )
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
                                UiStrings.t(scheme['title']!),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                UiStrings.t(scheme['desc']!),
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
                                  _InventoryChip(
                                    label: UiStrings.t(scheme['fit']!),
                                  ),
                                  _InventoryChip(
                                    label: UiStrings.t('farm_documents'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    UiStrings.t(scheme['status']!),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.greenDark,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Get.snackbar(
                                        UiStrings.t('schemes'),
                                        UiStrings.f('opening_application_for', {
                                          'scheme': UiStrings.t(
                                            scheme['title']!,
                                          ),
                                        }),
                                        snackPosition: SnackPosition.BOTTOM,
                                      );
                                    },
                                    child: Text(UiStrings.t('apply_now')),
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

class _SettingsPage extends StatefulWidget {
  final _FarmerProfile profile;
  final VoidCallback onOpenAddFarm;
  final VoidCallback onOpenNotifications;

  const _SettingsPage({
    required this.profile,
    required this.onOpenAddFarm,
    required this.onOpenNotifications,
  });

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  bool _farmAlerts = true;
  bool _marketUpdates = true;
  bool _gradingReminders = true;
  bool _offlineAccess = true;
  bool _autoSync = true;
  bool _deletionRequesting = false;

  void _saveToggle(String title, bool value, ValueChanged<bool> assign) {
    setState(() => assign(value));
    Get.snackbar(
      title,
      value ? UiStrings.t('enabled') : UiStrings.t('disabled'),
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void _openAddFarm() {
    Get.back();
    widget.onOpenAddFarm();
  }

  void _showPrivacyData() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(UiStrings.t('privacy_data')),
          content: Text(UiStrings.t('privacy_data_details')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(UiStrings.t('ok')),
            ),
          ],
        );
      },
    );
  }

  String _deletionRequestText() {
    return [
      'Account deletion request',
      'Name: ${widget.profile.name}',
      'Farmer ID: ${widget.profile.farmerId}',
      'Phone: ${widget.profile.phone}',
      'Location: ${widget.profile.location}',
      'Requested at: ${DateTime.now().toIso8601String()}',
    ].join('\n');
  }

  Future<void> _requestAccountDeletion() async {
    if (_deletionRequesting) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(UiStrings.t('delete_account_data')),
              content: Text(UiStrings.t('delete_account_data_body')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(UiStrings.t('cancel')),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(UiStrings.t('request_deletion')),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _deletionRequesting = true);
    final payload = {
      'status': 'requested',
      'source': 'farmer_app_settings',
      'farmer_id': widget.profile.farmerId,
      'farmer_name': widget.profile.name,
      'phone': widget.profile.phone,
      'location': widget.profile.location,
      'requested_at': DateTime.now().toIso8601String(),
    };

    try {
      final session = await ensureBackendBridgeSession();
      await SatelliteService().requestAccountDeletion(
        jwt: session.accessToken,
        payload: payload,
      );
      if (!mounted) return;
      Get.snackbar(
        UiStrings.t('delete_account_data'),
        UiStrings.t('deletion_request_saved'),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _deletionRequestText()));
      if (!mounted) return;
      Get.snackbar(
        UiStrings.t('delete_account_data'),
        UiStrings.t('deletion_request_copied'),
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
    } finally {
      if (mounted) setState(() => _deletionRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final farmCtrl = Get.isRegistered<FarmController>()
        ? Get.find<FarmController>()
        : null;
    final authCtrl = Get.find<MainAuthController>();
    return _PageScaffold(
      title: UiStrings.t('settings'),
      onBack: Get.back,
      safeArea: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHeader(profile: widget.profile, farmCtrl: farmCtrl),
          const SizedBox(height: 18),
          _FarmerSessionPassport(
            profile: widget.profile,
            farmCtrl: farmCtrl,
            authCtrl: authCtrl,
          ),
          const SizedBox(height: 18),
          _SettingsSectionLabel(UiStrings.t('account')),
          _Panel(
            child: Column(
              children: [
                _SettingsActionRow(
                  icon: Icons.badge_outlined,
                  title: UiStrings.t('farmer_identity'),
                  subtitle:
                      '${widget.profile.farmerId} • ${widget.profile.location}',
                  onTap: () => Get.snackbar(
                    UiStrings.t('farmer_account'),
                    '${UiStrings.t('profile_id_label')}: ${widget.profile.farmerId}',
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
                const Divider(height: 1),
                _SettingsActionRow(
                  icon: Icons.phone_iphone_rounded,
                  title: UiStrings.t('mobile_login'),
                  subtitle: widget.profile.phone,
                  onTap: () => Get.snackbar(
                    UiStrings.t('mobile_login'),
                    UiStrings.t('mobile_linked_profile'),
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
                const Divider(height: 1),
                _SettingsActionRow(
                  icon: Icons.language_rounded,
                  title: UiStrings.t('language'),
                  subtitle: UiStrings.t('language_options'),
                  onTap: () => Get.snackbar(
                    UiStrings.t('language'),
                    UiStrings.t('language_login_selector_hint'),
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SettingsSectionLabel(UiStrings.t('farms_and_sync')),
          _Panel(
            child: Column(
              children: [
                if (farmCtrl == null)
                  _SettingsActionRow(
                    icon: Icons.sync_rounded,
                    title: UiStrings.t('farm_data_sync'),
                    subtitle: UiStrings.t('farm_sync_not_available'),
                    onTap: () => Get.snackbar(
                      UiStrings.t('farm_data_sync'),
                      UiStrings.t('open_home_to_sync'),
                      snackPosition: SnackPosition.BOTTOM,
                    ),
                  )
                else
                  Obx(() {
                    final farmCount = farmCtrl.farms.length;
                    final loading = farmCtrl.isLoading.value;
                    return _SettingsActionRow(
                      icon: loading
                          ? Icons.cloud_sync_rounded
                          : Icons.cloud_done_rounded,
                      title: UiStrings.t('farm_data_sync'),
                      subtitle: loading
                          ? UiStrings.t('syncing_farms_from_cloud')
                          : '${LocaleText.number(farmCount)} ${UiStrings.t(farmCount == 1 ? 'synced_farm' : 'synced_farms')}',
                      trailing: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onTap: () async {
                        await farmCtrl.loadFarms();
                        Get.snackbar(
                          UiStrings.t('farm_data_sync'),
                          UiStrings.t('farm_data_refreshed'),
                          snackPosition: SnackPosition.BOTTOM,
                        );
                      },
                    );
                  }),
                const Divider(height: 1),
                _SettingsActionRow(
                  icon: Icons.map_rounded,
                  title: UiStrings.t('add_or_mark_farm'),
                  subtitle: UiStrings.t('farm_boundary_crop_details'),
                  onTap: _openAddFarm,
                ),
                const Divider(height: 1),
                _SettingsActionRow(
                  icon: Icons.delete_outline_rounded,
                  title: 'Manage farms',
                  subtitle: 'View synced farms and delete records from DB',
                  onTap: () => Get.toNamed('/farms/manage'),
                ),
                const Divider(height: 1),
                _SettingsSwitchRow(
                  icon: Icons.offline_bolt_outlined,
                  title: UiStrings.t('offline_access'),
                  subtitle: UiStrings.t('offline_context_available'),
                  value: _offlineAccess,
                  onChanged: (value) => _saveToggle(
                    UiStrings.t('offline_access'),
                    value,
                    (next) => _offlineAccess = next,
                  ),
                ),
                const Divider(height: 1),
                _SettingsSwitchRow(
                  icon: Icons.autorenew_rounded,
                  title: UiStrings.t('auto_sync_after_login'),
                  subtitle: UiStrings.t('refresh_farms_on_open'),
                  value: _autoSync,
                  onChanged: (value) => _saveToggle(
                    UiStrings.t('auto_sync_after_login'),
                    value,
                    (next) => _autoSync = next,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SettingsSectionLabel(UiStrings.t('notifications')),
          _Panel(
            child: Column(
              children: [
                _SettingsActionRow(
                  icon: Icons.notifications_active_outlined,
                  title: UiStrings.t('notification_panel'),
                  subtitle: UiStrings.t('notification_panel_desc'),
                  onTap: widget.onOpenNotifications,
                ),
                const Divider(height: 1),
                _SettingsSwitchRow(
                  icon: Icons.eco_outlined,
                  title: UiStrings.t('farm_health_alerts'),
                  subtitle: UiStrings.t('farm_health_alerts_desc'),
                  value: _farmAlerts,
                  onChanged: (value) => _saveToggle(
                    UiStrings.t('farm_health_alerts'),
                    value,
                    (next) => _farmAlerts = next,
                  ),
                ),
                const Divider(height: 1),
                _SettingsSwitchRow(
                  icon: Icons.storefront_outlined,
                  title: UiStrings.t('market_price_updates'),
                  subtitle: UiStrings.t('market_price_updates_desc'),
                  value: _marketUpdates,
                  onChanged: (value) => _saveToggle(
                    UiStrings.t('market_price_updates'),
                    value,
                    (next) => _marketUpdates = next,
                  ),
                ),
                const Divider(height: 1),
                _SettingsSwitchRow(
                  icon: Icons.grain,
                  title: UiStrings.t('grading_qr_reminders'),
                  subtitle: UiStrings.t('grading_qr_reminders_desc'),
                  value: _gradingReminders,
                  onChanged: (value) => _saveToggle(
                    UiStrings.t('grading_qr_reminders'),
                    value,
                    (next) => _gradingReminders = next,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SettingsSectionLabel(UiStrings.t('privacy_support')),
          _Panel(
            child: Column(
              children: [
                _SettingsActionRow(
                  icon: Icons.privacy_tip_outlined,
                  title: UiStrings.t('privacy_data'),
                  subtitle: UiStrings.t('privacy_data_desc'),
                  onTap: _showPrivacyData,
                ),
                const Divider(height: 1),
                _SettingsActionRow(
                  icon: Icons.delete_forever_outlined,
                  title: UiStrings.t('delete_account_data'),
                  subtitle: UiStrings.t('delete_account_data_desc'),
                  iconColor: Colors.redAccent,
                  textColor: Colors.redAccent,
                  trailing: _deletionRequesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _requestAccountDeletion,
                ),
                const Divider(height: 1),
                _SettingsActionRow(
                  icon: Icons.support_agent_rounded,
                  title: UiStrings.t('help_and_support'),
                  subtitle: UiStrings.t('support_account_farm'),
                  onTap: () => Get.snackbar(
                    UiStrings.t('support_title'),
                    UiStrings.t('support_account_help'),
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
                const Divider(height: 1),
                _SettingsActionRow(
                  icon: Icons.info_outline_rounded,
                  title: UiStrings.t('about_grainright'),
                  subtitle: UiStrings.t('grainright_about_desc'),
                  onTap: () => Get.snackbar(
                    'GrainRight',
                    UiStrings.f('version_value', {'version': '1.0.7'}),
                    snackPosition: SnackPosition.BOTTOM,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Panel(
            tint: const Color(0xFFFFFBFB),
            child: _SettingsActionRow(
              icon: Icons.logout_rounded,
              title: UiStrings.t('logout'),
              subtitle: UiStrings.t('return_to_role_selection'),
              iconColor: Colors.redAccent,
              textColor: Colors.redAccent,
              onTap: () => Get.find<MainAuthController>().logout(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmerNotificationsPage extends StatefulWidget {
  final String farmerId;
  final String farmerPhone;
  final FarmStatusNotificationService service;
  final String authToken;
  final String? initialNotificationId;

  const _FarmerNotificationsPage({
    required this.farmerId,
    required this.farmerPhone,
    required this.service,
    required this.authToken,
    this.initialNotificationId,
  });

  @override
  State<_FarmerNotificationsPage> createState() =>
      _FarmerNotificationsPageState();
}

class _FarmerNotificationsPageState extends State<_FarmerNotificationsPage> {
  static const _pageSize = 20;

  List<FarmerNotification> _items = const <FarmerNotification>[];
  int _visibleCount = _pageSize;
  bool _loading = true;
  bool _handledInitialNotification = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.listNotifications(
        farmerId: widget.farmerId,
        farmerPhone: widget.farmerPhone,
        authToken: widget.authToken,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _visibleCount = _pageSize;
      });
      await _markInitialNotificationRead(items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = UiStrings.t('notification_sync_failed'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(FarmerNotification item) async {
    if (item.isRead) return;
    final ok = await widget.service.markNotificationRead(
      farmerId: widget.farmerId,
      farmerPhone: widget.farmerPhone,
      notificationId: item.id,
      authToken: widget.authToken,
    );
    if (!mounted || !ok) return;
    setState(() {
      _items = _items
          .map(
            (entry) => entry.id == item.id
                ? entry.copyWith(readAt: DateTime.now())
                : entry,
          )
          .toList(growable: false);
    });
  }

  Future<void> _markInitialNotificationRead(
    List<FarmerNotification> items,
  ) async {
    if (_handledInitialNotification) return;
    _handledInitialNotification = true;
    final id = widget.initialNotificationId?.trim();
    if (id == null || id.isEmpty) return;
    for (final item in items) {
      if (item.id == id) {
        await _markRead(item);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _items.take(_visibleCount).toList(growable: false);
    final hasMoreItems = _visibleCount < _items.length;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('notifications')),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: UiStrings.t('refresh'),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              _Panel(
                tint: const Color(0xFFF0F8E8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_rounded,
                        color: AppTheme.greenDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          UiStrings.t('notification_panel_desc'),
                          style: const TextStyle(
                            color: AppTheme.greenDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_loading && _items.isEmpty)
                const _Panel(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_error != null)
                _Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(UiStrings.t('try_again')),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_items.isEmpty)
                _Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.notifications_none_rounded,
                          color: AppTheme.greenDark,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          UiStrings.t('no_farmer_notifications'),
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          UiStrings.t('no_farmer_notifications_desc'),
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                for (final item in visibleItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FarmerNotificationCard(
                      item: item,
                      onMarkRead: () => unawaited(_markRead(item)),
                    ),
                  ),
                if (hasMoreItems)
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          final next = _visibleCount + _pageSize;
                          _visibleCount = next > _items.length
                              ? _items.length
                              : next;
                        });
                      },
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(UiStrings.t('show_more_notifications')),
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

class _FarmerNotificationCard extends StatelessWidget {
  final FarmerNotification item;
  final VoidCallback onMarkRead;

  const _FarmerNotificationCard({required this.item, required this.onMarkRead});

  @override
  Widget build(BuildContext context) {
    final timeText =
        '${LocaleText.date(item.createdAt, pattern: 'dd/MM')} ${LocaleText.time(item.createdAt)}';
    return _Panel(
      tint: item.isRead ? Colors.white : const Color(0xFFF4FAEF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: item.isRead ? AppTheme.greenPale : AppTheme.green,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    item.isRead
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_active_rounded,
                    color: item.isRead ? AppTheme.greenDark : Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title.isEmpty
                            ? UiStrings.t('new_notification')
                            : item.title,
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.message,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      item.farmName,
                      timeText,
                    ].where((value) => value.trim().isNotEmpty).join(' • '),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!item.isRead)
                  TextButton(
                    onPressed: onMarkRead,
                    child: Text(UiStrings.t('mark_read')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final _FarmerProfile profile;
  final FarmController? farmCtrl;

  const _SettingsHeader({required this.profile, required this.farmCtrl});

  @override
  Widget build(BuildContext context) {
    Widget content(int farmCount, String activeFarmName) {
      return _Panel(
        tint: const Color(0xFFF7FBF2),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.green,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                      size: 30,
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
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          profile.phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SettingsPill(
                    icon: Icons.verified_rounded,
                    label: UiStrings.t('verified_farmer_short'),
                  ),
                  _SettingsPill(
                    icon: Icons.cloud_done_rounded,
                    label:
                        '${LocaleText.number(farmCount)} ${UiStrings.t(farmCount == 1 ? 'synced_farm' : 'synced_farms')}',
                  ),
                  _SettingsPill(
                    icon: Icons.grass_rounded,
                    label: activeFarmName,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (farmCtrl == null) {
      return content(0, UiStrings.t('no_active_farm'));
    }
    return Obx(() {
      final farms = farmCtrl!.farms;
      final selected = farmCtrl!.selectedFarm.value;
      return content(
        farms.length,
        selected?.name ??
            (farms.isEmpty ? UiStrings.t('no_active_farm') : farms.first.name),
      );
    });
  }
}

class _FarmerSessionPassport extends StatelessWidget {
  final _FarmerProfile profile;
  final FarmController? farmCtrl;
  final MainAuthController authCtrl;

  const _FarmerSessionPassport({
    required this.profile,
    required this.farmCtrl,
    required this.authCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final farmCount =
          farmCtrl?.farms.length ??
          authCtrl.lastFarmerLoginFarmCount.value ??
          authCtrl.farmerLoginSyncedFarmCount.value ??
          0;
      final selectedFarm = farmCtrl?.selectedFarm.value;
      final lastSync =
          authCtrl.lastFarmerLoginSyncAt.value ??
          authCtrl.farmerLoginLastSyncAt.value;
      final lastSyncLabel = lastSync == null
          ? UiStrings.t('last_sync_not_available')
          : UiStrings.f('last_sync_value', {
              'value':
                  '${LocaleText.date(lastSync, pattern: 'dd/MM/yyyy')} ${LocaleText.time(lastSync)}',
            });
      return _Panel(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.greenPale,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: AppTheme.greenDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          UiStrings.t('farmer_session_passport'),
                          style: const TextStyle(
                            color: AppTheme.greenDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          UiStrings.t('verified_login_sync_summary'),
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
              const SizedBox(height: 12),
              _InfoStrip(
                icon: Icons.badge_outlined,
                label: UiStrings.t('farmer_id'),
                value: profile.farmerId,
              ),
              _InfoStrip(
                icon: Icons.phone_iphone_rounded,
                label: UiStrings.t('mobile_number'),
                value: profile.phone,
              ),
              _InfoStrip(
                icon: Icons.grass_rounded,
                label: UiStrings.t('synced_farms_count'),
                value: UiStrings.f('farm_count_value', {'count': farmCount}),
              ),
              _InfoStrip(
                icon: Icons.schedule_rounded,
                label: UiStrings.t('last_sync'),
                value: lastSyncLabel,
              ),
              _InfoStrip(
                icon: Icons.map_rounded,
                label: UiStrings.t('active_farm'),
                value: selectedFarm?.name ?? UiStrings.t('no_active_farm'),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String label;

  const _SettingsSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.greenDark,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SettingsPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SettingsPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final maxLabelWidth = (MediaQuery.sizeOf(context).width - 128).clamp(
      120.0,
      260.0,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE8D4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.green, size: 17),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxLabelWidth.toDouble()),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? iconColor;
  final Color? textColor;

  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppTheme.green;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      minVerticalPadding: 12,
      horizontalTitleGap: 12,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? AppTheme.textDark,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.fromLTRB(14, 5, 10, 5),
      visualDensity: VisualDensity.standard,
      secondary: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.green.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: AppTheme.green),
      ),
      activeThumbColor: AppTheme.green,
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textDark,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FirstFarmLoadOverlay extends StatelessWidget {
  final String title;
  final String message;
  final bool isError;

  const _FirstFarmLoadOverlay({
    required this.title,
    required this.message,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    final displayTitle = title.trim().isEmpty
        ? UiStrings.t('please_wait')
        : title.trim();
    final displayMessage = message.trim().isEmpty
        ? UiStrings.t('checking_farms_for_mobile')
        : message.trim();
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.38),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 22),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFE0EBDD)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 34,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.greenPale.withValues(alpha: 0.95),
                        const Color(0xFFFFF8E1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (!isError)
                            const SizedBox(
                              width: 62,
                              height: 62,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                color: AppTheme.green,
                              ),
                            ),
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.greenDark.withValues(
                                    alpha: 0.10,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              isError
                                  ? Icons.sync_problem_rounded
                                  : Icons.add_location_alt_rounded,
                              color: isError ? Colors.orange : AppTheme.green,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              displayMessage,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isError) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(
                      minHeight: 7,
                      color: AppTheme.green,
                      backgroundColor: Color(0xFFEAF3E5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_sync_rounded,
                        color: AppTheme.greenDark,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          UiStrings.t('first_farm_loading_hint'),
                          style: const TextStyle(
                            color: AppTheme.greenDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FirstFarmGuideStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FirstFarmGuideStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2EEDD)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.greenPale.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppTheme.greenDark, size: 21),
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
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _SideNavGroupedLinks extends StatelessWidget {
  final bool expanded;
  final VoidCallback onOpenNews;
  final VoidCallback onOpenGrainGrading;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenApmcMarket;
  final VoidCallback onOpenSchemes;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenOfflineMaps;
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
    required this.onOpenOfflineMaps,
    required this.onOpenProfile,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final primary = [
      _SideUtilityItemData(
        icon: Icons.wb_cloudy_rounded,
        label: UiStrings.t('weather'),
        onTap: onOpenWeather,
      ),
      _SideUtilityItemData(
        icon: Icons.storefront_rounded,
        label: UiStrings.t('apmc_market'),
        onTap: onOpenApmcMarket,
      ),
      _SideUtilityItemData(
        icon: Icons.newspaper_rounded,
        label: UiStrings.t('news'),
        onTap: onOpenNews,
      ),
      _SideUtilityItemData(
        icon: Icons.assignment_rounded,
        label: UiStrings.t('schemes'),
        onTap: onOpenSchemes,
      ),
      _SideUtilityItemData(
        icon: Icons.grain,
        label: UiStrings.t('grain_grading'),
        onTap: onOpenGrainGrading,
      ),
      _SideUtilityItemData(
        icon: Icons.offline_pin_rounded,
        label: UiStrings.t('offline_maps'),
        onTap: onOpenOfflineMaps,
      ),
    ];
    final secondary = [
      _SideUtilityItemData(
        icon: Icons.history_rounded,
        label: UiStrings.t('farm_history'),
        onTap: onOpenHistory,
      ),
      _SideUtilityItemData(
        icon: Icons.inventory_2_rounded,
        label: UiStrings.t('inventory'),
        onTap: onOpenInventory,
      ),
      _SideUtilityItemData(
        icon: Icons.person_rounded,
        label: UiStrings.t('profile'),
        onTap: onOpenProfile,
      ),
      _SideUtilityItemData(
        icon: Icons.settings_rounded,
        label: UiStrings.t('settings'),
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
          opacity: value.clamp(0.0, 1.0).toDouble(),
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
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.logout_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        UiStrings.t('logout'),
                        style: const TextStyle(
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
  final VoidCallback? onBack;
  final Future<void> Function()? onRefresh;
  final bool safeArea;

  const _PageScaffold({
    required this.title,
    required this.child,
    this.onBack,
    this.onRefresh,
    this.safeArea = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 160),
      children: [
        Row(
          children: [
            if (onBack != null) ...[
              AppBackButton(onPressed: onBack),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
    final pageContent = safeArea ? SafeArea(child: content) : content;
    return Material(
      color: AppTheme.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFCF5), AppTheme.surface],
          ),
        ),
        child: onRefresh == null
            ? pageContent
            : RefreshIndicator(onRefresh: onRefresh!, child: pageContent),
      ),
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
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE3EADD)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenDark.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(color: Colors.transparent, child: child),
    );
  }
}

class _HarvestMoistureReadingCard extends StatelessWidget {
  final MoistureOcrResult reading;

  const _HarvestMoistureReadingCard({required this.reading});

  @override
  Widget build(BuildContext context) {
    final percent = reading.percent;
    final riskTag = _riskTag(percent);
    final riskColor = _riskColor(percent);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: riskColor.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.speed_rounded, color: riskColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.t('moisture_reading_title'),
                  style: TextStyle(
                    color: riskColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  UiStrings.f('moisture_reading_meta', {
                    'source': reading.source,
                    'confidence': reading.confidence == null
                        ? '--'
                        : '${(reading.confidence! * 100).round()}',
                  }),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                if (riskTag != null)
                  _StatusPill(
                    icon: Icons.report_problem_outlined,
                    label: UiStrings.t(riskTag),
                  ),
              ],
            ),
          ),
          Text(
            percent == null ? '--' : _formatLocalizedPercent(percent),
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  static String? _riskTag(double? percent) {
    if (percent == null) return null;
    if (percent <= 11) return 'moisture_risk_good';
    if (percent <= 12.8) return 'moisture_risk_watch';
    return 'moisture_risk_high';
  }

  static Color _riskColor(double? percent) {
    if (percent == null) return AppTheme.green;
    if (percent <= 11) return const Color(0xFF2E7D32);
    if (percent <= 12.8) return const Color(0xFFF57F17);
    return const Color(0xFFB71C1C);
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final maxWidth = math.max(72.0, MediaQuery.sizeOf(context).width - 48);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
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
          Flexible(
            child: Text(
              label,
              maxLines: 2,
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
