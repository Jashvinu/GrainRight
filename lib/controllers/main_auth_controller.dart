import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/verified_farmer_record.dart';
import '../services/local_app_database.dart';
import '../services/network_status_service.dart';
import '../services/secure_app_storage.dart';
import 'admin_controller.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';
import 'farmer_inventory_controller.dart';
import 'stakeholder_controller.dart';
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
  const FarmerServiceException(super.message, String code) : super(code: code);

  @override
  String toString() => '$code: $message';
}

class RoleAccountSignupException implements Exception {
  final String message;
  final String code;

  const RoleAccountSignupException(this.message, {this.code = ''});

  @override
  String toString() => code.isEmpty ? message : '$code: $message';
}

class MainAuthController extends GetxController {
  static const _localGuestIdKey = 'local_guest_id';
  static const _lastFarmerLoginKey = 'last_farmer_login_summary';
  static const adminLoginEmail = String.fromEnvironment(
    'ADMIN_LOGIN_EMAIL',
    defaultValue: 'kalsubaifarms@gmail.com',
  );
  static const _fpcServerRoles = {'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'};

  final _auth = Supabase.instance.client.auth;
  final _client = Supabase.instance.client;
  final _networkStatusService = NetworkStatusService();
  final _secureStorage = SecureAppStorage();

