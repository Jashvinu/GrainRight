import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'config/runtime_config.dart';
import 'config/supabase_config.dart';
import 'services/offline_map_download_manager.dart';
import 'services/local_notification_service.dart';
import 'app.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _installGlobalErrorHandlers();

    final bootstrap = await _bootstrapProductionApp();
    if (bootstrap.supabaseReady) {
      runApp(KalsubaiFarmsApp(initialLocale: bootstrap.locale));
      _deferWorkmanagerBootstrap();
    } else {
      runApp(_StartupRecoveryApp(initialLocale: bootstrap.locale));
    }
  }, _reportUncaughtError);
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

  try {
    await RuntimeConfig.initialize();
  } catch (error, stack) {
    _reportUncaughtError(error, stack);
  }

  try {
    await LocalNotificationService.instance.initialize();
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

  var language = 'en';
  try {
    final prefs = await SharedPreferences.getInstance();
    language = prefs.getString('app_language') ?? 'en';
  } catch (error, stack) {
    _reportUncaughtError(error, stack);
  }

  return _BootstrapResult(
    locale: Locale(language),
    supabaseReady: supabaseReady,
  );
}

void _deferWorkmanagerBootstrap() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeWorkmanager());
  });
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

class _StartupRecoveryApp extends StatelessWidget {
  final Locale initialLocale;

  const _StartupRecoveryApp({required this.initialLocale});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: initialLocale,
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: Color(0xFF0B5D2A),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Kalsubai Farms',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'The app could not start fully right now. Check your internet connection and open it again.',
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
