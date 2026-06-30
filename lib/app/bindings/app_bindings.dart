import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/connectivity_sync_controller.dart';
import '../../controllers/farm_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/main_auth_controller.dart';
import '../../controllers/satellite_controller.dart';
import '../../controllers/stakeholder_controller.dart';
import '../../controllers/survey_controller.dart';

class StartupBinding extends Bindings {
  final bool loadStartupControllers;

  StartupBinding({required this.loadStartupControllers});

  @override
  void dependencies() {
    Get.put(LanguageController());
    if (loadStartupControllers) {
      Get.put(SurveyController());
      Get.put(ConnectivitySyncController());
    }
    Get.put(MainAuthController());
  }
}

class AppBindings {
  const AppBindings._();

  static void ensureSatelliteAuth() {
    if (!Get.isRegistered<AuthController>()) {
      Get.put(AuthController());
    }
  }

  static void ensureSatelliteFarm() {
    if (!Get.isRegistered<FarmController>()) {
      Get.put(FarmController());
    }
  }

  static void ensureSatelliteMonitoring() {
    if (!Get.isRegistered<SatelliteController>()) {
      Get.put(SatelliteController());
    }
  }

  static void bindSatelliteAuth() {
    ensureSatelliteAuth();
  }

  static void bindSatelliteFarmFlow() {
    ensureSatelliteAuth();
    ensureSatelliteFarm();
  }

  static void bindSatelliteShell() {
    ensureSatelliteAuth();
    ensureSatelliteFarm();
    ensureSatelliteMonitoring();
  }

  static void bindStakeholder() {
    if (!Get.isRegistered<StakeholderController>()) {
      Get.put(StakeholderController());
    }
  }
}
