import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'config/runtime_config.dart';
import 'config/supabase_config.dart';
import 'services/offline_map_download_manager.dart';
import 'services/local_notification_service.dart';
import 'services/push_notification_service.dart';
import 'app.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    PushNotificationService.registerBackgroundHandler();
    _installGlobalErrorHandlers();
    runApp(const _StartupLoadingApp());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_completeProductionBootstrap());
    });
  }, _reportUncaughtError);
}

Future<void> _completeProductionBootstrap() async {
  final bootstrap = await _bootstrapProductionApp();
  if (bootstrap.supabaseReady) {
    runApp(KalsubaiFarmsApp(initialLocale: bootstrap.locale));
    _deferPlatformServicesBootstrap();
  } else {
    runApp(_StartupRecoveryApp(initialLocale: bootstrap.locale));
  }
}

void _installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
    _reportUncaughtError(details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _reportUncaughtError(error, stack);
    return true;
  };
}

void _reportUncaughtError(Object error, StackTrace? stack) {
  if (kDebugMode) {
    debugPrint('Unhandled app error: $error');
    if (stack != null) debugPrintStack(stackTrace: stack);
  }
}

Future<_BootstrapResult> _bootstrapProductionApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dateFormattingFuture = _initializeDateFormattingSafely();
  final localeFuture = _loadInitialLocale();

  try {
    await RuntimeConfig.initialize();
  } catch (error, stack) {
    _reportUncaughtError(error, stack);
  }

  var supabaseReady = true;
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  } catch (error, stack) {
    supabaseReady = false;
    _reportUncaughtError(error, stack);
  }

  await dateFormattingFuture;
  final locale = await localeFuture;

  return _BootstrapResult(locale: locale, supabaseReady: supabaseReady);
}

Future<void> _initializeDateFormattingSafely() async {
  try {
    await initializeDateFormatting();
  } catch (error, stack) {
    _reportUncaughtError(error, stack);
  }
}

Future<Locale> _loadInitialLocale() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return Locale(prefs.getString('app_language') ?? 'en');
  } catch (error, stack) {
    _reportUncaughtError(error, stack);
    return const Locale('en');
  }
}

void _deferPlatformServicesBootstrap() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeDeferredPlatformServices());
  });
}

Future<void> _initializeDeferredPlatformServices() async {
  try {
    await LocalNotificationService.instance.initialize();
  } catch (error, stack) {
    _reportUncaughtError(error, stack);
  }
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Firebase.initializeApp();
    await PushNotificationService.instance.initialize();
  } catch (error, stack) {
    _reportUncaughtError(error, stack);
  }
  await _initializeWorkmanager();
}

Future<void> _initializeWorkmanager() async {
  try {
    await Workmanager().initialize(offlineMapCallbackDispatcher);
  } catch (error, stack) {
    _reportUncaughtError(error, stack);
  }
}

class _BootstrapResult {
  final Locale locale;
  final bool supabaseReady;

  const _BootstrapResult({required this.locale, required this.supabaseReady});
}

class _StartupLoadingApp extends StatelessWidget {
  const _StartupLoadingApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFFAF7F0),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Kalsubai Farms',
                  style: TextStyle(
                    color: Color(0xFF0B5D2A),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 20),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF0B5D2A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupRecoveryApp extends StatelessWidget {
  final Locale initialLocale;

  const _StartupRecoveryApp({required this.initialLocale});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: initialLocale,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: Color(0xFF0B5D2A),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Kalsubai Farms',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _startupRecoveryMessage(initialLocale.languageCode),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _startupRecoveryMessage(String languageCode) {
  return switch (languageCode) {
    'hi' => 'ऐप अभी पूरी तरह शुरू नहीं हो सका। इंटरनेट जांचें और ऐप फिर खोलें।',
    'mr' =>
      'अ‍ॅप सध्या पूर्णपणे सुरू झाले नाही. इंटरनेट तपासा आणि अ‍ॅप पुन्हा उघडा.',
    _ =>
      'The app could not start fully right now. Check your internet connection and open it again.',
  };
}
