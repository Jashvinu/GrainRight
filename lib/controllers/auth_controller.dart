import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../config/runtime_config.dart';
import '../services/secure_app_storage.dart';
import '../services/satellite_service.dart';

class SatelliteUser {
  final String id;
  final String email;
  SatelliteUser({required this.id, required this.email});
}

class AuthController extends GetxController {
  final _service = SatelliteService();
  final _secureStorage = SecureAppStorage();
  final _firebaseAuth = firebase.FirebaseAuth.instance;
  firebase.ConfirmationResult? _phoneConfirmationResult;
  String? _phoneVerificationId;
  int? _phoneResendToken;

  final isLoggedIn = false.obs;
  final currentUser = Rxn<SatelliteUser>();
  final accessToken = ''.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final pendingPhoneOtp = ''.obs;

  static const _keyAccess = 'sat_access_token';
  static const _keyRefresh = 'sat_refresh_token';
  static const _keyUserId = 'sat_user_id';
  static const _keyEmail = 'sat_email';

  @override
  void onInit() {
    super.onInit();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await _secureStorage.readString(_keyAccess) ?? '';
    final refresh = await _secureStorage.readString(_keyRefresh) ?? '';
    final userId = await _secureStorage.readString(_keyUserId) ?? '';
    final email = await _secureStorage.readString(_keyEmail) ?? '';

    if (accessToken.value.isNotEmpty &&
        (currentUser.value?.id.isNotEmpty ?? false)) {
      return;
    }

    if (token.isEmpty) return;

    // Check JWT exp claim
    if (_isTokenExpired(token)) {
      if (refresh.isNotEmpty) {
        final result = await _service.refreshToken(refresh);
        if (result != null && result.accessToken.isNotEmpty) {
          if (accessToken.value.isNotEmpty &&
              (currentUser.value?.id.isNotEmpty ?? false)) {
            return;
          }
          await _saveSession(result);
          _setLoggedIn(result.accessToken, result.userId, result.email);
          return;
        }
      }
      if (accessToken.value.isNotEmpty &&
          (currentUser.value?.id.isNotEmpty ?? false)) {
        return;
      }
      await _clearSession();
      return;
    }

    if (accessToken.value.isNotEmpty &&
        (currentUser.value?.id.isNotEmpty ?? false)) {
      return;
    }
    _setLoggedIn(token, userId, email);
  }

  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      var payload = parts[1];
      // Fix base64url padding
      final mod = payload.length % 4;
      if (mod == 2) {
        payload += '==';
      } else if (mod == 3) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final expMatch = RegExp(r'"exp":(\d+)').firstMatch(decoded);
      if (expMatch == null) return true;
      final exp = int.parse(expMatch.group(1)!);
      final nowSecs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return nowSecs >= exp - 60; // 60s buffer
    } catch (_) {
      return true;
    }
  }

  void _setLoggedIn(String token, String userId, String email) {
    accessToken.value = token;
    currentUser.value = SatelliteUser(id: userId, email: email);
    isLoggedIn.value = true;
  }

  Future<void> _saveSession(AuthResult result) async {
    await _secureStorage.writeString(_keyAccess, result.accessToken);
    if (result.refreshToken != null) {
      await _secureStorage.writeString(_keyRefresh, result.refreshToken!);
    }
    await _secureStorage.writeString(_keyUserId, result.userId);
    await _secureStorage.writeString(_keyEmail, result.email);
  }

  Future<void> _clearSession() async {
    await _secureStorage.remove(_keyAccess);
    await _secureStorage.remove(_keyRefresh);
    await _secureStorage.remove(_keyUserId);
    await _secureStorage.remove(_keyEmail);
    isLoggedIn.value = false;
    accessToken.value = '';
    currentUser.value = null;
  }

  bool get isAuthenticated => isLoggedIn.value && accessToken.value.isNotEmpty;

  Future<void> clearSession() => _clearSession();

  Future<void> setExternalSession({
    required String accessTokenValue,
    String? refreshTokenValue,
    required String userId,
    required String email,
  }) async {
    if (accessTokenValue.isEmpty || userId.isEmpty) return;
    final result = AuthResult(
      accessToken: accessTokenValue,
      refreshToken: refreshTokenValue,
      userId: userId,
      email: email,
    );
    await _saveSession(result);
    _setLoggedIn(accessTokenValue, userId, email);
  }

  Future<AuthResult> ensureBackendAccountSession({
    required String email,
    required String password,
  }) async {
    await _restoreSession();
    final currentEmail = currentUser.value?.email.trim().toLowerCase();
    final expectedEmail = email.trim().toLowerCase();
    final token = accessToken.value.trim();
    if (currentEmail == expectedEmail &&
        token.isNotEmpty &&
        !_isTokenExpired(token)) {
      return AuthResult(
        accessToken: token,
        refreshToken: await _secureStorage.readString(_keyRefresh),
        userId: currentUser.value?.id ?? '',
        email: currentUser.value?.email ?? email,
      );
    }

    final result = await _service.signIn(email, password);
    await _saveSession(result);
    _setLoggedIn(result.accessToken, result.userId, result.email);
    return result;
  }

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _bridgeFirebaseUser(nextRoute: '/satellite/shell');
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } on SatelliteApiException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      errorMessage.value = 'Login failed. Check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> signup(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _bridgeFirebaseUser(nextRoute: '/satellite/draw-polygon');
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } on SatelliteApiException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      errorMessage.value = 'Signup failed. Check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> signInWithGoogle({String nextRoute = '/satellite/shell'}) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final provider = firebase.GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      if (kIsWeb) {
        await _firebaseAuth.signInWithPopup(provider);
      } else {
        await _firebaseAuth.signInWithProvider(provider);
      }
      await _bridgeFirebaseUser(nextRoute: nextRoute);
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } on SatelliteApiException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Could not sign in with Google.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> sendPhoneOtp(String phone) async {
    final formatted = _formatPhoneForOtp(phone);
    if (formatted == null) {
      errorMessage.value = 'Enter a valid mobile number.';
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      if (kIsWeb) {
        _phoneConfirmationResult = await _firebaseAuth.signInWithPhoneNumber(
          formatted,
        );
        pendingPhoneOtp.value = formatted;
      } else {
        final completer = Completer<bool>();
        await _firebaseAuth.verifyPhoneNumber(
          phoneNumber: formatted,
          timeout: const Duration(seconds: 60),
          forceResendingToken: _phoneResendToken,
          verificationCompleted: (credential) async {
            try {
              await _firebaseAuth.signInWithCredential(credential);
              pendingPhoneOtp.value = '';
              if (!completer.isCompleted) completer.complete(true);
            } catch (_) {
              if (!completer.isCompleted) completer.complete(false);
            }
          },
          verificationFailed: (e) {
            errorMessage.value = _firebaseAuthErrorMessage(e);
            if (!completer.isCompleted) completer.complete(false);
          },
          codeSent: (verificationId, resendToken) {
            _phoneVerificationId = verificationId;
            _phoneResendToken = resendToken;
            pendingPhoneOtp.value = formatted;
            if (!completer.isCompleted) completer.complete(true);
          },
          codeAutoRetrievalTimeout: (verificationId) {
            _phoneVerificationId = verificationId;
          },
        );
        final signedIn = await completer.future.timeout(
          const Duration(seconds: 20),
          onTimeout: () => false,
        );
        if (signedIn && _firebaseAuth.currentUser != null) {
          await _bridgeFirebaseUser(
            nextRoute: '/satellite/shell',
            fallbackEmail: formatted,
          );
          return;
        }
      }
      Get.snackbar(
        'OTP sent',
        'Enter the SMS code sent to $formatted.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } catch (_) {
      errorMessage.value = 'Could not send SMS code.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> verifyPhoneOtp(
    String phone,
    String token, {
    String nextRoute = '/satellite/shell',
  }) async {
    final formatted = _formatPhoneForOtp(phone) ?? pendingPhoneOtp.value;
    final cleanToken = token.trim();
    if (formatted.isEmpty || cleanToken.length < 4) {
      errorMessage.value = 'Enter the SMS code.';
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      if (kIsWeb) {
        final confirmation = _phoneConfirmationResult;
        if (confirmation == null) {
          errorMessage.value = 'Send the SMS code first.';
          return;
        }
        await confirmation.confirm(cleanToken);
      } else {
        final verificationId = _phoneVerificationId;
        if (verificationId == null) {
          errorMessage.value = 'Send the SMS code first.';
          return;
        }
        final credential = firebase.PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: cleanToken,
        );
        await _firebaseAuth.signInWithCredential(credential);
      }
      pendingPhoneOtp.value = '';
      await _bridgeFirebaseUser(nextRoute: nextRoute, fallbackEmail: formatted);
    } on firebase.FirebaseAuthException catch (e) {
      errorMessage.value = _firebaseAuthErrorMessage(e);
    } on SatelliteApiException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Could not verify SMS code.';
    } finally {
      isLoading.value = false;
    }
  }

  String? _formatPhoneForOtp(String phone) {
    final trimmed = phone.trim();
    if (trimmed.startsWith('+') && trimmed.length >= 8) return trimmed;
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return '+91$digits';
    if (digits.length > 10 && digits.length <= 15) return '+$digits';
    return null;
  }

  Future<void> _bridgeFirebaseUser({
    required String nextRoute,
    String? fallbackEmail,
  }) async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      throw StateError('Firebase sign in did not return a user.');
    }
    await firebaseUser.getIdToken(true);

    final backendEmail = RuntimeConfig.backendAuthEmail.trim();
    final backendPassword = RuntimeConfig.backendAuthPassword.trim();
    if (backendEmail.isEmpty || backendPassword.isEmpty) {
      throw SatelliteApiException(
        'Backend auth account is not configured. Set BACKEND_AUTH_PASSWORD for jashvinu@wrkfarm.com.',
        code: 'backend_auth_not_configured',
      );
    }

    await ensureBackendAccountSession(
      email: backendEmail,
      password: backendPassword,
    );
    Get.offAllNamed(nextRoute);
  }

  String _firebaseAuthErrorMessage(firebase.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'This email already has a Firebase account.';
      case 'weak-password':
        return 'Use a stronger password.';
      case 'invalid-phone-number':
        return 'Enter a valid mobile number.';
      case 'invalid-verification-code':
        return 'Enter the correct SMS verification code.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'quota-exceeded':
        return 'SMS verification quota is exhausted for now.';
      case 'popup-closed-by-user':
        return 'Google sign in was cancelled.';
      default:
        return e.message ?? 'Firebase authentication failed.';
    }
  }

  Future<bool> ensureAnonymousFarmerSession({
    required String phone,
    required String farmerId,
    required String farmerName,
  }) async {
    if (isAuthenticated) {
      await _service.upsertFarmerPhoneProfile(
        userId: currentUser.value?.id ?? '',
        phone: phone,
        farmerId: farmerId,
        farmerName: farmerName,
        jwt: accessToken.value,
      );
      return true;
    }
    try {
      final result = await _service.signInAnonymously(
        metadata: {
          'role': 'verified_farmer',
          'phone': phone,
          'farmer_id': farmerId,
          'farmer_name': farmerName,
        },
      );
      if (result.accessToken.isEmpty) return false;
      await _saveSession(result);
      _setLoggedIn(result.accessToken, result.userId, result.email);
      await _service.upsertFarmerPhoneProfile(
        userId: result.userId,
        phone: phone,
        farmerId: farmerId,
        farmerName: farmerName,
        jwt: result.accessToken,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    await _firebaseAuth.signOut();
    await _clearSession();
    // Also clear satellite-related GetX controllers
    if (Get.isRegistered<dynamic>(tag: 'farm')) {
      Get.delete<dynamic>(tag: 'farm');
    }
    Get.offAllNamed('/login');
  }
}
