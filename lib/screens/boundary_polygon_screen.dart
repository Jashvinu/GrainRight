import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../config/satellite_config.dart';
import '../config/theme.dart';
import '../services/location_service.dart';
import '../services/map_tile_provider.dart';
import '../services/network_status_service.dart';
import '../services/offline_map_service.dart';
import '../utils/polygon_geometry.dart';

class BoundaryPolygonScreen extends StatefulWidget {
  final List<List<double>>? initialPolygon;

  const BoundaryPolygonScreen({super.key, this.initialPolygon});

  @override
  State<BoundaryPolygonScreen> createState() => _BoundaryPolygonScreenState();
}

class _BoundaryPolygonScreenState extends State<BoundaryPolygonScreen> {
  final _mapKey = GlobalKey();
  final _mapController = MapController();
  final _locationService = LocationService();
  final _networkStatusService = NetworkStatusService();
  final _offlineMapService = OfflineMapService();

  final List<LatLng> _points = [];

  bool _mapReady = false;
  bool _loadingLocation = true;
  LatLng _center = LatLng(
    SatelliteConfig.defaultCenter.latitude,
    SatelliteConfig.defaultCenter.longitude,
  );
  double _zoom = SatelliteConfig.defaultZoom;

  @override
  void initState() {
    super.initState();
    if (widget.initialPolygon != null && widget.initialPolygon!.isNotEmpty) {
      _points.addAll(_openRing(PolygonGeometry.fromGeoJsonRing(widget.initialPolygon!)));
      if (_points.isNotEmpty) {
        _center = _points.first;
        _zoom = 18;
        _loadingLocation = false;
      }
    } else {
      unawaited(_loadInitialTarget());
    }
  }

  @override
  void dispose() {
    _offlineMapService.dispose();
    super.dispose();
  }

  Future<void> _loadInitialTarget() async {
    try {
      final hasNetwork = await _networkStatusService.hasNetworkInterface();
      if (!mounted) return;
      if (!hasNetwork) {
        // Still try location; if it fails we fall back to the default center.
      }

      final quickLocation = await _locationService.getLastKnownLocation();
      if (!mounted) return;
      if (quickLocation != null) {
        _center = LatLng(quickLocation.latitude, quickLocation.longitude);
        _zoom = 18;
        if (_mapReady) _moveMap(_center, _zoom);
      }

      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      if (location != null) {
        _center = LatLng(location.latitude, location.longitude);
        _zoom = 18;
        if (_mapReady) _moveMap(_center, _zoom);
      }
    } catch (e) {
      debugPrint('[BoundaryPolygonScreen._loadInitialTarget] $e');
    } finally {
      if (mounted) {
        setState(() => _loadingLocation = false);
      }
    }
  }

  void _addPoint(TapPosition _, LatLng point) {
    setState(() {
      _points.add(point);
    });
  }

  void _removeLastPoint() {
    if (_points.isEmpty) return;
    setState(() => _points.removeLast());
  }

  void _clearPoints() {
    if (_points.isEmpty) return;
    setState(() => _points.clear());
  }

  void _movePoint(int index, Offset globalPosition) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    try {
      final point = _mapController.camera.pointToLatLng(
        math.Point<double>(local.dx, local.dy),
      );
      setState(() => _points[index] = point);
    } catch (_) {
      // Ignore drag updates until the map is ready.
    }
  }

  void _moveMap(LatLng center, double zoom) {
    if (!_mapReady) return;
    try {
      _mapController.move(center, zoom);
    } catch (_) {
      // The controller can still be warming up.
    }
  }

  void _confirm() {
    if (_points.length < 3) {
      Get.snackbar(
        'Too few points',
        'Add at least 3 corners to save the farm boundary.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    Get.back(result: PolygonGeometry.toGeoJsonRing(_points));
  }

  List<LatLng> _openRing(List<LatLng> ring) {
    if (ring.isEmpty) return ring;
    if (ring.length > 1 && ring.first.latitude == ring.last.latitude && ring.first.longitude == ring.last.longitude) {
      return [...ring]..removeLast();
    }
    return ring;
  }

  @override
  Widget build(BuildContext context) {
    final areaHectares = PolygonGeometry.areaHectares(_points);
    final instruction = _points.isEmpty
        ? 'Tap corners to build the farm boundary.'
        : _points.length == 1
            ? 'Add a second point to create the first edge.'
            : _points.length == 2
                ? 'Add a third point to close the polygon.'
                : 'Drag points to refine the boundary, then confirm.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw farm boundary'),
        actions: [
          IconButton(
            tooltip: 'Re-center',
            onPressed: _loadingLocation
                ? null
                : () => _moveMap(_center, _zoom),
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Stack(
        key: _mapKey,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _points.isNotEmpty ? _points.first : _center,
              initialZoom: _points.isNotEmpty ? 18 : _zoom,
              minZoom: mapTileMinZoom,
              maxZoom: mapTileMaxZoom,
              initialCameraFit: _points.length >= 3
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(_points),
                      padding: const EdgeInsets.all(48),
                    )
                  : null,
              onTap: _addPoint,
              onMapReady: () {
                _mapReady = true;
                if (_points.isEmpty) {
                  _moveMap(_center, _zoom);
                }
              },
            ),
            children: [
              const OfflineMapBackground(
                message: 'Offline map\nTap points to mark boundary',
              ),
              OfflineAwareTileLayer(urlTemplate: fieldImageryTileUrl),
              if (_points.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _points,
                      strokeWidth: 4,
                      color: Colors.white,
                    ),
                  ],
                ),
              if (_points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _points,
                      color: AppTheme.green.withValues(alpha: 0.22),
                      borderColor: AppTheme.green,
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (var i = 0; i < _points.length; i++)
                    Marker(
                      point: _points[i],
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) =>
                            _movePoint(i, details.globalPosition),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.greenDark,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD9E4D8)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app_outlined, color: AppTheme.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          instruction,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                  borderRadius: BorderRadius.circular(14),
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
                          _points.length >= 3
                              ? '${areaHectares.toStringAsFixed(2)} ha'
                              : 'Add ${3 - _points.length} more point${3 - _points.length == 1 ? '' : 's'} to confirm',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _points.isEmpty ? null : _removeLastPoint,
                        child: const Text('Undo'),
                      ),
                      TextButton(
                        onPressed: _points.isEmpty ? null : _clearPoints,
                        child: const Text('Redraw'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _confirm,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Confirm'),
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
}
