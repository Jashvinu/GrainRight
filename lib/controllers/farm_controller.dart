import 'dart:async';

import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/ui_strings.dart';
import '../controllers/auth_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../models/satellite/farm_model.dart';
import '../services/local_app_database.dart';
import '../services/satellite_service.dart';
import '../utils/polygon_geometry.dart';

class FarmController extends GetxController {
  final _service = SatelliteService();

  final farms = <Farm>[].obs;
  final selectedFarm = Rxn<Farm>();
  final isLoading = false.obs;
  final hasError = false.obs;
  final errorMessage = ''.obs;
  String? _farmSessionCacheKey;
  List<Farm> _cachedSessionFarms = const [];
  bool _cacheLoadedForSession = false;
  String? _lastPhoneOwnerFallbackSessionKey;
  bool _phoneOwnerFallbackAttempted = false;
  String? _pendingSavedFarmSessionKey;
  final Map<String, Farm> _pendingSavedFarmsById = {};
  int _loadRequestId = 0;

  @override
  void onInit() {
    super.onInit();
    if (_hasLoadPrerequisites || _verifiedFarmerPhone != null) {
      loadFarms();
    }
  }

  String get _jwt {
    final supabaseToken = Supabase
        .instance
        .client
        .auth
        .currentSession
        ?.accessToken
        .trim();
    if (supabaseToken != null && supabaseToken.isNotEmpty) {
      return supabaseToken;
    }
    if (Get.isRegistered<AuthController>()) {
      final token = Get.find<AuthController>().accessToken.value.trim();
      if (token.isNotEmpty) return token;
    }
    return '';
  }

  String? get _verifiedFarmerPhone {
    if (!Get.isRegistered<MainAuthController>()) return null;
    final phone = Get.find<MainAuthController>().verifiedFarmer.value?.phone;
    final digits = phone?.replaceAll(RegExp(r'\D'), '');
    return digits == null || digits.isEmpty ? null : digits;
  }

  String? get _verifiedFarmerId {
    if (!Get.isRegistered<MainAuthController>()) return null;
    final farmerId = Get.find<MainAuthController>()
        .verifiedFarmer
        .value
        ?.farmerId
        .trim();
    return farmerId == null || farmerId.isEmpty ? null : farmerId;
  }

  String? get _currentUserId {
    final controllerId = Get.isRegistered<AuthController>()
        ? Get.find<AuthController>().currentUser.value?.id.trim()
        : null;
    if (controllerId != null && controllerId.isNotEmpty) {
      return controllerId;
    }
    final supabaseId = Supabase.instance.client.auth.currentUser?.id.trim();
    return supabaseId == null || supabaseId.isEmpty ? null : supabaseId;
  }

  LocalAppDatabase? get _localDb => LocalAppDatabase.maybeInstance;

  bool get _hasLoadPrerequisites {
    if (_jwt.trim().isEmpty) return false;
    return _verifiedFarmerPhone != null || _currentUserId != null;
  }

  bool get hasCurrentSessionFarmSnapshot {
    final activeKey = _activeVerifiedSessionKey;
    final hasCurrentSessionCache =
        activeKey != null && _farmSessionCacheKey == activeKey;
    return isLoading.value ||
        _pendingSavedFarmsById.isNotEmpty ||
        (_cacheLoadedForSession && hasCurrentSessionCache) ||
        (farms.isNotEmpty && hasCurrentSessionCache);
  }

  bool _isLatestFarmLoad(int requestId) => requestId == _loadRequestId;

