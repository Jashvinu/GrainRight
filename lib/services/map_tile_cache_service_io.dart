import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/runtime_config.dart';
import 'network_status_service.dart';

class MapTileCacheService {
  static const defaultTileUrl = '';
  static const fallbackCenterLatitude = 19.7515;
  static const fallbackCenterLongitude = 75.7139;
  static const statusUnknown = 'unknown';
  static const statusWaitingForInternet = 'waiting_for_internet';
  static const statusDownloading = 'downloading';
  static const statusReady = 'ready';
  static const statusPartial = 'partial';
  static const statusFailed = 'failed';

  static const _cacheVersion = 'v1';
  static const _lastPrefetchKey = 'offline_map_last_prefetch';
  static const _lastPrefetchLatKey = 'offline_map_last_prefetch_lat';
  static const _lastPrefetchLngKey = 'offline_map_last_prefetch_lng';
  static const _regionMetadataKey = 'offline_map_region_metadata_v1';
  static const _lastPrefetchMinInterval = Duration(hours: 12);
  static const _prefetchMoveThresholdKm = 5.0;
  static const _maxTilesPerRun = 260;
  static const _source = 'maptiler_field_imagery';
  static const _offlineFallbackTimeout = Duration(milliseconds: 600);
  static final Map<String, Future<MapTileCacheSnapshot>>
  _regionPrefetchInFlight = {};
  final NetworkStatusService _networkStatusService = NetworkStatusService();

  static const coreRegions = [
    OfflineMapRegion(
      id: 'nashik',
      label: 'Nashik',
      latitude: 19.9975,
      longitude: 73.7898,
      radiusKm: 35,
    ),
    OfflineMapRegion(
      id: 'akole',
      label: 'Akole',
      latitude: 19.5406,
      longitude: 74.0054,
      radiusKm: 28,
    ),
    OfflineMapRegion(
      id: 'sangamner',
      label: 'Sangamner',
      latitude: 19.5678,
      longitude: 74.2115,
      radiusKm: 28,
    ),
  ];

  Future<String?> localTileTemplate() async {
    final root = await _sourceDirectory();
    final path = root.path.replaceAll(r'\', '/');
    return '$path/{z}/{x}/{y}.png';
  }

  Future<List<MapTileCacheSnapshot>> loadRegionSnapshots() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadSnapshotMap(prefs).values.toList()
      ..sort((a, b) => a.regionId.compareTo(b.regionId));
  }

  Future<void> prefetchCoreRegions({
    String urlTemplate = defaultTileUrl,
    bool force = false,
  }) async {
    final effectiveUrlTemplate = _effectiveTileUrlTemplate(urlTemplate);
    for (final region in coreRegions) {
      await prefetchRegion(
        region: region,
        urlTemplate: effectiveUrlTemplate,
        force: force,
        plans: _plansForRadius(region.radiusKm),
      );
    }
  }

