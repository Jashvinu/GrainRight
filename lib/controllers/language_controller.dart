import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageController extends GetxController {
  static const _key = 'app_language';

  /// 'en', 'hi', or 'mr'
  final language = 'en'.obs;

  bool get isMarathi => language.value == 'mr';
  bool get isHindi => language.value == 'hi';

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    language.value = prefs.getString(_key) ?? 'en';
  }

  Future<void> toggle() async {
    language.value = isMarathi ? 'en' : 'mr';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, language.value);
    Get.updateLocale(Locale(language.value));
  }

  Future<void> setLanguage(String value) async {
    if (!{'en', 'hi', 'mr'}.contains(value)) return;
    language.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value);
    Get.updateLocale(Locale(value));
  }

  /// Translate a key using the provided map. Falls back to English value.
  String tr(String englishText, Map<String, String> translations) {
    if (!isMarathi) return englishText;
    return translations[englishText] ?? englishText;
  }
}