  Future<void> _ensureSatelliteSessionFromMainAuth() async {
    try {
      final authCtrl = Get.isRegistered<AuthController>()
          ? Get.find<AuthController>()
          : Get.put(AuthController());
      final supabaseAuth = Supabase.instance.client.auth;
      final session = supabaseAuth.currentSession;
      final user = supabaseAuth.currentUser;
      if (session == null ||
          user == null ||
          session.accessToken.trim().isEmpty) {
        return;
      }

      final currentSatelliteUserId = authCtrl.currentUser.value?.id.trim();
      final hasSatelliteSession =
          authCtrl.accessToken.value.trim().isNotEmpty &&
          authCtrl.accessToken.value.trim() == session.accessToken.trim() &&
          currentSatelliteUserId != null &&
          currentSatelliteUserId == user.id;
      if (hasSatelliteSession) return;

      final phone = _verifiedFarmerPhone;
      final email =
          user.email ??
          (phone == null || phone.isEmpty
              ? 'farmer-${user.id}@anonymous.local'
              : 'farmer-$phone@anonymous.local');
      await authCtrl.setExternalSession(
        accessTokenValue: session.accessToken,
        refreshTokenValue: session.refreshToken,
        userId: user.id,
        email: email,
      );
    } catch (error) {
      Get.log('Satellite session sync before farm load/save failed: $error');
    }
  }

  void _selectFreshFarmFrom(List<Farm> farmList, {String? preferredFarmId}) {
    if (farmList.isEmpty) {
      selectedFarm.value = null;
      return;
    }
    final preferredId = preferredFarmId?.trim();
    if (preferredId != null && preferredId.isNotEmpty) {
      for (final farm in farmList) {
        if (farm.id == preferredId) {
          selectedFarm.value = farm;
          return;
        }
      }
    }
    final selectedId = selectedFarm.value?.id;
    if (selectedId != null && selectedId.isNotEmpty) {
      for (final farm in farmList) {
        if (farm.id == selectedId) {
          selectedFarm.value = farm;
          return;
        }
      }
    }
    selectedFarm.value = farmList.first;
  }

