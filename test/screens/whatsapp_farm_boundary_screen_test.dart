import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/screens/whatsapp_farm_boundary_screen.dart';

void main() {
  setUp(() => Get.testMode = true);

  testWidgets('invalid WhatsApp boundary links show a clear recovery state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const GetMaterialApp(home: WhatsappFarmBoundaryScreen(token: 'invalid')),
    );

    expect(
      find.textContaining('WhatsApp boundary link is invalid'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('whatsapp_saved_farm_map')), findsNothing);
  });
}
