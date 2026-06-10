import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kalsubai_farms/config/supabase_config.dart';
import 'package:kalsubai_farms/controllers/survey_controller.dart';
import 'package:kalsubai_farms/models/survey_launch.dart';
import 'package:kalsubai_farms/screens/home_screen.dart';

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

  testWidgets('floating new survey button starts a fresh survey', (
    tester,
  ) async {
    final controller = _FakeSurveyController(hasDraft: false);
    Get.put<SurveyController>(controller);

    SurveyLaunchArgs? capturedArgs;
    await tester.pumpWidget(
      GetMaterialApp(
        home: const HomeScreen(),
        getPages: [
          GetPage(
            name: '/form',
            page: () {
              capturedArgs = SurveyLaunchArgs.from(Get.arguments);
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(capturedArgs?.mode, SurveyLaunchMode.newSurvey);
  });

  testWidgets('unfinished survey tile resumes the saved draft', (tester) async {
    final controller = _FakeSurveyController(hasDraft: true);
    Get.put<SurveyController>(controller);

    SurveyLaunchArgs? capturedArgs;
    await tester.pumpWidget(
      GetMaterialApp(
        home: const HomeScreen(),
        getPages: [
          GetPage(
            name: '/form',
            page: () {
              capturedArgs = SurveyLaunchArgs.from(Get.arguments);
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unfinished survey'));
    await tester.pumpAndSettle();

    expect(capturedArgs?.mode, SurveyLaunchMode.resumeDraft);
  });
}

class _FakeSurveyController extends SurveyController {
  _FakeSurveyController({required bool hasDraft}) {
    isLoading.value = false;
    hasActiveDraft.value = hasDraft;
    surveys.clear();
    pendingSubmissions.clear();
  }

  @override
  Future<void> loadSurveys() async {}

  @override
  Future<void> loadPendingSubmissions() async {}

  @override
  Future<void> refreshDraftState() async {}

  @override
  Future<void> syncPendingSurveys() async {}
}