  Future<void> prefetchWideRegion({
    required double latitude,
    required double longitude,
    String urlTemplate = defaultTileUrl,
    bool force = false,
  }) async {
    final effectiveUrlTemplate = _effectiveTileUrlTemplate(urlTemplate);
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_lastPrefetchKey) ?? '');
    final lastLat = prefs.getDouble(_lastPrefetchLatKey);
    final lastLng = prefs.getDouble(_lastPrefetchLngKey);
    final movedKm = lastLat == null || lastLng == null
        ? double.infinity
        : _distanceKm(latitude, longitude, lastLat, lastLng);
    if (!force &&
        last != null &&
        DateTime.now().toUtc().difference(last) < _lastPrefetchMinInterval &&
        movedKm < _prefetchMoveThresholdKm) {
      return;
    }

    final snapshot = await prefetchRegion(
      region: OfflineMapRegion(
        id: 'current_location',
        label: 'Current location',
        latitude: latitude,
        longitude: longitude,
        radiusKm: 40,
      ),
      urlTemplate: effectiveUrlTemplate,
      force: force,
    );
    if (snapshot.status == statusReady || snapshot.status == statusPartial) {
      await prefs.setString(
        _lastPrefetchKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      await prefs.setDouble(_lastPrefetchLatKey, latitude);
      await prefs.setDouble(_lastPrefetchLngKey, longitude);
    }
  }

  Future<MapTileCacheSnapshot> prefetchRegion({
    required OfflineMapRegion region,
    String urlTemplate = defaultTileUrl,
    bool force = false,
    List<PrefetchPlan> plans = defaultPrefetchPlans,
  }) {
    final effectiveUrlTemplate = _effectiveTileUrlTemplate(urlTemplate);
    final key = _prefetchKey(
      region: region,
      urlTemplate: effectiveUrlTemplate,
      force: force,
      plans: plans,
    );
    final inFlight = _regionPrefetchInFlight[key];
    if (inFlight != null) return inFlight;

    final future = _prefetchRegionInternal(
      region: region,
      urlTemplate: effectiveUrlTemplate,
      force: force,
      plans: plans,
    );
    _regionPrefetchInFlight[key] = future;
    return future.whenComplete(() => _regionPrefetchInFlight.remove(key));
  }

  Future<MapTileCacheSnapshot> _prefetchRegionInternal({
    required OfflineMapRegion region,
    required String urlTemplate,
    required bool force,
    required List<PrefetchPlan> plans,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = _loadSnapshotMap(prefs)[region.id];
    final updatedAt = existing?.updatedAt;
    if (!force &&
        existing?.status == statusReady &&
        updatedAt != null &&
        DateTime.now().toUtc().difference(updatedAt) <
            _lastPrefetchMinInterval) {
      return existing!;
    }

    if (urlTemplate.trim().isEmpty) {
      final snapshot = MapTileCacheSnapshot(
        regionId: region.id,
        label: region.label,
        latitude: region.latitude,
        longitude: region.longitude,
        radiusKm: region.radiusKm,
        zooms: plans.map((plan) => plan.zoom).toList(),
        status: statusFailed,
        updatedAt: DateTime.now().toUtc(),
        completedTiles: existing?.completedTiles ?? 0,
        totalTiles: existing?.totalTiles ?? 0,
        error: 'MapTiler field imagery is not configured.',
      );
      await _saveSnapshot(prefs, snapshot);
      return snapshot;
    }

    if (!await _networkStatusService.isOnline(
      timeout: _offlineFallbackTimeout,
    )) {
      final snapshot = MapTileCacheSnapshot(
        regionId: region.id,
        label: region.label,
        latitude: region.latitude,
        longitude: region.longitude,
        radiusKm: region.radiusKm,
        zooms: plans.map((plan) => plan.zoom).toList(),
        status: statusWaitingForInternet,
        updatedAt: DateTime.now().toUtc(),
        completedTiles: existing?.completedTiles ?? 0,
        totalTiles: existing?.totalTiles ?? 0,
      );
      await _saveSnapshot(prefs, snapshot);
      return snapshot;
    }

    final root = await _sourceDirectory();
    final client = http.Client();
    try {
      final totalTiles = _plannedTileCount(region, plans);
      var availableTiles = 0;
      var downloadedTiles = 0;
      var failedTiles = 0;
      var hitRunLimit = false;

      tileLoop:
      for (final plan in plans) {
        final bounds = _tileBounds(
          latitude: region.latitude,
          longitude: region.longitude,
          zoom: plan.zoom,
          radiusKm: plan.radiusKm,
        );
        for (var x = bounds.minX; x <= bounds.maxX; x++) {
          for (var y = bounds.minY; y <= bounds.maxY; y++) {
            final result = await _downloadTile(
              client: client,
              root: root,
              urlTemplate: urlTemplate,
              z: plan.zoom,
              x: x,
              y: y,
            );
            switch (result) {
              case _TileFetchResult.exists:
                availableTiles++;
              case _TileFetchResult.downloaded:
                availableTiles++;
                downloadedTiles++;
              case _TileFetchResult.failed:
                failedTiles++;
            }
            if (downloadedTiles >= _maxTilesPerRun) {
              hitRunLimit = true;
              break tileLoop;
            }
          }
        }
      }

      final status = availableTiles >= totalTiles
          ? statusReady
          : hitRunLimit || availableTiles > 0
          ? statusPartial
          : statusFailed;
      final snapshot = MapTileCacheSnapshot(
        regionId: region.id,
        label: region.label,
        latitude: region.latitude,
        longitude: region.longitude,
        radiusKm: region.radiusKm,
        zooms: plans.map((plan) => plan.zoom).toList(),
        status: status,
        updatedAt: DateTime.now().toUtc(),
        completedTiles: availableTiles,
        totalTiles: totalTiles,
        downloadedTiles: downloadedTiles,
        failedTiles: failedTiles,
      );
      await _saveSnapshot(prefs, snapshot);
      return snapshot;
    } catch (e) {
      debugPrint('[MapTileCacheService.prefetchRegion] $e');
      final snapshot = MapTileCacheSnapshot(
        regionId: region.id,
        label: region.label,
        latitude: region.latitude,
        longitude: region.longitude,
        radiusKm: region.radiusKm,
        zooms: plans.map((plan) => plan.zoom).toList(),
        status: statusFailed,
        updatedAt: DateTime.now().toUtc(),
        completedTiles: existing?.completedTiles ?? 0,
        totalTiles: existing?.totalTiles ?? 0,
        error: _shortError(e),
      );
      await _saveSnapshot(prefs, snapshot);
      return snapshot;
    } finally {
      client.close();
    }
  }

  String _prefetchKey({
    required OfflineMapRegion region,
    required String urlTemplate,
    required bool force,
    required List<PrefetchPlan> plans,
  }) {
    final planKey = plans
        .map((plan) => '${plan.zoom}:${plan.radiusKm.toStringAsFixed(3)}')
        .join('|');
    return [
      region.id,
      region.latitude.toStringAsFixed(6),
      region.longitude.toStringAsFixed(6),
      region.radiusKm.toStringAsFixed(3),
      urlTemplate,
      force ? 'force' : 'normal',
      planKey,
    ].join('::');
  }

  String _effectiveTileUrlTemplate(String template) {
    final resolved = template.trim();
    if (resolved.isNotEmpty) return resolved;
    return RuntimeConfig.onlineSatelliteTileUrlTemplate.trim();
  }

  Future<Directory> _sourceDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}/offline_map_tiles/$_cacheVersion/$_source',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  int _plannedTileCount(OfflineMapRegion region, List<PrefetchPlan> plans) {
    var total = 0;
    for (final plan in plans) {
      final bounds = _tileBounds(
        latitude: region.latitude,
        longitude: region.longitude,
        zoom: plan.zoom,
        radiusKm: plan.radiusKm,
      );
      total +=
          (bounds.maxX - bounds.minX + 1) * (bounds.maxY - bounds.minY + 1);
    }
    return total;
  }

  List<PrefetchPlan> _plansForRadius(double radiusKm) {
    return [
      PrefetchPlan(zoom: 12, radiusKm: radiusKm),
      PrefetchPlan(zoom: 13, radiusKm: radiusKm * 0.62),
      PrefetchPlan(zoom: 14, radiusKm: radiusKm * 0.3),
      PrefetchPlan(zoom: 15, radiusKm: radiusKm * 0.15),
      PrefetchPlan(zoom: 16, radiusKm: radiusKm * 0.075),
      PrefetchPlan(zoom: 17, radiusKm: radiusKm * 0.04),
    ];
  }

  Future<_TileFetchResult> _downloadTile({
    required http.Client client,
    required Directory root,
    required String urlTemplate,
    required int z,
    required int x,
    required int y,
  }) async {
    final file = File('${root.path}/$z/$x/$y.png');
    if (await file.exists()) return _TileFetchResult.exists;

    final uri = Uri.parse(
      urlTemplate
          .replaceAll('{z}', z.toString())
          .replaceAll('{x}', x.toString())
          .replaceAll('{y}', y.toString()),
    );
    late final http.Response response;
    try {
      response = await client
          .get(
            uri,
            headers: const {'User-Agent': 'grainright.wrkfarm offline maps'},
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return _TileFetchResult.failed;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _TileFetchResult.failed;
    }
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.bodyBytes, flush: false);
    return _TileFetchResult.downloaded;
  }

  _TileBounds _tileBounds({
    required double latitude,
    required double longitude,
    required int zoom,
    required double radiusKm,
  }) {
    final latDelta = radiusKm / 111.32;
    final lonScale = math
        .cos(latitude * math.pi / 180)
        .abs()
        .clamp(0.2, 1.0)
        .toDouble();
    final lonDelta = radiusKm / (111.32 * lonScale);
    final topLeft = _tileXY(latitude + latDelta, longitude - lonDelta, zoom);
    final bottomRight = _tileXY(
      latitude - latDelta,
      longitude + lonDelta,
      zoom,
    );
    final max = (1 << zoom) - 1;
    return _TileBounds(
      minX: math.max(0, math.min(topLeft.x, bottomRight.x)),
      maxX: math.min(max, math.max(topLeft.x, bottomRight.x)),
      minY: math.max(0, math.min(topLeft.y, bottomRight.y)),
      maxY: math.min(max, math.max(topLeft.y, bottomRight.y)),
    );
  }

  _TileXY _tileXY(double latitude, double longitude, int zoom) {
    final lat = latitude.clamp(-85.05112878, 85.05112878);
    final lon = longitude.clamp(-180.0, 180.0);
    final latRad = lat * math.pi / 180;
    final n = math.pow(2.0, zoom).toDouble();
    final x = ((lon + 180.0) / 360.0 * n).floor();
    final y =
        ((1 - math.log(math.tan(latRad) + (1 / math.cos(latRad))) / math.pi) /
                2 *
                n)
            .floor();
    return _TileXY(x, y);
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusKm * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Map<String, MapTileCacheSnapshot> _loadSnapshotMap(SharedPreferences prefs) {
    final raw = prefs.getString(_regionMetadataKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) {
        return MapEntry(
          key.toString(),
          MapTileCacheSnapshot.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        );
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveSnapshot(
    SharedPreferences prefs,
    MapTileCacheSnapshot snapshot,
  ) async {
    final snapshots = _loadSnapshotMap(prefs);
    snapshots[snapshot.regionId] = snapshot;
    await prefs.setString(
      _regionMetadataKey,
      jsonEncode(snapshots.map((key, value) => MapEntry(key, value.toJson()))),
    );
  }

  String _shortError(Object error) {
    final text = error.toString();
    return text.length <= 240 ? text : '${text.substring(0, 240)}...';
  }
}

const defaultPrefetchPlans = [
  PrefetchPlan(zoom: 12, radiusKm: 40),
  PrefetchPlan(zoom: 13, radiusKm: 25),
  PrefetchPlan(zoom: 14, radiusKm: 12),
  PrefetchPlan(zoom: 15, radiusKm: 6),
  PrefetchPlan(zoom: 16, radiusKm: 3),
  PrefetchPlan(zoom: 17, radiusKm: 1.5),
];

class OfflineMapRegion {
  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusKm;

  const OfflineMapRegion({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
  });
}

class MapTileCacheSnapshot {
  final String regionId;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final List<int> zooms;
  final String status;
  final DateTime? updatedAt;
  final int completedTiles;
  final int totalTiles;
  final int downloadedTiles;
  final int failedTiles;
  final String? error;

  const MapTileCacheSnapshot({
    required this.regionId,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.zooms,
    required this.status,
    required this.updatedAt,
    required this.completedTiles,
    required this.totalTiles,
    this.downloadedTiles = 0,
    this.failedTiles = 0,
    this.error,
  });

  factory MapTileCacheSnapshot.fromJson(Map<String, dynamic> json) {
    return MapTileCacheSnapshot(
      regionId: json['region_id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      radiusKm: _toDouble(json['radius_km']),
      zooms: (json['zooms'] as List? ?? [])
          .map((value) => int.tryParse(value.toString()))
          .whereType<int>()
          .toList(),
      status: json['status']?.toString() ?? MapTileCacheService.statusUnknown,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      completedTiles: _toInt(json['completed_tiles']),
      totalTiles: _toInt(json['total_tiles']),
      downloadedTiles: _toInt(json['downloaded_tiles']),
      failedTiles: _toInt(json['failed_tiles']),
      error: json['error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'region_id': regionId,
    'label': label,
    'latitude': latitude,
    'longitude': longitude,
    'radius_km': radiusKm,
    'zooms': zooms,
    'status': status,
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    'completed_tiles': completedTiles,
    'total_tiles': totalTiles,
    'downloaded_tiles': downloadedTiles,
    'failed_tiles': failedTiles,
    if (error != null && error!.isNotEmpty) 'error': error,
  };

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class PrefetchPlan {
  final int zoom;
  final double radiusKm;

  const PrefetchPlan({required this.zoom, required this.radiusKm});
}

class _TileXY {
  final int x;
  final int y;

  const _TileXY(this.x, this.y);
}

class _TileBounds {
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  const _TileBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });
}

enum _TileFetchResult { exists, downloaded, failed }
