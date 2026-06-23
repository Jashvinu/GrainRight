import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'config/theme.dart';
import 'controllers/connectivity_sync_controller.dart';
import 'controllers/survey_controller.dart';
import 'controllers/language_controller.dart';
import 'controllers/main_auth_controller.dart';
import 'controllers/auth_controller.dart';
import 'controllers/farm_controller.dart';
import 'controllers/satellite_controller.dart';
import 'screens/splash_screen.dart';
import 'screens/farmer_home_screen.dart';
import 'screens/farmer_login_screen.dart';
import 'screens/farmer_signup_screen.dart';
import 'screens/fpc_login_screen.dart';
import 'screens/fpo_farmer_qr_scan_screen.dart';
import 'screens/fpo_grading_review_screen.dart';
import 'screens/fpo_home_screen.dart';
import 'screens/fpo_receiver_screen.dart';
import 'screens/harvest_qr_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/public_trace_screen.dart';
import 'screens/home_screen.dart';
import 'screens/survey_form_screen.dart';
import 'screens/farmer_ai_chat_screen.dart';
import 'screens/farmer_ai_grading_screen.dart';
import 'screens/main_login_screen.dart';
import 'screens/chatbot_survey_screen.dart';
import 'screens/diagnostics_home_screen.dart';
import 'screens/offline_maps_screen.dart';
import 'screens/satellite/draw_polygon_screen.dart';
import 'screens/satellite/login_screen.dart';
import 'screens/satellite/satellite_shell.dart';
import 'screens/satellite/signup_screen.dart';

class KalsubaiFarmsApp extends StatelessWidget {
  final Locale initialLocale;
  final bool loadStartupControllers;

  const KalsubaiFarmsApp({
    super.key,
    this.initialLocale = const Locale('en'),
    this.loadStartupControllers = true,
  });

  void _ensureSatelliteAuth() {
    if (!Get.isRegistered<AuthController>()) {
      Get.put(AuthController());
    }
  }

  void _ensureSatelliteFarm() {
    if (!Get.isRegistered<FarmController>()) {
      Get.put(FarmController());
    }
  }

  void _ensureSatelliteMonitoring() {
    if (!Get.isRegistered<SatelliteController>()) {
      Get.put(SatelliteController());
    }
  }

  void _bindSatelliteAuth() {
    _ensureSatelliteAuth();
  }

  void _bindSatelliteFarmFlow() {
    _ensureSatelliteAuth();
    _ensureSatelliteFarm();
  }

  void _bindSatelliteShell() {
    _ensureSatelliteAuth();
    _ensureSatelliteFarm();
    _ensureSatelliteMonitoring();
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Kalsubai Farms',
      theme: AppTheme.theme,
      locale: initialLocale,
      fallbackLocale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('hi'), Locale('mr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      initialBinding: BindingsBuilder(() {
        Get.put(LanguageController());
        if (loadStartupControllers) {
          Get.put(SurveyController());
          Get.put(ConnectivitySyncController());
        }
        Get.put(MainAuthController());
      }),
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/login', page: () => const MainLoginScreen()),
        GetPage(name: '/farmer/login', page: () => const FarmerLoginScreen()),
        GetPage(name: '/farmer/signup', page: () => const FarmerSignupScreen()),
        GetPage(name: '/fpc/login', page: () => const FpcLoginScreen()),
        GetPage(
          name: '/farmer',
          page: () => const FarmerHomeScreen(),
          binding: BindingsBuilder(_bindSatelliteFarmFlow),
        ),
        GetPage(
          name: '/farmer/ai-chat',
          page: () => const FarmerAiChatScreen(),
          binding: BindingsBuilder(_bindSatelliteFarmFlow),
        ),
        GetPage(
          name: '/farmer/ai-grading',
          page: () => const FarmerAiGradingScreen(),
        ),
        GetPage(
          name: '/farmer/harvest-qr',
          page: () => const HarvestQrScreen(),
        ),
        GetPage(name: '/fpo', page: () => const FpoHomeScreen()),
        GetPage(
          name: '/fpo/scan-farmer',
          page: () => const FpoFarmerQrScanScreen(),
        ),
        GetPage(
          name: '/fpo/grading-review',
          page: () => const FpoGradingReviewScreen(),
        ),
        GetPage(
          name: '/fpo/grain-grading',
          page: () => const FarmerAiGradingScreen(),
        ),
        GetPage(
          name: '/fpo/receiver',
          page: () => const FpoReceiverScreen(),
        ),
        GetPage(
          name: '/trace/:token',
          page: () => const PublicTraceScreen(),
        ),
        GetPage(name: '/home', page: () => const LandingScreen()),
        GetPage(name: '/surveys', page: () => const HomeScreen()),
        GetPage(name: '/form', page: () => const ChatbotSurveyScreen()),
        GetPage(name: '/form/classic', page: () => const SurveyFormScreen()),
        GetPage(
          name: '/diagnostics',
          page: () => const DiagnosticsHomeScreen(),
        ),
        GetPage(name: '/offline-maps', page: () => const OfflineMapsScreen()),
        GetPage(
          name: '/satellite/login',
          page: () => const LoginScreen(),
          binding: BindingsBuilder(_bindSatelliteAuth),
        ),
        GetPage(
          name: '/satellite/signup',
          page: () => const SignupScreen(),
          binding: BindingsBuilder(_bindSatelliteAuth),
        ),
        GetPage(
          name: '/satellite/draw-polygon',
          page: () => const DrawPolygonScreen(),
          binding: BindingsBuilder(_bindSatelliteFarmFlow),
        ),
        GetPage(
          name: '/satellite/shell',
          page: () => const SatelliteShell(),
          binding: BindingsBuilder(_bindSatelliteShell),
        ),
      ],
    );
  }
}
