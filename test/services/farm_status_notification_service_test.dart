import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kalsubai_farms/services/farm_status_notification_service.dart';

void main() {
  test(
    'returns notification when farm status notify function acknowledges',
    () async {
      final service = FarmStatusNotificationService(
        client: MockClient((request) async {
          expect(
            request.url.path,
            endsWith('/functions/v1/farm-status-notify'),
          );
          expect(request.headers['Content-Type'], 'application/json');
          expect(request.body, contains('farm_status_update'));
          expect(request.body, contains('farm-1'));
          return http.Response('''
          {
            "success": true,
            "notification": {
              "id": "note-1",
              "farmer_id": "FMR-1",
              "farm_id": "farm-1",
              "type": "farm_status_update",
              "title": "Status saved",
              "message": "Farm status updated",
              "farm_name": "Test Farm",
              "created_at": "2026-06-18T10:00:00.000Z"
            }
          }
          ''', 200);
        }),
      );

      final notification = await service.sendFarmStatusNotification(
        farmerId: 'FMR-1',
        farmerName: 'Test Farmer',
        farmId: 'farm-1',
        farmName: 'Test Farm',
        crop: 'Millet',
        variety: 'Local',
        location: 'Kalsubai',
        stage: 'Vegetative',
        stageQuestion: 'How is the crop?',
        daysAfterSowing: 32,
        statusText: 'Healthy crop',
      );

      expect(notification, isNotNull);
      expect(notification!.id, 'note-1');
      expect(notification.farmId, 'farm-1');
      expect(notification.farmName, 'Test Farm');
    },
  );

  test('creates generic selected farm alert notification', () async {
    final service = FarmStatusNotificationService(
      client: MockClient((request) async {
        expect(request.body, contains('urgent_farm_alert'));
        expect(request.body, contains('farm-2'));
        return http.Response('''
          {
            "success": true,
            "data": {
              "notification": {
                "id": "note-2",
                "farmer_id": "FMR-2",
                "farm_id": "farm-2",
                "type": "urgent_farm_alert",
                "title": "Water stress high",
                "message": "Irrigate in the evening and scout the crop.",
                "farm_name": "Second Farm",
                "created_at": "2026-06-18T11:00:00.000Z"
              }
            }
          }
          ''', 200);
      }),
    );

    final notification = await service.sendFarmAlertNotification(
      farmerId: 'FMR-2',
      farmerName: 'Test Farmer',
      farmerPhone: '9999999999',
      farmId: 'farm-2',
      farmName: 'Second Farm',
      crop: 'Millet',
      variety: 'Local',
      location: 'Kalsubai',
      type: 'urgent_farm_alert',
      title: 'Water stress high',
      message: 'Irrigate in the evening and scout the crop.',
    );

    expect(notification, isNotNull);
    expect(notification!.type, 'urgent_farm_alert');
    expect(notification.farmId, 'farm-2');
  });

  test('creates farm added notification with farmer and farm context', () async {
    final service = FarmStatusNotificationService(
      client: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['action'], 'create');
        expect(payload['type'], 'farm_added');
        expect(payload['farmerId'], 'FMR-3');
        expect(payload['farmerPhone'], '9876543210');
        expect(payload['farmId'], 'farm-3');
        expect(payload['source'], 'farmer_dashboard_add_farm');
        expect(payload['payload'], isA<Map<String, dynamic>>());
        final details = payload['payload'] as Map<String, dynamic>;
        expect(details['crop'], 'Nachani');
        return http.Response('''
          {
            "success": true,
            "data": {
              "notification": {
                "id": "note-farm-added",
                "farmer_id": "FMR-3",
                "farm_id": "farm-3",
                "type": "farm_added",
                "title": "New farm added",
                "message": "New farm is saved and ready.",
                "farm_name": "New Farm",
                "created_at": "2026-06-18T11:30:00.000Z"
              }
            }
          }
          ''', 200);
      }),
    );

    final notification = await service.sendFarmAlertNotification(
      farmerId: 'FMR-3',
      farmerName: 'New Farmer',
      farmerPhone: '9876543210',
      farmId: 'farm-3',
      farmName: 'New Farm',
      crop: 'Nachani',
      variety: 'Local',
      location: 'Kalsubai',
      type: 'farm_added',
      title: 'New farm added',
      message: 'New farm is saved and ready.',
      source: 'farmer_dashboard_add_farm',
      payload: {'crop': 'Nachani'},
    );

    expect(notification, isNotNull);
    expect(notification!.id, 'note-farm-added');
    expect(notification.type, 'farm_added');
    expect(notification.farmId, 'farm-3');
  });

  test('sends farmer auth token for protected notification function', () async {
    final service = FarmStatusNotificationService(
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer farmer-jwt');
        return http.Response('''
          {
            "success": true,
            "notification": {
              "id": "note-auth",
              "farmer_id": "FMR-2",
              "farm_id": "farm-2",
              "type": "farm_status_update",
              "title": "Status saved",
              "message": "Farm status updated",
              "farm_name": "Second Farm",
              "created_at": "2026-06-18T11:15:00.000Z"
            }
          }
          ''', 200);
      }),
    );

    final notification = await service.sendFarmStatusNotification(
      farmerId: 'FMR-2',
      farmerName: 'Test Farmer',
      farmerPhone: '9876543210',
      farmId: 'farm-2',
      farmName: 'Second Farm',
      crop: 'Millet',
      variety: 'Local',
      location: 'Kalsubai',
      stage: 'Vegetative',
      stageQuestion: 'How is the crop?',
      daysAfterSowing: 32,
      statusText: 'Healthy crop',
      authToken: 'farmer-jwt',
    );

    expect(notification, isNotNull);
    expect(notification!.id, 'note-auth');
  });

  test('returns null when farm status notify function is missing', () async {
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

    expect(ok, isNull);
  });

  test('lists notifications with farmer phone fallback', () async {
    final service = FarmStatusNotificationService(
      client: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['action'], 'list');
        expect(payload['farmerId'], 'FMR-1');
        expect(payload['farmerPhone'], '+91 98765 43210');
        return http.Response('''
          {
            "success": true,
            "data": {
              "notifications": [
                {
                  "id": "note-3",
                  "farmer_id": "FMR-OLD",
                  "farm_id": "farm-3",
                  "type": "farm_status_update",
                  "title": "Status saved",
                  "message": "Crop looks healthy",
                  "farm_name": "Phone Farm",
                  "created_at": "2026-06-18T12:00:00.000Z"
                }
              ]
            }
          }
          ''', 200);
      }),
    );

    final items = await service.listNotifications(
      farmerId: 'FMR-1',
      farmerPhone: '+91 98765 43210',
    );

    expect(items, hasLength(1));
    expect(items.single.id, 'note-3');
    expect(items.single.farmName, 'Phone Farm');
  });

  test('marks notification read with farmer phone fallback', () async {
    final service = FarmStatusNotificationService(
      client: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['action'], 'mark_read');
        expect(payload['farmerId'], 'FMR-1');
        expect(payload['farmerPhone'], '9876543210');
        expect(payload['notificationId'], 'note-4');
        return http.Response('''
          {
            "success": true,
            "data": {
              "marked_read": true,
              "notification": {
                "id": "note-4",
                "farmer_id": "FMR-OLD",
                "farm_id": "farm-4",
                "type": "farm_alert",
                "title": "Scout today",
                "message": "Check the north side of the farm.",
                "farm_name": "Phone Farm",
                "created_at": "2026-06-18T12:30:00.000Z",
                "read_at": "2026-06-18T12:31:00.000Z"
              }
            }
          }
          ''', 200);
      }),
    );

    final ok = await service.markNotificationRead(
      farmerId: 'FMR-1',
      farmerPhone: '9876543210',
      notificationId: 'note-4',
    );

    expect(ok, isTrue);
  });
}
