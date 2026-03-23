import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'config/theme.dart';
import 'controllers/survey_controller.dart';
import 'controllers/auth_controller.dart';
import 'controllers/farm_controller.dart';
import 'controllers/satellite_controller.dart';
import 'screens/splash_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/home_screen.dart';
import 'screens/survey_form_screen.dart';
import 'screens/satellite/login_screen.dart';
import 'screens/satellite/signup_screen.dart';
import 'screens/satellite/draw_polygon_screen.dart';
import 'screens/satellite/satellite_shell.dart';

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
        Get.put(AuthController());
      }),
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const SplashScreen()),
        GetPage(name: '/home', page: () => const LandingScreen()),
        GetPage(name: '/surveys', page: () => const HomeScreen()),
        GetPage(name: '/form', page: () => const SurveyFormScreen()),

        // Satellite — unauthenticated
        GetPage(name: '/satellite/login', page: () => const LoginScreen()),
        GetPage(name: '/satellite/signup', page: () => const SignupScreen()),

        // Satellite — authenticated
        GetPage(
          name: '/satellite/draw-polygon',
          page: () => const DrawPolygonScreen(),
          binding: BindingsBuilder(() {
            if (!Get.isRegistered<FarmController>()) {
              Get.put(FarmController());
            }
          }),
        ),
        GetPage(
          name: '/satellite/shell',
          page: () => const SatelliteShell(),
          binding: BindingsBuilder(() {
            if (!Get.isRegistered<FarmController>()) {
              Get.put(FarmController());
            }
            if (!Get.isRegistered<SatelliteController>()) {
              Get.put(SatelliteController());
            }
          }),
        ),
      ],
    );
  }
}
