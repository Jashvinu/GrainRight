import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MainAuthController extends GetxController {
  final _auth = Supabase.instance.client.auth;

  final isLoggedIn = false.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    isLoggedIn.value = _auth.currentSession != null;
    _auth.onAuthStateChange.listen((data) {
      isLoggedIn.value = data.session != null;
    });
  }

  bool get isAuthenticated => _auth.currentSession != null;

  String? get userEmail => _auth.currentUser?.email;

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _auth.signInWithPassword(email: email, password: password);
      Get.offAllNamed('/home');
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Login failed. Check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> signup(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final res = await _auth.signUp(email: email, password: password);
      if (res.session != null) {
        Get.offAllNamed('/home');
      } else {
        Get.snackbar(
          'Check your email',
          'We sent a confirmation link to $email',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Signup failed. Check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    Get.offAllNamed('/login');
  }
}
