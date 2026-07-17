import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/runtime_config.dart';
import '../models/verified_farmer_record.dart';
import '../services/local_app_database.dart';
import '../services/network_status_service.dart';
import '../services/satellite_service.dart';
import '../services/secure_app_storage.dart';
import 'auth_controller.dart';
import 'farm_controller.dart';
import 'farmer_inventory_controller.dart';
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

class MainAuthController extends GetxController {
  static const _localGuestIdKey = 'local_guest_id';
  static const _lastFarmerLoginKey = 'last_farmer_login_summary';
  static const _lastLoginRoleKey = 'last_login_role';

  final _auth = Supabase.instance.client.auth;
  final _client = Supabase.instance.client;
  final _networkStatusService = NetworkStatusService();
  final _secureStorage = SecureAppStorage();
  final _satelliteService = SatelliteService();
  final _firebaseAuth = firebase.FirebaseAuth.instance;

  final isLoggedIn = false.obs;
  final hasLocalGuest = false.obs;
  final isLoading = false.obs;
  final isSmsCodeSent = false.obs;
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
  final lastLoginRole = ''.obs;
  bool _farmerSessionLinkInProgress = false;
  firebase.ConfirmationResult? _farmerPhoneConfirmationResult;
  String? _firebaseVerificationId;
  int? _firebaseResendToken;
  String? _pendingVerifiedPhone;
  String? _pendingVerifiedDialCode;
  String? _pendingVerifiedE164;
  String? _verifiedSignupPhone;
  String? _verifiedSignupE164;

