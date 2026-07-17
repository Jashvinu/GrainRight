import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/services/farm_status_notification_service.dart';
import 'package:kalsubai_farms/services/local_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('grainright.wrkfarm/notifications');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('farmer alert posts exactly one Android tray notification', () async {
    final shown = await LocalNotificationService().showFarmerNotification(
      FarmerNotification(
        id: 'notification-1',
        farmerId: 'farmer-1',
        farmId: 'farm-1',
        type: 'farm_status_update',
        title: 'Farm status updated',
        message: 'The farm status was saved.',
        farmName: 'North Farm',
        createdAt: DateTime(2026, 7, 15),
        readAt: null,
      ),
    );

    expect(shown, isTrue);
    expect(calls.map((call) => call.method), [
      'requestPermission',
      'showNotification',
    ]);
    expect(
      calls.where((call) => call.method == 'showNotification'),
      hasLength(1),
    );
  });
}
