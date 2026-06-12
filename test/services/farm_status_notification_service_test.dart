import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kalsubai_farms/services/farm_status_notification_service.dart';

void main() {
  test('returns true when farm status notify function acknowledges', () async {
    final service = FarmStatusNotificationService(
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/functions/v1/farm-status-notify'));
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.body, contains('farm_status_update'));
        return http.Response('{"success":true,"delivered":true}', 200);
      }),
    );

    final ok = await service.sendFarmStatusNotification(
      farmerId: 'FMR-1',
      farmerName: 'Test Farmer',
      farmName: 'Test Farm',
      crop: 'Millet',
      variety: 'Local',
      location: 'Kalsubai',
      stage: 'Vegetative',
      stageQuestion: 'How is the crop?',
      daysAfterSowing: 32,
      statusText: 'Healthy crop',
    );

    expect(ok, isTrue);
  });

  test('returns false when farm status notify function is missing', () async {
    final service = FarmStatusNotificationService(
      client: MockClient((_) async {
        return http.Response('{"code":"NOT_FOUND"}', 404);
      }),
    );

    final ok = await service.sendFarmStatusNotification(
      farmerId: 'FMR-1',
      farmerName: 'Test Farmer',
      farmName: 'Test Farm',
      crop: 'Millet',
      variety: 'Local',
      location: 'Kalsubai',
      stage: 'Vegetative',
      stageQuestion: 'How is the crop?',
      daysAfterSowing: 32,
      statusText: 'Healthy crop',
    );

    expect(ok, isFalse);
  });
}
