import 'package:flutter/services.dart';

import 'runtime_local_config.dart';

class RuntimeConfig {
  static const _defaultOfflineTileSourceLabel = 'Configured field imagery';
  static const _defaultOnlineFieldTileUrlTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _channel = MethodChannel('grainright.wrkfarm/config');
  static const _mapTilerApiKeyFallback = String.fromEnvironment(
    'MAPTILER_API_KEY',
  );
  static const onlineBaseTileUrlTemplate = String.fromEnvironment(
    'ONLINE_BASE_TILE_URL_TEMPLATE',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  static const _onlineSatelliteTileUrlTemplate = String.fromEnvironment(
    'ONLINE_SATELLITE_TILE_URL_TEMPLATE',
  );
  static const _offlineTileUrlTemplateFallback = String.fromEnvironment(
    'OFFLINE_TILE_URL_TEMPLATE',
  );
  static const _offlineTileSourceLabelFallback = String.fromEnvironment(
    'OFFLINE_TILE_SOURCE_LABEL',
  );

  static Map<String, String> _localConfig = const {};

  static Future<void> initialize() async {
    _localConfig = await loadRuntimeLocalConfig();
  }

  static String get mapTilerApiKey {
    final fallback = _mapTilerApiKeyFallback.trim();
    if (fallback.isNotEmpty) return fallback;
    return _localConfigValue('MAPTILER_API_KEY');
  }

  static String get offlineTileUrlTemplate {
    final override = _offlineTileUrlTemplateFallback.trim();
    if (_isUsable(override)) return override;
    final apiKey = mapTilerApiKey;
    if (apiKey.isNotEmpty) return mapTilerHybridTileUrlTemplate(apiKey);
    return '';
  }

  static String get offlineTileSourceLabel {
    final label = _offlineTileSourceLabelFallback.trim();
    if (_isUsable(label)) return label;
    if (_isMapTilerTemplate(offlineTileUrlTemplate)) {
      return 'MapTiler Hybrid tiles';
    }
    return _defaultOfflineTileSourceLabel;
  }

  static String get onlineSatelliteTileUrlTemplate {
    final override = _onlineSatelliteTileUrlTemplate.trim();
    if (_isUsable(override)) return override;
    final localOverride = _localConfigValue('ONLINE_SATELLITE_TILE_URL_TEMPLATE');
    if (localOverride.isNotEmpty) return localOverride;
    final apiKey = mapTilerApiKey;
    if (apiKey.isNotEmpty) {
      return mapTilerHybridTileUrlTemplate(apiKey);
    }
    return _defaultOnlineFieldTileUrlTemplate;
  }

  static String mapTilerHybridTileUrlTemplate(String apiKey) {
    return 'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}@2x.jpg?key=$apiKey';
  }

  static Future<String> mapTilerApiKeyRuntime() {
    return _runtimeString(
      'mapTilerApiKey',
      _mapTilerApiKeyFallback,
      envKey: 'MAPTILER_API_KEY',
    );
  }

  static Future<String> offlineTileUrlTemplateRuntime() async {
    final template = await _runtimeString(
      'offlineTileUrlTemplate',
      _offlineTileUrlTemplateFallback,
      envKey: 'OFFLINE_TILE_URL_TEMPLATE',
    );
    if (template.isNotEmpty) return template;

    final apiKey = await mapTilerApiKeyRuntime();
    if (apiKey.isNotEmpty) return mapTilerHybridTileUrlTemplate(apiKey);
    return '';
  }

  static Future<String> offlineTileSourceLabelRuntime() async {
    final label = await _runtimeString(
      'offlineTileSourceLabel',
      _offlineTileSourceLabelFallback,
      envKey: 'OFFLINE_TILE_SOURCE_LABEL',
    );
    if (label.isNotEmpty) return label;

    final template = await offlineTileUrlTemplateRuntime();
    if (_isMapTilerTemplate(template)) return 'MapTiler Hybrid tiles';
    return _defaultOfflineTileSourceLabel;
  }

  static Future<String> _runtimeString(
    String method,
    String fallback, {
    required String envKey,
  }) async {
    try {
      final value = await _channel.invokeMethod<String>(method);
      final trimmed = value?.trim() ?? '';
      if (_isUsable(trimmed)) {
        return trimmed;
      }
    } catch (_) {
      // Desktop/tests and older native builds can still use --dart-define.
    }
    final trimmedFallback = fallback.trim();
    if (_isUsable(trimmedFallback)) return trimmedFallback;
    return _localConfigValue(envKey);
  }

  static bool _isUsable(String value) {
    return value.isNotEmpty && !value.startsWith(r'$(');
  }

  static bool _isMapTilerTemplate(String template) {
    return template.contains('api.maptiler.com');
  }

  static String _localConfigValue(String key) {
    final value = _localConfig[key]?.trim() ?? '';
    return _isUsable(value) ? value : '';
  }
}
