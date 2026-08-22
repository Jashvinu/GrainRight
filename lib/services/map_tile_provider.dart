import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/runtime_config.dart';
import 'local_app_database.dart';
import 'network_status_service.dart';

String get fieldImageryTileUrl {
  final satellite = RuntimeConfig.onlineSatelliteTileUrlTemplate.trim();
  return satellite.isNotEmpty ? satellite : openStreetMapTileUrl;
}

const String openStreetMapTileUrl = RuntimeConfig.onlineBaseTileUrlTemplate;
const String fieldRoadsTileUrl =
    'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}';
const String fieldPlacesTileUrl =
    'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';
const int mapTileMaxNativeZoom = 20;
const int fieldImageryMaxNativeZoom = 18;
const int fieldReferenceMaxNativeZoom = 19;
const double mapTileMinZoom = 3;
const double mapTileMaxZoom = 20;

List<Widget> fieldImageryTileLayers({
  String? urlTemplate,
  String? offlineUrlTemplateOverride,
  int? maxOfflineNativeZoom,
  bool includeReferenceLabels = true,
  int keepBuffer = 2,
  int panBuffer = 1,
  TileDisplay tileDisplay = const TileDisplay.fadeIn(),
}) {
  final imageryTemplate = (urlTemplate?.trim().isNotEmpty ?? false)
      ? urlTemplate!.trim()
      : fieldImageryTileUrl;
  return [
    OfflineAwareTileLayer(
      key: const ValueKey('field-imagery-base-layer'),
      urlTemplate: imageryTemplate,
      offlineUrlTemplateOverride: offlineUrlTemplateOverride,
      maxNativeZoom: fieldImageryMaxNativeZoom,
      maxOfflineNativeZoom: maxOfflineNativeZoom,
      fallbackUrlTemplate: openStreetMapTileUrl,
      keepBuffer: keepBuffer,
      panBuffer: panBuffer,
      tileDisplay: tileDisplay,
    ),
    if (includeReferenceLabels &&
        shouldShowFieldReferenceLabels(imageryTemplate))
      ...fieldReferenceTileLayers(
        keepBuffer: keepBuffer,
        panBuffer: panBuffer,
        tileDisplay: tileDisplay,
      ),
  ];
}

List<Widget> fieldReferenceTileLayers({
  int keepBuffer = 2,
  int panBuffer = 1,
  TileDisplay tileDisplay = const TileDisplay.fadeIn(),
}) {
  return [
    OfflineAwareTileLayer(
      key: const ValueKey('field-roads-reference-layer'),
      urlTemplate: fieldRoadsTileUrl,
      maxNativeZoom: fieldReferenceMaxNativeZoom,
      preferOfflineTemplateWhenOffline: false,
      keepBuffer: keepBuffer,
      panBuffer: panBuffer,
      tileDisplay: tileDisplay,
    ),
    OfflineAwareTileLayer(
      key: const ValueKey('field-places-reference-layer'),
      urlTemplate: fieldPlacesTileUrl,
      maxNativeZoom: fieldReferenceMaxNativeZoom,
      preferOfflineTemplateWhenOffline: false,
      keepBuffer: keepBuffer,
      panBuffer: panBuffer,
      tileDisplay: tileDisplay,
    ),
  ];
}

bool shouldShowFieldReferenceLabels(String template) {
  final lower = template.toLowerCase();
  return !lower.contains('openstreetmap.org') &&
      !lower.contains('/maps/hybrid/') &&
      !lower.contains('maptiler.com/maps/hybrid');
}

class OfflineAwareTileLayer extends StatefulWidget {
  final String urlTemplate;
  final String? fallbackUrlTemplate;
  final String? offlineUrlTemplateOverride;
  final int? maxNativeZoom;
  final int? maxOfflineNativeZoom;
  final String userAgentPackageName;
  final bool preferOfflineTemplateWhenOffline;
  final bool forceOfflineTemplateOverride;
  final int keepBuffer;
  final int panBuffer;
  final TileDisplay tileDisplay;

