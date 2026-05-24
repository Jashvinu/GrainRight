import 'package:flutter/services.dart';

class RuntimeConfig {
  static const _channel = MethodChannel('grainright.wrkfarm/config');
  static const _googleMapsApiKeyFallback = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );

  static Future<String> googleMapsApiKey() async {
    try {
      final value = await _channel.invokeMethod<String>('googleMapsApiKey');
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty && !trimmed.startsWith(r'$(')) {
        return trimmed;
      }
    } catch (_) {
      // Desktop/tests and older native builds can still use --dart-define.
    }
    return _googleMapsApiKeyFallback;
  }
}
