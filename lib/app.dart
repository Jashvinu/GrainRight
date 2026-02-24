import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'config/theme.dart';
import 'controllers/survey_controller.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/survey_form_screen.dart';

class MilletsNowApp extends StatelessWidget {
  const MilletsNowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'MilletsNow',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      initialBinding: BindingsBuilder(() {
        Get.put(SurveyController());
      }),
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/home', page: () => const HomeScreen()),
        GetPage(name: '/form', page: () => const SurveyFormScreen()),
      ],
    );
  }
}