  const OfflineAwareTileLayer({
    super.key,
    required this.urlTemplate,
    this.fallbackUrlTemplate,
    this.offlineUrlTemplateOverride,
    this.maxNativeZoom,
    this.maxOfflineNativeZoom,
    this.userAgentPackageName = 'grainright.wrkfarm',
    this.preferOfflineTemplateWhenOffline = true,
    this.forceOfflineTemplateOverride = false,
    this.keepBuffer = 2,
    this.panBuffer = 1,
    this.tileDisplay = const TileDisplay.fadeIn(),
  });

  @override
  State<OfflineAwareTileLayer> createState() => _OfflineAwareTileLayerState();
}

class _OfflineAwareTileLayerState extends State<OfflineAwareTileLayer> {
  static const _offlineFallbackTimeout = Duration(milliseconds: 600);
  final _networkStatusService = NetworkStatusService();
  StreamSubscription<Object>? _subscription;
  bool _hasNetworkInterface = true;
  bool _online = true;
  String _offlineTemplate = RuntimeConfig.offlineTileUrlTemplate;
  late final _CachedMapTileProvider _tileProvider;

  @override
  void initState() {
    super.initState();
    _tileProvider = _CachedMapTileProvider(
      userAgentPackageName: widget.userAgentPackageName,
    );
    unawaited(_refreshConnectivity());
    unawaited(_refreshRuntimeConfig());
    _subscription = _networkStatusService.connectivityChanges.listen((_) {
      unawaited(_refreshConnectivity());
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _refreshConnectivity() async {
    try {
      final hasNetworkInterface = await _networkStatusService
          .hasNetworkInterface();
      final online = await _networkStatusService.isOnline(
        timeout: _offlineFallbackTimeout,
      );
      if (online) {
        await _refreshRuntimeConfig();
      }
      if (!mounted ||
          (online == _online && hasNetworkInterface == _hasNetworkInterface)) {
        return;
      }
      setState(() {
        _hasNetworkInterface = hasNetworkInterface;
        _online = online;
      });
    } catch (e) {
      debugPrint('[OfflineAwareTileLayer._refreshConnectivity] $e');
      if (mounted) {
        setState(() {
          _hasNetworkInterface = false;
          _online = false;
        });
      }
    }
  }

  Future<void> _refreshRuntimeConfig() async {
    final offlineTemplate = await RuntimeConfig.offlineTileUrlTemplateRuntime();
    if (!mounted || offlineTemplate == _offlineTemplate) return;
    setState(() => _offlineTemplate = offlineTemplate);
  }

  @override
  Widget build(BuildContext context) {
    final offlineTemplate = _effectiveOfflineTemplate();
    final forceOfflineSource =
        widget.offlineUrlTemplateOverride?.trim().isNotEmpty ?? false;
    final canTryLiveTiles = _online || _hasNetworkInterface;
    final usingOfflineTemplate =
        offlineTemplate.isNotEmpty &&
        ((forceOfflineSource && widget.forceOfflineTemplateOverride) ||
            (!canTryLiveTiles && widget.preferOfflineTemplateWhenOffline));
    final activeTemplate = usingOfflineTemplate
        ? offlineTemplate
        : widget.urlTemplate;
    if (activeTemplate.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final maxNativeZoom =
        (usingOfflineTemplate
            ? widget.maxOfflineNativeZoom ?? widget.maxNativeZoom
            : widget.maxNativeZoom) ??
        mapTileMaxNativeZoom;
    final effectiveMaxNativeZoom = maxNativeZoom
        .clamp(0, mapTileMaxNativeZoom)
        .toInt();
    _tileProvider.configure(
      sourceId: activeTemplate,
      allowNetwork: canTryLiveTiles,
      fallbackSourceId: widget.fallbackUrlTemplate,
      preferCache: true,
      writeNetworkTiles: canTryLiveTiles,
    );
    return TileLayer(
      urlTemplate: activeTemplate,
      fallbackUrl: widget.fallbackUrlTemplate,
      minZoom: mapTileMinZoom,
      maxZoom: mapTileMaxZoom,
      maxNativeZoom: effectiveMaxNativeZoom,
      userAgentPackageName: widget.userAgentPackageName,
      keepBuffer: widget.keepBuffer,
      panBuffer: widget.panBuffer,
      tileDisplay: widget.tileDisplay,
      tileProvider: _tileProvider,
      errorTileCallback: (tile, error, stackTrace) {
        if (_looksOffline(error)) {
          unawaited(_refreshConnectivity());
        }
      },
    );
  }

  bool _looksOffline(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socket') ||
        text.contains('network') ||
        text.contains('connection') ||
        text.contains('failed host lookup') ||
        text.contains('xmlhttprequest') ||
        text.contains('timeout');
  }

  String _effectiveOfflineTemplate() {
    final override = widget.offlineUrlTemplateOverride?.trim();
    if (override != null && override.isNotEmpty) return override;
    return _offlineTemplate.trim();
  }
}

class OfflineMapBackground extends StatelessWidget {
  final String message;

  const OfflineMapBackground({
    super.key,
    this.message = 'Offline field imagery\nDraw boundary normally',
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: const Color(0xFFEAF2EA),
        child: CustomPaint(
          painter: _OfflineMapGridPainter(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 240 || constraints.maxHeight < 170;
              return Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD3DFD4)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 12,
                      vertical: compact ? 6 : 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.map_outlined,
                          size: compact ? 16 : 20,
                          color: const Color(0xFF386A3C),
                        ),
                        SizedBox(width: compact ? 5 : 8),
                        Flexible(
                          child: Text(
                            message,
                            textAlign: TextAlign.center,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF2F4F32),
                              fontSize: compact ? 10 : 12,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OfflineMapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = const Color(0xFFCFE0D0)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0xFFBBD1BD)
      ..strokeWidth = 1.4;

    for (double x = 0; x <= size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
    }
    for (double y = 0; y <= size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minor);
    }
    for (double x = 0; x <= size.width; x += 112) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
    }
    for (double y = 0; y <= size.height; y += 112) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), major);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CachedMapTileProvider extends TileProvider {
  static final http.Client _httpClient = http.Client();

  String _sourceId = '';
  String? _fallbackSourceId;
  bool _allowNetwork = true;
  bool _preferCache = false;
  bool _writeNetworkTiles = false;

  _CachedMapTileProvider({required String userAgentPackageName})
    : super(headers: {'User-Agent': userAgentPackageName});

  void configure({
    required String sourceId,
    required bool allowNetwork,
    required bool preferCache,
    required bool writeNetworkTiles,
    String? fallbackSourceId,
  }) {
    _sourceId = sourceId;
    _fallbackSourceId = fallbackSourceId;
    _allowNetwork = allowNetwork;
    _preferCache = preferCache;
    _writeNetworkTiles = writeNetworkTiles;
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImageProvider(
      url: getTileUrl(coordinates, options),
      fallbackUrl: getTileFallbackUrl(coordinates, options),
      sourceId: _sourceId,
      fallbackSourceId: _fallbackSourceId,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      headers: headers,
      allowNetwork: _allowNetwork,
      preferCache: _preferCache,
      writeNetworkTiles: _writeNetworkTiles,
      httpClient: _httpClient,
    );
  }
}

@immutable
class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  static final _BrowserTileCache _browserTileCache = _BrowserTileCache();
  static final Uint8List _transparentTileBytes = base64Decode(
    'R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==',
  );

  final String url;
  final String? fallbackUrl;
  final String sourceId;
  final String? fallbackSourceId;
  final int z;
  final int x;
  final int y;
  final Map<String, String> headers;
  final bool allowNetwork;
  final bool preferCache;
  final bool writeNetworkTiles;
  final http.Client httpClient;

  const _CachedTileImageProvider({
    required this.url,
    required this.fallbackUrl,
    required this.sourceId,
    required this.fallbackSourceId,
    required this.z,
    required this.x,
    required this.y,
    required this.headers,
    required this.allowNetwork,
    required this.preferCache,
    required this.writeNetworkTiles,
    required this.httpClient,
  });

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CachedTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: key._loadAsync(decode),
      scale: 1,
      debugLabel: _redactUrl(url),
      informationCollector: () => [
        DiagnosticsProperty<String>('Tile URL', _redactUrl(url)),
        DiagnosticsProperty<String>('Source ID', _redactUrl(sourceId)),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final db = LocalAppDatabase.maybeInstance;
    if (preferCache) {
      final cachedCodec = await _tryLoadCachedTile(db, decode);
      if (cachedCodec != null) return cachedCodec;
      final cachedFallbackCodec = await _tryLoadCachedTile(
        db,
        decode,
        sourceIdOverride: fallbackSourceId,
      );
      if (cachedFallbackCodec != null) return cachedFallbackCodec;
    }

    if (!allowNetwork) {
      return _decodeTransparentTile(decode);
    }

    final fallbackTileUrl = fallbackUrl;
    final fallbackTileSourceId = fallbackSourceId;
    if (fallbackTileUrl != null && fallbackTileSourceId != null) {
      // Let a healthy satellite request win, but do not make a weak mobile
      // connection wait before showing a readable road map underneath it.
      final primaryFuture = _loadNetworkTile(
        decode,
        db: db,
        tileUrl: url,
        tileSourceId: sourceId,
      );
      final fallbackFuture = _loadNetworkTile(
        decode,
        db: db,
        tileUrl: fallbackTileUrl,
        tileSourceId: fallbackTileSourceId,
      );
      final primaryCodec = await primaryFuture.timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () => null,
      );
      if (primaryCodec != null) return primaryCodec;
      final fallbackCodec = await fallbackFuture;
      if (fallbackCodec != null) return fallbackCodec;
    } else {
      final networkCodec = await _loadNetworkTile(
        decode,
        db: db,
        tileUrl: url,
        tileSourceId: sourceId,
      );
      if (networkCodec != null) return networkCodec;
    }

    final cachedCodec = await _tryLoadCachedTile(db, decode);
    if (cachedCodec != null) return cachedCodec;
    final cachedFallbackCodec = await _tryLoadCachedTile(
      db,
      decode,
      sourceIdOverride: fallbackSourceId,
    );
    return cachedFallbackCodec ?? _decodeTransparentTile(decode);
  }

  Future<ui.Codec?> _loadNetworkTile(
    ImageDecoderCallback decode, {
    required LocalAppDatabase? db,
    required String tileUrl,
    required String tileSourceId,
  }) async {
    try {
      final response = await httpClient
          .get(Uri.parse(tileUrl), headers: headers)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final bytes = response.bodyBytes;
      if (bytes.isEmpty) return null;

      if (writeNetworkTiles && kIsWeb) {
        unawaited(
          _browserTileCache.write(
            sourceId: tileSourceId,
            z: z,
            x: x,
            y: y,
            bytes: bytes,
          ),
        );
      } else if (writeNetworkTiles && db != null) {
        unawaited(
          db
              .writeTile(
                sourceId: tileSourceId,
                z: z,
                x: x,
                y: y,
                bytes: bytes,
                contentType: response.headers['content-type'] ?? 'image/png',
              )
              .catchError(
                (Object e) => debugPrint(
                  '[OfflineAwareTileLayer.writeTile] ${_shortError(e)}',
                ),
              ),
        );
      }

      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (_) {
      return null;
    }
  }

  Future<ui.Codec?> _tryLoadCachedTile(
    LocalAppDatabase? db,
    ImageDecoderCallback decode, {
    String? sourceIdOverride,
  }) async {
    if (!kIsWeb && db == null) return null;
    try {
      final tileSourceId = sourceIdOverride ?? sourceId;
      if (tileSourceId.isEmpty) return null;
      final cached = kIsWeb
          ? await _browserTileCache.read(
              sourceId: tileSourceId,
              z: z,
              x: x,
              y: y,
            )
          : (await db!.readTile(
              sourceId: tileSourceId,
              z: z,
              x: x,
              y: y,
            ))?.bytes;
      if (cached == null) return null;
      final buffer = await ui.ImmutableBuffer.fromUint8List(cached);
      return decode(buffer);
    } catch (e) {
      debugPrint('[OfflineAwareTileLayer.readTile] ${_shortError(e)}');
      return null;
    }
  }

  static String _shortError(Object error) {
    final text = error.toString();
    return text.length <= 180 ? text : '${text.substring(0, 180)}...';
  }

  Future<ui.Codec> _decodeTransparentTile(ImageDecoderCallback decode) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      _transparentTileBytes,
    );
    return decode(buffer);
  }