  Future<void> loadFarms({
    bool forceRefresh = false,
    String? preferredFarmId,
  }) async {
    final requestId = ++_loadRequestId;
    await _ensureSatelliteSessionFromMainAuth();
    if (!_isLatestFarmLoad(requestId)) return;
    isLoading.value = true;
    hasError.value = false;
    final restrictToVerifiedFarmer = _verifiedFarmerPhone != null;
    if (!_hasLoadPrerequisites) {
      if (restrictToVerifiedFarmer) {
        final cached = await _loadCachedVerifiedFarmerFarms();
        if (!_isLatestFarmLoad(requestId)) return;
        if (cached.isNotEmpty) {
          farms.assignAll(cached);
          _selectFreshFarmFrom(cached, preferredFarmId: preferredFarmId);
          _cacheLoadedForSession = true;
          _farmSessionCacheKey = _activeVerifiedSessionKey;
          _cachedSessionFarms = List<Farm>.from(cached, growable: false);
          _markVerifiedFarmSyncReady();
        }
      }
      if (_isLatestFarmLoad(requestId)) {
        isLoading.value = false;
      }
      return;
    }
    final verifiedCacheKey = _activeVerifiedSessionKey;
    if (restrictToVerifiedFarmer &&
        verifiedCacheKey != _lastPhoneOwnerFallbackSessionKey) {
      _phoneOwnerFallbackAttempted = false;
      _lastPhoneOwnerFallbackSessionKey = verifiedCacheKey;
    }
    if (restrictToVerifiedFarmer &&
        verifiedCacheKey != _pendingSavedFarmSessionKey) {
      _pendingSavedFarmsById.clear();
      _pendingSavedFarmSessionKey = verifiedCacheKey;
    }

    if (restrictToVerifiedFarmer && !forceRefresh) {
      final cacheKey = _farmSessionCacheKey;
      if (_cacheLoadedForSession &&
          cacheKey != null &&
          cacheKey == _activeVerifiedSessionKey &&
          _cachedSessionFarms.isNotEmpty) {
        farms.assignAll(_cachedSessionFarms);
        _selectFreshFarmFrom(farms, preferredFarmId: preferredFarmId);
        _markVerifiedFarmSyncReady();
        if (_isLatestFarmLoad(requestId)) {
          isLoading.value = false;
        }
        return;
      }
    } else if (!restrictToVerifiedFarmer) {
      _cacheLoadedForSession = false;
      _farmSessionCacheKey = null;
    }

    try {
      final canPreserveVisibleFarms =
          restrictToVerifiedFarmer &&
          verifiedCacheKey != null &&
          _farmSessionCacheKey == verifiedCacheKey;
      final previousVisibleFarms = !canPreserveVisibleFarms
          ? const <Farm>[]
          : farms.isNotEmpty
          ? List<Farm>.from(farms, growable: false)
          : List<Farm>.from(_cachedSessionFarms, growable: false);
      var result = await _loadFarmsForCurrentFarmer(
        preferredFarmId: preferredFarmId,
      );
      if (!_isLatestFarmLoad(requestId)) return;
      if (restrictToVerifiedFarmer) {
        result = _mergePendingSavedFarms(result);
        if (result.isEmpty && previousVisibleFarms.isNotEmpty) {
          result = previousVisibleFarms;
          Get.log(
            'Preserved local farmer farms after empty remote response for $_activeVerifiedSessionKey',
          );
        }
      } else {
        _pendingSavedFarmsById.clear();
      }
      farms.assignAll(result);
      if (restrictToVerifiedFarmer) {
        _cacheLoadedForSession = true;
        _farmSessionCacheKey = _activeVerifiedSessionKey;
        _lastPhoneOwnerFallbackSessionKey = _farmSessionCacheKey;
        _cachedSessionFarms = result.isEmpty
            ? const []
            : List<Farm>.from(result, growable: false);
        _markVerifiedFarmSyncReady();
      } else {
        _cacheLoadedForSession = false;
        _farmSessionCacheKey = null;
        _cachedSessionFarms = const [];
      }
      _selectFreshFarmFrom(farms, preferredFarmId: preferredFarmId);
      if (restrictToVerifiedFarmer) {
        await _cacheVerifiedFarmerFarms();
      }
    } on Exception catch (e) {
      if (!_isLatestFarmLoad(requestId)) return;
      hasError.value = true;
      errorMessage.value = e.toString();
      if (farms.isEmpty && restrictToVerifiedFarmer) {
        final cached = await _loadCachedVerifiedFarmerFarms();
        if (!_isLatestFarmLoad(requestId)) return;
        if (cached.isNotEmpty) {
          farms.assignAll(cached);
          _selectFreshFarmFrom(cached, preferredFarmId: preferredFarmId);
          hasError.value = false;
          errorMessage.value = '';
          _cacheLoadedForSession = true;
          _farmSessionCacheKey = _activeVerifiedSessionKey;
          _cachedSessionFarms = List<Farm>.from(cached, growable: false);
          _markVerifiedFarmSyncReady();
        } else {
          _cacheLoadedForSession = false;
        }
      }
    } finally {
      if (_isLatestFarmLoad(requestId)) {
        isLoading.value = false;
      }
    }
  }

  Future<void> repairEmptyFarmCache() async {
    _cacheLoadedForSession = false;
    _farmSessionCacheKey = null;
    _cachedSessionFarms = const [];
    _phoneOwnerFallbackAttempted = false;
    selectedFarm.value = null;
    await loadFarms(forceRefresh: true);
  }

