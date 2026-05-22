import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'survey_controller.dart';

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
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;
  String? get userEmail => _auth.currentUser?.email;

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _auth.signInWithPassword(email: email, password: password);
      await _afterSignIn();
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Login failed. Check your connection.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> continueAsGuest() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _auth.signInAnonymously();
      await _afterSignIn();
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = 'Could not continue as guest.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _afterSignIn() async {
    if (Get.isRegistered<SurveyController>()) {
      await Get.find<SurveyController>().loadSurveys();
    }
    Get.offAllNamed('/home');
  }

  Future<void> logout() async {
    await _auth.signOut();
    Get.offAllNamed('/login');
  }
}
