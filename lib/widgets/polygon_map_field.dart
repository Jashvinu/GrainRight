import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../services/local_app_database.dart';
import '../services/location_service.dart';
import '../services/map_tile_cache_service.dart';
import '../services/map_tile_provider.dart';
import '../services/network_status_service.dart';
import '../services/offline_map_service.dart';

class PolygonMapField extends StatefulWidget {
  final String label;
  final bool hasError;
  final Rxn<List<List<double>>> polygonState;

  const PolygonMapField({
    super.key,
    required this.label,
    this.hasError = false,
    required this.polygonState,
  });

  @override
  State<PolygonMapField> createState() => _PolygonMapFieldState();
}

class _PolygonMapFieldState extends State<PolygonMapField> {
  static const _initialZoom = 5.0;
  static const _preferredRegionKey = 'preferred_offline_field_region_id';
  final _controller = MapController();
  final _locationService = LocationService();
  final _tileCacheService = MapTileCacheService();
  final _mapSearchService = OfflineMapService();
  final _networkStatusService = NetworkStatusService();

  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<OfflinePlacePrediction> _predictions = [];

  bool _mapReady = false;
  bool _loadingDownloadedMaps = false;
  bool _searching = false;
  List<LatLng> _currentPoints = [];
  double _targetZoom = _initialZoom;
  List<OfflineMapRegionRecord> _downloadedRegions = const [];
  OfflineMapRegionRecord? _selectedOfflineRegion;
  LatLng _center = const LatLng(
    MapTileCacheService.fallbackCenterLatitude,
    MapTileCacheService.fallbackCenterLongitude,
  );
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.polygonState.value != null &&
        widget.polygonState.value!.isNotEmpty) {
      _currentPoints = widget.polygonState.value!
          .map((pt) => LatLng(pt[1], pt[0]))
          .toList();
      _center = _currentPoints.first;
      _targetZoom = 16;
    } else {
      unawaited(_loadInitialMapTarget());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_tileCacheService.prefetchCoreRegions());
    });
  }

  Future<void> _loadInitialMapTarget() async {
    final regions = await _refreshDownloadedRegions();
    if (!mounted) return;

    final hasNetwork = await _networkStatusService.hasNetworkInterface();
    if (!mounted) return;

    if (!hasNetwork && regions.isNotEmpty) {
      final preferred = await _preferredOfflineRegion(regions);
      if (!mounted) return;
      if (preferred != null) {
        _focusOfflineRegion(preferred, showSnack: false);
        return;
      }
    }

    await _loadLocation();
  }

  Future<List<OfflineMapRegionRecord>> _refreshDownloadedRegions() async {
    try {
      final regions = await _mapSearchService.listRegions();
      final readyRegions = regions.where(_canUseOfflineRegion).toList();
      if (mounted) setState(() => _downloadedRegions = readyRegions);
      return readyRegions;
    } catch (e) {
      debugPrint('[PolygonMapField._refreshDownloadedRegions] $e');
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
    final center = LatLng(location.latitude, location.longitude);
    setState(() {
      _center = center;
      _targetZoom = 18;
      _selectedOfflineRegion = null;
    });
    unawaited(
      _tileCacheService.prefetchWideRegion(
        latitude: location.latitude,
        longitude: location.longitude,
      ),
    );
    _moveMap(center, 18);
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
        'No complete downloaded field maps are available yet.',
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
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    UiStrings.t('select_downloaded_field_map'),
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
                  '${region.radiusKm.toStringAsFixed(0)} km · zoom ${region.minZoom}-${region.maxZoom} · ${region.downloadedTileCount}/${region.tileCount} tiles',
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
    final center = LatLng(region.centerLat, region.centerLng);
    final zoom = region.maxZoom.clamp(10, mapTileMaxZoom.toInt()).toDouble();
    setState(() {
      _center = center;
      _targetZoom = zoom;
      _selectedOfflineRegion = region;
    });
    unawaited(_savePreferredOfflineRegion(region.regionId));
    _moveMap(center, zoom);
    if (showSnack) {
      Get.snackbar(
        'Downloaded map selected',
        'Loaded ${region.label} for offline boundary marking.',
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _mapSearchService.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _currentPoints.add(position);
      _updateState();
    });
  }

  void _undoLastPoint() {
    if (_currentPoints.isNotEmpty) {
      setState(() {
        _currentPoints.removeLast();
        _updateState();
      });
    }
  }

  void _clearPolygon() {
    setState(() {
      _currentPoints.clear();
      _updateState();
    });
  }

  void _updateState() {
    if (_currentPoints.isEmpty) {
      widget.polygonState.value = null;
    } else {
      widget.polygonState.value = _currentPoints
          .map((pt) => [pt.longitude, pt.latitude])
          .toList();
    }
  }

  void _searchPlaces(String input) {
    _searchDebounce?.cancel();
    final query = input.trim();
    _searchGeneration += 1;
    final generation = _searchGeneration;

    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _predictions = [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final proximity = _mapReady ? _controller.camera.center : _center;
        final predictions = await _mapSearchService.searchPlaces(
          query,
          languageCode: LocaleText.languageCode(),
          proximityLatitude: proximity.latitude,
          proximityLongitude: proximity.longitude,
        );
        if (!mounted || generation != _searchGeneration) return;
        setState(() => _predictions = predictions);
      } catch (e) {
        if (mounted && generation == _searchGeneration) {
          setState(() => _predictions = []);
        }
        debugPrint('Search error: $e');
      } finally {
        if (mounted && generation == _searchGeneration) {
          setState(() => _searching = false);
        }
      }
    });
  }

  Future<void> _goToPlace(OfflinePlacePrediction prediction) async {
    _searchDebounce?.cancel();
    _searchGeneration += 1;
    setState(() {
      _predictions = [];
      _searching = false;
      _searchController.text = prediction.address ?? prediction.title;
    });
    FocusScope.of(context).unfocus();

    try {
      final place = await _mapSearchService.resolvePrediction(prediction);
      if (place != null) {
        final center = LatLng(place.latitude, place.longitude);
        setState(() {
          _center = center;
          _targetZoom = 18;
          _selectedOfflineRegion = null;
        });
        _moveMap(center, 18);
      }
    } catch (e) {
      debugPrint('Details error: $e');
    }
  }

  void _zoomBy(double delta) {
    if (!_mapReady || !mounted) return;
    try {
      final camera = _controller.camera;
      final nextZoom = (camera.zoom + delta)
          .clamp(mapTileMinZoom, mapTileMaxZoom)
          .toDouble();
      _controller.move(camera.center, nextZoom);
    } catch (e) {
      debugPrint('[PolygonMapField._zoomBy] $e');
    }
  }

  void _moveMap(LatLng center, double zoom) {
    if (!_mapReady) return;
    try {
      _controller.move(center, zoom);
    } catch (e) {
      debugPrint('[PolygonMapField._moveMap] $e');
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            widget.label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        Container(
          height: 400,
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.hasError ? Colors.red : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: _currentPoints.isEmpty
                        ? _center
                        : _currentPoints.first,
                    initialZoom: _currentPoints.isEmpty ? _targetZoom : 16,
                    minZoom: mapTileMinZoom,
                    maxZoom: mapTileMaxZoom,
                    initialCameraFit: _currentPoints.length >= 3
                        ? CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(_currentPoints),
                            padding: const EdgeInsets.all(40),
                          )
                        : null,
                    onTap: (_, latLng) => _onMapTap(latLng),
                    onMapReady: () {
                      _mapReady = true;
                      if (_currentPoints.isEmpty) {
                        _moveMap(_center, _targetZoom);
                      }
                    },
                  ),
                  children: [
                    OfflineMapBackground(
                      message: UiStrings.t('offline_map_tap_boundary'),
                    ),
                    OfflineAwareTileLayer(
                      urlTemplate: fieldImageryTileUrl,
                      offlineUrlTemplateOverride:
                          _selectedOfflineRegion?.sourceId,
                      maxOfflineNativeZoom: _selectedOfflineRegion?.maxZoom,
                    ),
                    if (_currentPoints.length >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _currentPoints,
                            color: AppTheme.green.withValues(alpha: 0.22),
                            borderColor: AppTheme.green,
                            borderStrokeWidth: 3,
                          ),
                        ],
                      ),
                    CircleLayer(
                      circles: _currentPoints
                          .map(
                            (point) => CircleMarker(
                              point: point,
                              radius: 7,
                              color: AppTheme.greenDark,
                              borderColor: Colors.white,
                              borderStrokeWidth: 1.5,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),

                // Search Bar Overlay
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: _searchPlaces,
                                decoration: InputDecoration(
                                  hintText: UiStrings.t(
                                    'search_village_field_area',
                                  ),
                                  border: InputBorder.none,
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: Colors.grey,
                                  ),
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
                                          icon: const Icon(
                                            Icons.clear,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            _searchDebounce?.cancel();
                                            _searchController.clear();
                                            _searchGeneration += 1;
                                            setState(() {
                                              _predictions = [];
                                              _searching = false;
                                            });
                                          },
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            elevation: 2,
                            child: IconButton(
                              tooltip: UiStrings.t('downloaded_maps'),
                              onPressed: _loadingDownloadedMaps
                                  ? null
                                  : _selectDownloadedMap,
                              icon: _loadingDownloadedMaps
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.offline_pin_outlined),
                            ),
                          ),
                        ],
                      ),
                      if (_selectedOfflineRegion != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFD9E4D8),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Text(
                                  '${_selectedOfflineRegion!.label} · Z${_selectedOfflineRegion!.minZoom}-${_selectedOfflineRegion!.maxZoom}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.greenDark,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_predictions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Material(
                            color: Colors.white,
                            clipBehavior: Clip.antiAlias,
                            borderRadius: BorderRadius.circular(8),
                            elevation: 2,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _predictions.length,
                                itemBuilder: (context, index) {
                                  final p = _predictions[index];
                                  return ListTile(
                                    leading: const Icon(
                                      Icons.location_on,
                                      color: Colors.grey,
                                    ),
                                    title: Text(p.title),
                                    subtitle: p.subtitle.isEmpty
                                        ? null
                                        : Text(p.subtitle),
                                    onTap: () => _goToPlace(p),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Controls Overlay
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Row(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'undo_btn',
                        backgroundColor: Colors.white,
                        onPressed: _currentPoints.isNotEmpty
                            ? _undoLastPoint
                            : null,
                        child: Icon(
                          Icons.undo,
                          color: _currentPoints.isNotEmpty
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'clear_btn',
                        backgroundColor: Colors.white,
                        onPressed: _currentPoints.isNotEmpty
                            ? _clearPolygon
                            : null,
                        child: Icon(
                          Icons.delete_outline,
                          color: _currentPoints.isNotEmpty
                              ? Colors.red
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _MapZoomControls(
                    onZoomIn: () => _zoomBy(1),
                    onZoomOut: () => _zoomBy(-1),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 12.0),
            child: Text(
              UiStrings.t('farm_location_required'),
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _MapZoomControls({required this.onZoomIn, required this.onZoomOut});

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
            tooltip: UiStrings.t('zoom_in'),
            onPressed: onZoomIn,
            icon: const Icon(Icons.add_rounded),
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: UiStrings.t('zoom_out'),
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded),
          ),
        ],
      ),
    );
  }
}
