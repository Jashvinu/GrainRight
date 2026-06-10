import 'dart:async';

import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/verified_farmer_record.dart';
import '../services/network_status_service.dart';
import '../services/secure_app_storage.dart';
import '../services/verified_farmer_seed_service.dart';
import 'survey_controller.dart';

class MainAuthController extends GetxController {
  static const _localGuestIdKey = 'local_guest_id';
  static const _verifiedFarmerSessionKey = 'verified_farmer_session';

  final _auth = Supabase.instance.client.auth;
  final _networkStatusService = NetworkStatusService();
  final _secureStorage = SecureAppStorage();

  final isLoggedIn = false.obs;
  final hasLocalGuest = false.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final Rxn<VerifiedFarmerRecord> verifiedFarmer = Rxn<VerifiedFarmerRecord>();

  @override
  void onInit() {
    super.onInit();
    isLoggedIn.value = _auth.currentSession != null;
    unawaited(_refreshLocalGuestState());
    unawaited(_refreshVerifiedSession());
    _auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        unawaited(_clearLocalGuest());
        unawaited(_clearVerifiedFarmerSession());
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

  Future<bool> hasAnySession() async {
    await _refreshLocalGuestState();
    await _refreshVerifiedSession();
    return _auth.currentSession != null ||
        hasLocalGuest.value ||
        verifiedFarmer.value != null;
  }

  Future<bool> ensureOfflineSessionWhenOffline() async {
    await _refreshLocalGuestState();
    await _refreshVerifiedSession();
    if (_auth.currentSession != null ||
        hasLocalGuest.value ||
        verifiedFarmer.value != null) return true;
    if (await _networkStatusService.isOnline()) return false;
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

  Future<void> continueAsGuest({String nextRoute = '/home'}) async {
    isLoading.value = true;
    errorMessage.value = '';
    await _clearVerifiedFarmerSession();
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
    final digits = _normalizePhone(phone);
    if (digits.length != 10) {
      errorMessage.value = 'Enter a valid 10 digit mobile number';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    try {
      final record = await VerifiedFarmerSeedService.instance.getByPhone(digits);
      if (record == null) {
        errorMessage.value =
            'Phone number is not linked to a verified farmer profile.';
        return;
      }
      await _clearLocalGuest();
      await _clearVerifiedFarmerSession();
      verifiedFarmer.value = record;
      await _secureStorage.writeString(_verifiedFarmerSessionKey, digits);
      isLoggedIn.value = true;
      await _afterSignIn(nextRoute);
    } catch (_) {
      errorMessage.value = 'Could not verify farmer profile.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _afterSignIn(String nextRoute) async {
    if (nextRoute == '/home' && Get.isRegistered<SurveyController>()) {
      await Get.find<SurveyController>().loadSurveys();
    }
    Get.offAllNamed(nextRoute);
  }

  Future<void> logout() async {
    await _auth.signOut();
    await _clearVerifiedFarmerSession();
    await _clearLocalGuest();
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

  Future<void> _refreshVerifiedSession() async {
    final phone = await _secureStorage.readString(_verifiedFarmerSessionKey);
    if (phone == null || phone.isEmpty) {
      verifiedFarmer.value = null;
      isLoggedIn.value =
          _auth.currentSession != null ||
          hasLocalGuest.value ||
          verifiedFarmer.value != null;
      return;
    }

    final record = await VerifiedFarmerSeedService.instance.getByPhone(phone);
    verifiedFarmer.value = record;
    if (record == null) {
      await _clearVerifiedFarmerSession();
      return;
    }

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

  Future<void> _clearVerifiedFarmerSession() async {
    await _secureStorage.remove(_verifiedFarmerSessionKey);
    verifiedFarmer.value = null;
    isLoggedIn.value =
        _auth.currentSession != null || hasLocalGuest.value;
  }

  String _normalizePhone(String phone) => phone.replaceAll(RegExp(r'\D'), '');
}
