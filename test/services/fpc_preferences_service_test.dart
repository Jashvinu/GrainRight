import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/services/fpc_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads farmer-service defaults', () async {
    final preferences = await FpcPreferences.load();

    expect(preferences.autoRefreshLedgers, isTrue);
    expect(preferences.reviewQueueAlerts, isTrue);
    expect(preferences.marketplaceInterestAlerts, isTrue);
    expect(preferences.scannerSoundFeedback, isFalse);
  });

  test('persists all workspace preferences', () async {
    await const FpcPreferences(
      autoRefreshLedgers: false,
      reviewQueueAlerts: false,
      marketplaceInterestAlerts: false,
      scannerSoundFeedback: true,
    ).save();

    final restored = await FpcPreferences.load();
    expect(restored.autoRefreshLedgers, isFalse);
    expect(restored.reviewQueueAlerts, isFalse);
    expect(restored.marketplaceInterestAlerts, isFalse);
    expect(restored.scannerSoundFeedback, isTrue);
  });
}
