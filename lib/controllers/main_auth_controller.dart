import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/verified_farmer_record.dart';
import '../services/local_app_database.dart';
import '../services/network_status_service.dart';
import '../services/secure_app_storage.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';
import 'survey_controller.dart';

enum FarmerLoginState {
  verifying,
  verified,
  linked,
  farmsSynced,
  ready,
  needsSignup,
}

class FarmerVerificationException implements Exception {
  final String message;
  final String code;

  const FarmerVerificationException(this.message, {this.code = ''});

  @override
  String toString() => code.isEmpty ? message : '$code: $message';
}

class FarmerProfileNotFoundException extends FarmerVerificationException {
  const FarmerProfileNotFoundException(
    super.message, {
    super.code = 'farmer_not_found',
  });
}

class FarmerProfileAlreadyExistsException extends FarmerVerificationException {
  const FarmerProfileAlreadyExistsException(
    super.message, {
    super.code = 'farmer_already_exists',
  });
}

class FarmerServiceException extends FarmerVerificationException {
  const FarmerServiceException(String message, String code)
    : super(message, code: code);

  @override
  String toString() => '$code: $message';
}

class MainAuthController extends GetxController {
  static const _localGuestIdKey = 'local_guest_id';
  static const _lastFarmerLoginKey = 'last_farmer_login_summary';

  final _auth = Supabase.instance.client.auth;
  final _client = Supabase.instance.client;
  final _networkStatusService = NetworkStatusService();
  final _secureStorage = SecureAppStorage();

  final isLoggedIn = false.obs;
  final hasLocalGuest = false.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final Rxn<FarmerLoginState> farmerLoginState = Rxn<FarmerLoginState>();
  final farmerLoginSyncStatusKey = ''.obs;
  final farmerLoginSyncStatusCode = ''.obs;
  final farmerLoginSyncPhone = ''.obs;
  final farmerLoginSyncedFarmCount = Rxn<int>();
  final farmerLoginLastSyncAt = Rxn<DateTime>();
  final lastFarmerLoginPhone = ''.obs;
  final lastFarmerLoginName = ''.obs;
  final lastFarmerLoginId = ''.obs;
  final lastFarmerLoginLocation = ''.obs;
  final lastFarmerLoginFarmCount = Rxn<int>();
  final lastFarmerLoginSyncAt = Rxn<DateTime>();
  final farmerLoginAnalyticsEvents = <Map<String, dynamic>>[].obs;
  final Rxn<VerifiedFarmerRecord> verifiedFarmer = Rxn<VerifiedFarmerRecord>();
  bool _farmerSessionLinkInProgress = false;

