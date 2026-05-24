import 'dart:convert';
import 'package:get/get.dart';
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

  final isLoggedIn = false.obs;
  final currentUser = Rxn<SatelliteUser>();
  final accessToken = ''.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;

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

    if (token.isEmpty) return;

    // Check JWT exp claim
    if (_isTokenExpired(token)) {
      if (refresh.isNotEmpty) {
        final result = await _service.refreshToken(refresh);
        if (result != null && result.accessToken.isNotEmpty) {
          await _saveSession(result);
          _setLoggedIn(result.accessToken, result.userId, result.email);
          return;
        }
      }
      await _clearSession();
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

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await _service.signIn(email, password);
      await _saveSession(result);
      _setLoggedIn(result.accessToken, result.userId, result.email);
      Get.offAllNamed('/satellite/shell');
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
      final result = await _service.signUp(email, password);
      if (result.accessToken.isEmpty) {
        // Email confirmation required
        errorMessage.value = '';
        Get.snackbar(
          'Check your email',
          'We sent a confirmation link to $email',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      await _saveSession(result);
      _setLoggedIn(result.accessToken, result.userId, result.email);
      Get.offAllNamed('/satellite/draw-polygon');
    } on SatelliteApiException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      errorMessage.value = 'Signup failed. Check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    await _clearSession();
    // Also clear satellite-related GetX controllers
    if (Get.isRegistered<dynamic>(tag: 'farm')) {
      Get.delete<dynamic>(tag: 'farm');
    }
    Get.offAllNamed('/home');
  }
}