  Future<Farm?> syncSavedFarmFromRemote(
    String farmId, {
    Duration timeout = const Duration(seconds: 4),
    bool retryHttpErrors = true,
  }) async {
    final preferredId = farmId.trim();
    if (preferredId.isEmpty) return null;
    await _ensureSatelliteSessionFromMainAuth();
    final farmerPhone = _verifiedFarmerPhone;
    final jwt = _jwt;
    if (farmerPhone != null && jwt.trim().isNotEmpty) {
      try {
        final remoteFarms = await _service.getFarmsForFarmerPhone(
          phone: farmerPhone,
          farmerId: _verifiedFarmerId,
          preferredFarmId: preferredId,
          jwt: jwt,
          retryHttpErrors: retryHttpErrors,
          timeout: timeout,
        );
        for (final farm in remoteFarms) {
          if (farm.id == preferredId) {
            _replaceWithConfirmedFarmList(
              remoteFarms,
              preferredFarmId: preferredId,
            );
            return farm;
          }
        }
        if (!retryHttpErrors) return null;
      } catch (error) {
        Get.log('Fast saved farm sync failed: $error');
        if (!retryHttpErrors) return null;
      }
    }
    await loadFarms(forceRefresh: true, preferredFarmId: preferredId);
    for (final farm in farms) {
      if (farm.id == preferredId) {
        selectFarm(farm);
        await _cacheVerifiedFarmerFarms();
        return farm;
      }
    }
    return null;
  }

  void invalidateFarmCache() {
    _cacheLoadedForSession = false;
    _farmSessionCacheKey = null;
    _cachedSessionFarms = const [];
  }

  List<Farm> _mergePendingSavedFarms(List<Farm> remoteFarms) {
    if (_pendingSavedFarmsById.isEmpty) return remoteFarms;
    final remoteIds = remoteFarms.map((farm) => farm.id).toSet();
    final merged = List<Farm>.from(remoteFarms, growable: true);
    for (final entry in List<MapEntry<String, Farm>>.from(
      _pendingSavedFarmsById.entries,
    )) {
      if (remoteIds.contains(entry.key)) {
        _pendingSavedFarmsById.remove(entry.key);
        continue;
      }
      merged.insert(0, entry.value);
    }
    return merged;
  }

  void _upsertSavedFarm(Farm farm) {
    _pendingSavedFarmsById[farm.id] = farm;
    _pendingSavedFarmSessionKey = _activeVerifiedSessionKey;
    final existingIndex = farms.indexWhere((item) => item.id == farm.id);
    if (existingIndex >= 0) {
      farms[existingIndex] = farm;
    } else {
      farms.insert(0, farm);
    }
    selectFarm(farm);

    if (_verifiedFarmerPhone != null) {
      _cacheLoadedForSession = true;
      _farmSessionCacheKey = _activeVerifiedSessionKey;
      _lastPhoneOwnerFallbackSessionKey = _farmSessionCacheKey;
      _cachedSessionFarms = List<Farm>.from(farms, growable: false);
      _markVerifiedFarmSyncReady();
    }
  }

  void _replaceWithConfirmedFarmList(
    List<Farm> remoteFarms, {
    required String preferredFarmId,
  }) {
    final merged = _mergePendingSavedFarms(remoteFarms);
    farms.assignAll(merged);
    _selectFreshFarmFrom(farms, preferredFarmId: preferredFarmId);
    if (_verifiedFarmerPhone != null) {
      _cacheLoadedForSession = true;
      _farmSessionCacheKey = _activeVerifiedSessionKey;
      _lastPhoneOwnerFallbackSessionKey = _farmSessionCacheKey;
      _cachedSessionFarms = List<Farm>.from(farms, growable: false);
      _markVerifiedFarmSyncReady();
    }
    unawaited(_cacheVerifiedFarmerFarms());
  }

  void _markVerifiedFarmSyncReady() {
    if (_verifiedFarmerPhone == null ||
        !Get.isRegistered<MainAuthController>()) {
      return;
    }
    final auth = Get.find<MainAuthController>();
    auth.farmerLoginSyncedFarmCount.value = farms.length;
    auth.farmerLoginLastSyncAt.value = DateTime.now().toUtc();
    auth.farmerLoginSyncStatusCode.value = farms.isEmpty
        ? 'farms_not_found'
        : 'farms_synced';
    auth.farmerLoginState.value = FarmerLoginState.ready;
  }

