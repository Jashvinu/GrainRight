import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final OfflineMapService? mapService;
  final bool loadMapTiles;

  const BoundaryPolygonScreen({
    super.key,
    this.initialPolygon,
    this.mapService,
    this.loadMapTiles = true,
  });

  @override
  State<BoundaryPolygonScreen> createState() => _BoundaryPolygonScreenState();
}

enum _BoundaryMapMode { browse, draw }

enum _BoundaryBaseMap { roads, satellite }

class _BoundaryPolygonScreenState extends State<BoundaryPolygonScreen> {
  static const _preferredRegionKey = 'preferred_offline_field_region_id';
  final _mapKey = GlobalKey();
  final _mapController = MapController();
  final _locationService = LocationService();
  final _networkStatusService = NetworkStatusService();
  late final OfflineMapService _offlineMapService;
  late final bool _ownsOfflineMapService;
  final _searchController = TextEditingController();

  final List<LatLng> _points = [];
  Timer? _searchDebounce;
  List<OfflinePlacePrediction> _searchResults = const [];

  bool _mapReady = false;
  bool _loadingLocation = true;
  bool _loadingDownloadedMaps = false;
  bool _searching = false;
  String? _searchError;
  int _searchGeneration = 0;
  _BoundaryMapMode _mode = _BoundaryMapMode.browse;
  _BoundaryBaseMap _baseMap = _BoundaryBaseMap.roads;
  OfflineMapRegionRecord? _selectedOfflineRegion;
  LatLng? _searchedPlaceCenter;
  String? _searchedPlaceLabel;
  LatLng _center = LatLng(
    SatelliteConfig.defaultCenter.latitude,
    SatelliteConfig.defaultCenter.longitude,
  );
  double _zoom = SatelliteConfig.defaultZoom;