  @override
  void onInit() {
    super.onInit();
    isLoggedIn.value = _hasUserSupabaseSession;
    unawaited(_clearLocalGuest());
    unawaited(_loadLastLoginRole());
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
          _hasUserSupabaseSession ||
          verifiedFarmer.value != null ||
          _hasFirebaseFpcSession;
    });
  }

  bool get isAuthenticated =>
      _hasUserSupabaseSession ||
      verifiedFarmer.value != null ||
      _hasFirebaseFpcSession;
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;
  String? get userEmail => _auth.currentUser?.email;
  String? get remoteUserId => _auth.currentUser?.id;
  bool get _hasFirebaseFpcSession =>
      _firebaseAuth.currentUser != null && _isFpcRole(lastLoginRole.value);
  String? get _backendAuthToken {
    if (!Get.isRegistered<AuthController>()) return null;
    final token = Get.find<AuthController>().accessToken.value.trim();
    return token.isEmpty ? null : token;
  }

  String? get _backendAuthUserId {
    if (!Get.isRegistered<AuthController>()) return null;
    final userId = Get.find<AuthController>().currentUser.value?.id.trim();
    return userId == null || userId.isEmpty ? null : userId;
  }

  bool get farmerLoginHealthFarmerVerified =>
      verifiedFarmer.value != null || lastFarmerLoginPhone.value.length == 10;
  bool get farmerLoginHealthSessionLinked =>
      farmerLoginState.value == FarmerLoginState.linked ||
      farmerLoginState.value == FarmerLoginState.farmsSynced ||
      farmerLoginState.value == FarmerLoginState.ready ||
      _auth.currentSession != null ||
      _backendAuthToken != null;
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
    await _clearLocalGuest();
    await _refreshVerifiedProfile();
    return _hasUserSupabaseSession || verifiedFarmer.value != null;
  }

  Future<bool> ensureOfflineSessionWhenOffline() async {
    await _clearLocalGuest();
    await _refreshVerifiedProfile();
    if (_hasUserSupabaseSession || verifiedFarmer.value != null) {
      return true;
    }
    return false;
  }

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _ensureBackendAuthSession();
      await _afterSignIn('/home');
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } on FarmerVerificationException catch (e) {
      errorMessage.value = _farmerLoginErrorMessage(e);
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
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _ensureBackendAuthSession();
      final record =
          await _loadRemoteFarmerProfile() ??
          _createFarmerProfileFromFirebaseUser(email);
      verifiedFarmer.value = record;
      await _rememberLocalFarmerProfile(record: record);

      final session = _auth.currentSession;
      final user = _auth.currentUser;
      if (session != null && user != null) {
        await _syncSatelliteSession(session, user, email);
      }

      isLoggedIn.value = true;
      await _afterSignIn(nextRoute);
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } on FarmerVerificationException catch (e) {
      errorMessage.value = _farmerLoginErrorMessage(e);
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
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _rememberLastLoginRole('fpo_fpc');
      await _primeBackendBridgeForFpc();
      isLoggedIn.value = true;
      await _afterSignIn(nextRoute, syncFarmerBeforeRoute: false);
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } on FarmerVerificationException catch (e) {
      errorMessage.value = _farmerLoginErrorMessage(e);
    } catch (_) {
      errorMessage.value = 'Could not login FPC account.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> signupFpc(
    String email,
    String password, {
    String nextRoute = '/fpo',
    String? organizationName,
  }) async {
    isLoading.value = true;
    errorMessage.value = '';
    verifiedFarmer.value = null;
    try {
      await _clearLocalGuest();
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final name = organizationName?.trim();
      if (name != null && name.isNotEmpty) {
        await credential.user?.updateDisplayName(name);
      }
      await credential.user?.getIdToken(true);
      await _rememberLastLoginRole('fpo_fpc');
      await _primeBackendBridgeForFpc();
      isLoggedIn.value = true;
      await _afterSignIn(nextRoute, syncFarmerBeforeRoute: false);
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } on FarmerVerificationException catch (e) {
      errorMessage.value = _farmerLoginErrorMessage(e);
    } catch (_) {
      errorMessage.value = 'Could not create FPC account.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> continueAsGuest({String nextRoute = '/home'}) async {
    await _clearLocalGuest();
    errorMessage.value =
        'Guest access has been removed. Please sign in as a Farmer or FPO/FPC.';
  }

  Future<bool> sendFarmerPhoneCode(
    String phone, {
    String nextRoute = '/farmer',
    bool verifyOnly = false,
    String countryDialCode = '+91',
  }) async {
    if (isLoading.value) return false;
    final digits = _normalizePhone(phone);
    final dialCode = _normalizeDialCode(countryDialCode);
    final e164Phone = '$dialCode$digits';
    if (digits.length != 10) {
      errorMessage.value = 'Enter a valid 10 digit mobile number';
      _clearFarmerLoginSyncStatus();
      return false;
    }

    isLoading.value = true;
    errorMessage.value = '';
    _pendingVerifiedPhone = digits;
    _pendingVerifiedDialCode = dialCode;
    _pendingVerifiedE164 = e164Phone;
    isSmsCodeSent.value = false;

    try {
      await _startFreshPhoneAuthAttempt();
      if (kIsWeb) {
        _farmerPhoneConfirmationResult = await _firebaseAuth
            .signInWithPhoneNumber(e164Phone);
        isSmsCodeSent.value = true;
        return true;
      }

      final completer = Completer<bool>();
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: e164Phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _firebaseResendToken,
        verificationCompleted: (credential) async {
          try {
            await _firebaseAuth.signInWithCredential(credential);
            if (verifyOnly) {
              _verifiedSignupPhone = digits;
              _verifiedSignupE164 = e164Phone;
              _resetPhoneVerification();
              if (!completer.isCompleted) completer.complete(true);
              isLoading.value = false;
              return;
            }
            _resetPhoneVerification();
            if (!completer.isCompleted) completer.complete(true);
            isLoading.value = false;
            await continueAsVerifiedFarmer(
              digits,
              nextRoute: nextRoute,
              countryDialCode: dialCode,
            );
          } on firebase.FirebaseAuthException catch (e) {
            errorMessage.value = _firebaseAuthErrorMessage(e);
            if (!completer.isCompleted) completer.complete(false);
          } catch (_) {
            errorMessage.value = 'Could not verify farmer profile.';
            if (!completer.isCompleted) completer.complete(false);
          }
        },
        verificationFailed: (e) {
          errorMessage.value = _firebaseAuthErrorMessage(e);
          if (!completer.isCompleted) completer.complete(false);
        },
        codeSent: (verificationId, resendToken) {
          _firebaseVerificationId = verificationId;
          _firebaseResendToken = resendToken;
          isSmsCodeSent.value = true;
          if (!completer.isCompleted) completer.complete(true);
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _firebaseVerificationId = verificationId;
        },
      );

      return completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => isSmsCodeSent.value,
      );
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
      return false;
    } catch (_) {
      errorMessage.value = 'Could not send verification code.';
      return false;
    } finally {
      if (isSmsCodeSent.value || _firebaseAuth.currentUser == null) {
        isLoading.value = false;
      }
    }
  }

  Future<void> verifyFarmerPhoneCode(
    String smsCode, {
    String nextRoute = '/farmer',
    bool verifyOnly = false,
    String countryDialCode = '+91',
  }) async {
    if (isLoading.value) return;
    final phone = _pendingVerifiedPhone;
    final code = smsCode.trim();
    if (phone == null || phone.length != 10) {
      errorMessage.value = 'Send the verification code first.';
      return;
    }
    if (code.length < 4) {
      errorMessage.value = 'Enter the SMS verification code.';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    try {
      if (kIsWeb) {
        final confirmation = _farmerPhoneConfirmationResult;
        if (confirmation == null) {
          errorMessage.value = 'Send the verification code first.';
          return;
        }
        await confirmation.confirm(code);
      } else {
        final verificationId = _firebaseVerificationId;
        if (verificationId == null) {
          errorMessage.value = 'Send the verification code first.';
          return;
        }
        final credential = firebase.PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: code,
        );
        await _firebaseAuth.signInWithCredential(credential);
      }
      if (verifyOnly) {
        _verifiedSignupPhone = phone;
        _verifiedSignupE164 = _pendingVerifiedE164;
        _resetPhoneVerification();
        isLoading.value = false;
        return;
      }
      _resetPhoneVerification();
      isLoading.value = false;
      await continueAsVerifiedFarmer(
        phone,
        nextRoute: nextRoute,
        countryDialCode: countryDialCode,
      );
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } catch (_) {
      errorMessage.value = 'Could not verify farmer profile.';
    } finally {
      if (isLoading.value) isLoading.value = false;
    }
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
      final online = await _networkStatusService.isOnline();
      if (!online) {
        _setFarmerLoginSyncStatus('offline_cached_session');
        _setFarmerLoginSyncStatusCode('network_issue');
        final opened = await _openCachedFarmerSessionIfAvailable(
          digits,
          nextRoute,
          requireAgriRecord: requireAgriRecord,
        );
        if (!opened) {
          errorMessage.value = requireAgriRecord
              ? 'Network issue. Connect to internet so we can confirm stakeholder access.'
              : 'You are offline. Last saved farm data will open when available.';
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
      final record = await _signInAndSyncRemoteFarmer(
        digits,
        requireAgriRecord: requireAgriRecord,
      );
      verifiedFarmer.value = record;
      await _rememberLocalFarmerProfile(record: record);
      isLoggedIn.value = true;
      _setFarmerLoginSyncStatus('syncing_farm_records');
      final farmCount = await _syncFarmerFarmDataForLogin();
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
      _trackFarmerLoginEvent('farm_sync_success', {
        'phone': digits,
        'farmCount': farmCount,
        'cachedFallback': usedCachedFarmFallback,
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
      Get.offNamed(
        '/farmer/signup',
        arguments: {'phone': digits, 'countryDialCode': countryDialCode},
      );
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
    required String aadhaarMasked,
    required String aadhaarLast4,
    required String identityDocumentPath,
    double? identityOcrConfidence,
    String nextRoute = '/farmer',
    String countryDialCode = '+91',
  }) async {
    final digits = _normalizePhone(phone);
    final name = farmerName.trim();
    final location = defaultLocation.trim();
    final recordId = agriRecordId.trim();
    final maskedAadhaar = aadhaarMasked.trim();
    final aadhaarLastDigits = aadhaarLast4.replaceAll(RegExp(r'\D'), '');
    final documentPath = identityDocumentPath.trim();
    if (digits.length != 10) {
      errorMessage.value = 'Enter a valid 10 digit mobile number';
      return;
    }
    if (name.isEmpty) {
      errorMessage.value = 'Enter farmer name';
      return;
    }
    if (recordId.isEmpty) {
      errorMessage.value = 'Enter farmer agri record ID';
      return;
    }
    if (aadhaarLastDigits.length != 4 || maskedAadhaar.isEmpty) {
      errorMessage.value = 'Enter a 12 digit Aadhaar number';
      return;
    }
    if (documentPath.isEmpty) {
      errorMessage.value = 'Upload agri record document';
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
        aadhaarMasked: maskedAadhaar,
        aadhaarLast4: aadhaarLastDigits,
        identityDocumentPath: documentPath,
        identityOcrConfidence: identityOcrConfidence,
      );

      verifiedFarmer.value = record;
      farmerLoginState.value = FarmerLoginState.verified;
      await _rememberLocalFarmerProfile(record: record);
      _setFarmerLoginSyncStatus('syncing_farm_records');
      final farmCount = await _syncFarmerFarmDataForLogin();
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
      _trackFarmerLoginEvent('farm_sync_success', {
        'phone': digits,
        'farmCount': farmCount,
        'mode': 'signup',
        'cachedFallback': usedCachedFarmFallback,
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
        if (farmCtrl.lastLoadUsedCachedFallback && farmCtrl.farms.isNotEmpty) {
          _setFarmerLoginSyncStatus('offline_cached_session');
          farmerLoginSyncStatusCode.value = 'network_issue';
        } else {
          farmerLoginSyncStatusCode.value = farmCtrl.farms.isEmpty
              ? 'farms_not_found'
              : 'farms_synced';
        }
        await _syncFarmerInventoryForLogin();
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
    await _firebaseAuth.signOut();
    await _auth.signOut();
    _resetPhoneVerification();
    verifiedFarmer.value = null;
    if (Get.isRegistered<FarmerInventoryController>()) {
      Get.find<FarmerInventoryController>().clear();
    }
    _clearFarmerLoginSyncStatus();
    await _clearLocalGuest();
    await _clearLastLoginRole();
    if (Get.isRegistered<AuthController>()) {
      await Get.find<AuthController>().clearSession();
    }
    Get.offAllNamed('/login');
  }

  Future<String> startupRoute() async {
    await _loadLastLoginRole();
    final user = _auth.currentUser;
    final supabaseRole = '${user?.userMetadata?['role'] ?? ''}'
        .trim()
        .toLowerCase();
    if (verifiedFarmer.value != null || supabaseRole == 'farmer') {
      return '/farmer';
    }
    if (_isFpcRole(supabaseRole) || _hasFirebaseFpcSession) {
      return '/fpo';
    }
    if (_hasUserSupabaseSession) {
      return '/home';
    }
    return '/login';
  }

  Future<bool> ensureRemoteGuestSession() async {
    await _clearLocalGuest();
    errorMessage.value =
        'Guest access has been removed. Please sign in before syncing.';
    return false;
  }

  Future<void> _refreshVerifiedProfile() async {
    await _loadLastFarmerLoginSummary();

    VerifiedFarmerRecord? record;
    try {
      record = await _loadRemoteFarmerProfile();
    } catch (e) {
      if (_networkStatusService.looksOffline(e)) {
        isLoggedIn.value =
            _hasUserSupabaseSession || verifiedFarmer.value != null;
        return;
      }
      rethrow;
    }
    if (record == null) {
      verifiedFarmer.value = null;
      isLoggedIn.value = _hasUserSupabaseSession;
      return;
    }
    verifiedFarmer.value = record;
    await _rememberLocalFarmerProfile(record: record);

    isLoggedIn.value = _hasUserSupabaseSession || verifiedFarmer.value != null;
  }

  Future<void> _clearLocalGuest() async {
    await _secureStorage.remove(_localGuestIdKey);
    hasLocalGuest.value = false;
    isLoggedIn.value = _hasUserSupabaseSession || verifiedFarmer.value != null;
  }

  Future<void> _loadLastLoginRole() async {
    final role = await _secureStorage.readString(_lastLoginRoleKey) ?? '';
    lastLoginRole.value = role.trim().toLowerCase();
    if (_hasFirebaseFpcSession) {
      isLoggedIn.value = true;
    }
  }

  Future<void> _rememberLastLoginRole(String role) async {
    final normalized = role.trim().toLowerCase();
    lastLoginRole.value = normalized;
    if (normalized.isEmpty) {
      await _secureStorage.remove(_lastLoginRoleKey);
    } else {
      await _secureStorage.writeString(_lastLoginRoleKey, normalized);
    }
  }

  Future<void> _clearLastLoginRole() async {
    lastLoginRole.value = '';
    await _secureStorage.remove(_lastLoginRoleKey);
  }

  bool _isFpcRole(String role) {
    return {
      'fpc',
      'fpo',
      'fpo_fpc',
      'fpo/fpc',
    }.contains(role.trim().toLowerCase());
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

  bool get _hasUserSupabaseSession {
    final session = _auth.currentSession;
    final user = _auth.currentUser;
    return session != null &&
        !(user?.isAnonymous ?? false) &&
        !_isBackendBridgeSupabaseUser(user);
  }

  bool _isBackendBridgeSupabaseUser(User? user) {
    final backendEmail = RuntimeConfig.backendAuthEmail.trim().toLowerCase();
    if (backendEmail.isEmpty) return false;
    return (user?.email ?? '').trim().toLowerCase() == backendEmail;
  }

  Future<void> _startFreshPhoneAuthAttempt() async {
    await _firebaseAuth.signOut();
    await _clearFarmerRemoteSession();
    verifiedFarmer.value = null;
    isLoggedIn.value = false;
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
          userId: _backendAuthUserId ?? _auth.currentUser?.id ?? '',
          defaultLocation: record.defaultLocation,
          preferredLanguage: 'en',
          agriRecordId: record.agriRecordId,
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
      isLoggedIn.value = _hasUserSupabaseSession;
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

    _setFarmerLoginSyncStatus('starting_farmer_session');
    await _ensureBackendAuthSession();

    _setFarmerLoginSyncStatus('linking_farmer_profile');
    await _linkRemoteFarmerPhone(phone: phone, record: verifiedRecord);
    farmerLoginState.value = FarmerLoginState.linked;
    _setFarmerLoginSyncStatusCode('farmer_linked');

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
    final token = _backendAuthToken ?? _auth.currentSession?.accessToken;
    return token == null || token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
  }

  Future<void> _linkRemoteFarmerPhoneDirect({
    required String phone,
    required VerifiedFarmerRecord record,
  }) async {
    final userId = _backendAuthUserId ?? _auth.currentUser?.id;
    final token = _backendAuthToken ?? _auth.currentSession?.accessToken;
    if (userId == null || userId.isEmpty || token == null || token.isEmpty) {
      throw const FarmerVerificationException('No backend farmer session.');
    }

    await _client.from('farmer_phone_profiles').upsert({
      'user_id': user.id,
      'phone': phone,
      'farmer_id': record.farmerId,
      'farmer_name': record.farmerName,
      'default_location': record.defaultLocation,
      'agri_record_id': record.agriRecordId,
      'aadhaar_masked': record.aadhaarMasked,
      'aadhaar_last4': record.aadhaarLast4,
      'identity_document_path': record.identityDocumentPath,
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
        record.identityDocumentPath.trim().isNotEmpty;
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
    farmerLoginSyncStatusCode.value =
        farmCtrl.lastLoadUsedCachedFallback && farmCtrl.farms.isNotEmpty
        ? 'network_issue'
        : farmCtrl.farms.isEmpty
        ? 'farms_not_found'
        : 'farms_synced';
    if (farmCtrl.lastLoadUsedCachedFallback && farmCtrl.farms.isNotEmpty) {
      _setFarmerLoginSyncStatus('offline_cached_session');
    }
    await _syncFarmerInventoryForLogin();
    return farmCtrl.farms.length;
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
    if (_backendAuthToken != null && _backendAuthUserId != null) return;
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
    required String aadhaarMasked,
    required String aadhaarLast4,
    required String identityDocumentPath,
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
          'aadhaarMasked': aadhaarMasked,
          'aadhaarLast4': aadhaarLast4,
          'identityDocumentPath': identityDocumentPath,
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

  Future<VerifiedFarmerRecord?> _loadRemoteFarmerProfile() async {
    final firebasePhone = _normalizePhone(
      _firebaseAuth.currentUser?.phoneNumber ?? '',
    );
    if (firebasePhone.length == 10) {
      try {
        final record = await _verifyFarmerPhone(firebasePhone);
        unawaited(_linkRemoteFarmerPhone(phone: firebasePhone, record: record));
        return record;
      } on FarmerProfileNotFoundException {
        return null;
      }
    }

    final user = _auth.currentUser;
    if (user == null || _isBackendBridgeSupabaseUser(user)) return null;

    final rows = await _client
        .from('farmer_phone_profiles')
        .select(
          'phone, farmer_id, farmer_name, default_location, agri_record_id, aadhaar_masked, aadhaar_last4, identity_document_path',
        )
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isNotEmpty) {
      final row = Map<String, dynamic>.from(rows.first as Map);
      return VerifiedFarmerRecord(
        phone: '${row['phone'] ?? ''}',
        farmerId: '${row['farmer_id'] ?? 'FMR-${row['phone'] ?? user.id}'}',
        farmerName: '${row['farmer_name'] ?? 'Farmer'}',
        defaultLocation: '${row['default_location'] ?? 'Remote farm profile'}',
        agriRecordId: '${row['agri_record_id'] ?? ''}'.trim(),
        aadhaarMasked: '${row['aadhaar_masked'] ?? ''}'.trim(),
        aadhaarLast4: '${row['aadhaar_last4'] ?? ''}'.trim(),
        identityDocumentPath: '${row['identity_document_path'] ?? ''}'.trim(),
        lots: const [],
      );
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final phone = _normalizePhone('${metadata['phone'] ?? ''}');
    if (phone.length == 10) {
      try {
        final record = await _verifyFarmerPhone(phone);
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

    await _client.from('farmer_phone_profiles').upsert({
      'user_id': user.id,
      'phone': phone.isEmpty ? user.id : phone,
      'farmer_id': farmerId,
      'farmer_name': farmerName,
      'default_location': defaultLocation,
      'auth_method': 'email_password',
      'agri_record_id': '${metadata['agri_record_id'] ?? ''}'.trim(),
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
