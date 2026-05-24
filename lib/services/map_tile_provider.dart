import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

const String arcGisWorldImageryUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
const String openStreetMapTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

final TileProvider sharedMapTileProvider = _SharedMapTileProvider();

class OfflineAwareTileLayer extends StatefulWidget {
  final String urlTemplate;
  final String userAgentPackageName;

  const OfflineAwareTileLayer({
    super.key,
    required this.urlTemplate,
    this.userAgentPackageName = 'grainright.wrkfarm',
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
    if (!_online) return const SizedBox.shrink();
    return TileLayer(
      urlTemplate: widget.urlTemplate,
      userAgentPackageName: widget.userAgentPackageName,
      tileProvider: sharedMapTileProvider,
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

class _SharedMapTileProvider extends NetworkTileProvider {
  _SharedMapTileProvider();

  @override
  void dispose() {
    // Keep the shared HTTP client alive for the app lifetime. Closing it while
    // Flutter is still resolving tile images causes RequestAbortedException logs
    // when a map route is popped.
  }
}
