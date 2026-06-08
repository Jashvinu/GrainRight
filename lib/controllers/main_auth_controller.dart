import 'dart:async';

import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/network_status_service.dart';
import '../services/secure_app_storage.dart';
import 'survey_controller.dart';

class MainAuthController extends GetxController {
  static const _localGuestIdKey = 'local_guest_id';

  final _auth = Supabase.instance.client.auth;
  final _networkStatusService = NetworkStatusService();
  final _secureStorage = SecureAppStorage();

  final isLoggedIn = false.obs;
  final hasLocalGuest = false.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    isLoggedIn.value = _auth.currentSession != null;
    unawaited(_refreshLocalGuestState());
    _auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        unawaited(_clearLocalGuest());
      }
      isLoggedIn.value = data.session != null || hasLocalGuest.value;
    });
  }

  bool get isAuthenticated =>
      _auth.currentSession != null || hasLocalGuest.value;
  bool get isAnonymous =>
      (_auth.currentUser?.isAnonymous ?? false) || hasLocalGuest.value;
  String? get userEmail => _auth.currentUser?.email;
  String? get remoteUserId => _auth.currentUser?.id;

  Future<bool> hasAnySession() async {
    await _refreshLocalGuestState();
    return _auth.currentSession != null || hasLocalGuest.value;
  }

  Future<bool> ensureOfflineSessionWhenOffline() async {
    await _refreshLocalGuestState();
    if (_auth.currentSession != null || hasLocalGuest.value) return true;
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

  Future<void> _afterSignIn(String nextRoute) async {
    if (Get.isRegistered<SurveyController>()) {
      await Get.find<SurveyController>().loadSurveys();
    }
    Get.offAllNamed(nextRoute);
  }

  Future<void> logout() async {
    await _auth.signOut();
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
    isLoggedIn.value = _auth.currentSession != null || hasLocalGuest.value;
  }

  Future<void> _clearLocalGuest() async {
    await _secureStorage.remove(_localGuestIdKey);
    hasLocalGuest.value = false;
    isLoggedIn.value = _auth.currentSession != null;
  }
}
