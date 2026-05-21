import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'config/theme.dart';
import 'controllers/survey_controller.dart';
import 'controllers/language_controller.dart';
import 'controllers/main_auth_controller.dart';
import 'screens/splash_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/home_screen.dart';
import 'screens/survey_form_screen.dart';
import 'screens/main_login_screen.dart';
import 'screens/chatbot_survey_screen.dart';
import 'screens/diagnostics_home_screen.dart';

class MilletsNowApp extends StatelessWidget {
  final Locale initialLocale;
  final bool loadStartupControllers;

  const MilletsNowApp({
    super.key,
    this.initialLocale = const Locale('en'),
    this.loadStartupControllers = true,
  });

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'MilletsNow',
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
        }
        Get.put(MainAuthController());
      }),
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/login', page: () => const MainLoginScreen()),
        GetPage(name: '/home', page: () => const LandingScreen()),
        GetPage(name: '/surveys', page: () => const HomeScreen()),
        GetPage(name: '/form', page: () => const ChatbotSurveyScreen()),
        GetPage(name: '/form/classic', page: () => const SurveyFormScreen()),
        GetPage(
          name: '/diagnostics',
          page: () => const DiagnosticsHomeScreen(),
        ),
      ],
    );
  }
}
