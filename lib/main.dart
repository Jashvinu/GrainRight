import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'config/runtime_config.dart';
import 'config/supabase_config.dart';
import 'services/offline_map_download_manager.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RuntimeConfig.initialize();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Workmanager().initialize(offlineMapCallbackDispatcher);
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  final prefs = await SharedPreferences.getInstance();
  final language = prefs.getString('app_language') ?? 'en';
  runApp(MilletsNowApp(initialLocale: Locale(language)));
}