  @override
  void initState() {
    super.initState();
    _ownsOfflineMapService = widget.mapService == null;
    _offlineMapService = widget.mapService ?? OfflineMapService();
    if (widget.initialPolygon != null && widget.initialPolygon!.isNotEmpty) {
      _points.addAll(
        _openRing(PolygonGeometry.fromGeoJsonRing(widget.initialPolygon!)),
      );
      if (_points.isNotEmpty) {
        _center = _points.first;
        _zoom = 18;
        _loadingLocation = false;
        _mode = _BoundaryMapMode.draw;
      }
    } else {
      unawaited(_loadInitialTarget());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    if (_ownsOfflineMapService) _offlineMapService.dispose();
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
      await Get.toNamed<void>('/offline-maps');
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
      _baseMap = _BoundaryBaseMap.satellite;
      _mode = _BoundaryMapMode.browse;
      _searchResults = const [];
      _searchError = null;
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchGeneration += 1;
    final generation = _searchGeneration;
    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _searchResults = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final proximity = _mapReady ? _mapController.camera.center : _center;
        final results = await _offlineMapService.searchPlaces(
          query,
          languageCode: LocaleText.languageCode(),
          proximityLatitude: proximity.latitude,
          proximityLongitude: proximity.longitude,
        );
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _searchResults = results;
          _searchError = results.isEmpty
              ? UiStrings.t('no_map_places_found')
              : null;
        });
      } catch (error) {
        if (!mounted || generation != _searchGeneration) return;
        final missingKey =
            error is StateError &&
            error.toString().contains('MAPTILER_API_KEY');
        setState(() {
          _searchResults = const [];
          _searchError = UiStrings.t(
            missingKey ? 'map_search_not_configured' : 'map_search_failed',
          );
        });
      } finally {
        if (mounted && generation == _searchGeneration) {
          setState(() => _searching = false);
        }
      }
    });
  }

  Future<void> _selectSearchResult(OfflinePlacePrediction prediction) async {
    _searchDebounce?.cancel();
    _searchGeneration += 1;
    FocusScope.of(context).unfocus();
    setState(() {
      _searchResults = const [];
      _searchError = null;
      _searching = true;
      _searchController.text = prediction.address ?? prediction.title;
    });

    try {
      final place = await _offlineMapService.resolvePrediction(prediction);
      if (!mounted) return;
      if (place == null) {
        setState(() => _searchError = UiStrings.t('could_not_load_place'));
        return;
      }
      final center = LatLng(place.latitude, place.longitude);
      setState(() {
        _center = center;
        _zoom = 18;
        _selectedOfflineRegion = null;
        _searchedPlaceCenter = center;
        _searchedPlaceLabel = place.address.trim().isEmpty
            ? place.title
            : place.address;
        _baseMap = _BoundaryBaseMap.roads;
        _mode = _BoundaryMapMode.draw;
      });
      _moveMap(center, 18);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveMap(center, 18);
      });
      Get.snackbar(
        UiStrings.t('place_found'),
        UiStrings.f('centered_on_draw_boundary', {'region': place.title}),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _searchError = UiStrings.t('could_not_load_place'));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchGeneration += 1;
    _searchController.clear();
    setState(() {
      _searchResults = const [];
      _searchError = null;
      _searching = false;
    });
  }

  void _selectBaseMap(_BoundaryBaseMap baseMap) {
    if (_baseMap == baseMap) return;
    setState(() => _baseMap = baseMap);
  }

  void _selectMapMode(_BoundaryMapMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
  }

  void _addPoint(TapPosition _, LatLng point) {
    if (_mode != _BoundaryMapMode.draw) return;
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
    final issue = PolygonGeometry.boundaryIssue(_points);
    if (issue != null) {
      Get.snackbar(
        issue == PolygonBoundaryIssue.tooFewDistinctPoints
            ? UiStrings.t('too_few_boundary_points')
            : UiStrings.t('invalid_farm_boundary'),
        _boundaryIssueMessage(issue),
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    Get.back(result: PolygonGeometry.toGeoJsonRing(_points));
  }

  String _boundaryIssueMessage(PolygonBoundaryIssue issue) {
    return switch (issue) {
      PolygonBoundaryIssue.tooFewDistinctPoints => UiStrings.t(
        'add_three_corners_to_save_boundary',
      ),
      PolygonBoundaryIssue.repeatedPoint => UiStrings.t(
        'boundary_point_repeated',
      ),
      PolygonBoundaryIssue.selfIntersection => UiStrings.t(
        'boundary_lines_cross',
      ),
      PolygonBoundaryIssue.zeroArea => UiStrings.t('boundary_has_no_area'),
    };
  }

  List<LatLng> _openRing(List<LatLng> ring) {
    if (ring.isEmpty) return ring;
    if (ring.length > 1 &&
        ring.first.latitude == ring.last.latitude &&
        ring.first.longitude == ring.last.longitude) {
      return [...ring]..removeLast();
    }
    return ring;
  }

  @override
  Widget build(BuildContext context) {
    final areaHectares = PolygonGeometry.areaHectares(_points);
    final boundaryIssue = PolygonGeometry.boundaryIssue(_points);
    final instruction = _mode == _BoundaryMapMode.browse
        ? UiStrings.t('browse_map_then_draw')
        : _points.isEmpty
        ? UiStrings.t('tap_corners_boundary')
        : _points.length == 1
        ? UiStrings.t('add_second_boundary_point')
        : _points.length == 2
        ? UiStrings.t('add_third_boundary_point')
        : UiStrings.t('drag_points_confirm_boundary');
    final boundarySummary = boundaryIssue != null && _points.length >= 3
        ? _boundaryIssueMessage(boundaryIssue)
        : _points.length >= 3
        ? UiStrings.f('hectare_value', {
            'value': LocaleText.number(areaHectares, fractionDigits: 2),
          })
        : UiStrings.f('points_more_to_confirm', {
            'count': 3 - _points.length,
            'plural': 3 - _points.length == 1 ? '' : 's',
          });

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('draw_farm_boundary')),
      ),
      body: Stack(
        key: _mapKey,
        children: [
          FlutterMap(
            key: const Key('farm_boundary_map'),
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
              if (widget.loadMapTiles)
                OfflineAwareTileLayer(
                  key: const ValueKey('farm-boundary-base-map-layer'),
                  urlTemplate: _baseMap == _BoundaryBaseMap.roads
                      ? openStreetMapTileUrl
                      : fieldImageryTileUrl,
                  offlineUrlTemplateOverride:
                      _baseMap == _BoundaryBaseMap.satellite
                      ? _selectedOfflineRegion?.sourceId
                      : null,
                  maxNativeZoom: _baseMap == _BoundaryBaseMap.roads
                      ? mapTileMaxNativeZoom
                      : fieldImageryMaxNativeZoom,
                  maxOfflineNativeZoom: _baseMap == _BoundaryBaseMap.satellite
                      ? _selectedOfflineRegion?.maxZoom
                      : null,
                  keepBuffer: 3,
                  panBuffer: 1,
                  tileDisplay: const TileDisplay.fadeIn(
                    duration: Duration(milliseconds: 80),
                    startOpacity: 0.35,
                    reloadStartOpacity: 0.35,
                  ),
                ),
              if (widget.loadMapTiles &&
                  _baseMap == _BoundaryBaseMap.satellite &&
                  shouldShowFieldReferenceLabels(fieldImageryTileUrl))
                ...fieldReferenceTileLayers(
                  keepBuffer: 3,
                  panBuffer: 1,
                  tileDisplay: const TileDisplay.fadeIn(
                    duration: Duration(milliseconds: 80),
                    startOpacity: 0.35,
                    reloadStartOpacity: 0.35,
                  ),
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
                  if (_searchedPlaceCenter != null)
                    Marker(
                      point: _searchedPlaceCenter!,
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      child: Tooltip(
                        message: _searchedPlaceLabel ?? '',
                        child: const Icon(
                          key: Key('farm_boundary_search_marker'),
                          Icons.location_pin,
                          color: Color(0xFFD84315),
                          size: 48,
                          shadows: [Shadow(color: Colors.white, blurRadius: 5)],
                        ),
                      ),
                    ),
                  for (var i = 0; i < _points.length; i++)
                    Marker(
                      point: _points[i],
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: _mode == _BoundaryMapMode.draw
                            ? (details) => _movePoint(i, details.globalPosition)
                            : null,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: AppTheme.greenDark,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
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
            top: 12,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Colors.white.withValues(alpha: 0.97),
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: TextField(
                      key: const Key('farm_boundary_search'),
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: UiStrings.t('search_village_field_area'),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                            ? IconButton(
                                tooltip: UiStrings.t('clear_search'),
                                onPressed: _clearSearch,
                                icon: const Icon(Icons.close_rounded),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_searchResults.isNotEmpty)
                    Material(
                      color: Colors.white,
                      elevation: 4,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final result in _searchResults.take(4))
                            ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.location_on_outlined,
                                color: AppTheme.green,
                              ),
                              title: Text(
                                result.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: result.subtitle.isEmpty
                                  ? null
                                  : Text(
                                      result.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () => _selectSearchResult(result),
                            ),
                        ],
                      ),
                    ),
                  if (_searchError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            _searchError!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      key: const Key('farm_boundary_compact_controls'),
                      constraints: const BoxConstraints(maxWidth: 284),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final mapView = _BoundaryControlGroup(
                                key: const Key('farm_boundary_map_view_group'),
                                semanticLabel: UiStrings.t('choose_map_view'),
                                icon: Icons.layers_outlined,
                                first: _BoundaryModeButton(
                                  key: const Key('farm_boundary_road_map'),
                                  selected: _baseMap == _BoundaryBaseMap.roads,
                                  label: UiStrings.t('roads_view_short'),
                                  semanticLabel: UiStrings.t('roads_view'),
                                  onTap: () =>
                                      _selectBaseMap(_BoundaryBaseMap.roads),
                                ),
                                second: _BoundaryModeButton(
                                  key: const Key('farm_boundary_satellite_map'),
                                  selected:
                                      _baseMap == _BoundaryBaseMap.satellite,
                                  label: UiStrings.t('farm_view_short'),
                                  semanticLabel: UiStrings.t('farm_view'),
                                  onTap: () => _selectBaseMap(
                                    _BoundaryBaseMap.satellite,
                                  ),
                                ),
                              );
                              final mapAction = _BoundaryControlGroup(
                                key: const Key(
                                  'farm_boundary_map_action_group',
                                ),
                                semanticLabel: UiStrings.t(
                                  'choose_marking_mode',
                                ),
                                icon: Icons.touch_app_outlined,
                                first: _BoundaryModeButton(
                                  key: const Key('farm_boundary_browse_mode'),
                                  selected: _mode == _BoundaryMapMode.browse,
                                  label: UiStrings.t('move_map_short'),
                                  semanticLabel: UiStrings.t('move_map'),
                                  onTap: () =>
                                      _selectMapMode(_BoundaryMapMode.browse),
                                ),
                                second: _BoundaryModeButton(
                                  key: const Key('farm_boundary_draw_mode'),
                                  selected: _mode == _BoundaryMapMode.draw,
                                  label: UiStrings.t('mark_farm_short'),
                                  semanticLabel: UiStrings.t('mark_farm'),
                                  onTap: () =>
                                      _selectMapMode(_BoundaryMapMode.draw),
                                ),
                              );

                              if (constraints.maxWidth < 260) {
                                return Column(
                                  children: [
                                    mapView,
                                    const SizedBox(height: 4),
                                    mapAction,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: mapView),
                                  const SizedBox(width: 6),
                                  Expanded(child: mapAction),
                                ],
                              );
                            },
                          ),
                          if (_searchedPlaceLabel != null ||
                              (_baseMap == _BoundaryBaseMap.satellite &&
                                  _selectedOfflineRegion != null)) ...[
                            const SizedBox(height: 6),
                            DecoratedBox(
                              key: const Key('farm_boundary_map_status'),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.97),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: const Color(0xFFD9E4D8),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 7,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_searchedPlaceLabel != null)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on_outlined,
                                            color: Color(0xFFD84315),
                                            size: 17,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              UiStrings.f(
                                                'searched_place_marking',
                                                {
                                                  'region':
                                                      _searchedPlaceLabel!,
                                                },
                                              ),
                                              key: const Key(
                                                'farm_boundary_searched_place_label',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppTheme.greenDark,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (_searchedPlaceLabel != null &&
                                        _baseMap ==
                                            _BoundaryBaseMap.satellite &&
                                        _selectedOfflineRegion != null)
                                      const SizedBox(height: 5),
                                    if (_baseMap ==
                                            _BoundaryBaseMap.satellite &&
                                        _selectedOfflineRegion != null)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.offline_pin_rounded,
                                            color: AppTheme.greenDark,
                                            size: 17,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              _selectedOfflineRegion!.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppTheme.greenDark,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 142,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    key: const Key('farm_boundary_undo_button'),
                    heroTag: 'farm-boundary-undo',
                    tooltip: UiStrings.t('undo_last_point'),
                    onPressed: _points.isEmpty ? null : _removeLastPoint,
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.greenDark,
                    child: const Icon(Icons.undo_rounded),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    key: const Key('farm_boundary_clear_button'),
                    heroTag: 'farm-boundary-clear',
                    tooltip: UiStrings.t('clear_boundary'),
                    onPressed: _points.isEmpty ? null : _clearPoints,
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.error,
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    key: const Key('farm_boundary_download_maps_fab'),
                    heroTag: 'farm-boundary-download-maps',
                    tooltip: UiStrings.t('downloaded_maps'),
                    onPressed: _loadingDownloadedMaps
                        ? null
                        : _selectDownloadedMap,
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.greenDark,
                    child: _loadingDownloadedMaps
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_for_offline_outlined),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    key: const Key('farm_boundary_recenter_fab'),
                    heroTag: 'farm-boundary-recenter',
                    tooltip: UiStrings.t('re_center'),
                    onPressed: _loadingLocation
                        ? null
                        : () => _moveMap(_center, _zoom),
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.greenDark,
                    child: const Icon(Icons.my_location_rounded),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 12,
            bottom: 142,
            child: _MapAttributionButton(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  key: const Key('farm_boundary_bottom_panel'),
                  constraints: const BoxConstraints(maxWidth: 304),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD9E4D8)),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppTheme.greenPale,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _mode == _BoundaryMapMode.draw
                                      ? Icons.touch_app_outlined
                                      : Icons.open_with_rounded,
                                  color: AppTheme.greenDark,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  instruction,
                                  key: const Key('farm_boundary_instruction'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 48,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.greenPale,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.straighten_rounded,
                                        size: 16,
                                        color: AppTheme.greenDark,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          boundarySummary,
                                          key: const Key(
                                            'boundary_point_summary',
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            height: 1.05,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.greenDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Semantics(
                                label: UiStrings.t('save_farm_boundary'),
                                button: true,
                                child: Tooltip(
                                  message: UiStrings.t('save_farm_boundary'),
                                  child: SizedBox(
                                    width: 112,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      key: const Key(
                                        'farm_boundary_confirm_button',
                                      ),
                                      onPressed: _confirm,
                                      icon: const Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 19,
                                      ),
                                      label: Text(UiStrings.t('save_short')),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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

class _BoundaryModeButton extends StatelessWidget {
  final bool selected;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  const _BoundaryModeButton({
    super.key,
    required this.selected,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          color: selected ? AppTheme.green : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : AppTheme.greenDark,
                          fontSize: 10.5,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
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
    );
  }
}

class _BoundaryControlGroup extends StatelessWidget {
  final String semanticLabel;
  final IconData icon;
  final Widget first;
  final Widget second;

  const _BoundaryControlGroup({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.first,
    required this.second,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFD9E4D8)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Tooltip(
              message: semanticLabel,
              child: Container(
                width: 27,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                ),
                child: Icon(icon, size: 15, color: AppTheme.greenDark),
              ),
            ),
            Container(width: 1, height: 30, color: const Color(0xFFD9E4D8)),
            Expanded(child: first),
            Expanded(child: second),
          ],
        ),
      ),
    );
  }
}

class _MapAttributionButton extends StatelessWidget {
  const _MapAttributionButton();

  static final _sources = <({String label, Uri url})>[
    (label: 'MapTiler', url: Uri.parse('https://www.maptiler.com/copyright/')),
    (
      label: 'OpenStreetMap contributors',
      url: Uri.parse('https://www.openstreetmap.org/copyright'),
    ),
    (
      label: 'Esri',
      url: Uri.parse(
        'https://www.esri.com/en-us/legal/terms/full-master-agreement',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<Uri>(
        tooltip: UiStrings.t('map_data_sources'),
        onSelected: (url) =>
            launchUrl(url, mode: LaunchMode.externalApplication),
        itemBuilder: (context) => [
          for (final source in _sources)
            PopupMenuItem<Uri>(
              value: source.url,
              child: Text('© ${source.label}'),
            ),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            '©',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
