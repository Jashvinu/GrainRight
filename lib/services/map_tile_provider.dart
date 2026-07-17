import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

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
}) {
  final imageryTemplate = (urlTemplate?.trim().isNotEmpty ?? false)
      ? urlTemplate!.trim()
      : fieldImageryTileUrl;
  return [
    OfflineAwareTileLayer(
      urlTemplate: imageryTemplate,
      offlineUrlTemplateOverride: offlineUrlTemplateOverride,
      maxNativeZoom: fieldImageryMaxNativeZoom,
      maxOfflineNativeZoom: maxOfflineNativeZoom,
    ),
    if (includeReferenceLabels &&
        shouldShowFieldReferenceLabels(imageryTemplate))
      ...fieldReferenceTileLayers(),
  ];
}

List<Widget> fieldReferenceTileLayers() {
  return const [
    OfflineAwareTileLayer(
      urlTemplate: fieldRoadsTileUrl,
      maxNativeZoom: fieldReferenceMaxNativeZoom,
      preferOfflineTemplateWhenOffline: false,
    ),
    OfflineAwareTileLayer(
      urlTemplate: fieldPlacesTileUrl,
      maxNativeZoom: fieldReferenceMaxNativeZoom,
      preferOfflineTemplateWhenOffline: false,
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
  final String? offlineUrlTemplateOverride;
  final int? maxNativeZoom;
  final int? maxOfflineNativeZoom;
  final String userAgentPackageName;
  final bool preferOfflineTemplateWhenOffline;
  final bool forceOfflineTemplateOverride;

  const OfflineAwareTileLayer({
    super.key,
    required this.urlTemplate,
    this.offlineUrlTemplateOverride,
    this.maxNativeZoom,
    this.maxOfflineNativeZoom,
    this.userAgentPackageName = 'grainright.wrkfarm',
    this.preferOfflineTemplateWhenOffline = true,
    this.forceOfflineTemplateOverride = false,
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

  @override
  void initState() {
    super.initState();
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
          (online == _online &&
              hasNetworkInterface == _hasNetworkInterface)) {
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
    if (!usingOfflineTemplate && canTryLiveTiles) {
      return TileLayer(
        urlTemplate: activeTemplate,
        minZoom: mapTileMinZoom,
        maxZoom: mapTileMaxZoom,
        maxNativeZoom: effectiveMaxNativeZoom,
        userAgentPackageName: widget.userAgentPackageName,
        errorTileCallback: (tile, error, stackTrace) {
          if (_looksOffline(error)) {
            unawaited(_refreshConnectivity());
          }
        },
      );
    }
    return TileLayer(
      urlTemplate: activeTemplate,
      minZoom: mapTileMinZoom,
      maxZoom: mapTileMaxZoom,
      maxNativeZoom: effectiveMaxNativeZoom,
      userAgentPackageName: widget.userAgentPackageName,
      tileProvider: _CachedMapTileProvider(
        sourceId: activeTemplate,
        allowNetwork: canTryLiveTiles,
        preferCache: usingOfflineTemplate || !canTryLiveTiles,
        writeNetworkTiles: _online && usingOfflineTemplate,
      ),
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

  final String sourceId;
  final bool allowNetwork;
  final bool preferCache;
  final bool writeNetworkTiles;

  _CachedMapTileProvider({
    required this.sourceId,
    required this.allowNetwork,
    required this.preferCache,
    required this.writeNetworkTiles,
  }) : super(headers: {'User-Agent': 'grainright.wrkfarm'});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImageProvider(
      url: getTileUrl(coordinates, options),
      sourceId: sourceId,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      headers: headers,
      allowNetwork: allowNetwork,
      preferCache: preferCache,
      writeNetworkTiles: writeNetworkTiles,
      httpClient: _httpClient,
    );
  }
}

@immutable
class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  static final Uint8List _transparentTileBytes = base64Decode(
    'R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==',
  );

  final String url;
  final String sourceId;
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
    required this.sourceId,
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
    }

    if (!allowNetwork) {
      return _decodeTransparentTile(decode);
    }

    try {
      final response = await httpClient
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _decodeTransparentTile(decode);
      }

      final bytes = response.bodyBytes;
      if (bytes.isEmpty) return _decodeTransparentTile(decode);

      if (writeNetworkTiles && db != null) {
        unawaited(
          db
              .writeTile(
                sourceId: sourceId,
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
      final cachedCodec = await _tryLoadCachedTile(db, decode);
      return cachedCodec ?? _decodeTransparentTile(decode);
    }
  }

  Future<ui.Codec?> _tryLoadCachedTile(
    LocalAppDatabase? db,
    ImageDecoderCallback decode,
  ) async {
    if (db == null) return null;
    try {
      final cached = await db.readTile(sourceId: sourceId, z: z, x: x, y: y);
      if (cached == null) return null;
      final buffer = await ui.ImmutableBuffer.fromUint8List(cached.bytes);
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
        other.sourceId == sourceId &&
        other.z == z &&
        other.x == x &&
        other.y == y &&
        other.allowNetwork == allowNetwork &&
        other.preferCache == preferCache &&
        other.writeNetworkTiles == writeNetworkTiles;
  }

  @override
  int get hashCode =>
      Object.hash(
        url,
        sourceId,
        z,
        x,
        y,
        allowNetwork,
        preferCache,
        writeNetworkTiles,
      );
}
