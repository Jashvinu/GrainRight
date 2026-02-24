import 'package:flutter_test/flutter_test.dart';
import 'package:millets_now/app.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MilletsNowApp());
    expect(find.text('by wrkFarm'), findsOneWidget);
  });
}