  static String _redactUrl(String value) {
    return value.replaceAllMapped(
      RegExp(r'([?&](?:api_key|key|access_token)=)[^&]+', caseSensitive: false),
      (match) => '${match.group(1)}REDACTED',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _CachedTileImageProvider &&
        other.url == url &&
        other.fallbackUrl == fallbackUrl &&
        other.sourceId == sourceId &&
        other.fallbackSourceId == fallbackSourceId &&
        other.z == z &&
        other.x == x &&
        other.y == y &&
        other.allowNetwork == allowNetwork &&
        other.preferCache == preferCache &&
        other.writeNetworkTiles == writeNetworkTiles;
  }

  @override
  int get hashCode => Object.hash(
    url,
    fallbackUrl,
    sourceId,
    fallbackSourceId,
    z,
    x,
    y,
    allowNetwork,
    preferCache,
    writeNetworkTiles,
  );
}

/// Small bounded tile cache for Flutter web, backed by browser localStorage.
/// The native path uses LocalAppDatabase; web has no SQLite connection.
class _BrowserTileCache {
  static const _indexKey = 'grainright_map_tile_cache_index_v1';
  static const _keyPrefix = 'grainright_map_tile_v1_';
  static const _maxEntries = 20;
  static const _maxTileBytes = 140000;

