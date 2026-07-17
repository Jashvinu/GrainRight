import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kalsubai_farms/core/localization/locale_text.dart';
import '../config/satellite_config.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../services/local_app_database.dart';
import '../services/location_service.dart';
import '../services/map_tile_provider.dart';
import '../services/network_status_service.dart';
import '../services/offline_map_service.dart';
import '../utils/polygon_geometry.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';

class BoundaryPolygonScreen extends StatefulWidget {
  final List<List<double>>? initialPolygon;

  const BoundaryPolygonScreen({super.key, this.initialPolygon});

  @override
  State<BoundaryPolygonScreen> createState() => _BoundaryPolygonScreenState();
}

class _BoundaryPolygonScreenState extends State<BoundaryPolygonScreen> {
  static const _preferredRegionKey = 'preferred_offline_field_region_id';
  final _mapKey = GlobalKey();
  final _mapController = MapController();
  final _locationService = LocationService();
  final _networkStatusService = NetworkStatusService();
  final _offlineMapService = OfflineMapService();

  final List<LatLng> _points = [];

  bool _mapReady = false;
  bool _loadingLocation = true;
  bool _loadingDownloadedMaps = false;
  OfflineMapRegionRecord? _selectedOfflineRegion;
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
      final regions = await _refreshDownloadedRegions();
      if (!mounted) return;

      final hasNetwork = await _networkStatusService.hasNetworkInterface();
      if (!mounted) return;
      if (!hasNetwork) {
        final preferred = await _preferredOfflineRegion(regions);
        if (!mounted) return;
        if (preferred != null) {
          _focusOfflineRegion(preferred, showSnack: false);
          return;
        }
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

  Future<List<OfflineMapRegionRecord>> _refreshDownloadedRegions() async {
    try {
      final regions = await _offlineMapService.listRegions();
      final readyRegions = regions.where(_canUseOfflineRegion).toList();
      return readyRegions;
    } catch (e) {
      debugPrint('[BoundaryPolygonScreen._refreshDownloadedRegions] $e');
      return const [];
    }
  }

  bool _canUseOfflineRegion(OfflineMapRegionRecord region) {
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
    if (preferredId == null || preferredId.isEmpty) return regions.first;
    for (final region in regions) {
      if (region.regionId == preferredId) return region;
    }
    return regions.first;
  }

  Future<void> _savePreferredOfflineRegion(String regionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredRegionKey, regionId);
  }

  Future<void> _selectDownloadedMap() async {
    if (_loadingDownloadedMaps) return;
    setState(() => _loadingDownloadedMaps = true);
    final regions = await _refreshDownloadedRegions();
    if (mounted) setState(() => _loadingDownloadedMaps = false);
    if (!mounted) return;

    if (regions.isEmpty) {
      Get.snackbar(
        UiStrings.t('downloaded_maps'),
        UiStrings.t('no_downloaded_field_maps_available'),
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
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    UiStrings.t('select_downloaded_field_map'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }

              final region = regions[index - 1];
              final isSelected =
                  _selectedOfflineRegion?.regionId == region.regionId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isSelected ? Icons.offline_pin_rounded : Icons.map_outlined,
                  color: isSelected ? AppTheme.green : AppTheme.textMuted,
                ),
                title: Text(
                  region.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  UiStrings.f('downloaded_region_summary', {
                    'radius': region.radiusKm,
                    'minZoom': region.minZoom,
                    'maxZoom': region.maxZoom,
                    'downloaded': region.downloadedTileCount,
                    'total': region.tileCount,
                  }),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isSelected
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
    final center = LatLng(region.centerLat, region.centerLng);
    final zoom = region.maxZoom.clamp(10, mapTileMaxZoom.toInt()).toDouble();
    setState(() {
      _center = center;
      _zoom = zoom;
      _selectedOfflineRegion = region;
    });
    unawaited(_savePreferredOfflineRegion(region.regionId));
    _moveMap(center, zoom);
    if (showSnack) {
      Get.snackbar(
        UiStrings.t('downloaded_map_selected'),
        UiStrings.f('loaded_offline_boundary_map', {'region': region.label}),
      );
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
        ? UiStrings.t('tap_corners_boundary')
        : _points.length == 1
            ? UiStrings.t('add_second_boundary_point')
            : _points.length == 2
                ? UiStrings.t('add_third_boundary_point')
                : UiStrings.t('drag_points_confirm_boundary');

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('draw_farm_boundary')),
        actions: [
          IconButton(
            tooltip: UiStrings.t('re_center'),
            onPressed: _loadingLocation
                ? null
                : () => _moveMap(_center, _zoom),
            icon: const Icon(Icons.my_location_rounded),
          ),
          IconButton(
            tooltip: UiStrings.t('downloaded_maps'),
            onPressed: _loadingDownloadedMaps ? null : _selectDownloadedMap,
            icon: _loadingDownloadedMaps
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.offline_pin_outlined),
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
              OfflineMapBackground(
                message: UiStrings.t('offline_map_tap_boundary'),
              ),
              ...fieldImageryTileLayers(
                offlineUrlTemplateOverride: _selectedOfflineRegion?.sourceId,
                maxOfflineNativeZoom: _selectedOfflineRegion?.maxZoom,
              ),
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
            top: _selectedOfflineRegion == null ? 16 : 64,
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
          if (_selectedOfflineRegion != null)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.greenDark.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.offline_pin_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _selectedOfflineRegion!.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
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
                              ? UiStrings.f('hectare_value', {
                                  'value': LocaleText.number(
                                    areaHectares,
                                    fractionDigits: 2,
                                  ),
                                })
                              : UiStrings.f('points_more_to_confirm', {
                                  'count': 3 - _points.length,
                                  'plural': 3 - _points.length == 1 ? '' : 's',
                                }),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _points.isEmpty ? null : _removeLastPoint,
                        child: Text(UiStrings.t('undo')),
                      ),
                      TextButton(
                        onPressed: _points.isEmpty ? null : _clearPoints,
                        child: Text(UiStrings.t('redraw')),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _confirm,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(UiStrings.t('confirm')),
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