  @override
  void onInit() {
    super.onInit();
    isLoggedIn.value = _auth.currentSession != null;
    unawaited(_refreshLocalGuestState());
    unawaited(_loadLastFarmerLoginSummary());
    unawaited(_refreshVerifiedProfile());
    _auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        unawaited(_clearLocalGuest());
        if (!_farmerSessionLinkInProgress) {
          unawaited(_refreshVerifiedProfile());
        }
      }
      isLoggedIn.value =
          data.session != null ||
          hasLocalGuest.value ||
          verifiedFarmer.value != null;
    });
  }

  bool get isAuthenticated =>
      _auth.currentSession != null ||
      hasLocalGuest.value ||
      verifiedFarmer.value != null;
  bool get isAnonymous =>
      (_auth.currentUser?.isAnonymous ?? false) || hasLocalGuest.value;
  String? get userEmail => _auth.currentUser?.email;
  String? get remoteUserId => _auth.currentUser?.id;
  bool get farmerLoginHealthFarmerVerified =>
      verifiedFarmer.value != null || lastFarmerLoginPhone.value.length == 10;
  bool get farmerLoginHealthSessionLinked =>
      farmerLoginState.value == FarmerLoginState.linked ||
      farmerLoginState.value == FarmerLoginState.farmsSynced ||
      farmerLoginState.value == FarmerLoginState.ready ||
      _auth.currentSession != null;
  bool get farmerLoginHealthFarmSynced =>
      farmerLoginSyncedFarmCount.value != null ||
      lastFarmerLoginFarmCount.value != null;
  bool get farmerLoginHealthOfflineCacheReady =>
      lastFarmerLoginPhone.value.length == 10;
  int? get farmerLoginHealthFarmCount =>
      farmerLoginSyncedFarmCount.value ?? lastFarmerLoginFarmCount.value;
  DateTime? get farmerLoginHealthLastSyncAt =>
      farmerLoginLastSyncAt.value ?? lastFarmerLoginSyncAt.value;

  Future<bool> hasAnySession() async {
    await _refreshLocalGuestState();
    await _refreshVerifiedProfile();
    return _auth.currentSession != null ||
        hasLocalGuest.value ||
        verifiedFarmer.value != null;
  }

  Future<bool> ensureOfflineSessionWhenOffline() async {
    await _refreshLocalGuestState();
    await _refreshVerifiedProfile();
    if (_auth.currentSession != null ||
        hasLocalGuest.value ||
        verifiedFarmer.value != null) {
      return true;
    }
    if (await _networkStatusService.isOnline()) {
      return false;
    }
    await _startLocalGuest();
    return true;
  }

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _auth.signInWithPassword(email: email, password: password);
      await _afterSignIn('/home');
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Login failed. Check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loginVerifiedFarmer(
    String email,
    String password, {
    String nextRoute = '/farmer',
  }) async {
    isLoading.value = true;
    errorMessage.value = '';
    verifiedFarmer.value = null;
    try {
      await _clearLocalGuest();
      await _auth.signInWithPassword(email: email, password: password);
      final record =
          await _loadRemoteFarmerProfile() ??
          await _createFarmerProfileFromCurrentUser(email);
      verifiedFarmer.value = record;
      await _rememberLocalFarmerProfile(record: record);

      final session = _auth.currentSession;
      final user = _auth.currentUser;
      if (session != null && user != null) {
        await _syncSatelliteSession(session, user, email);
      }

      isLoggedIn.value = true;
      await _afterSignIn(nextRoute);
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Could not login farmer profile.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loginFpc(
    String email,
    String password, {
    String nextRoute = '/fpo',
  }) async {
    isLoading.value = true;
    errorMessage.value = '';
    verifiedFarmer.value = null;
    try {
      await _clearLocalGuest();
      await _auth.signInWithPassword(email: email, password: password);
      final role = '${_auth.currentUser?.userMetadata?['role'] ?? ''}'
          .trim()
          .toLowerCase();
      if (role.isNotEmpty &&
          !{'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'}.contains(role)) {
        await _auth.signOut();
        errorMessage.value = 'This account is not enabled for FPC login.';
        return;
      }
      isLoggedIn.value = true;
      await _afterSignIn(nextRoute, syncFarmerBeforeRoute: false);
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Could not login FPC account.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> continueAsGuest({String nextRoute = '/home'}) async {
    isLoading.value = true;
    errorMessage.value = '';
    verifiedFarmer.value = null;
    try {
      final online = await _networkStatusService.isOnline();
      if (!online) {
        await _startLocalGuest();
        await _afterSignIn(nextRoute);
        return;
      }
      try {
        await _auth.signInAnonymously();
      } catch (e) {
        if (!_networkStatusService.looksOffline(e)) rethrow;
        await _startLocalGuest();
      }
      await _afterSignIn(nextRoute);
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Could not continue as guest.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> continueAsVerifiedFarmer(
    String phone, {
    String nextRoute = '/farmer',
  }) async {
    if (isLoading.value) return;
    final digits = _normalizePhone(phone);
    if (digits.length != 10) {
      errorMessage.value = 'Enter a valid 10 digit mobile number';
      _clearFarmerLoginSyncStatus();
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    farmerLoginState.value = FarmerLoginState.verifying;
    farmerLoginSyncPhone.value = digits;
    farmerLoginSyncedFarmCount.value = null;
    farmerLoginLastSyncAt.value = null;
    farmerLoginSyncStatusCode.value = '';
    _setFarmerLoginSyncStatus('checking_farmer_number');
    _trackFarmerLoginEvent('login_started', {'phone': digits});
    _farmerSessionLinkInProgress = true;
    try {
      final online = await _networkStatusService.isOnline();
      if (!online) {
        _setFarmerLoginSyncStatus('offline_cached_session');
        _setFarmerLoginSyncStatusCode('network_issue');
        final opened = await _openCachedFarmerSessionIfAvailable(
          digits,
          nextRoute,
        );
        if (!opened) {
          errorMessage.value =
              'You are offline. Last saved farm data will open when available.';
          farmerLoginState.value = null;
          _trackFarmerLoginEvent('farm_sync_failed', {
            'phone': digits,
            'reason': 'offline_no_cached_session',
          });
        }
        return;
      }
      await _clearLocalGuest();
      await _clearFarmerRemoteSession();
      final record = await _signInAndSyncRemoteFarmer(digits);
      verifiedFarmer.value = record;
      await _rememberLocalFarmerProfile(record: record);
      isLoggedIn.value = true;
      _setFarmerLoginSyncStatus('syncing_farm_records');
      final farmCount = await _syncFarmerFarmDataForLogin();
      farmerLoginSyncedFarmCount.value = farmCount;
      final syncedAt = DateTime.now().toUtc();
      farmerLoginLastSyncAt.value = syncedAt;
      await _rememberFarmerLogin(
        record: record,
        farmCount: farmCount,
        syncedAt: syncedAt,
      );
      _setFarmerLoginSyncStatus(
        farmCount > 0 ? 'farm_records_synced' : 'no_farm_records_found',
        code: farmCount > 0 ? 'farms_synced' : 'farms_not_found',
      );
      _trackFarmerLoginEvent('farm_sync_success', {
        'phone': digits,
        'farmCount': farmCount,
      });
      farmerLoginState.value = FarmerLoginState.farmsSynced;
      _setFarmerLoginSyncStatus('opening_farmer_dashboard');
      farmerLoginState.value = FarmerLoginState.ready;
      _trackFarmerLoginEvent('dashboard_opened', {'phone': digits});
      await _afterSignIn(nextRoute, syncFarmerBeforeRoute: false);
    } on FarmerProfileNotFoundException {
      await _clearFarmerRemoteSession();
      _clearFarmerLoginSyncStatus();
      farmerLoginAnalyticsEvents.clear();
      errorMessage.value = '';
      farmerLoginState.value = FarmerLoginState.needsSignup;
      Get.offNamed('/farmer/signup', arguments: {'phone': digits});
    } on FarmerProfileAlreadyExistsException catch (e) {
      await _clearFarmerRemoteSession();
      farmerLoginState.value = FarmerLoginState.ready;
      _setFarmerLoginSyncStatusCode(e.code);
      errorMessage.value = _farmerLoginErrorMessage(e);
      _setFarmerLoginSyncStatus('farmer_profile_sync_retry');
      _trackFarmerLoginEvent('farm_sync_failed', {
        'phone': digits,
        'reason': e.code,
      });
    } on FarmerVerificationException catch (e) {
      await _clearFarmerRemoteSession();
      _setFarmerLoginSyncStatusCode(e.code);
      errorMessage.value = _farmerLoginErrorMessage(e);
      farmerLoginState.value = null;
      _setFarmerLoginSyncStatus('farmer_session_sync_failed');
      _trackFarmerLoginEvent('farm_sync_failed', {
        'phone': digits,
        'reason': e.code,
      });
    } catch (e) {
      await _clearFarmerRemoteSession();
      if (_networkStatusService.looksOffline(e)) {
        _setFarmerLoginSyncStatusCode('network_issue');
        errorMessage.value = 'Network issue. Check internet and try again.';
        farmerLoginState.value = null;
      } else if (_looksLikeFarmerSignupRequired(e)) {
        _setFarmerLoginSyncStatusCode('farmer_not_found');
        errorMessage.value =
            'Create a new farmer account. Tap Sign up to continue.';
        farmerLoginState.value = FarmerLoginState.needsSignup;
      } else {
        _setFarmerLoginSyncStatusCode('server_sync_failed');
        errorMessage.value = 'Server sync failed. Try again in a moment.';
        farmerLoginState.value = null;
      }
      _setFarmerLoginSyncStatus('farmer_session_sync_failed');
      _trackFarmerLoginEvent('farm_sync_failed', {
        'phone': digits,
        'reason': farmerLoginSyncStatusCode.value,
      });
    } finally {
      _farmerSessionLinkInProgress = false;
      isLoading.value = false;
    }
  }

  Future<void> registerFarmerProfile({
    required String phone,
    required String farmerName,
    required String defaultLocation,
    String nextRoute = '/farmer',
  }) async {
    final digits = _normalizePhone(phone);
    final name = farmerName.trim();
    final location = defaultLocation.trim();
    if (digits.length != 10) {
      errorMessage.value = 'Enter a valid 10 digit mobile number';
      return;
    }
    if (name.isEmpty) {
      errorMessage.value = 'Enter farmer name';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    farmerLoginState.value = FarmerLoginState.verifying;
    farmerLoginSyncPhone.value = digits;
    farmerLoginSyncedFarmCount.value = null;
    farmerLoginLastSyncAt.value = null;
    farmerLoginSyncStatusCode.value = '';
    _setFarmerLoginSyncStatus('creating_farmer_profile');
    _trackFarmerLoginEvent('signup_started', {'phone': digits});
    _farmerSessionLinkInProgress = true;
    try {
      await _clearLocalGuest();
      await _clearFarmerRemoteSession();
      await _auth.signInAnonymously(
        data: {
          'role': 'farmer',
          'phone': digits,
          'farmer_name': name,
          'default_location': location,
        },
      );

      final session = _auth.currentSession;
      final user = _auth.currentUser;
      if (session == null || user == null) {
        throw StateError('No Supabase farmer session.');
      }

      final record = await _registerRemoteFarmerPhone(
        phone: digits,
        farmerName: name,
        defaultLocation: location.isEmpty ? 'Kalsubai Farms' : location,
      );

      verifiedFarmer.value = record;
      farmerLoginState.value = FarmerLoginState.verified;
      await _rememberLocalFarmerProfile(record: record);
      _setFarmerLoginSyncStatus('syncing_farmer_session');
      await _syncSatelliteSession(
        session,
        user,
        user.email ?? 'farmer-$digits@anonymous.local',
      );
      _setFarmerLoginSyncStatus('syncing_farm_records');
      final farmCount = await _syncFarmerFarmDataForLogin();
      farmerLoginSyncedFarmCount.value = farmCount;
      final syncedAt = DateTime.now().toUtc();
      farmerLoginLastSyncAt.value = syncedAt;
      await _rememberFarmerLogin(
        record: record,
        farmCount: farmCount,
        syncedAt: syncedAt,
      );
      _setFarmerLoginSyncStatus(
        farmCount > 0 ? 'farm_records_synced' : 'no_farm_records_found',
        code: farmCount > 0 ? 'farms_synced' : 'farms_not_found',
      );
      _trackFarmerLoginEvent('farm_sync_success', {
        'phone': digits,
        'farmCount': farmCount,
        'mode': 'signup',
      });
      farmerLoginState.value = FarmerLoginState.farmsSynced;
      isLoggedIn.value = true;
      _setFarmerLoginSyncStatus('opening_farmer_dashboard');
      farmerLoginState.value = FarmerLoginState.ready;
      _trackFarmerLoginEvent('dashboard_opened', {
        'phone': digits,
        'mode': 'signup',
      });
      await _afterSignIn(
        nextRoute,
        arguments: {'showFirstFarmGuide': true, 'newFarmerPhone': digits},
        syncFarmerBeforeRoute: false,
      );
    } on AuthException catch (e) {
      await _clearFarmerRemoteSession();
      errorMessage.value = e.message;
    } on FarmerProfileAlreadyExistsException catch (e) {
      await _clearFarmerRemoteSession();
      _setFarmerLoginSyncStatusCode(e.code);
      errorMessage.value = e.message;
      await Future<void>.delayed(const Duration(milliseconds: 900));
      Get.offNamed(
        '/farmer/login',
        arguments: {'phone': digits, 'message': e.message},
      );
    } on FarmerVerificationException catch (e) {
      await _clearFarmerRemoteSession();
      _setFarmerLoginSyncStatusCode(e.code);
      errorMessage.value = _farmerLoginErrorMessage(e);
      farmerLoginState.value = null;
      _setFarmerLoginSyncStatus('farmer_session_sync_failed');
    } catch (_) {
      await _clearFarmerRemoteSession();
      errorMessage.value = 'Could not create farmer profile.';
      farmerLoginState.value = null;
      _setFarmerLoginSyncStatus('farmer_session_sync_failed');
    } finally {
      _farmerSessionLinkInProgress = false;
      isLoading.value = false;
    }
  }

  Future<void> syncFarmerData({bool forceRefresh = false}) async {
    isLoading.value = true;
    try {
      await _refreshVerifiedProfile();

      final user = _auth.currentUser;
      final role = '${user?.userMetadata?['role'] ?? ''}'.trim().toLowerCase();
      final isFarmerSession =
          verifiedFarmer.value != null ||
          role == 'farmer' ||
          role == 'verified_farmer';
      if (isFarmerSession) {
        await _syncCurrentSupabaseSessionForSatellite();
        final farmCtrl = Get.isRegistered<FarmController>()
            ? Get.find<FarmController>()
            : Get.put(FarmController());
        await farmCtrl.loadFarms(forceRefresh: forceRefresh);
        farmerLoginSyncedFarmCount.value = farmCtrl.farms.length;
        final syncedAt = DateTime.now().toUtc();
        farmerLoginLastSyncAt.value = syncedAt;
        if (verifiedFarmer.value != null) {
          await _rememberFarmerLogin(
            record: verifiedFarmer.value!,
            farmCount: farmCtrl.farms.length,
            syncedAt: syncedAt,
          );
        }
        farmerLoginSyncStatusCode.value = farmCtrl.farms.isEmpty
            ? 'farms_not_found'
            : 'farms_synced';
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _afterSignIn(
    String nextRoute, {
    dynamic arguments,
    bool syncFarmerBeforeRoute = true,
  }) async {
    if (nextRoute == '/home' && Get.isRegistered<SurveyController>()) {
      await Get.find<SurveyController>().loadSurveys();
    }
    if (nextRoute == '/farmer' && syncFarmerBeforeRoute) {
      await syncFarmerData(forceRefresh: true);
    }
    Get.offAllNamed(nextRoute, arguments: arguments);
  }

  Future<void> logout() async {
    await _auth.signOut();
    verifiedFarmer.value = null;
    _clearFarmerLoginSyncStatus();
    await _clearLocalGuest();
    if (Get.isRegistered<AuthController>()) {
      await Get.find<AuthController>().clearSession();
    }
    Get.offAllNamed('/login');
  }

  Future<bool> ensureRemoteGuestSession() async {
    if (_auth.currentUser != null) return true;
    await _refreshLocalGuestState();
    if (!hasLocalGuest.value || !await _networkStatusService.isOnline()) {
      return false;
    }
    try {
      await _auth.signInAnonymously();
      await _clearLocalGuest();
      return true;
    } catch (e) {
      errorMessage.value = _networkStatusService.looksOffline(e)
          ? 'Still offline. Surveys will sync when internet returns.'
          : 'Could not prepare guest sync.';
      return false;
    }
  }

  Future<void> _startLocalGuest() async {
    final current = await _secureStorage.readString(_localGuestIdKey);
    if (current == null || current.isEmpty) {
      await _secureStorage.writeString(
        _localGuestIdKey,
        'local-guest-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
    }
    hasLocalGuest.value = true;
    isLoggedIn.value = true;
  }

  Future<void> _refreshLocalGuestState() async {
    final value = await _secureStorage.readString(_localGuestIdKey);
    hasLocalGuest.value = value != null && value.isNotEmpty;
    isLoggedIn.value =
        _auth.currentSession != null ||
        hasLocalGuest.value ||
        verifiedFarmer.value != null;
  }

  Future<void> _refreshVerifiedProfile() async {
    if (_auth.currentUser == null) {
      verifiedFarmer.value = null;
      isLoggedIn.value =
          _auth.currentSession != null ||
          hasLocalGuest.value ||
          verifiedFarmer.value != null;
      return;
    }

    VerifiedFarmerRecord? record;
    try {
      record = await _loadRemoteFarmerProfile();
    } catch (e) {
      if (_networkStatusService.looksOffline(e)) {
        isLoggedIn.value =
            _auth.currentSession != null ||
            hasLocalGuest.value ||
            verifiedFarmer.value != null;
        return;
      }
      rethrow;
    }
    if (record == null) {
      verifiedFarmer.value = null;
      isLoggedIn.value = _auth.currentSession != null || hasLocalGuest.value;
      return;
    }
    verifiedFarmer.value = record;
    await _rememberLocalFarmerProfile(record: record);

    isLoggedIn.value =
        _auth.currentSession != null ||
        hasLocalGuest.value ||
        verifiedFarmer.value != null;
  }

  Future<void> _clearLocalGuest() async {
    await _secureStorage.remove(_localGuestIdKey);
    hasLocalGuest.value = false;
    isLoggedIn.value =
        _auth.currentSession != null || verifiedFarmer.value != null;
  }

  Future<void> _clearFarmerRemoteSession() async {
    if (_auth.currentSession != null) {
      await _auth.signOut();
    }
    verifiedFarmer.value = null;
    if (Get.isRegistered<AuthController>()) {
      await Get.find<AuthController>().clearSession();
    }
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }

  LocalAppDatabase? get _localDb => LocalAppDatabase.maybeInstance;

  Future<void> _rememberLocalFarmerProfile({
    required VerifiedFarmerRecord record,
    DateTime? syncedAt,
  }) async {
    final db = _localDb;
    if (db == null) return;
    final now = syncedAt ?? DateTime.now().toUtc();
    final phone = _normalizePhone(record.phone);
    if (phone.length != 10) return;
    try {
      await db.upsertFarmerProfileCache(
        record: LocalFarmerProfileRecord(
          phone: phone,
          farmerId: record.farmerId,
          farmerName: record.farmerName,
          userId: _auth.currentUser?.id ?? '',
          defaultLocation: record.defaultLocation,
          preferredLanguage: 'en',
          profileComplete: true,
          lastVerifiedAt: now.toIso8601String(),
          syncedAt: now.toIso8601String(),
        ),
      );
    } catch (error) {
      Get.log('Local farmer profile cache write failed: $error');
    }
  }

  void _setFarmerLoginSyncStatus(String key, {String? code}) {
    farmerLoginSyncStatusKey.value = key;
    if (code != null) {
      final trimmed = code.trim();
      if (trimmed.isNotEmpty) {
        farmerLoginSyncStatusCode.value = trimmed;
      }
    }
  }

  void _setFarmerLoginSyncStatusCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isNotEmpty) {
      farmerLoginSyncStatusCode.value = trimmed;
    }
  }

  void _clearFarmerLoginSyncStatus() {
    farmerLoginSyncStatusKey.value = '';
    farmerLoginSyncStatusCode.value = '';
    farmerLoginState.value = null;
    farmerLoginSyncPhone.value = '';
    farmerLoginSyncedFarmCount.value = null;
    farmerLoginLastSyncAt.value = null;
  }

  Future<void> _loadLastFarmerLoginSummary() async {
    try {
      final data = await _secureStorage.readJsonMap(_lastFarmerLoginKey);
      if (data == null) return;
      lastFarmerLoginPhone.value = _normalizePhone('${data['phone'] ?? ''}');
      lastFarmerLoginName.value = '${data['farmerName'] ?? ''}'.trim();
      lastFarmerLoginId.value = '${data['farmerId'] ?? ''}'.trim();
      lastFarmerLoginLocation.value = '${data['defaultLocation'] ?? ''}'.trim();
      final farmCount = data['farmCount'];
      lastFarmerLoginFarmCount.value = farmCount is num
          ? farmCount.toInt()
          : int.tryParse('$farmCount');
      lastFarmerLoginSyncAt.value = DateTime.tryParse(
        '${data['syncedAt'] ?? ''}',
      );
    } catch (_) {
      // Ignore corrupt local login summary. It will be replaced on next login.
    }
  }

  Future<void> _rememberFarmerLogin({
    required VerifiedFarmerRecord record,
    required int farmCount,
    required DateTime syncedAt,
  }) async {
    final phone = _normalizePhone(record.phone);
    lastFarmerLoginPhone.value = phone;
    lastFarmerLoginName.value = record.farmerName;
    lastFarmerLoginId.value = record.farmerId;
    lastFarmerLoginLocation.value = record.defaultLocation;
    lastFarmerLoginFarmCount.value = farmCount;
    lastFarmerLoginSyncAt.value = syncedAt;
    await _rememberLocalFarmerProfile(record: record, syncedAt: syncedAt);
    await _secureStorage.writeJson(_lastFarmerLoginKey, {
      'phone': phone,
      'farmerName': record.farmerName,
      'farmerId': record.farmerId,
      'defaultLocation': record.defaultLocation,
      'farmCount': farmCount,
      'syncedAt': syncedAt.toIso8601String(),
    });
  }

  Future<VerifiedFarmerRecord?> _cachedFarmerRecordForPhone(
    String phone,
  ) async {
    final digits = _normalizePhone(phone);
    final db = _localDb;
    if (db != null && digits.length == 10) {
      try {
        final cached = await db.readFarmerProfileByPhone(digits);
        if (cached != null) {
          lastFarmerLoginPhone.value = cached.phone;
          lastFarmerLoginName.value = cached.farmerName;
          lastFarmerLoginId.value = cached.farmerId;
          lastFarmerLoginLocation.value = cached.defaultLocation;
          lastFarmerLoginSyncAt.value = DateTime.tryParse(cached.syncedAt);
          return VerifiedFarmerRecord(
            phone: cached.phone,
            farmerId: cached.farmerId,
            farmerName: cached.farmerName,
            defaultLocation: cached.defaultLocation,
            lots: const [],
          );
        }
      } catch (error) {
        Get.log('Local farmer profile cache read failed: $error');
      }
    }

    await _loadLastFarmerLoginSummary();
    if (digits.length != 10 || lastFarmerLoginPhone.value != digits) {
      return null;
    }
    final name = lastFarmerLoginName.value.trim();
    final farmerId = lastFarmerLoginId.value.trim();
    return VerifiedFarmerRecord(
      phone: digits,
      farmerId: farmerId.isEmpty ? 'FMR-$digits' : farmerId,
      farmerName: name.isEmpty ? 'Farmer' : name,
      defaultLocation: lastFarmerLoginLocation.value.trim().isEmpty
          ? 'Remote farm profile'
          : lastFarmerLoginLocation.value.trim(),
      lots: const [],
    );
  }

  Future<bool> _openCachedFarmerSessionIfAvailable(
    String phone,
    String nextRoute,
  ) async {
    final record = await _cachedFarmerRecordForPhone(phone);
    if (record == null) return false;

    verifiedFarmer.value = record;
    isLoggedIn.value = true;
    farmerLoginState.value = FarmerLoginState.ready;
    farmerLoginSyncedFarmCount.value = lastFarmerLoginFarmCount.value;
    farmerLoginLastSyncAt.value = lastFarmerLoginSyncAt.value;

    final farmCtrl = Get.isRegistered<FarmController>()
        ? Get.find<FarmController>()
        : Get.put(FarmController());
    await farmCtrl.loadFarms(forceRefresh: false);
    if (farmCtrl.farms.isNotEmpty) {
      farmerLoginSyncedFarmCount.value = farmCtrl.farms.length;
    } else {
      verifiedFarmer.value = null;
      isLoggedIn.value = _auth.currentSession != null || hasLocalGuest.value;
      farmerLoginState.value = null;
      farmerLoginSyncedFarmCount.value = null;
      return false;
    }

    _trackFarmerLoginEvent('dashboard_opened', {
      'phone': phone,
      'mode': 'offline_cached',
    });
    await _afterSignIn(nextRoute, syncFarmerBeforeRoute: false);
    return true;
  }

  void _trackFarmerLoginEvent(String event, Map<String, Object?> details) {
    final entry = <String, dynamic>{
      'event': event,
      'at': DateTime.now().toUtc().toIso8601String(),
      ...details,
    };
    farmerLoginAnalyticsEvents.insert(0, entry);
    if (farmerLoginAnalyticsEvents.length > 40) {
      farmerLoginAnalyticsEvents.removeRange(
        40,
        farmerLoginAnalyticsEvents.length,
      );
    }
    Get.log('[farmer_login] ${jsonEncode(entry)}');
  }

  Future<VerifiedFarmerRecord> _signInAndSyncRemoteFarmer(String phone) async {
    _setFarmerLoginSyncStatus('checking_farmer_number');
    final verifiedRecord = await _verifyFarmerPhone(phone);
    verifiedFarmer.value = verifiedRecord;
    _setFarmerLoginSyncStatus('farmer_profile_found');
    _trackFarmerLoginEvent('farmer_found', {
      'phone': phone,
      'farmerId': verifiedRecord.farmerId,
    });
    farmerLoginState.value = FarmerLoginState.verified;

    if (_auth.currentSession == null) {
      _setFarmerLoginSyncStatus('starting_farmer_session');
      await _auth.signInAnonymously(
        data: {
          'role': 'farmer',
          'phone': phone,
          'farmer_id': verifiedRecord.farmerId,
          'farmer_name': verifiedRecord.farmerName,
        },
      );
    }

    final session = _auth.currentSession;
    final user = _auth.currentUser;
    if (session == null || user == null) {
      throw StateError('No Supabase farmer session.');
    }

    _setFarmerLoginSyncStatus('linking_farmer_profile');
    await _linkRemoteFarmerPhone(phone: phone, record: verifiedRecord);
    farmerLoginState.value = FarmerLoginState.linked;
    _setFarmerLoginSyncStatusCode('farmer_linked');

    _setFarmerLoginSyncStatus('syncing_farmer_session');
    await _syncSatelliteSession(
      session,
      user,
      user.email ?? 'farmer-$phone@anonymous.local',
    );

    return verifiedRecord;
  }

  Future<void> _linkRemoteFarmerPhone({
    required String phone,
    required VerifiedFarmerRecord record,
  }) async {
    Object? edgeError;
    String? edgeCode;
    try {
      final response = await _client.functions.invoke(
        'link-farmer-phone',
        headers: _functionAuthHeaders(),
        body: {
          'phone': phone,
          'farmerId': record.farmerId,
          'farmerName': record.farmerName,
          'defaultLocation': record.defaultLocation,
        },
      );
      final data = _responseMap(response.data);
      final code = _readResponseCode(data);
      if (code != null) {
        _setFarmerLoginSyncStatusCode(code);
      }
      if (data['success'] == false) {
        final message = '${data['error'] ?? 'Could not link farmer profile.'}';
        final linkCode = code ?? 'farmer_link_failed';
        if (_isHardLinkCode(linkCode) || _isProfileBindingErrorCode(linkCode)) {
          throw FarmerVerificationException(message, code: linkCode);
        }
        throw FarmerVerificationException(message, code: linkCode);
      }
      return;
    } catch (e) {
      edgeError = e;
      final parsed = _remoteFunctionErrorMessageWithCode(edgeError);
      edgeCode = parsed.code;
      if (edgeCode != null) {
        _setFarmerLoginSyncStatusCode(edgeCode);
      }
      if (edgeCode == null ||
          edgeCode == 'farmer_link_failed' ||
          edgeCode == 'farmer_service_error' ||
          edgeCode == 'farmer_session_not_linked') {
        // Allow one-time direct fallback only for transport/unknown failures.
      } else {
        if (e is FarmerVerificationException) {
          rethrow;
        }
        throw FarmerVerificationException(
          'Could not link farmer profile to this session. ${_remoteFunctionErrorMessage(e)}',
          code: edgeCode,
        );
      }
    }

    try {
      await _linkRemoteFarmerPhoneDirect(phone: phone, record: record);
    } catch (directError) {
      final edgeMessage = _remoteFunctionErrorMessage(edgeError);
      final directMessage = _remoteFunctionErrorMessage(directError);
      throw FarmerVerificationException(
        'Could not link farmer profile to this session. $edgeMessage $directMessage',
        code: _responseMapFromError(directError)['code'] is String
            ? '${_responseMapFromError(directError)['code']}'
            : (edgeCode ?? 'farmer_link_failed'),
      );
    }
  }

  Map<String, String>? _functionAuthHeaders() {
    final token = _auth.currentSession?.accessToken;
    return token == null || token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
  }

  Future<void> _linkRemoteFarmerPhoneDirect({
    required String phone,
    required VerifiedFarmerRecord record,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const FarmerVerificationException('No Supabase farmer session.');
    }

    await _client.from('farmer_phone_profiles').upsert({
      'user_id': user.id,
      'phone': phone,
      'farmer_id': record.farmerId,
      'farmer_name': record.farmerName,
      'default_location': record.defaultLocation,
      'auth_method': 'anonymous_link',
      'status': 'active',
      'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'phone_login',
    }, onConflict: 'user_id');
  }

  String _remoteFunctionErrorMessage(Object? error) {
    if (error == null) return '';
    final raw = error.toString();
    if (raw.trim().isEmpty) return '';
    final decoded = RegExp(r'\{.*\}').firstMatch(raw)?.group(0);
    if (decoded != null) {
      try {
        final data = jsonDecode(decoded);
        if (data is Map) {
          final message = data['error'] ?? data['message'] ?? data['details'];
          if (message != null && '$message'.trim().isNotEmpty) {
            return '$message';
          }
        }
      } catch (_) {
        // Fall through to the plain exception text.
      }
    }
    return raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('FarmerVerificationException: ', '')
        .trim();
  }

  ({String message, String? code}) _remoteFunctionErrorMessageWithCode(
    Object? error,
  ) {
    if (error == null) {
      return (message: '', code: null);
    }
    if (error is FarmerVerificationException) {
      return (
        message: error.message,
        code: error.code.isEmpty ? null : error.code,
      );
    }
    final parsed = _responseMapFromError(error);
    final messageCode = parsed['code'];
    final mappedCode = messageCode is String && messageCode.isNotEmpty
        ? messageCode
        : null;
    return (message: _remoteFunctionErrorMessage(error), code: mappedCode);
  }

  Map<String, dynamic> _responseMapFromError(Object? error) {
    if (error == null) return const <String, dynamic>{};
    final raw = error.toString();
    final match = RegExp(r'\{.*\}').firstMatch(raw)?.group(0);
    if (match == null) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(match);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const <String, dynamic>{};
  }

  bool _isProfileBindingErrorCode(String code) {
    return code == 'farmer_not_found' ||
        code == 'farmer_session_not_linked' ||
        code == 'farmer_profile_inactive' ||
        code == 'farmer_id_mismatch' ||
        code == 'farmer_mismatch';
  }

  bool _isHardLinkCode(String code) {
    return code == 'invalid_phone' ||
        code == 'missing_farmer_id' ||
        code == 'missing_auth_token' ||
        code == 'invalid_auth_token' ||
        code == 'method_not_allowed';
  }

  String _farmerLoginErrorMessage(FarmerVerificationException e) {
    if (_looksLikeFarmerSignupRequired(e)) {
      return 'Create a new farmer account. Tap Sign up to continue.';
    }
    switch (e.code) {
      case 'farmer_not_found':
        return 'Create a new farmer account. Tap Sign up to continue.';
      case 'network_issue':
        return 'Network issue. Check internet and try again.';
      case 'farm_sync_failed':
      case 'farms_not_found':
        return 'Farm data missing. Refresh farm sync or contact support.';
      case 'server_sync_failed':
      case 'farmer_verification_failed':
      case 'farmer_registration_failed':
        return 'Server sync failed. Try again in a moment.';
      case 'missing_auth_token':
      case 'invalid_auth_token':
      case 'session_expired':
        return 'Session expired. Login again.';
    }
    if (e.message.isNotEmpty) {
      return e.message;
    }
    return 'Unable to complete farmer verification. Try again.';
  }

  bool _looksLikeFarmerSignupRequired(Object? value) {
    if (value == null) return false;
    if (value is FarmerVerificationException) {
      return _looksLikeFarmerSignupRequired(value.code) ||
          _looksLikeFarmerSignupRequired(value.message);
    }
    if (value is Map) {
      return _looksLikeFarmerSignupRequired(value['code']) ||
          _looksLikeFarmerSignupRequired(value['error']) ||
          _looksLikeFarmerSignupRequired(value['message']) ||
          _looksLikeFarmerSignupRequired(value['details']);
    }
    final normalized = value.toString().trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('farmer_not_found') ||
        normalized.contains('no farmer profile found') ||
        normalized.contains('no approved farmer profile') ||
        normalized.contains('create a new farmer account') ||
        normalized.contains('tap sign up') ||
        normalized.contains('redirecting to sign up') ||
        normalized.contains('not verified') ||
        normalized.contains('not approved');
  }

  Map<String, dynamic> _responseMapFromThrowable(Object throwable) {
    if (throwable is FarmerVerificationException) {
      final raw = _responseMapFromError(throwable);
      if (raw.isNotEmpty) return raw;
      if (throwable.code.isNotEmpty) {
        return {'code': throwable.code};
      }
    }
    final parsed = _remoteFunctionErrorMessageWithCode(throwable);
    return {'code': parsed.code, 'error': parsed.message};
  }

  Future<int> _syncFarmerFarmDataForLogin() async {
    await _syncCurrentSupabaseSessionForSatellite();
    final farmCtrl = Get.isRegistered<FarmController>()
        ? Get.find<FarmController>()
        : Get.put(FarmController());
    farmCtrl.invalidateFarmCache();
    await farmCtrl.loadFarms(forceRefresh: true);
    if (farmCtrl.farms.isEmpty) {
      for (final delay in const [
        Duration(milliseconds: 180),
        Duration(milliseconds: 650),
        Duration(milliseconds: 1300),
      ]) {
        _setFarmerLoginSyncStatus('repairing_empty_farm_cache');
        await Future<void>.delayed(delay);
        await farmCtrl.repairEmptyFarmCache();
        final shouldRetryError =
            farmCtrl.hasError.value &&
            _networkStatusService.looksOffline(farmCtrl.errorMessage.value);
        if (farmCtrl.farms.isNotEmpty ||
            (farmCtrl.hasError.value && !shouldRetryError)) {
          break;
        }
      }
    }
    if (farmCtrl.hasError.value && farmCtrl.farms.isEmpty) {
      throw FarmerVerificationException(
        farmCtrl.errorMessage.value.isEmpty
            ? 'Farm data sync failed.'
            : farmCtrl.errorMessage.value,
        code: _networkStatusService.looksOffline(farmCtrl.errorMessage.value)
            ? 'network_issue'
            : 'farm_sync_failed',
      );
    }
    farmerLoginSyncStatusCode.value = farmCtrl.farms.isEmpty
        ? 'farms_not_found'
        : 'farms_synced';
    return farmCtrl.farms.length;
  }

  Future<void> _syncCurrentSupabaseSessionForSatellite() async {
    final session = _auth.currentSession;
    final user = _auth.currentUser;
    if (session == null || user == null) return;
    final farmerPhone = verifiedFarmer.value?.phone.replaceAll(
      RegExp(r'\D'),
      '',
    );
    final email =
        user.email ??
        (farmerPhone == null || farmerPhone.isEmpty
            ? 'farmer-${user.id}@anonymous.local'
            : 'farmer-$farmerPhone@anonymous.local');
    await _syncSatelliteSession(session, user, email);
  }

  Future<VerifiedFarmerRecord> _registerRemoteFarmerPhone({
    required String phone,
    required String farmerName,
    required String defaultLocation,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'register-farmer-phone',
        headers: _functionAuthHeaders(),
        body: {
          'phone': phone,
          'farmerName': farmerName,
          'defaultLocation': defaultLocation,
        },
      );
      final data = _responseMap(response.data);
      final code = _readResponseCode(data);
      if (code != null) {
        _setFarmerLoginSyncStatusCode(code);
      }
      if (data['success'] == false) {
        final message = '${data['error'] ?? 'Could not register farmer.'}';
        if (code == 'farmer_already_exists') {
          throw FarmerProfileAlreadyExistsException(
            message,
            code: code ?? 'farmer_already_exists',
          );
        }
        if (code == 'farmer_profile_inactive' || code == 'invalid_phone') {
          throw FarmerVerificationException(
            message,
            code: code ?? 'farmer_profile_inactive',
          );
        }
        throw FarmerVerificationException(
          message,
          code: code ?? 'farmer_registration_failed',
        );
      }
      final farmer = data['farmer'];
      if (farmer is! Map) {
        throw const FarmerVerificationException(
          'Could not confirm farmer profile after signup.',
          code: 'farmer_record_missing',
        );
      }
      return VerifiedFarmerRecord.fromJson(Map<String, dynamic>.from(farmer));
    } on FarmerVerificationException {
      rethrow;
    } catch (e) {
      final parsed = _responseMapFromThrowable(e);
      final parsedCode = parsed['code'] is String
          ? parsed['code'] as String
          : '';
      if (_networkStatusService.looksOffline(e)) {
        throw const FarmerVerificationException(
          'Network issue. Check internet and try again.',
          code: 'network_issue',
        );
      }
      if (parsedCode == 'farmer_already_exists') {
        throw const FarmerProfileAlreadyExistsException(
          'This mobile number already has a farmer profile. Please login instead.',
          code: 'farmer_already_exists',
        );
      }
      throw FarmerVerificationException(
        'Could not register farmer in remote database. Check connection and try again.',
        code: parsedCode.isEmpty ? 'farmer_registration_failed' : parsedCode,
      );
    }
  }

  Future<VerifiedFarmerRecord> _verifyFarmerPhone(String phone) async {
    try {
      final response = await _client.functions.invoke(
        'verify-farmer-phone',
        body: {'phone': phone},
      );
      final data = _responseMap(response.data);
      final code = _readResponseCode(data);
      if (code != null) {
        _setFarmerLoginSyncStatusCode(code);
      }
      if (data['success'] == false) {
        final message =
            '${data['error'] ?? 'Could not verify farmer profile.'}';
        if (code == 'farmer_not_found') {
          throw FarmerProfileNotFoundException(
            message,
            code: code ?? 'farmer_not_found',
          );
        }
        if (code == 'farmer_profile_inactive') {
          throw FarmerVerificationException(
            message,
            code: code ?? 'farmer_profile_inactive',
          );
        }
        throw FarmerVerificationException(
          message,
          code: code ?? 'farmer_verification_failed',
        );
      }
      final farmer = data['farmer'];
      if (farmer is! Map) {
        throw const FarmerProfileNotFoundException(
          'Create a new farmer account. Tap Sign up to continue.',
          code: 'farmer_not_found',
        );
      }
      if (farmer['profileComplete'] == false) {
        throw const FarmerProfileNotFoundException(
          'Create a new farmer account. Tap Sign up to continue.',
          code: 'farmer_not_found',
        );
      }
      _setFarmerLoginSyncStatusCode(_readResponseCode(data) ?? '');
      return VerifiedFarmerRecord.fromJson(Map<String, dynamic>.from(farmer));
    } on FarmerVerificationException {
      rethrow;
    } catch (e) {
      final parsed = _responseMapFromThrowable(e);
      final parsedCode = parsed['code'] is String
          ? parsed['code'] as String
          : '';
      if (_networkStatusService.looksOffline(e)) {
        throw const FarmerVerificationException(
          'Network issue. Check internet and try again.',
          code: 'network_issue',
        );
      }
      if (_looksLikeFarmerSignupRequired(parsed) ||
          _looksLikeFarmerSignupRequired(parsedCode) ||
          _looksLikeFarmerSignupRequired(e)) {
        throw const FarmerProfileNotFoundException(
          'Create a new farmer account. Tap Sign up to continue.',
          code: 'farmer_not_found',
        );
      }
      throw FarmerVerificationException(
        'Could not verify farmer profile. Check the number or contact admin.',
        code: parsedCode.isEmpty ? 'farmer_verification_failed' : parsedCode,
      );
    }
  }

  Map<String, dynamic> _responseMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return const <String, dynamic>{};
  }

  String? _readResponseCode(Map<String, dynamic> data) {
    final raw = data['code'];
    return raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
  }

  Future<VerifiedFarmerRecord?> _loadRemoteFarmerProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    // 1. Try primary lookup by user_id
    final rows = await _client
        .from('farmer_phone_profiles')
        .select('phone, farmer_id, farmer_name, default_location')
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isNotEmpty) {
      final row = Map<String, dynamic>.from(rows.first as Map);
      return VerifiedFarmerRecord(
        phone: '${row['phone'] ?? ''}',
        farmerId: '${row['farmer_id'] ?? 'FMR-${row['phone'] ?? user.id}'}',
        farmerName: '${row['farmer_name'] ?? 'Farmer'}',
        defaultLocation: '${row['default_location'] ?? 'Remote farm profile'}',
        lots: const [],
      );
    }

    // 2. Secondary lookup by phone from metadata (for returning users in new sessions)
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final phone = _normalizePhone('${metadata['phone'] ?? ''}');
    if (phone.length == 10) {
      try {
        final record = await _verifyFarmerPhone(phone);
        // Automatically link this new session to the existing profile
        unawaited(_linkRemoteFarmerPhone(phone: phone, record: record));
        return record;
      } catch (_) {
        // Fallback to minimal record if verify fails
        return VerifiedFarmerRecord(
          phone: phone,
          farmerId: '${metadata['farmer_id'] ?? 'FMR-$phone'}',
          farmerName: '${metadata['farmer_name'] ?? 'Farmer'}',
          defaultLocation:
              '${metadata['default_location'] ?? 'Remote farm profile'}',
          lots: const [],
        );
      }
    }

    return null;
  }

  Future<VerifiedFarmerRecord> _createFarmerProfileFromCurrentUser(
    String email,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No Supabase farmer user.');

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final phone = _normalizePhone('${metadata['phone'] ?? ''}');
    final fallbackId = 'FMR-${user.id.substring(0, 8).toUpperCase()}';
    final farmerId = '${metadata['farmer_id'] ?? fallbackId}';
    final farmerName =
        '${metadata['farmer_name'] ?? metadata['name'] ?? email.split('@').first}';
    final defaultLocation =
        '${metadata['default_location'] ?? 'Remote farm profile'}';

    await _client.from('farmer_phone_profiles').upsert({
      'user_id': user.id,
      'phone': phone.isEmpty ? user.id : phone,
      'farmer_id': farmerId,
      'farmer_name': farmerName,
      'default_location': defaultLocation,
      'auth_method': 'email_password',
    }, onConflict: 'user_id');

    return VerifiedFarmerRecord(
      phone: phone,
      farmerId: farmerId,
      farmerName: farmerName,
      defaultLocation: defaultLocation,
      lots: const [],
    );
  }

  Future<void> _syncSatelliteSession(
    Session session,
    User user,
    String email,
  ) async {
    final satelliteAuth = Get.isRegistered<AuthController>()
        ? Get.find<AuthController>()
        : Get.put(AuthController());
    await satelliteAuth.setExternalSession(
      accessTokenValue: session.accessToken,
      refreshTokenValue: session.refreshToken,
      userId: user.id,
      email: email,
    );
  }
}
