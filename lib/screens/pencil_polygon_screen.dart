import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../services/local_app_database.dart';
import '../services/location_service.dart';
import '../services/map_tile_cache_service.dart';
import '../services/map_tile_provider.dart';
import '../services/network_status_service.dart';
import '../services/offline_map_service.dart';
import '../utils/polygon_geometry.dart';
import '../utils/polygon_simplify.dart';

class PencilPolygonScreen extends StatefulWidget {
  final List<List<double>>? initialPolygon;

  const PencilPolygonScreen({super.key, this.initialPolygon});

  @override
  State<PencilPolygonScreen> createState() => _PencilPolygonScreenState();
}

class _PencilPolygonScreenState extends State<PencilPolygonScreen> {
  static const _preferredRegionKey = 'preferred_offline_field_region_id';
  final _mapKey = GlobalKey();
  final _mapController = MapController();
  final _locationService = LocationService();
  final _mapTileCacheService = MapTileCacheService();
  final _offlineMapService = OfflineMapService();
  final _networkStatusService = NetworkStatusService();
  final _liveStroke = <ll.LatLng>[];

  bool _mapReady = false;
  bool _pencilMode = false;
  bool _loadingDownloadedMaps = false;
  double _targetZoom = 18;
  OfflineMapRegionRecord? _selectedOfflineRegion;
  List<OfflineMapRegionRecord> _downloadedRegions = const [];
  ll.LatLng _center = ll.LatLng(
    MapTileCacheService.fallbackCenterLatitude,
    MapTileCacheService.fallbackCenterLongitude,
  );
  List<ll.LatLng> _ring = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_mapTileCacheService.prefetchCoreRegions());
    });
    if (widget.initialPolygon != null && widget.initialPolygon!.isNotEmpty) {
      _ring = _openRing(
        PolygonGeometry.fromGeoJsonRing(widget.initialPolygon!),
      );
      _center = _ring.first;
    } else {
      unawaited(_loadInitialMapTarget());
    }
  }

  @override
  void dispose() {
    _offlineMapService.dispose();
    super.dispose();
  }

  Future<void> _loadInitialMapTarget() async {
    final regions = await _refreshDownloadedRegions();
    if (!mounted) return;

    final hasNetwork = await _networkStatusService.hasNetworkInterface();
    if (!mounted) return;

    if (!hasNetwork && regions.isNotEmpty) {
      final preferred = await _preferredOfflineRegion(regions);
      if (!mounted) return;
      _focusOfflineRegion(preferred ?? regions.first, showSnack: false);
      return;
    }

    await _loadLocation();
  }

  Future<List<OfflineMapRegionRecord>> _refreshDownloadedRegions() async {
    try {
      final regions = await _offlineMapService.listRegions();
      final drawableRegions = regions.where(_canDrawOnRegion).toList();
      if (mounted) setState(() => _downloadedRegions = drawableRegions);
      return drawableRegions;
    } catch (e) {
      debugPrint('[PencilPolygonScreen._refreshDownloadedRegions] $e');
      return const [];
    }
  }

  Future<void> _loadLocation() async {
    final quickLocation = await _locationService.getLastKnownLocation();
    if (!mounted) return;
    if (quickLocation != null) {
      _focusLiveLocation(quickLocation);
    }

    final location = await _locationService.getCurrentLocation();
    if (!mounted) return;
    if (location == null) {
      if (quickLocation != null) return;
      final fallbackRegion = await _preferredOfflineRegion(_downloadedRegions);
      if (fallbackRegion != null) {
        _focusOfflineRegion(fallbackRegion, showSnack: false);
      }
      return;
    }
    _focusLiveLocation(location);
  }

  void _focusLiveLocation(LocationResult location) {
    setState(() {
      _center = ll.LatLng(location.latitude, location.longitude);
      _targetZoom = 18;
      _selectedOfflineRegion = null;
    });
    unawaited(
      _mapTileCacheService.prefetchWideRegion(
        latitude: location.latitude,
        longitude: location.longitude,
      ),
    );
    _moveMap(_center, zoom: 18);
  }

  Future<void> _selectDownloadedMap() async {
    if (_loadingDownloadedMaps) return;
    setState(() => _loadingDownloadedMaps = true);
    final regions = await _refreshDownloadedRegions();
    if (mounted) setState(() => _loadingDownloadedMaps = false);
    if (!mounted) return;

    if (regions.isEmpty) {
      Get.snackbar(
        'Downloaded maps',
        'No downloaded map regions are available for drawing.',
      );
      return;
    }

    final selected = await showModalBottomSheet<OfflineMapRegionRecord>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Select downloaded map',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                );
              }

              final region = regions[index - 1];
              final selected =
                  _selectedOfflineRegion?.regionId == region.regionId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  selected ? Icons.offline_pin_rounded : Icons.map_outlined,
                  color: selected ? AppTheme.green : AppTheme.textMuted,
                ),
                title: Text(
                  region.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${region.status.toUpperCase()} · ${region.radiusKm.toStringAsFixed(0)} km · zoom ${region.minZoom}-${region.maxZoom} · ${region.downloadedTileCount}/${region.tileCount} tiles',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: selected
                    ? const Icon(Icons.check_circle, color: AppTheme.green)
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).pop(region),
              );
            },
            separatorBuilder: (_, index) =>
                index == 0 ? const SizedBox(height: 6) : const Divider(),
            itemCount: regions.length + 1,
          ),
        );
      },
    );

    if (selected != null) _focusOfflineRegion(selected);
  }

  void _focusOfflineRegion(
    OfflineMapRegionRecord region, {
    bool showSnack = true,
  }) {
    final center = ll.LatLng(region.centerLat, region.centerLng);
    final zoom = region.maxZoom.clamp(10, mapTileMaxZoom.toInt()).toDouble();
    setState(() {
      _selectedOfflineRegion = region;
      _center = center;
      _targetZoom = zoom;
    });
    unawaited(_savePreferredOfflineRegion(region.regionId));
    _moveMap(center, zoom: zoom);
    if (showSnack) {
      Get.snackbar(
        'Downloaded map selected',
        'Centered on ${region.label}. Switch to Draw and mark the farm boundary.',
      );
    }
  }

  ll.LatLng? _pointFromGlobalPosition(Offset globalPosition) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(globalPosition);
    try {
      final point = _mapController.camera.pointToLatLng(
        math.Point<double>(local.dx, local.dy),
      );
      return point;
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
      final nextZoom = (camera.zoom + delta)
          .clamp(mapTileMinZoom, mapTileMaxZoom)
          .toDouble();
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
            tooltip: 'Downloaded maps',
            onPressed: _loadingDownloadedMaps ? null : _selectDownloadedMap,
            icon: _loadingDownloadedMaps
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.offline_pin_outlined),
          ),
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
              initialCenter: _center,
              initialZoom: _targetZoom,
              minZoom: mapTileMinZoom,
              maxZoom: mapTileMaxZoom,
              initialCameraFit: _ring.length >= 3
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(_ring),
                      padding: const EdgeInsets.all(48),
                    )
                  : null,
              interactionOptions: InteractionOptions(
                flags: _pencilMode ? InteractiveFlag.none : InteractiveFlag.all,
              ),
              onMapReady: () {
                _mapReady = true;
                if (_ring.isEmpty) _moveMap(_center, zoom: _targetZoom);
              },
            ),
            children: [
              const OfflineMapBackground(
                message: 'Offline map\nPan to your farm and draw',
              ),
              OfflineAwareTileLayer(
                urlTemplate: fieldImageryTileUrl,
                offlineUrlTemplateOverride: _selectedOfflineRegion?.sourceId,
                maxOfflineNativeZoom: _selectedOfflineRegion?.maxZoom,
              ),
              if (_ring.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _ring,
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
                      points: _liveStroke,
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
                          point: point,
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
            left: 16,
            right: 88,
            top: 16,
            child: SafeArea(
              child: _DownloadedMapBanner(region: _selectedOfflineRegion),
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

  void _moveMap(ll.LatLng center, {required double zoom}) {
    if (!_mapReady) return;
    try {
      _mapController.move(center, zoom);
    } catch (_) {
      // The controller may not be attached yet during startup.
    }
  }

  List<ll.LatLng> _openRing(List<ll.LatLng> points) {
    if (points.length < 2) return [...points];
    final out = [...points];
    if (_samePoint(out.first, out.last)) out.removeLast();
    return out;
  }

  bool _samePoint(ll.LatLng a, ll.LatLng b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;

  bool _canDrawOnRegion(OfflineMapRegionRecord region) {
    if (region.tileCount <= 0 || region.downloadedTileCount <= 0) {
      return false;
    }
    return region.status == 'ready' ||
        region.downloadedTileCount >= region.tileCount;
  }

  Future<OfflineMapRegionRecord?> _preferredOfflineRegion(
    List<OfflineMapRegionRecord> regions,
  ) async {
    if (regions.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final preferredId = prefs.getString(_preferredRegionKey);
    if (preferredId == null || preferredId.isEmpty) {
      return regions.first;
    }
    for (final region in regions) {
      if (region.regionId == preferredId) return region;
    }
    return regions.first;
  }

  Future<void> _savePreferredOfflineRegion(String regionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredRegionKey, regionId);
  }
}

class _DownloadedMapBanner extends StatelessWidget {
  final OfflineMapRegionRecord? region;

  const _DownloadedMapBanner({required this.region});

  @override
  Widget build(BuildContext context) {
    final selected = region;
    if (selected == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9E4D8)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.offline_pin_outlined,
              color: AppTheme.green,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Z${selected.minZoom}-${selected.maxZoom}',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
