import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/satellite_config.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../../services/local_app_database.dart';
import '../../services/map_tile_provider.dart';
import '../../services/offline_map_service.dart';
import '../../utils/polygon_geometry.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/farm_controller.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';

class DrawPolygonScreen extends StatefulWidget {
  const DrawPolygonScreen({super.key});

  @override
  State<DrawPolygonScreen> createState() => _DrawPolygonScreenState();
}

class _DrawPolygonScreenState extends State<DrawPolygonScreen> {
  static const _preferredRegionKey = 'preferred_offline_field_region_id';
  final _mapController = MapController();
  final _offlineMapService = OfflineMapService();
  final List<LatLng> _points = [];
  bool _isSaving = false;
  bool _mapReady = false;
  bool _loadingDownloadedMaps = false;
  LatLng _center = SatelliteConfig.defaultCenter;
  double _zoom = SatelliteConfig.defaultZoom;
  OfflineMapRegionRecord? _selectedOfflineRegion;

  @override
  void initState() {
    super.initState();
    final auth = Get.find<AuthController>();
    if (!auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAllNamed('/satellite/login');
      });
    }
    unawaited(_loadPreferredOfflineRegion());
  }

  @override
  void dispose() {
    _offlineMapService.dispose();
    super.dispose();
  }

  Future<void> _loadPreferredOfflineRegion() async {
    final regions = await _usableOfflineRegions();
    if (!mounted || regions.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final preferredId = prefs.getString(_preferredRegionKey);
    final region = regions.firstWhere(
      (item) => item.regionId == preferredId,
      orElse: () => regions.first,
    );
    _focusOfflineRegion(region, showSnack: false);
  }

  Future<List<OfflineMapRegionRecord>> _usableOfflineRegions() async {
    try {
      final regions = await _offlineMapService.listRegions();
      return regions.where((region) {
        if (region.tileCount <= 0 || region.downloadedTileCount <= 0) {
          return false;
        }
        return region.status == 'ready' ||
            region.downloadedTileCount >= region.tileCount;
      }).toList();
    } catch (e) {
      debugPrint('[DrawPolygonScreen._usableOfflineRegions] $e');
      return const [];
    }
  }

  Future<void> _selectDownloadedMap() async {
    if (_loadingDownloadedMaps) return;
    setState(() => _loadingDownloadedMaps = true);
    final regions = await _usableOfflineRegions();
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
    if (_mapReady) {
      try {
        _mapController.move(center, zoom);
      } catch (e) {
        debugPrint('[DrawPolygonScreen._focusOfflineRegion] $e');
      }
    }
    unawaited(_savePreferredOfflineRegion(region.regionId));
    if (showSnack) {
      Get.snackbar(
        UiStrings.t('downloaded_map_selected'),
        UiStrings.f('loaded_offline_boundary_map', {'region': region.label}),
      );
    }
  }

  Future<void> _savePreferredOfflineRegion(String regionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredRegionKey, regionId);
  }

  void _addPoint(TapPosition _, LatLng latLng) {
    setState(() => _points.add(latLng));
  }

  void _removeLastPoint() {
    if (_points.isNotEmpty) setState(() => _points.removeLast());
  }

  void _clearPoints() {
    setState(() => _points.clear());
  }

  Future<void> _onSave() async {
    final boundaryIssue = PolygonGeometry.boundaryIssue(_points);
    if (boundaryIssue != null) {
      Get.snackbar(
        boundaryIssue == PolygonBoundaryIssue.tooFewDistinctPoints
            ? UiStrings.t('too_few_points')
            : UiStrings.t('invalid_farm_boundary'),
        switch (boundaryIssue) {
          PolygonBoundaryIssue.tooFewDistinctPoints => UiStrings.t(
            'draw_at_least_three_points',
          ),
          PolygonBoundaryIssue.repeatedPoint => UiStrings.t(
            'boundary_point_repeated',
          ),
          PolygonBoundaryIssue.selfIntersection => UiStrings.t(
            'boundary_lines_cross',
          ),
          PolygonBoundaryIssue.zeroArea => UiStrings.t('boundary_has_no_area'),
        },
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              UiStrings.t('name_your_farm'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: UiStrings.t('farm_name'),
                prefixIcon: const Icon(Icons.grass_outlined),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(UiStrings.t('save_farm')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(UiStrings.t('cancel')),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final name = nameCtrl.text.trim().isEmpty
        ? UiStrings.t('my_farm')
        : nameCtrl.text.trim();

    setState(() => _isSaving = true);
    final farmCtrl = Get.find<FarmController>();
    final success = await farmCtrl.saveFarm(name: name, points: _points);
    setState(() => _isSaving = false);

    if (success) {
      Get.offAllNamed('/satellite/shell');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('draw_your_farm')),
        actions: [
          if (_points.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: UiStrings.t('undo_last_point'),
              onPressed: _removeLastPoint,
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
          if (_points.length >= 3)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _onSave,
                    child: Text(
                      UiStrings.t('save'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _zoom,
              minZoom: mapTileMinZoom,
              maxZoom: mapTileMaxZoom,
              onTap: _addPoint,
              onMapReady: () {
                _mapReady = true;
                _mapController.move(_center, _zoom);
              },
            ),
            children: [
              OfflineMapBackground(
                message: UiStrings.t('offline_map_tap_draw_farm'),
              ),
              ...fieldImageryTileLayers(
                offlineUrlTemplateOverride: _selectedOfflineRegion?.sourceId,
                maxOfflineNativeZoom: _selectedOfflineRegion?.maxZoom,
              ),
              if (_points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _points,
                      color: AppTheme.green.withValues(alpha: 0.22),
                      borderColor: AppTheme.green,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
              CircleLayer(
                circles: _points
                    .map(
                      (p) => CircleMarker(
                        point: p,
                        radius: 7,
                        color: AppTheme.greenDark,
                        borderColor: Colors.white,
                        borderStrokeWidth: 1.5,
                        useRadiusInMeter: false,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),

          // Bottom instruction card
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
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      color: AppTheme.green,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _points.isEmpty
                                ? UiStrings.t('tap_map_add_boundary_points')
                                : _points.length >= 3
                                ? UiStrings.f('points_added_save_when_done', {
                                    'count': _points.length,
                                    'plural': _points.length == 1 ? '' : 's',
                                  })
                                : UiStrings.f('points_added_add_more', {
                                    'count': _points.length,
                                    'plural': _points.length == 1 ? '' : 's',
                                    'remaining': 3 - _points.length,
                                  }),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textDark,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_points.isNotEmpty)
                      TextButton(
                        onPressed: _clearPoints,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(40, 32),
                        ),
                        child: Text(
                          UiStrings.t('clear'),
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
