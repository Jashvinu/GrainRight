import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/screens/farmer_status_chat_screen.dart';

void main() {
  FarmStatusUpdateResult? submittedResult;

  tearDown(() {
    Get.reset();
  });

  Widget statusChat({bool requiresPhoto = false}) {
    return FarmerStatusChatScreen(
      farmName: 'North Field',
      crop: 'Finger Millet',
      variety: 'Brown Top',
      location: 'Rajur, Akole',
      stage: 'Vegetative',
      daysAfterSowing: 42,
      stageQuestion: 'How is crop growth today?',
      priorStatus: 'Irrigation completed',
      weatherSnapshot: const {'rain_24h_mm': 2.4, 'rain_7d_mm': 12.8},
      requiresPhoto: requiresPhoto,
    );
  }

  Widget launcher({bool requiresPhoto = false}) {
    return GetMaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('open-status-chat'),
                onPressed: () async {
                  submittedResult = await Navigator.of(context).push(
                    MaterialPageRoute<FarmStatusUpdateResult>(
                      builder: (_) => statusChat(requiresPhoto: requiresPhoto),
                    ),
                  );
                },
                child: const Text('Open status chat'),
              ),
            ),
          );
        },
      ),
    );
  }

  testWidgets('guided reply returns the status and structured transcript', (
    tester,
  ) async {
    submittedResult = null;
    await tester.pumpWidget(launcher());
    await tester.tap(find.byKey(const ValueKey('open-status-chat')));
    await tester.pumpAndSettle();

    expect(find.text('North Field'), findsWidgets);
    expect(find.byIcon(Icons.psychology_alt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsWidgets);

    final reply = UiStrings.t('status_reply_growth_normal');
    await tester.tap(find.text(reply).first);
    await tester.pumpAndSettle();

    expect(find.text(reply), findsAtLeastNWidgets(2));
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);

    await tester.tap(find.text(UiStrings.t('submit_status')));
    await tester.pumpAndSettle();

    expect(submittedResult, isNotNull);
    expect(submittedResult!.message, reply);
    expect(
      submittedResult!.transcript.any(
        (entry) =>
            entry.role == 'farmer' &&
            entry.source == 'status_chat' &&
            entry.message == reply,
      ),
      isTrue,
    );
    expect(
      submittedResult!.transcript.any(
        (entry) => entry.role == 'assistant' && entry.source == 'status_chat',
      ),
      isTrue,
    );
  });

  testWidgets('required photo blocks submission without an attachment', (
    tester,
  ) async {
    submittedResult = null;
    await tester.pumpWidget(launcher(requiresPhoto: true));
    await tester.tap(find.byKey(const ValueKey('open-status-chat')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Crop is ready for field inspection',
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(UiStrings.t('submit_status')));
    await tester.pump();

    expect(
      find.text(UiStrings.t('attach_photo_before_stage_submit')),
      findsOneWidget,
    );
    expect(find.byType(FarmerStatusChatScreen), findsOneWidget);
    expect(submittedResult, isNull);
  });

  testWidgets('back arrow closes without submitting a status', (tester) async {
    submittedResult = null;
    await tester.pumpWidget(launcher());
    await tester.tap(find.byKey(const ValueKey('open-status-chat')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-status-chat')), findsOneWidget);
    expect(submittedResult, isNull);
  });

  testWidgets('guided chat fits compact phones with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      GetMaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: statusChat(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.text(UiStrings.t('submit_status')), findsOneWidget);
  });
}
