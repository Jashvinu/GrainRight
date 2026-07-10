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
  static const _publicTraceBaseUrlFallback = String.fromEnvironment(
    'PUBLIC_TRACE_BASE_URL',
  );
  static const _backendAuthEmailFallback = String.fromEnvironment(
    'BACKEND_AUTH_EMAIL',
    defaultValue: 'jashvinu@wrkfarm.com',
  );
  static const _backendAuthPasswordFallback = String.fromEnvironment(
    'BACKEND_AUTH_PASSWORD',
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
    final localOverride = _localConfigValue(
      'ONLINE_SATELLITE_TILE_URL_TEMPLATE',
    );
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

  static String get publicTraceBaseUrl {
    final fallback = _stripTrailingSlash(_publicTraceBaseUrlFallback.trim());
    if (_isUsable(fallback)) return fallback;
    final local = _stripTrailingSlash(
      _localConfigValue('PUBLIC_TRACE_BASE_URL'),
    );
    return local.isEmpty ? 'https://grainright.app' : local;
  }

  static String publicTraceUrl(String token) {
    return '$publicTraceBaseUrl/#/trace/$token';
  }

  static String get backendAuthEmail {
    final fallback = _backendAuthEmailFallback.trim();
    if (_isUsable(fallback)) return fallback;
    final local = _localConfigValue('BACKEND_AUTH_EMAIL');
    return local.isEmpty ? 'jashvinu@wrkfarm.com' : local;
  }

  static String get backendAuthPassword {
    final fallback = _backendAuthPasswordFallback.trim();
    if (_isUsable(fallback)) return fallback;
    return _localConfigValue('BACKEND_AUTH_PASSWORD');
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

  static String _stripTrailingSlash(String value) {
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  static String _localConfigValue(String key) {
    final value = _localConfig[key]?.trim() ?? '';
    return _isUsable(value) ? value : '';
  }
}