  Future<void> _cacheVerifiedFarmerFarms() async {
    final db = _localDb;
    final phone = _verifiedFarmerPhone;
    if (db == null || phone == null) return;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final selectedId = selectedFarm.value?.id;
      await db.replaceFarmCacheForFarmer(
        farmerPhone: phone,
        farmerId: _verifiedFarmerId,
        farms: farms
            .map(
              (farm) => LocalFarmCacheRecord(
                farmId: farm.id,
                userId: farm.userId,
                farmerPhone: phone,
                farmerIdValue: _verifiedFarmerId,
                name: farm.name,
                geometry: farm.geometry,
                bounds: farm.bounds,
                areaHectares: farm.areaHectares,
                areaAcres: farm.areaAcres,
                crop: farm.crop,
                variety: farm.variety,
                previousCrop: farm.previousCrop,
                season: farm.season,
                irrigation: farm.irrigation,
                soilType: farm.soilType,
                ownershipType: farm.ownershipType,
                seedSource: farm.seedSource,
                harvestIntent: farm.harvestIntent,
                sowingDate: farm.sowingDate,
                currentStatus: farm.currentStatus,
                currentStatusStage: farm.currentStatusStage,
                currentStatusUpdatedAt: farm.currentStatusUpdatedAt,
                createdAt: farm.createdAt.isEmpty ? now : farm.createdAt,
                updatedAt: farm.currentStatusUpdatedAt ?? now,
                selected: farm.id == selectedId,
              ),
            )
            .toList(growable: false),
      );
    } catch (error) {
      Get.log('Local farm cache write failed: $error');
    }
  }

  Future<List<Farm>> _loadCachedVerifiedFarmerFarms() async {
    final db = _localDb;
    final phone = _verifiedFarmerPhone;
    if (db == null || phone == null) return const [];
    try {
      final records = await db.loadCachedFarmsForFarmer(
        farmerPhone: phone,
        farmerId: _verifiedFarmerId,
      );
      return records.map(_farmFromLocalCache).toList(growable: false);
    } catch (error) {
      Get.log('Local farm cache read failed: $error');
      return const [];
    }
  }

  Farm _farmFromLocalCache(LocalFarmCacheRecord record) {
    return Farm(
      id: record.farmId,
      name: record.name,
      geometry: record.geometry,
      bounds: record.bounds,
      areaHectares: record.areaHectares,
      areaAcres: record.areaAcres,
      userId: record.userId,
      createdAt: record.createdAt,
      crop: record.crop,
      variety: record.variety,
      previousCrop: record.previousCrop,
      season: record.season,
      irrigation: record.irrigation,
      soilType: record.soilType,
      ownershipType: record.ownershipType,
      seedSource: record.seedSource,
      harvestIntent: record.harvestIntent,
      sowingDate: record.sowingDate,
      currentStatus: record.currentStatus,
      currentStatusStage: record.currentStatusStage,
      currentStatusUpdatedAt: record.currentStatusUpdatedAt,
    );
  }

  Future<List<Farm>> _loadFarmsForCurrentFarmer({
    String? preferredFarmId,
  }) async {
    final jwt = _jwt;
    if (jwt.trim().isEmpty) return const [];

    final ownerUserId = _currentUserId;
    final phone = _verifiedFarmerPhone;
    if (phone != null) {
      List<Farm> phoneFarms;
      try {
        phoneFarms = await _service.getFarmsForFarmerPhone(
          phone: phone,
          farmerId: _verifiedFarmerId,
          preferredFarmId: preferredFarmId,
          jwt: jwt,
        );
      } catch (error) {
        if (ownerUserId != null &&
            !_phoneOwnerFallbackAttempted &&
            _activeVerifiedSessionKey == _lastPhoneOwnerFallbackSessionKey) {
          _phoneOwnerFallbackAttempted = true;
          return await _service.getFarms(jwt, ownerUserId: ownerUserId);
        }
        rethrow;
      }

      if (phoneFarms.isNotEmpty) {
        _phoneOwnerFallbackAttempted = false;
        return phoneFarms;
      }

      if (ownerUserId != null &&
          !_phoneOwnerFallbackAttempted &&
          _activeVerifiedSessionKey == _lastPhoneOwnerFallbackSessionKey) {
        _phoneOwnerFallbackAttempted = true;
        return await _service.getFarms(jwt, ownerUserId: ownerUserId);
      }
      return phoneFarms;
    }

    if (ownerUserId == null) return const [];
    return _service.getFarms(jwt, ownerUserId: ownerUserId);
  }

  String? get _activeVerifiedSessionKey {
    final phone = _verifiedFarmerPhone;
    if (phone == null) return null;
    final farmerId = _verifiedFarmerId ?? '';
    final ownerUserId = _currentUserId ?? '';
    return '$phone|$farmerId|$ownerUserId';
  }

  void selectFarm(Farm farm) {
    selectedFarm.value = farm;
    final db = _localDb;
    final phone = _verifiedFarmerPhone;
    if (db != null && phone != null) {
      unawaited(db.setSelectedFarmCache(farmerPhone: phone, farmId: farm.id));
    }
  }

  bool _looksLikeFarmerLinkError(Object error) {
    if (error is! SatelliteApiException || error.statusCode != 403) {
      return false;
    }
    final message = [
      error.code,
      error.message,
      error.details,
    ].whereType<String>().join(' ').toLowerCase();
    return message.contains('not linked') ||
        message.contains('farmer_session_not_linked') ||
        message.contains('farmer_id_mismatch') ||
        message.contains('farmer_mismatch');
  }

  bool _isPermanentFarmSaveError(SatelliteApiException error) {
    final message = [
      error.code,
      error.message,
      error.details,
    ].whereType<String>().join(' ').toLowerCase();
    return error.statusCode == 401 ||
        message.contains('invalid_phone') ||
        message.contains('missing_auth_token') ||
        message.contains('invalid_auth_token') ||
        message.contains('missing_farm_name') ||
        message.contains('farm_geometry_required') ||
        message.contains('farm_area_required') ||
        message.contains('farmer_id_mismatch') ||
        message.contains('farmer_mismatch');
  }

  String _farmSaveErrorMessage(Object error) {
    if (error is! SatelliteApiException) {
      return UiStrings.t('farm_save_network_retry');
    }
    final message = [
      error.code,
      error.message,
      error.details,
    ].whereType<String>().join(' ').toLowerCase();
    if (error.statusCode == 401 ||
        message.contains('missing_auth_token') ||
        message.contains('invalid_auth_token')) {
      return UiStrings.t('farm_save_auth_required');
    }
    if (message.contains('farm_geometry_required') ||
        message.contains('farm_area_required') ||
        message.contains('boundary')) {
      return UiStrings.t('farm_save_boundary_required');
    }
    if (message.contains('farmer_id_mismatch') ||
        message.contains('farmer_mismatch')) {
      return UiStrings.t('farm_save_farmer_mismatch');
    }
    if (error.statusCode != null && error.statusCode! >= 500) {
      return UiStrings.t('farm_save_network_retry');
    }
    return UiStrings.t('could_not_save_farm');
  }

  Future<void> _repairVerifiedFarmerProfileLink({
    required String jwt,
    required String userId,
  }) async {
    if (!Get.isRegistered<MainAuthController>()) return;
    final verified = Get.find<MainAuthController>().verifiedFarmer.value;
    final phone = _verifiedFarmerPhone;
    final farmerId = verified?.farmerId.trim() ?? '';
    if (verified == null ||
        phone == null ||
        phone.isEmpty ||
        farmerId.isEmpty ||
        jwt.trim().isEmpty ||
        userId.trim().isEmpty) {
      return;
    }
    await _service.upsertFarmerPhoneProfile(
      userId: userId,
      phone: phone,
      farmerId: farmerId,
      farmerName: verified.farmerName,
      jwt: jwt,
    );
  }

  Future<Farm?> _retryVerifiedFarmerLinkedSave({
    required Map<String, dynamic> farmJson,
    required String farmerPhone,
    required String jwt,
  }) async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return await _service.insertFarmerLinkedFarm(
        farmJson: farmJson,
        farmerPhone: farmerPhone,
        farmerId: _verifiedFarmerId,
        jwt: jwt,
      );
    } on SatelliteApiException catch (error) {
      if (_isPermanentFarmSaveError(error)) rethrow;
      Get.log('Farmer linked farm save retry still unavailable: $error');
      return null;
    } catch (error) {
      Get.log('Farmer linked farm save retry failed: $error');
      return null;
    }
  }

  Future<Farm> _saveVerifiedFarmerFarm({
    required Map<String, dynamic> farmJson,
    required String farmerPhone,
    required String jwt,
    required String userId,
  }) async {
    try {
      return await _service.insertFarmerLinkedFarm(
        farmJson: farmJson,
        farmerPhone: farmerPhone,
        farmerId: _verifiedFarmerId,
        jwt: jwt,
      );
    } on SatelliteApiException catch (error) {
      var lastError = error;
      var repairedLink = false;
      if (_looksLikeFarmerLinkError(error)) {
        try {
          await _repairVerifiedFarmerProfileLink(jwt: jwt, userId: userId);
          repairedLink = true;
          return await _service.insertFarmerLinkedFarm(
            farmJson: farmJson,
            farmerPhone: farmerPhone,
            farmerId: _verifiedFarmerId,
            jwt: jwt,
          );
        } on SatelliteApiException catch (retryError) {
          lastError = retryError;
        } catch (repairError) {
          Get.log('Farmer link repair failed: $repairError');
        }
      }
      if (_isPermanentFarmSaveError(lastError)) throw lastError;
      if (!repairedLink) {
        try {
          await _repairVerifiedFarmerProfileLink(jwt: jwt, userId: userId);
        } catch (repairError) {
          Get.log(
            'Farmer link refresh before direct farm save failed: $repairError',
          );
        }
      }
      final linkedFarm = await _retryVerifiedFarmerLinkedSave(
        farmJson: farmJson,
        farmerPhone: farmerPhone,
        jwt: jwt,
      );
      if (linkedFarm != null) return linkedFarm;
      final farm = await _service.insertFarm(farmJson, jwt);
      try {
        await _repairVerifiedFarmerProfileLink(jwt: jwt, userId: userId);
      } catch (repairError) {
        Get.log(
          'Farmer link refresh after direct farm save failed: $repairError',
        );
      }
      return farm;
    } on Exception catch (error) {
      Get.log('Farmer linked farm save unavailable, using direct save: $error');
      try {
        await _repairVerifiedFarmerProfileLink(jwt: jwt, userId: userId);
      } catch (repairError) {
        Get.log(
          'Farmer link refresh before direct farm save failed: $repairError',
        );
      }
      final linkedFarm = await _retryVerifiedFarmerLinkedSave(
        farmJson: farmJson,
        farmerPhone: farmerPhone,
        jwt: jwt,
      );
      if (linkedFarm != null) return linkedFarm;
      final farm = await _service.insertFarm(farmJson, jwt);
      try {
        await _repairVerifiedFarmerProfileLink(jwt: jwt, userId: userId);
      } catch (repairError) {
        Get.log(
          'Farmer link refresh after direct farm save failed: $repairError',
        );
      }
      return farm;
    }
  }

  Future<bool> _confirmSavedFarmVisibleForVerifiedFarmer({
    required Farm savedFarm,
    required String farmerPhone,
    required String jwt,
    required String userId,
    List<Duration> delays = const [
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 700),
      Duration(milliseconds: 1400),
    ],
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final farmId = savedFarm.id.trim();
    if (farmId.isEmpty || farmerPhone.trim().isEmpty || jwt.trim().isEmpty) {
      return false;
    }
    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      try {
        await _repairVerifiedFarmerProfileLink(jwt: jwt, userId: userId);
      } catch (repairError) {
        Get.log(
          'Farmer link refresh during farm confirmation failed: $repairError',
        );
      }
      try {
        final remoteFarms = await _service.getFarmsForFarmerPhone(
          phone: farmerPhone,
          farmerId: _verifiedFarmerId,
          preferredFarmId: farmId,
          jwt: jwt,
          retryHttpErrors: false,
          timeout: timeout,
        );
        for (final farm in remoteFarms) {
          if (farm.id == farmId) {
            _replaceWithConfirmedFarmList(remoteFarms, preferredFarmId: farmId);
            return true;
          }
        }
      } catch (error) {
        Get.log('Saved farm confirmation pending: $error');
      }
    }
    return false;
  }

  Future<Farm?> saveFarmRecord({
    required String name,
    required List<LatLng> points,
    Map<String, dynamic> metadata = const {},
    bool showSnackbars = true,
  }) async {
    try {
      await _ensureSatelliteSessionFromMainAuth();
      if (points.length < 3) {
        if (showSnackbars) {
          Get.snackbar(
            UiStrings.t('too_few_points'),
            UiStrings.t('add_boundary_points_before_save'),
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        return null;
      }

      final geometry = {
        'type': 'Polygon',
        'coordinates': [PolygonGeometry.toGeoJsonRing(points)],
      };

      final bounds = PolygonGeometry.bounds(points);
      final areaHa = PolygonGeometry.areaHectares(points);
      if (areaHa <= 0) {
        if (showSnackbars) {
          Get.snackbar(
            UiStrings.t('too_few_points'),
            UiStrings.t('add_boundary_points_before_save'),
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        return null;
      }

      final userId = _currentUserId;
      final jwt = _jwt;
      if (jwt.trim().isEmpty || userId == null || userId.trim().isEmpty) {
        if (showSnackbars) {
          Get.snackbar(
            UiStrings.t('login_required'),
            UiStrings.t('farm_link_login_required'),
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        return null;
      }

      final farmJson = {
        'name': name,
        'geometry': geometry,
        'bounds': bounds,
        'area_hectares': areaHa,
        'area_acres': areaHa * 2.47105,
        'user_id': userId,
        ...metadata,
      };

      final farmerPhone = _verifiedFarmerPhone;
      Farm farm;
      if (farmerPhone == null) {
        farm = await _service.insertFarm(farmJson, jwt);
      } else {
        farm = await _saveVerifiedFarmerFarm(
          farmJson: farmJson,
          farmerPhone: farmerPhone,
          jwt: jwt,
          userId: userId,
        );
      }
      _upsertSavedFarm(farm);
      await _cacheVerifiedFarmerFarms();
      if (farmerPhone != null) {
        final confirmedFast = await _confirmSavedFarmVisibleForVerifiedFarmer(
          savedFarm: farm,
          farmerPhone: farmerPhone,
          jwt: jwt,
          userId: userId,
          delays: const [Duration.zero],
          timeout: const Duration(seconds: 1),
        );
        if (!confirmedFast) {
          unawaited(
            _confirmSavedFarmVisibleForVerifiedFarmer(
              savedFarm: farm,
              farmerPhone: farmerPhone,
              jwt: jwt,
              userId: userId,
              delays: const [
                Duration(milliseconds: 250),
                Duration(milliseconds: 700),
                Duration(milliseconds: 1400),
              ],
            ),
          );
        }
      }
      return farm;
    } catch (e) {
      Get.log('Farm save failed: $e');
      if (showSnackbars) {
        Get.snackbar(
          UiStrings.t('error'),
          _farmSaveErrorMessage(e),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
      return null;
    }
  }

  Future<bool> saveFarm({
    required String name,
    required List<LatLng> points,
    Map<String, dynamic> metadata = const {},
  }) async {
    final farm = await saveFarmRecord(
      name: name,
      points: points,
      metadata: metadata,
    );
    return farm != null;
  }
}
