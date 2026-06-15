import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/verified_farmer_record.dart';
import '../services/network_status_service.dart';
import '../services/secure_app_storage.dart';
import 'auth_controller.dart';
import 'survey_controller.dart';

class FarmerVerificationException implements Exception {
  final String message;

  const FarmerVerificationException(this.message);

  @override
  String toString() => message;
}

class MainAuthController extends GetxController {
  static const _localGuestIdKey = 'local_guest_id';

  final _auth = Supabase.instance.client.auth;
  final _client = Supabase.instance.client;
  final _networkStatusService = NetworkStatusService();
  final _secureStorage = SecureAppStorage();

  final isLoggedIn = false.obs;
  final hasLocalGuest = false.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final Rxn<VerifiedFarmerRecord> verifiedFarmer = Rxn<VerifiedFarmerRecord>();

  bool get _farmerPhoneVerificationEnabled => false;

  @override
  void onInit() {
    super.onInit();
    isLoggedIn.value = _auth.currentSession != null;
    unawaited(_refreshLocalGuestState());
    unawaited(_refreshVerifiedProfile());
    _auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        unawaited(_clearLocalGuest());
        unawaited(_refreshVerifiedProfile());
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
      final record = await _loadRemoteFarmerProfile() ??
          await _createFarmerProfileFromCurrentUser(email);
      verifiedFarmer.value = record;

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
      await _afterSignIn(nextRoute);
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
    final digits = _normalizePhone(phone);
    if (digits.length != 10) {
      errorMessage.value = 'Enter a valid 10 digit mobile number';
      return;
    }

    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _clearLocalGuest();
      final record = await _signInAndSyncRemoteFarmer(digits);
      verifiedFarmer.value = record;
      isLoggedIn.value = true;
      await _afterSignIn(nextRoute);
    } on FarmerVerificationException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = _farmerPhoneVerificationEnabled
          ? 'Could not verify farmer profile.'
          : 'Could not start farmer session.';
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
    verifiedFarmer.value = null;
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

    final record = await _loadRemoteFarmerProfile();
    if (record == null) {
      verifiedFarmer.value = null;
      isLoggedIn.value = _auth.currentSession != null || hasLocalGuest.value;
      return;
    }
    verifiedFarmer.value = record;

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

  String _normalizePhone(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  Future<VerifiedFarmerRecord> _signInAndSyncRemoteFarmer(String phone) async {
    final verifiedRecord = _farmerPhoneVerificationEnabled
        ? await _verifyFarmerPhone(phone)
        : _unverifiedFarmerRecord(phone);

    if (_auth.currentSession == null) {
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

    await _client.from('farmer_phone_profiles').upsert(
      {
        'user_id': user.id,
        'phone': phone,
        'farmer_id': verifiedRecord.farmerId,
        'farmer_name': verifiedRecord.farmerName,
        'default_location': verifiedRecord.defaultLocation,
        'auth_method': 'anonymous_link',
        'status': 'active',
        if (_farmerPhoneVerificationEnabled)
          'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
        'source': _farmerPhoneVerificationEnabled
            ? 'registry_fallback'
            : 'verification_disabled',
      },
      onConflict: 'user_id',
    );

    await _syncSatelliteSession(
      session,
      user,
      user.email ?? 'farmer-$phone@anonymous.local',
    );

    return verifiedRecord;
  }

  VerifiedFarmerRecord _unverifiedFarmerRecord(String phone) {
    return VerifiedFarmerRecord(
      phone: phone,
      farmerId: 'FMR-$phone',
      farmerName: 'Farmer',
      defaultLocation: 'Kalsubai Farms',
      lots: const [],
    );
  }

  Future<VerifiedFarmerRecord> _verifyFarmerPhone(String phone) async {
    try {
      final response = await _client.functions.invoke(
        'verify-farmer-phone',
        body: {'phone': phone},
      );
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw FarmerVerificationException(
          '${data['error'] ?? 'Could not verify farmer profile.'}',
        );
      }
      final farmer = data['farmer'];
      if (farmer is! Map) {
        throw const FarmerVerificationException(
          'No approved farmer profile found for this number.',
        );
      }
      return VerifiedFarmerRecord.fromJson(
        Map<String, dynamic>.from(farmer as Map),
      );
    } on FarmerVerificationException {
      rethrow;
    } catch (_) {
      throw const FarmerVerificationException(
        'Could not verify farmer profile. Check the number or contact admin.',
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

  Future<VerifiedFarmerRecord?> _loadRemoteFarmerProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final rows = await _client
        .from('farmer_phone_profiles')
        .select('phone, farmer_id, farmer_name, default_location')
        .eq('user_id', user.id)
        .limit(1);
    if (rows is! List || rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    return VerifiedFarmerRecord(
      phone: '${row['phone'] ?? ''}',
      farmerId: '${row['farmer_id'] ?? 'FMR-${row['phone'] ?? user.id}'}',
      farmerName: '${row['farmer_name'] ?? 'Farmer'}',
      defaultLocation: '${row['default_location'] ?? 'Remote farm profile'}',
      lots: const [],
    );
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

    await _client.from('farmer_phone_profiles').upsert(
      {
        'user_id': user.id,
        'phone': phone.isEmpty ? user.id : phone,
        'farmer_id': farmerId,
        'farmer_name': farmerName,
        'default_location': defaultLocation,
        'auth_method': 'email_password',
      },
      onConflict: 'user_id',
    );

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
