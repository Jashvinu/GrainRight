import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll;
import '../config/satellite_config.dart';
import '../config/theme.dart';
import '../services/location_service.dart';
import '../services/map_tile_provider.dart';
import '../utils/polygon_geometry.dart';
import '../utils/polygon_simplify.dart';

class PencilPolygonScreen extends StatefulWidget {
  final List<List<double>>? initialPolygon;

  const PencilPolygonScreen({super.key, this.initialPolygon});

  @override
  State<PencilPolygonScreen> createState() => _PencilPolygonScreenState();
}

class _PencilPolygonScreenState extends State<PencilPolygonScreen> {
  final _mapKey = GlobalKey();
  final _mapController = MapController();
  final _locationService = LocationService();
  final _liveStroke = <gmaps.LatLng>[];

  bool _mapReady = false;
  bool _pencilMode = false;
  gmaps.LatLng _center = gmaps.LatLng(
    SatelliteConfig.defaultCenter.latitude,
    SatelliteConfig.defaultCenter.longitude,
  );
  List<gmaps.LatLng> _ring = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPolygon != null && widget.initialPolygon!.isNotEmpty) {
      _ring = _openRing(
        PolygonGeometry.fromGeoJsonRing(widget.initialPolygon!),
      );
      _center = _ring.first;
    } else {
      _loadLocation();
    }
  }

  Future<void> _loadLocation() async {
    final location = await _locationService.getCurrentLocation();
    if (!mounted || location == null) return;
    setState(() {
      _center = gmaps.LatLng(location.latitude, location.longitude);
    });
    _moveMap(_center, zoom: 17);
  }

  gmaps.LatLng? _pointFromGlobalPosition(Offset globalPosition) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(globalPosition);
    try {
      final point = _mapController.camera.pointToLatLng(
        math.Point<double>(local.dx, local.dy),
      );
      return _fromMapPoint(point);
    } catch (_) {
      return null;
    }
  }

  void _appendStrokePoint(Offset globalPosition) {
    final point = _pointFromGlobalPosition(globalPosition);
    if (!mounted || point == null) return;
    setState(() => _liveStroke.add(point));
  }

  void _appendBoundaryPoint(Offset globalPosition) {
    final point = _pointFromGlobalPosition(globalPosition);
    if (!mounted || point == null) return;
    setState(() {
      _liveStroke.clear();
      if (_ring.isEmpty || !_samePoint(_ring.last, point)) {
        _ring.add(point);
      }
    });
  }

  void _finishStroke() {
    if (_liveStroke.length < 3) {
      setState(_liveStroke.clear);
      return;
    }
    final simplified = PolygonSimplifier.simplify(_liveStroke);
    setState(() {
      _liveStroke.clear();
      if (simplified.isNotEmpty) {
        _ring = _openRing(simplified);
      }
    });
  }

  void _clear() {
    setState(() {
      _liveStroke.clear();
      _ring.clear();
    });
  }

  void _undo() {
    if (_liveStroke.isNotEmpty) {
      setState(_liveStroke.clear);
      return;
    }
    if (_ring.isEmpty) return;
    setState(() {
      _ring.removeLast();
    });
  }

  void _save() {
    if (_ring.length < 3) {
      Get.snackbar('Draw boundary', 'Add at least 3 boundary points');
      return;
    }
    Get.back(result: PolygonGeometry.toGeoJsonRing(_ring));
  }

  void _zoomBy(double delta) {
    if (!_mapReady || !mounted) return;
    try {
      final camera = _mapController.camera;
      final nextZoom = (camera.zoom + delta).clamp(3.0, 20.0).toDouble();
      _mapController.move(camera.center, nextZoom);
    } catch (e) {
      debugPrint('[PencilPolygonScreen._zoomBy] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final area = PolygonGeometry.areaHectares(_ring);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw farm boundary'),
        actions: [
          IconButton(
            tooltip: 'Re-center',
            onPressed: _loadLocation,
            icon: const Icon(Icons.my_location_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.pan_tool_alt),
                  label: Text('Pan'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.edit),
                  label: Text('Draw'),
                ),
              ],
              selected: {_pencilMode},
              onSelectionChanged: (values) {
                setState(() => _pencilMode = values.first);
              },
            ),
          ),
        ],
      ),
      body: Stack(
        key: _mapKey,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _toMapPoint(_center),
              initialZoom: 17,
              initialCameraFit: _ring.length >= 3
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(_mapPoints(_ring)),
                      padding: const EdgeInsets.all(48),
                    )
                  : null,
              interactionOptions: InteractionOptions(
                flags: _pencilMode ? InteractiveFlag.none : InteractiveFlag.all,
              ),
              onMapReady: () {
                _mapReady = true;
                if (_ring.isEmpty) _moveMap(_center, zoom: 17);
              },
            ),
            children: [
              const OfflineMapBackground(
                message: 'Offline map\nPan to your farm and draw',
              ),
              OfflineAwareTileLayer(urlTemplate: arcGisWorldImageryUrl),
              if (_ring.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _mapPoints(_ring),
                      color: AppTheme.green.withValues(alpha: 0.22),
                      borderColor: AppTheme.green,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              if (_liveStroke.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _mapPoints(_liveStroke),
                      strokeWidth: 4,
                      color: Colors.white,
                    ),
                  ],
                ),
              if (_ring.isNotEmpty)
                CircleLayer(
                  circles: _ring
                      .map(
                        (point) => CircleMarker(
                          point: _toMapPoint(point),
                          radius: 6,
                          color: AppTheme.greenDark,
                          borderColor: Colors.white,
                          borderStrokeWidth: 1.5,
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
          if (_pencilMode)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) =>
                    _appendBoundaryPoint(details.globalPosition),
                onPanStart: (details) {
                  _liveStroke.clear();
                  _appendStrokePoint(details.globalPosition);
                },
                onPanUpdate: (details) =>
                    _appendStrokePoint(details.globalPosition),
                onPanEnd: (_) => _finishStroke(),
              ),
            ),
          Positioned(
            right: 16,
            top: 16,
            child: SafeArea(
              child: _ZoomControls(
                onZoomIn: () => _zoomBy(1),
                onZoomOut: () => _zoomBy(-1),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          area > 0
                              ? '${area.toStringAsFixed(2)} ha'
                              : 'Pan to the field, then Draw: tap corners or drag the boundary',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: _ring.isEmpty && _liveStroke.isEmpty
                            ? null
                            : _undo,
                        icon: const Icon(Icons.undo_rounded),
                      ),
                      IconButton(
                        tooltip: 'Clear',
                        onPressed: _ring.isEmpty ? null : _clear,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _moveMap(gmaps.LatLng center, {required double zoom}) {
    if (!_mapReady) return;
    try {
      _mapController.move(_toMapPoint(center), zoom);
    } catch (_) {
      // The controller may not be attached yet during startup.
    }
  }

  ll.LatLng _toMapPoint(gmaps.LatLng point) =>
      ll.LatLng(point.latitude, point.longitude);

  gmaps.LatLng _fromMapPoint(ll.LatLng point) =>
      gmaps.LatLng(point.latitude, point.longitude);

  List<ll.LatLng> _mapPoints(List<gmaps.LatLng> points) =>
      points.map(_toMapPoint).toList();

  List<gmaps.LatLng> _openRing(List<gmaps.LatLng> points) {
    if (points.length < 2) return [...points];
    final out = [...points];
    if (_samePoint(out.first, out.last)) out.removeLast();
    return out;
  }

  bool _samePoint(gmaps.LatLng a, gmaps.LatLng b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;
}

class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add_rounded),
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded),
          ),
        ],
      ),
    );
  }
}
