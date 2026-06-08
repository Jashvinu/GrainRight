import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kalsubai_farms/app.dart';
import 'package:kalsubai_farms/config/supabase_config.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  });

  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const KalsubaiFarmsApp(loadStartupControllers: false),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.byType(GetMaterialApp), findsOneWidget);
  });
}
