import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/satellite_config.dart';
import '../config/theme.dart';
import '../services/location_service.dart';
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
  final _controller = Completer<GoogleMapController>();
  final _locationService = LocationService();
  final _strokes = <List<LatLng>>[];
  final _liveStroke = <LatLng>[];

  bool _pencilMode = false;
  LatLng _center = LatLng(
    SatelliteConfig.defaultCenter.latitude,
    SatelliteConfig.defaultCenter.longitude,
  );
  List<LatLng> _ring = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPolygon != null && widget.initialPolygon!.isNotEmpty) {
      _ring = PolygonGeometry.fromGeoJsonRing(widget.initialPolygon!);
      _center = _ring.first;
    } else {
      _loadLocation();
    }
  }

  Future<void> _loadLocation() async {
    final location = await _locationService.getCurrentLocation();
    if (!mounted || location == null) return;
    setState(() {
      _center = LatLng(location.latitude, location.longitude);
    });
    if (_controller.isCompleted) {
      final map = await _controller.future;
      await map.animateCamera(CameraUpdate.newLatLngZoom(_center, 17));
    }
  }

  Future<void> _appendPoint(Offset globalPosition) async {
    if (!_controller.isCompleted) return;
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final map = await _controller.future;
    final latLng = await map.getLatLng(
      ScreenCoordinate(x: local.dx.round(), y: local.dy.round()),
    );
    if (!mounted) return;
    setState(() => _liveStroke.add(latLng));
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
        _strokes.add(simplified);
        _ring = simplified;
      }
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _liveStroke.clear();
      _ring.clear();
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
      _ring = _strokes.isEmpty ? [] : _strokes.last;
    });
  }

  void _save() {
    if (_ring.length < 4) {
      Get.snackbar('Draw boundary', 'Draw a closed boundary before saving');
      return;
    }
    Get.back(result: PolygonGeometry.toGeoJsonRing(_ring));
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
                ButtonSegment(value: false, icon: Icon(Icons.pan_tool_alt), label: Text('Pan')),
                ButtonSegment(value: true, icon: Icon(Icons.edit), label: Text('Draw')),
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
          GoogleMap(
            mapType: MapType.satellite,
            initialCameraPosition: CameraPosition(target: _center, zoom: 17),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: !_pencilMode,
            scrollGesturesEnabled: !_pencilMode,
            tiltGesturesEnabled: !_pencilMode,
            zoomGesturesEnabled: !_pencilMode,
            polygons: {
              if (_ring.length >= 4)
                Polygon(
                  polygonId: const PolygonId('farm_boundary'),
                  points: _ring,
                  strokeWidth: 3,
                  strokeColor: AppTheme.green,
                  fillColor: AppTheme.green.withValues(alpha: 0.22),
                ),
            },
            polylines: {
              if (_liveStroke.length > 1)
                Polyline(
                  polylineId: const PolylineId('live_stroke'),
                  points: _liveStroke,
                  width: 4,
                  color: Colors.white,
                ),
            },
            onMapCreated: (map) {
              if (!_controller.isCompleted) _controller.complete(map);
              if (_ring.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  map.animateCamera(CameraUpdate.newLatLngBounds(_bounds(_ring), 48));
                });
              }
            },
          ),
          if (_pencilMode)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) {
                  _liveStroke.clear();
                  _appendPoint(details.globalPosition);
                },
                onPanUpdate: (details) => _appendPoint(details.globalPosition),
                onPanEnd: (_) => _finishStroke(),
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
                    BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          area > 0 ? '${area.toStringAsFixed(2)} ha' : 'Tap Draw, then drag around the field',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: _strokes.isEmpty ? null : _undo,
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

  LatLngBounds _bounds(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}
