import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'farm_status_notification_service.dart';

class LocalNotificationService {
  static const MethodChannel _channel = MethodChannel(
    'grainright.wrkfarm/notifications',
  );

  static final LocalNotificationService instance = LocalNotificationService();

  LocalNotificationService();

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('initialize');
    } on PlatformException catch (error) {
      debugPrint('[LocalNotification] initialize skipped: $error');
    } on MissingPluginException catch (error) {
      debugPrint('[LocalNotification] initialize unavailable: $error');
    }
  }

  Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException catch (error) {
      debugPrint('[LocalNotification] permission skipped: $error');
      return false;
    } on MissingPluginException catch (error) {
      debugPrint('[LocalNotification] permission unavailable: $error');
      return false;
    }
  }

  Future<String?> consumeNotificationPayload() async {
    if (!_isAndroid) return null;
    try {
      final payload = await _channel.invokeMethod<String>(
        'consumeNotificationPayload',
      );
      final text = payload?.trim() ?? '';
      return text.isEmpty ? null : text;
    } on PlatformException catch (error) {
      debugPrint('[LocalNotification] payload skipped: $error');
      return null;
    } on MissingPluginException catch (error) {
      debugPrint('[LocalNotification] payload unavailable: $error');
      return null;
    }
  }

  Future<bool> showFarmerNotification(
    FarmerNotification notification, {
    String? fallbackTitle,
  }) {
    return show(
      id: _stableNotificationId(notification.id),
      title: notification.title.trim().isEmpty
          ? (fallbackTitle ?? '').trim()
          : notification.title,
      message: notification.message,
      payload: notification.id,
      farmName: notification.farmName,
      type: notification.type,
    );
  }

  Future<bool> showFarmAlert({
    required String id,
    required String title,
    required String message,
  }) {
    return show(
      id: _stableNotificationId(id),
      title: title,
      message: message,
      payload: id,
    );
  }

  Future<bool> show({
    required int id,
    required String title,
    required String message,
    String? payload,
    String? farmName,
    String? type,
  }) async {
    if (!_isAndroid) return false;
    final safeTitle = title.trim();
    final safeMessage = message.trim();
    if (safeTitle.isEmpty || safeMessage.isEmpty) return false;

    try {
      final permitted = await requestPermission();
      if (!permitted) return false;
      return await _channel.invokeMethod<bool>('showNotification', {
            'id': id,
            'title': safeTitle,
            'message': safeMessage,
            'payload': payload ?? '',
            'farmName': farmName?.trim() ?? '',
            'type': type?.trim() ?? '',
          }) ??
          false;
    } on PlatformException catch (error) {
      debugPrint('[LocalNotification] show skipped: $error');
      return false;
    } on MissingPluginException catch (error) {
      debugPrint('[LocalNotification] show unavailable: $error');
      return false;
    }
  }

  int _stableNotificationId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0
        ? DateTime.now().millisecondsSinceEpoch & 0x7fffffff
        : hash;
  }
}