  static final Future<SharedPreferences> _preferences =
      SharedPreferences.getInstance();
  Future<void>? _writeQueue;

  Future<Uint8List?> read({
    required String sourceId,
    required int z,
    required int x,
    required int y,
  }) async {
    if (!kIsWeb) return null;
    try {
      final encoded = (await _preferences).getString(
        _tileKey(sourceId: sourceId, z: z, x: x, y: y),
      );
      if (encoded == null || encoded.isEmpty) return null;
      return Uint8List.fromList(base64Url.decode(encoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String sourceId,
    required int z,
    required int x,
    required int y,
    required Uint8List bytes,
  }) async {
    if (!kIsWeb || bytes.isEmpty || bytes.length > _maxTileBytes) return;

    final operation = (_writeQueue ?? Future<void>.value()).then<void>((
      _,
    ) async {
      try {
        final preferences = await _preferences;
        final tileKey = _tileKey(sourceId: sourceId, z: z, x: x, y: y);
        await preferences.setString(tileKey, base64Url.encode(bytes));

        final index = preferences.getStringList(_indexKey) ?? <String>[];
        index.remove(tileKey);
        index.add(tileKey);
        while (index.length > _maxEntries) {
          await preferences.remove(index.removeAt(0));
        }
        await preferences.setStringList(_indexKey, index);
      } catch (_) {
        // Browser storage can be disabled or quota-limited. Map rendering
        // continues from the network/fallback source in that case.
      }
    });
    _writeQueue = operation;
    await operation;
  }

  String _tileKey({
    required String sourceId,
    required int z,
    required int x,
    required int y,
  }) {
    final identity = '$sourceId|$z|$x|$y';
    return '$_keyPrefix${base64Url.encode(utf8.encode(identity))}';
  }
}
