import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/controllers/language_controller.dart';
import 'package:kalsubai_farms/widgets/chat/repeat_group_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    Get.put(LanguageController());
  });

  tearDown(Get.reset);

  testWidgets(
    'rice/ragi agronomy hides difference noticed but keeps seedling ready',
    (tester) async {
      await _pumpPracticePrompt(tester, cropRole: 'main');

      expect(find.text('Seedling ready (days)'), findsOneWidget);
      expect(find.text('Difference noticed'), findsNothing);
    },
  );

  testWidgets(
    'bajra/other agronomy hides seedling ready and difference noticed',
    (tester) async {
      await _pumpPracticePrompt(tester, cropRole: 'other');

      expect(find.text('Seedling ready (days)'), findsNothing);
      expect(find.text('Difference noticed'), findsNothing);
    },
  );

  testWidgets('main crop yearly form shows yield average per acre', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepeatGroupPrompt(
              groupKey: 'main_crop_yearly',
              title: 'Main crop production history',
              onDone: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yield (average per acre)'), findsNWidgets(3));
  });
}

Future<void> _pumpPracticePrompt(
  WidgetTester tester, {
  required String cropRole,
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RepeatGroupPrompt(
            groupKey: 'crop_practices',
            title: 'Crop practices',
            cropRole: cropRole,
            onDone: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final next = find.widgetWithText(ElevatedButton, 'Next');
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pumpAndSettle();
}
