import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/config/supabase_config.dart';
import 'package:kalsubai_farms/controllers/main_auth_controller.dart';
import 'package:kalsubai_farms/screens/farmer_home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  });

  tearDown(() async {
    Get.reset();
  });

  for (final device in <({Size size, double textScale, String name})>[
    (size: const Size(320, 568), textScale: 1, name: 'compact phone'),
    (size: const Size(360, 640), textScale: 2, name: 'large text phone'),
    (size: const Size(800, 1280), textScale: 1, name: 'tablet'),
  ]) {
    testWidgets('farmer dashboard has no layout exceptions on ${device.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = device.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Get.put<MainAuthController>(MainAuthController());

      await tester.pumpWidget(
        GetMaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: device.size,
              textScaler: TextScaler.linear(device.textScale),
            ),
            child: const FarmerHomeScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      for (var second = 0; second < 8; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
    });
  }
}