  final isLoggedIn = false.obs;
  final hasLocalGuest = false.obs;
  final isLoading = false.obs;
  final isLoggingOut = false.obs;
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
  Future<void>? _farmerDataSyncInFlight;

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
    if (await _networkStatusService.hasNetworkInterface()) {
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
      final normalizedEmail = email.trim().toLowerCase();
      if (normalizedEmail.isEmpty || password.isEmpty) {
        errorMessage.value = 'Enter the FPC email and password.';
        return;
      }
      await _clearLocalGuest();
      if (_auth.currentSession != null) {
        await _auth.signOut();
      }
      await _auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      if (!_hasServerRole(_auth.currentUser, _fpcServerRoles)) {
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

  Future<void> signupAdmin({
    required String email,
    required String password,
    required String displayName,
    required String organizationName,
    required String phone,
    String nextRoute = '/admin',
  }) {
    return _signupRoleAccount(
      role: 'admin',
      email: email,
      password: password,
      displayName: displayName,
      organizationName: organizationName,
      phone: phone,
      allowedRoles: const {'admin'},
      nextRoute: nextRoute,
    );
  }

  Future<void> signupFpc({
    required String email,
    required String password,
    required String displayName,
    required String organizationName,
    required String phone,
    String nextRoute = '/fpo',
  }) {
    return _signupRoleAccount(
      role: 'fpc',
      email: email,
      password: password,
      displayName: displayName,
      organizationName: organizationName,
      phone: phone,
      allowedRoles: _fpcServerRoles,
      nextRoute: nextRoute,
    );
  }

  Future<void> _signupRoleAccount({
    required String role,
    required String email,
    required String password,
    required String displayName,
    required String organizationName,
    required String phone,
    required Set<String> allowedRoles,
    required String nextRoute,
  }) async {
    if (isLoading.value) return;
    final normalizedEmail = email.trim().toLowerCase();
    final name = displayName.trim();
    final organization = organizationName.trim();
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    final accountLabel = role == 'admin' ? 'admin' : 'FPC';

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      errorMessage.value = 'Enter a valid email.';
      return;
    }
    if (password.length < 6) {
      errorMessage.value = 'Password must be at least 6 characters.';
      return;
    }
    if (name.isEmpty) {
      errorMessage.value = 'Enter your name.';
      return;
    }
    if (organization.isEmpty) {
      errorMessage.value = role == 'admin'
          ? 'Enter organization name.'
          : 'Enter FPC name.';
      return;
    }
    if (phoneDigits.length < 10) {
      errorMessage.value = 'Enter a valid mobile number.';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    verifiedFarmer.value = null;
    try {
      await _clearLocalGuest();
      if (_auth.currentSession != null) {
        await _auth.signOut();
      }
      final response = await _client.functions.invoke(
        'role-account-signup',
        body: {
          'role': role,
          'email': normalizedEmail,
          'password': password,
          'displayName': name,
          'organizationName': organization,
          'phone': phoneDigits,
        },
      );
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw RoleAccountSignupException(
          '${data['error'] ?? 'Could not create $accountLabel account.'}',
          code: '${data['code'] ?? ''}'.trim(),
        );
      }
      await _auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      if (!_hasServerRole(_auth.currentUser, allowedRoles)) {
        await _auth.signOut();
        errorMessage.value =
            'Account created, but $accountLabel access was not enabled. Contact support.';
        return;
      }
      isLoggedIn.value = true;
      await _afterSignIn(nextRoute, syncFarmerBeforeRoute: false);
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } on RoleAccountSignupException catch (e) {
      errorMessage.value = _roleAccountSignupErrorMessage(e, accountLabel);
    } catch (e) {
      errorMessage.value = _roleAccountSignupErrorMessage(e, accountLabel);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loginAdmin(
    String email,
    String password, {
    String nextRoute = '/admin',
  }) async {
    isLoading.value = true;
    errorMessage.value = '';
    verifiedFarmer.value = null;
    try {
      final normalizedEmail = email.trim().toLowerCase();
      if (normalizedEmail.isEmpty || password.isEmpty) {
        errorMessage.value = 'Enter the admin email and password.';
        return;
      }
      await _clearLocalGuest();
      if (_auth.currentSession != null) {
        await _auth.signOut();
      }
      await _auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      if (!_hasServerRole(_auth.currentUser, const {'admin'})) {
        await _auth.signOut();
        errorMessage.value = 'This account is not enabled for admin login.';
        return;
      }
      isLoggedIn.value = true;
      await _afterSignIn(nextRoute, syncFarmerBeforeRoute: false);
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Could not login admin account.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> continueAsGuest({String nextRoute = '/home'}) async {
    isLoading.value = true;
    errorMessage.value = '';
    verifiedFarmer.value = null;
    try {
      if (!await _networkStatusService.hasNetworkInterface()) {
        await _startLocalGuest();
        await _afterSignIn(nextRoute);
        return;
      }
      await _auth.signInAnonymously();
      await _afterSignIn(nextRoute);
    } on AuthException catch (e) {
      if (_networkStatusService.looksOffline(e)) {
        await _startLocalGuest();
        await _afterSignIn(nextRoute);
        return;
      }
      errorMessage.value = e.message;
    } catch (e) {
      if (_networkStatusService.looksOffline(e)) {
        await _startLocalGuest();
        await _afterSignIn(nextRoute);
        return;
      }
      errorMessage.value = 'Could not continue as guest.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> _openOfflineFarmerFallback({
    required String phone,
    required String nextRoute,
    required bool requireAgriRecord,
  }) async {
    _setFarmerLoginSyncStatus('offline_cached_session');
    _setFarmerLoginSyncStatusCode('network_issue');
    final opened = await _openCachedFarmerSessionIfAvailable(
      phone,
      nextRoute,
      requireAgriRecord: requireAgriRecord,
    );
    if (!opened) {
      errorMessage.value = requireAgriRecord
          ? 'Network issue. Connect to internet so we can confirm stakeholder access.'
          : 'You are offline. Last saved farm data will open when available.';
      farmerLoginState.value = null;
      _trackFarmerLoginEvent('farm_sync_failed', {
        'phone': phone,
        'reason': 'offline_no_cached_session',
      });
    }
    return opened;
  }

  Future<void> _runVerifiedFarmerRemoteLogin({
    required String phone,
    required String nextRoute,
    required bool requireAgriRecord,
  }) async {
    await _clearLocalGuest();
    await _clearFarmerRemoteSession();
    final record = await _signInAndSyncRemoteFarmer(
      phone,
      requireAgriRecord: requireAgriRecord,
    );
    verifiedFarmer.value = record;
    await _rememberLocalFarmerProfile(record: record);
    isLoggedIn.value = true;
    farmerLoginState.value = FarmerLoginState.ready;
    farmerLoginSyncStatusKey.value = '';
    farmerLoginSyncStatusCode.value = '';
    _trackFarmerLoginEvent('dashboard_opened', {'phone': phone});
    _startBackgroundFarmerDataSync(record: record, phone: phone, mode: 'login');
    await _afterSignIn(nextRoute, syncFarmerBeforeRoute: false);
  }

  bool _shouldUseOfflineFarmerFallback(Object error) {
    if (_networkStatusService.looksOffline(error)) return true;
    return error is FarmerVerificationException &&
        error.code == 'network_issue';
  }

  Future<void> _handleVerifiedFarmerLoginFailure(
    Object error, {
    required String phone,
    required String nextRoute,
    required bool requireAgriRecord,
  }) async {
    if (_shouldUseOfflineFarmerFallback(error) &&
        await _openOfflineFarmerFallback(
          phone: phone,
          nextRoute: nextRoute,
          requireAgriRecord: requireAgriRecord,
        )) {
      return;
    }
    if (error is FarmerVerificationException) {
      throw error;
    }
    if (_networkStatusService.looksOffline(error)) {
      throw FarmerVerificationException(
        requireAgriRecord
            ? 'Network issue. Connect to internet so we can confirm stakeholder access.'
            : 'Network issue. Check internet and try again.',
        code: 'network_issue',
      );
    }
    throw error;
  }

  Future<void> continueAsVerifiedFarmer(
    String phone, {
    String nextRoute = '/farmer',
    bool requireAgriRecord = false,
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
      if (!await _networkStatusService.hasNetworkInterface()) {
        await _openOfflineFarmerFallback(
          phone: digits,
          nextRoute: nextRoute,
          requireAgriRecord: requireAgriRecord,
        );
        return;
      }
      try {
        await _runVerifiedFarmerRemoteLogin(
          phone: digits,
          nextRoute: nextRoute,
          requireAgriRecord: requireAgriRecord,
        );
      } catch (e) {
        await _handleVerifiedFarmerLoginFailure(
          e,
          phone: digits,
          nextRoute: nextRoute,
          requireAgriRecord: requireAgriRecord,
        );
      }
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

  Future<void> continueAsStakeholderFarmer(
    String phone, {
    String nextRoute = '/stakeholder',
  }) {
    return continueAsVerifiedFarmer(
      phone,
      nextRoute: nextRoute,
      requireAgriRecord: true,
    );
  }

  Future<void> registerFarmerProfile({
    required String phone,
    required String farmerName,
    required String defaultLocation,
    required String agriRecordId,
    required String aadhaarNumber,
    required String aadhaarMasked,
    required String aadhaarLast4,
    required String identityDocumentPath,
    String identitySource = 'agri_record_document',
    double? identityOcrConfidence,
    String nextRoute = '/farmer',
  }) async {
    final digits = _normalizePhone(phone);
    final name = farmerName.trim();
    final location = defaultLocation.trim();
    final recordId = agriRecordId.trim();
    final aadhaarDigits = aadhaarNumber.replaceAll(RegExp(r'\D'), '');
    final maskedAadhaar = aadhaarMasked.trim();
    final aadhaarLastDigits = aadhaarLast4.replaceAll(RegExp(r'\D'), '');
    final documentPath = identityDocumentPath.trim();
    final proofSource = identitySource.trim().isEmpty
        ? (documentPath.isEmpty ? 'manual_entry' : 'agri_record_document')
        : identitySource.trim();
    if (digits.length != 10) {
      errorMessage.value = 'Enter a valid 10 digit mobile number';
      return;
    }
    if (name.isEmpty) {
      errorMessage.value = 'Enter farmer name';
      return;
    }
    if (aadhaarDigits.length != 12 ||
        aadhaarLastDigits.length != 4 ||
        maskedAadhaar.isEmpty) {
      errorMessage.value = 'Enter a 12 digit Aadhaar number';
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
      final canReuseDocumentSession =
          _auth.currentSession != null &&
          _auth.currentUser != null &&
          documentPath.split('/').first == _auth.currentUser!.id;
      if (!canReuseDocumentSession) {
        await _clearFarmerRemoteSession();
        await _auth.signInAnonymously(
          data: {
            'role': 'farmer',
            'phone': digits,
            'farmer_name': name,
            'default_location': location,
          },
        );
      }

      final session = _auth.currentSession;
      final user = _auth.currentUser;
      if (session == null || user == null) {
        throw StateError('No Supabase farmer session.');
      }

      final record = await _registerRemoteFarmerPhone(
        phone: digits,
        farmerName: name,
        defaultLocation: location.isEmpty ? 'Kalsubai Farms' : location,
        agriRecordId: recordId,
        aadhaarNumber: aadhaarDigits,
        aadhaarMasked: maskedAadhaar,
        aadhaarLast4: aadhaarLastDigits,
        identityDocumentPath: documentPath,
        identitySource: proofSource,
        identityOcrConfidence: identityOcrConfidence,
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
      isLoggedIn.value = true;
      farmerLoginState.value = FarmerLoginState.ready;
      farmerLoginSyncStatusKey.value = '';
      farmerLoginSyncStatusCode.value = '';
      _trackFarmerLoginEvent('dashboard_opened', {
        'phone': digits,
        'mode': 'signup',
      });
      _startBackgroundFarmerDataSync(
        record: record,
        phone: digits,
        mode: 'signup',
        retryEmptyFarmCache: false,
      );
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

  Future<void> syncFarmerData({
    bool forceRefresh = false,
    bool showLoading = true,
  }) async {
    final inFlight = _farmerDataSyncInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final sync = _syncFarmerDataOnce(
      forceRefresh: forceRefresh,
      showLoading: showLoading,
    );
    _farmerDataSyncInFlight = sync;
    try {
      await sync;
    } finally {
      if (identical(_farmerDataSyncInFlight, sync)) {
        _farmerDataSyncInFlight = null;
      }
    }
  }

  Future<void> _syncFarmerDataOnce({
    required bool forceRefresh,
    required bool showLoading,
  }) async {
    if (showLoading) {
      isLoading.value = true;
    }
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
        if (farmCtrl.lastLoadUsedCachedFallback && farmCtrl.farms.isNotEmpty) {
          _setFarmerLoginSyncStatus('offline_cached_session');
          farmerLoginSyncStatusCode.value = 'network_issue';
        } else {
          farmerLoginSyncStatusCode.value = farmCtrl.farms.isEmpty
              ? 'farms_not_found'
              : 'farms_synced';
        }
        unawaited(_syncFarmerInventoryForLogin());
      }
    } finally {
      if (showLoading) {
        isLoading.value = false;
      }
    }
  }

  bool _hasServerRole(User? user, Set<String> allowedRoles) {
    if (user == null) return false;
    final role = '${user.appMetadata['role'] ?? ''}'.trim().toLowerCase();
    if (allowedRoles.contains(role)) return true;
    final roles = user.appMetadata['roles'];
    if (roles is Iterable) {
      return roles
          .map((value) => '$value'.trim().toLowerCase())
          .any(allowedRoles.contains);
    }
    if (roles is String) {
      return roles
          .split(',')
          .map((value) => value.trim().toLowerCase())
          .any(allowedRoles.contains);
    }
    return false;
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
    if (isLoggingOut.value) return;
    isLoggingOut.value = true;
    isLoading.value = true;
    errorMessage.value = '';
    try {
      try {
        if (_auth.currentSession != null) {
          await _auth.signOut();
        }
      } catch (error) {
        Get.log('Supabase sign out failed during logout cleanup: $error');
      }
      verifiedFarmer.value = null;
      farmerLoginAnalyticsEvents.clear();
      if (Get.isRegistered<FarmerInventoryController>()) {
        Get.find<FarmerInventoryController>().clear();
      }
      if (Get.isRegistered<StakeholderController>()) {
        Get.delete<StakeholderController>(force: true);
      }
      if (Get.isRegistered<AdminController>()) {
        Get.delete<AdminController>(force: true);
      }
      _clearFarmerLoginSyncStatus();
      await _clearLocalGuest();
      if (Get.isRegistered<AuthController>()) {
        await Get.find<AuthController>().clearSession();
      }
      isLoggedIn.value = false;
      Get.offAllNamed('/login');
    } finally {
      isLoading.value = false;
      isLoggingOut.value = false;
    }
  }

  Future<bool> ensureRemoteGuestSession() async {
    if (_auth.currentUser != null) return true;
    await _refreshLocalGuestState();
    if (!hasLocalGuest.value ||
        !await _networkStatusService.hasNetworkInterface()) {
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

  Future<void> ensureFarmerSignupSession({required String phone}) async {
    final digits = _normalizePhone(phone);
    if (digits.length != 10) {
      throw const FarmerVerificationException(
        'Enter a valid 10 digit mobile number',
        code: 'invalid_phone',
      );
    }
    final currentUser = _auth.currentUser;
    if (_auth.currentSession != null && currentUser != null) {
      final metadata = currentUser.userMetadata ?? const <String, dynamic>{};
      final sessionPhone = _normalizePhone('${metadata['phone'] ?? ''}');
      if (sessionPhone == digits) {
        return;
      }
    }
    _farmerSessionLinkInProgress = true;
    try {
      await _clearLocalGuest();
      await _clearFarmerRemoteSession();
      await _auth.signInAnonymously(data: {'role': 'farmer', 'phone': digits});
    } finally {
      _farmerSessionLinkInProgress = false;
    }
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
          agriRecordId: record.agriRecordId,
          aadhaarNumber: record.aadhaarNumber,
          aadhaarMasked: record.aadhaarMasked,
          aadhaarLast4: record.aadhaarLast4,
          identityDocumentPath: record.identityDocumentPath,
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
      'agriRecordId': record.agriRecordId,
      'aadhaarNumber': record.aadhaarNumber,
      'aadhaarMasked': record.aadhaarMasked,
      'aadhaarLast4': record.aadhaarLast4,
      'identityDocumentPath': record.identityDocumentPath,
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
            agriRecordId: cached.agriRecordId,
            aadhaarNumber: cached.aadhaarNumber,
            aadhaarMasked: cached.aadhaarMasked,
            aadhaarLast4: cached.aadhaarLast4,
            identityDocumentPath: cached.identityDocumentPath,
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
    String nextRoute, {
    bool requireAgriRecord = false,
  }) async {
    final record = await _cachedFarmerRecordForPhone(phone);
    if (record == null) return false;
    if (requireAgriRecord && !_hasStakeholderAgriRecord(record)) {
      return false;
    }

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

  Future<VerifiedFarmerRecord> _signInAndSyncRemoteFarmer(
    String phone, {
    bool requireAgriRecord = false,
  }) async {
    _setFarmerLoginSyncStatus('checking_farmer_number');
    final verifiedRecord = await _verifyFarmerPhone(
      phone,
      requireAgriRecord: requireAgriRecord,
    );
    if (requireAgriRecord && !_hasStakeholderAgriRecord(verifiedRecord)) {
      throw const FarmerVerificationException(
        'Stakeholder login needs a government agri record. Complete farmer signup with your agri record card first.',
        code: 'farmer_agri_record_required',
      );
    }
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

    await _upsertFarmerPhoneProfile({
      'user_id': user.id,
      'phone': phone,
      'farmer_id': record.farmerId,
      'farmer_name': record.farmerName,
      'default_location': record.defaultLocation,
      'agri_record_id': record.agriRecordId,
      'aadhaar_number': record.aadhaarNumber,
      'aadhaar_masked': record.aadhaarMasked,
      'aadhaar_last4': record.aadhaarLast4,
      'identity_document_path': record.identityDocumentPath,
      'auth_method': 'anonymous_link',
      'status': 'active',
      'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'phone_login',
    }, onConflict: 'user_id');
  }

  Future<void> _upsertFarmerPhoneProfile(
    Map<String, Object?> row, {
    required String onConflict,
  }) async {
    try {
      await _client
          .from('farmer_phone_profiles')
          .upsert(row, onConflict: onConflict);
    } catch (error) {
      if (!_isMissingAadhaarNumberColumn(error)) rethrow;
      final legacyRow = Map<String, Object?>.from(row)
        ..remove('aadhaar_number');
      await _client
          .from('farmer_phone_profiles')
          .upsert(legacyRow, onConflict: onConflict);
    }
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
        final data = _responseMapFromLooseMap(raw);
        final message = data['error'] ?? data['message'] ?? data['details'];
        if (message != null && '$message'.trim().isNotEmpty) {
          return '$message';
        }
      }
    }
    return raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('FarmerVerificationException: ', '')
        .replaceFirst('RoleAccountSignupException: ', '')
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
    if (match == null) return _responseMapFromLooseMap(raw);
    try {
      final decoded = jsonDecode(match);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return _responseMapFromLooseMap(raw);
  }

  Map<String, dynamic> _responseMapFromLooseMap(String raw) {
    final match = RegExp(r'\{([^{}]*)\}').firstMatch(raw);
    if (match == null) return const <String, dynamic>{};
    final body = match.group(1);
    if (body == null || body.trim().isEmpty) return const <String, dynamic>{};
    final result = <String, dynamic>{};
    for (final entry in body.split(',')) {
      final separator = entry.indexOf(':');
      if (separator <= 0) continue;
      final key = entry.substring(0, separator).trim();
      final value = entry.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  String _roleAccountSignupErrorMessage(Object error, String accountLabel) {
    if (error is RoleAccountSignupException) {
      switch (error.code) {
        case 'account_already_exists':
          return 'This email is already registered. Login instead.';
        case 'invalid_role':
          return 'This signup link is not valid.';
      }
      if (error.message.isNotEmpty) return error.message;
    }
    final parsed = _responseMapFromThrowable(error);
    final code = '${parsed['code'] ?? ''}'.trim();
    final message = '${parsed['error'] ?? parsed['message'] ?? ''}'.trim();
    switch (code) {
      case 'account_already_exists':
        return 'This email is already registered. Login instead.';
      case 'invalid_role':
        return 'This signup link is not valid.';
    }
    if (message.isNotEmpty && !message.startsWith('FunctionException')) {
      return message;
    }
    return 'Could not create $accountLabel account. Check connection and try again.';
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
      case 'farmer_agri_record_required':
        return 'Stakeholder login needs a government agri record. Complete farmer signup with your agri record card first.';
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

  bool _hasStakeholderAgriRecord(VerifiedFarmerRecord record) {
    return record.agriRecordId.trim().isNotEmpty &&
        record.aadhaarLast4.trim().isNotEmpty;
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

  Future<int> _syncFarmerFarmDataForLogin({
    bool retryEmptyFarmCache = true,
  }) async {
    await _syncCurrentSupabaseSessionForSatellite();
    final farmCtrl = Get.isRegistered<FarmController>()
        ? Get.find<FarmController>()
        : Get.put(FarmController());
    farmCtrl.invalidateFarmCache();
    await farmCtrl.loadFarms(forceRefresh: true);
    final shouldRepairEmptyCache =
        retryEmptyFarmCache &&
        farmCtrl.farms.isEmpty &&
        !farmCtrl.lastLoadRemoteConfirmed;
    if (shouldRepairEmptyCache) {
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
    farmerLoginSyncStatusCode.value =
        farmCtrl.lastLoadUsedCachedFallback && farmCtrl.farms.isNotEmpty
        ? 'network_issue'
        : farmCtrl.farms.isEmpty
        ? 'farms_not_found'
        : 'farms_synced';
    if (farmCtrl.lastLoadUsedCachedFallback && farmCtrl.farms.isNotEmpty) {
      _setFarmerLoginSyncStatus('offline_cached_session');
    }
    return farmCtrl.farms.length;
  }

  void _startBackgroundFarmerDataSync({
    required VerifiedFarmerRecord record,
    required String phone,
    required String mode,
    bool retryEmptyFarmCache = true,
  }) {
    unawaited(
      _syncFarmerFarmDataAfterRoute(
        record: record,
        phone: phone,
        mode: mode,
        retryEmptyFarmCache: retryEmptyFarmCache,
      ),
    );
  }

  Future<void> _syncFarmerFarmDataAfterRoute({
    required VerifiedFarmerRecord record,
    required String phone,
    required String mode,
    required bool retryEmptyFarmCache,
  }) async {
    farmerLoginSyncPhone.value = phone;
    try {
      final farmCount = await _syncFarmerFarmDataForLogin(
        retryEmptyFarmCache: retryEmptyFarmCache,
      );
      final farmCtrl = Get.isRegistered<FarmController>()
          ? Get.find<FarmController>()
          : null;
      final usedCachedFarmFallback =
          farmCtrl?.lastLoadUsedCachedFallback == true && farmCount > 0;
      farmerLoginSyncedFarmCount.value = farmCount;
      final syncedAt = DateTime.now().toUtc();
      farmerLoginLastSyncAt.value = syncedAt;
      await _rememberFarmerLogin(
        record: record,
        farmCount: farmCount,
        syncedAt: syncedAt,
      );
      _setFarmerLoginSyncStatus(
        usedCachedFarmFallback
            ? 'offline_cached_session'
            : farmCount > 0
            ? 'farm_records_synced'
            : 'no_farm_records_found',
        code: usedCachedFarmFallback
            ? 'network_issue'
            : farmCount > 0
            ? 'farms_synced'
            : 'farms_not_found',
      );
      farmerLoginState.value = FarmerLoginState.farmsSynced;
      _trackFarmerLoginEvent('farm_sync_success', {
        'phone': phone,
        'farmCount': farmCount,
        'mode': mode,
        'cachedFallback': usedCachedFarmFallback,
      });
      unawaited(_syncFarmerInventoryForLogin());
    } on FarmerVerificationException catch (e) {
      _setFarmerLoginSyncStatusCode(e.code);
      _setFarmerLoginSyncStatus('farmer_session_sync_failed');
      _trackFarmerLoginEvent('farm_sync_failed', {
        'phone': phone,
        'mode': mode,
        'reason': e.code,
      });
    } catch (e) {
      final code = _networkStatusService.looksOffline(e)
          ? 'network_issue'
          : 'farm_sync_failed';
      _setFarmerLoginSyncStatusCode(code);
      _setFarmerLoginSyncStatus('farmer_session_sync_failed');
      _trackFarmerLoginEvent('farm_sync_failed', {
        'phone': phone,
        'mode': mode,
        'reason': code,
      });
    }
  }

  Future<void> _syncFarmerInventoryForLogin() async {
    final record = verifiedFarmer.value;
    final phone = _normalizePhone(record?.phone ?? '');
    if (phone.length != 10) return;
    try {
      final inventoryCtrl = Get.isRegistered<FarmerInventoryController>()
          ? Get.find<FarmerInventoryController>()
          : Get.put(FarmerInventoryController());
      await inventoryCtrl.syncForFarmer(
        farmerPhone: phone,
        farmerId: record?.farmerId,
      );
    } catch (error) {
      Get.log('Farmer inventory sync failed: $error');
    }
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
    required String agriRecordId,
    required String aadhaarNumber,
    required String aadhaarMasked,
    required String aadhaarLast4,
    required String identityDocumentPath,
    required String identitySource,
    double? identityOcrConfidence,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'register-farmer-phone',
        headers: _functionAuthHeaders(),
        body: {
          'phone': phone,
          'farmerName': farmerName,
          'defaultLocation': defaultLocation,
          'agriRecordId': agriRecordId,
          'aadhaarNumber': aadhaarNumber,
          'aadhaarMasked': aadhaarMasked,
          'aadhaarLast4': aadhaarLast4,
          'identityDocumentPath': identityDocumentPath,
          'identitySource': identitySource,
          ...(identityOcrConfidence == null
              ? const <String, Object?>{}
              : {'identityOcrConfidence': identityOcrConfidence}),
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

  Future<VerifiedFarmerRecord> _verifyFarmerPhone(
    String phone, {
    bool requireAgriRecord = false,
  }) async {
    try {
      final body = <String, dynamic>{'phone': phone};
      if (requireAgriRecord) {
        body['require_agri_record'] = true;
      }
      final response = await _client.functions.invoke(
        'verify-farmer-phone',
        body: body,
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

  bool _isMissingAadhaarNumberColumn(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('aadhaar_number') &&
        (message.contains('42703') ||
            message.contains('schema cache') ||
            message.contains('column') ||
            message.contains('does not exist'));
  }

  Future<List<dynamic>> _farmerProfileRowsForUser(String userId) async {
    try {
      return await _client
          .from('farmer_phone_profiles')
          .select(
            'phone, farmer_id, farmer_name, default_location, agri_record_id, aadhaar_number, aadhaar_masked, aadhaar_last4, identity_document_path',
          )
          .eq('user_id', userId)
          .limit(1);
    } catch (error) {
      if (!_isMissingAadhaarNumberColumn(error)) rethrow;
      return await _client
          .from('farmer_phone_profiles')
          .select(
            'phone, farmer_id, farmer_name, default_location, agri_record_id, aadhaar_masked, aadhaar_last4, identity_document_path',
          )
          .eq('user_id', userId)
          .limit(1);
    }
  }

  Future<VerifiedFarmerRecord?> _loadRemoteFarmerProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    // 1. Try primary lookup by user_id
    final rows = await _farmerProfileRowsForUser(user.id);

    if (rows.isNotEmpty) {
      final row = Map<String, dynamic>.from(rows.first as Map);
      return VerifiedFarmerRecord(
        phone: '${row['phone'] ?? ''}',
        farmerId: '${row['farmer_id'] ?? 'FMR-${row['phone'] ?? user.id}'}',
        farmerName: '${row['farmer_name'] ?? 'Farmer'}',
        defaultLocation: '${row['default_location'] ?? 'Remote farm profile'}',
        agriRecordId: '${row['agri_record_id'] ?? ''}'.trim(),
        aadhaarNumber: '${row['aadhaar_number'] ?? ''}'.trim(),
        aadhaarMasked: '${row['aadhaar_masked'] ?? ''}'.trim(),
        aadhaarLast4: '${row['aadhaar_last4'] ?? ''}'.trim(),
        identityDocumentPath: '${row['identity_document_path'] ?? ''}'.trim(),
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
          agriRecordId: '${metadata['agri_record_id'] ?? ''}'.trim(),
          aadhaarNumber: '${metadata['aadhaar_number'] ?? ''}'.trim(),
          aadhaarMasked: '${metadata['aadhaar_masked'] ?? ''}'.trim(),
          aadhaarLast4: '${metadata['aadhaar_last4'] ?? ''}'.trim(),
          identityDocumentPath: '${metadata['identity_document_path'] ?? ''}'
              .trim(),
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

    await _upsertFarmerPhoneProfile({
      'user_id': user.id,
      'phone': phone.isEmpty ? user.id : phone,
      'farmer_id': farmerId,
      'farmer_name': farmerName,
      'default_location': defaultLocation,
      'auth_method': 'email_password',
      'agri_record_id': '${metadata['agri_record_id'] ?? ''}'.trim(),
      'aadhaar_number': '${metadata['aadhaar_number'] ?? ''}'.trim(),
      'aadhaar_masked': '${metadata['aadhaar_masked'] ?? ''}'.trim(),
      'aadhaar_last4': '${metadata['aadhaar_last4'] ?? ''}'.trim(),
      'identity_document_path': '${metadata['identity_document_path'] ?? ''}'
          .trim(),
    }, onConflict: 'user_id');

    return VerifiedFarmerRecord(
      phone: phone,
      farmerId: farmerId,
      farmerName: farmerName,
      defaultLocation: defaultLocation,
      agriRecordId: '${metadata['agri_record_id'] ?? ''}'.trim(),
      aadhaarNumber: '${metadata['aadhaar_number'] ?? ''}'.trim(),
      aadhaarMasked: '${metadata['aadhaar_masked'] ?? ''}'.trim(),
      aadhaarLast4: '${metadata['aadhaar_last4'] ?? ''}'.trim(),
      identityDocumentPath: '${metadata['identity_document_path'] ?? ''}'
          .trim(),
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
