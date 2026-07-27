import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/config/supabase_config.dart';
import 'package:kalsubai_farms/controllers/language_controller.dart';
import 'package:kalsubai_farms/controllers/main_auth_controller.dart';
import 'package:kalsubai_farms/screens/main_login_screen.dart';
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

  tearDown(Get.reset);

  for (final device in <({Size size, double textScale, String name})>[
    (size: const Size(320, 568), textScale: 1, name: 'compact phone'),
    (size: const Size(360, 640), textScale: 2, name: 'large text phone'),
    (size: const Size(800, 1280), textScale: 1, name: 'tablet'),
  ]) {
    testWidgets('role selection is responsive on ${device.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = device.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Get.put<LanguageController>(_StaticLanguageController());
      Get.put(MainAuthController());

      await tester.pumpWidget(
        GetMaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: device.size,
              textScaler: TextScaler.linear(device.textScale),
            ),
            child: const MainLoginScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

class _StaticLanguageController extends LanguageController {
  @override
  // Avoid an asynchronous Get.updateLocale call crossing test fake clocks.
  // ignore: must_call_super
  void onInit() {}
}
