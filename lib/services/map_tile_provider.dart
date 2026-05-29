import 'dart:async';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import '../config/runtime_config.dart';
import 'local_app_database.dart';

final String arcGisWorldImageryUrl =
    RuntimeConfig.onlineSatelliteTileUrlTemplate;
const String openStreetMapTileUrl = RuntimeConfig.onlineBaseTileUrlTemplate;

class OfflineAwareTileLayer extends StatefulWidget {
  final String urlTemplate;
  final String userAgentPackageName;
  final bool preferOfflineTemplateWhenOffline;

  const OfflineAwareTileLayer({
    super.key,
    required this.urlTemplate,
    this.userAgentPackageName = 'grainright.wrkfarm',
    this.preferOfflineTemplateWhenOffline = true,
  });

  @override
  State<OfflineAwareTileLayer> createState() => _OfflineAwareTileLayerState();
}

class _OfflineAwareTileLayerState extends State<OfflineAwareTileLayer> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshConnectivity());
    _subscription = _connectivity.onConnectivityChanged.listen(_setConnection);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _refreshConnectivity() async {
    try {
      _setConnection(await _connectivity.checkConnectivity());
    } catch (e) {
      debugPrint('[OfflineAwareTileLayer._refreshConnectivity] $e');
      if (mounted) setState(() => _online = true);
    }
  }

  void _setConnection(List<ConnectivityResult> results) {
    final online = results.any((result) => result != ConnectivityResult.none);
    if (!mounted || online == _online) return;
    setState(() => _online = online);
  }

  @override
  Widget build(BuildContext context) {
    final offlineTemplate = RuntimeConfig.offlineTileUrlTemplate.trim();
    final activeTemplate =
        !_online &&
            widget.preferOfflineTemplateWhenOffline &&
            offlineTemplate.isNotEmpty
        ? offlineTemplate
        : widget.urlTemplate;
    return TileLayer(
      urlTemplate: activeTemplate,
      userAgentPackageName: widget.userAgentPackageName,
      tileProvider: _CachedMapTileProvider(
        sourceId: activeTemplate,
        allowNetwork: _online,
        writeNetworkTiles: activeTemplate == offlineTemplate,
      ),
      errorTileCallback: (tile, error, stackTrace) {
        if (_looksOffline(error)) {
          _setConnection(const [ConnectivityResult.none]);
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
        text.contains('clientexception') ||
        text.contains('xmlhttprequest') ||
        text.contains('timeout');
  }
}

class OfflineMapBackground extends StatelessWidget {
  final String message;

  const OfflineMapBackground({
    super.key,
    this.message = 'Offline map\nDraw boundary normally',
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
  final bool writeNetworkTiles;

  _CachedMapTileProvider({
    required this.sourceId,
    required this.allowNetwork,
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
      writeNetworkTiles: writeNetworkTiles,
      httpClient: _httpClient,
    );
  }
}

@immutable
class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  final String url;
  final String sourceId;
  final int z;
  final int x;
  final int y;
  final Map<String, String> headers;
  final bool allowNetwork;
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
      debugLabel: url,
      informationCollector: () => [
        DiagnosticsProperty<String>('Tile URL', url),
        DiagnosticsProperty<String>('Source ID', sourceId),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final cached = await LocalAppDatabase.instance.readTile(
      sourceId: sourceId,
      z: z,
      x: x,
      y: y,
    );
    if (cached != null) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(cached.bytes);
      return decode(buffer);
    }

    if (!allowNetwork) {
      throw StateError('Tile is not downloaded for offline use.');
    }

    final response = await httpClient.get(Uri.parse(url), headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Tile request failed with ${response.statusCode}',
        Uri.parse(url),
      );
    }
    final bytes = response.bodyBytes;
    if (writeNetworkTiles) {
      await LocalAppDatabase.instance.writeTile(
        sourceId: sourceId,
        z: z,
        x: x,
        y: y,
        bytes: bytes,
        contentType: response.headers['content-type'] ?? 'image/png',
      );
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    return other is _CachedTileImageProvider &&
        other.url == url &&
        other.sourceId == sourceId &&
        other.z == z &&
        other.x == x &&
        other.y == y;
  }

  @override
  int get hashCode => Object.hash(url, sourceId, z, x, y);
}
