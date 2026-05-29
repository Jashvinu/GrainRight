import 'package:flutter/services.dart';

class RuntimeConfig {
  static const _channel = MethodChannel('grainright.wrkfarm/config');
  static const _googleMapsApiKeyFallback = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );
  static const mapTilerApiKey = String.fromEnvironment('MAPTILER_API_KEY');
  static const onlineBaseTileUrlTemplate = String.fromEnvironment(
    'ONLINE_BASE_TILE_URL_TEMPLATE',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  static const _onlineSatelliteTileUrlTemplate = String.fromEnvironment(
    'ONLINE_SATELLITE_TILE_URL_TEMPLATE',
  );
  static const offlineTileUrlTemplate = String.fromEnvironment(
    'OFFLINE_TILE_URL_TEMPLATE',
  );
  static const offlineTileSourceLabel = String.fromEnvironment(
    'OFFLINE_TILE_SOURCE_LABEL',
    defaultValue: 'self-hosted India OSM tiles',
  );

  static String get onlineSatelliteTileUrlTemplate {
    final override = _onlineSatelliteTileUrlTemplate.trim();
    if (override.isNotEmpty) return override;
    if (mapTilerApiKey.trim().isNotEmpty) {
      return 'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}.jpg?key=$mapTilerApiKey';
    }
    return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  }

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
