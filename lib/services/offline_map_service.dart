import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/runtime_config.dart';
import 'local_app_database.dart';

class OfflinePlacePrediction {
  final String placeId;
  final String title;
  final String subtitle;
  final String provider;
  final String? address;
  final double? latitude;
  final double? longitude;

  const OfflinePlacePrediction({
    required this.placeId,
    required this.title,
    required this.subtitle,
    this.provider = OfflineMapService.mapTilerProvider,
    this.address,
    this.latitude,
    this.longitude,
  });
}

class OfflinePlaceResult {
  final String placeId;
  final String title;
  final String address;
  final double latitude;
  final double longitude;

  const OfflinePlaceResult({
    required this.placeId,
    required this.title,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

class OfflineMapDownloadProgress {
  final OfflineMapRegionRecord region;
  final int downloadedTiles;
  final int totalTiles;

  const OfflineMapDownloadProgress({
    required this.region,
    required this.downloadedTiles,
    required this.totalTiles,
  });

  double get fraction {
    if (totalTiles <= 0) return 0;
    return downloadedTiles / totalTiles;
  }
}

class _TileCoord {
  final int z;
  final int x;
  final int y;

  const _TileCoord(this.z, this.x, this.y);
}

class _ZoomRange {
  final int minZoom;
  final int maxZoom;

  const _ZoomRange(this.minZoom, this.maxZoom);
}

class OfflineMapService {
  static const mapTilerProvider = 'maptiler';
  static const defaultRadiusKm = 2.0;
  static const defaultMaxRadiusKm = 20.0;
  static const defaultMinZoom = 15;
  static const defaultMaxZoom = 20;
  static const minDownloadZoom = 3;
  static const maxDownloadZoom = 20;
  static const _maxTilesPerRegion = 12000;
  static const _defaultTileRetryDelay = Duration(seconds: 20);
  static const _defaultTileMaxRetries = 4;

  final http.Client _client;
  final LocalAppDatabase? _db;
  final FutureOr<String> Function() _mapTilerApiKeyProvider;
  final FutureOr<String> Function() _offlineTileUrlTemplateProvider;
  final FutureOr<String> Function() _offlineTileSourceLabelProvider;
  final Duration? _tileRequestIntervalOverride;
  final Duration _tileRetryDelay;
  final int _tileMaxRetries;

  OfflineMapService({
    http.Client? client,
    LocalAppDatabase? database,
    FutureOr<String> Function()? mapTilerApiKeyProvider,
    FutureOr<String> Function()? offlineTileUrlTemplateProvider,
    FutureOr<String> Function()? offlineTileSourceLabelProvider,
    Duration? tileRequestInterval,
    Duration tileRetryDelay = _defaultTileRetryDelay,
    int tileMaxRetries = _defaultTileMaxRetries,
  }) : _client = client ?? http.Client(),
       _db = database ?? LocalAppDatabase.maybeInstance,
       _mapTilerApiKeyProvider =
           mapTilerApiKeyProvider ?? RuntimeConfig.mapTilerApiKeyRuntime,
       _offlineTileUrlTemplateProvider =
           offlineTileUrlTemplateProvider ??
           RuntimeConfig.offlineTileUrlTemplateRuntime,
       _offlineTileSourceLabelProvider =
           offlineTileSourceLabelProvider ??
           RuntimeConfig.offlineTileSourceLabelRuntime,
       _tileRequestIntervalOverride = tileRequestInterval,
       _tileRetryDelay = tileRetryDelay,
       _tileMaxRetries = tileMaxRetries;

  bool get supportsOfflineDownloads => _db != null;

  Future<bool> hasOfflineTileSource() async =>
      (await _offlineTileUrlTemplate()).isNotEmpty;

  Future<String> offlineTileSourceLabel() async {
    final label = (await _offlineTileSourceLabelProvider()).trim();
    return label.isNotEmpty ? label : RuntimeConfig.offlineTileSourceLabel;
  }

  Future<List<OfflinePlacePrediction>> searchPlaces(String input) async {
    final query = input.trim();
    if (query.length < 2) return const [];

    final mapTilerKey = (await _mapTilerApiKeyProvider()).trim();
    if (mapTilerKey.isEmpty) {
      throw StateError(
        'MapTiler search is not configured. Set MAPTILER_API_KEY.',
      );
    }
    return _searchMapTilerPlaces(query, mapTilerKey);
  }

  Future<List<OfflinePlacePrediction>> _searchMapTilerPlaces(
    String query,
    String apiKey,
  ) async {
    final uri = Uri(
      scheme: 'https',
      host: 'api.maptiler.com',
      pathSegments: ['geocoding', '$query.json'],
      queryParameters: {
        'key': apiKey,
        'country': 'in',
        'language': 'en,hi,mr',
        'limit': '8',
        'types': 'place,locality,neighbourhood,municipality,address,poi',
        'autocomplete': 'true',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'MapTiler place search failed with ${response.statusCode}',
        uri,
      );
    }
    final decoded = jsonDecode(response.body);
    final features = decoded is Map ? decoded['features'] : null;
    if (features is! List) return const [];
    return features
        .whereType<Map>()
        .map(_mapTilerFeatureToPrediction)
        .whereType<OfflinePlacePrediction>()
        .toList();
  }

  Future<OfflinePlaceResult?> resolvePrediction(
    OfflinePlacePrediction prediction,
  ) async {
    if (prediction.provider == mapTilerProvider &&
        prediction.latitude != null &&
        prediction.longitude != null) {
      return OfflinePlaceResult(
        placeId: prediction.placeId,
        title: prediction.title,
        address: prediction.address ?? prediction.subtitle,
        latitude: prediction.latitude!,
        longitude: prediction.longitude!,
      );
    }
    return null;
  }

  Stream<OfflineMapDownloadProgress> downloadRegion({
    required OfflinePlaceResult place,
    double radiusKm = defaultRadiusKm,
    int minZoom = defaultMinZoom,
    int maxZoom = defaultMaxZoom,
  }) async* {
    final template = await _offlineTileUrlTemplate();
    if (template.isEmpty) {
      throw StateError(
        'Offline tile source is not configured. Set MAPTILER_API_KEY or OFFLINE_TILE_URL_TEMPLATE.',
      );
    }
    final db = _db;
    if (db == null) {
      throw UnsupportedError(
        'Offline map downloads are not available on this platform.',
      );
    }
    final zoomRange = _normalizedZoomRange(minZoom: minZoom, maxZoom: maxZoom);
    final regionId = _regionIdForPlace(place);
    final sourceId = _sourceId(template, regionId);
    final tiles = _tilesForAdaptiveFieldDetail(
      latitude: place.latitude,
      longitude: place.longitude,
      radiusKm: radiusKm,
      minZoom: zoomRange.minZoom,
      maxZoom: zoomRange.maxZoom,
    );
    if (tiles.length > _maxTilesPerRegion) {
      throw StateError(
        'This region still needs ${tiles.length} tiles. Use a smaller radius or download this village in two parts.',
      );
    }

    var downloaded = 0;
    var bytes = 0;
    var region = _region(
      regionId: regionId,
      place: place,
      radiusKm: radiusKm,
      minZoom: zoomRange.minZoom,
      maxZoom: zoomRange.maxZoom,
      status: 'downloading',
      tileCount: tiles.length,
      downloadedTileCount: 0,
      sizeBytes: 0,
      sourceId: sourceId,
    );
    await db.upsertOfflineMapRegion(region: region);
    yield OfflineMapDownloadProgress(
      region: region,
      downloadedTiles: downloaded,
      totalTiles: tiles.length,
    );

    final throttle = _TileRequestThrottle(
      _tileRequestIntervalOverride ?? Duration.zero,
    );
    try {
      for (final tile in tiles) {
        final cached = await db.readTile(
          sourceId: sourceId,
          z: tile.z,
          x: tile.x,
          y: tile.y,
        );
        if (cached != null) {
          downloaded += 1;
          bytes += cached.bytes.lengthInBytes;
          if (downloaded == tiles.length || downloaded % 12 == 0) {
            region = _region(
              regionId: regionId,
              place: place,
              radiusKm: radiusKm,
              minZoom: zoomRange.minZoom,
              maxZoom: zoomRange.maxZoom,
              status: 'downloading',
              tileCount: tiles.length,
              downloadedTileCount: downloaded,
              sizeBytes: bytes,
              sourceId: sourceId,
            );
            await db.upsertOfflineMapRegion(region: region);
            yield OfflineMapDownloadProgress(
              region: region,
              downloadedTiles: downloaded,
              totalTiles: tiles.length,
            );
          }
          continue;
        }

        final tileUrl = _tileUrl(template, tile);
        final downloadedTile = await _downloadTileWithRetry(
          tile: tile,
          uri: Uri.parse(tileUrl),
          throttle: throttle,
        );
        final body = downloadedTile.bytes;
        await db.writeTile(
          sourceId: sourceId,
          z: tile.z,
          x: tile.x,
          y: tile.y,
          bytes: body,
          contentType: downloadedTile.contentType,
        );
        downloaded += 1;
        bytes += body.lengthInBytes;
        if (downloaded == tiles.length || downloaded % 12 == 0) {
          region = _region(
            regionId: regionId,
            place: place,
            radiusKm: radiusKm,
            minZoom: zoomRange.minZoom,
            maxZoom: zoomRange.maxZoom,
            status: 'downloading',
            tileCount: tiles.length,
            downloadedTileCount: downloaded,
            sizeBytes: bytes,
            sourceId: sourceId,
          );
          await db.upsertOfflineMapRegion(region: region);
          yield OfflineMapDownloadProgress(
            region: region,
            downloadedTiles: downloaded,
            totalTiles: tiles.length,
          );
        }
      }

      final readyRegion = _region(
        regionId: regionId,
        place: place,
        radiusKm: radiusKm,
        minZoom: zoomRange.minZoom,
        maxZoom: zoomRange.maxZoom,
        status: 'ready',
        tileCount: tiles.length,
        downloadedTileCount: downloaded,
        sizeBytes: bytes,
        sourceId: sourceId,
        downloadedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await db.upsertOfflineMapRegion(region: readyRegion);
      yield OfflineMapDownloadProgress(
        region: readyRegion,
        downloadedTiles: downloaded,
        totalTiles: tiles.length,
      );
    } catch (e) {
      final failedRegion = _region(
        regionId: regionId,
        place: place,
        radiusKm: radiusKm,
        minZoom: zoomRange.minZoom,
        maxZoom: zoomRange.maxZoom,
        status: _downloadStatusFor(e),
        tileCount: tiles.length,
        downloadedTileCount: downloaded,
        sizeBytes: bytes,
        sourceId: sourceId,
        lastError: _shortError(e),
      );
      await db.upsertOfflineMapRegion(region: failedRegion);
      yield OfflineMapDownloadProgress(
        region: failedRegion,
        downloadedTiles: downloaded,
        totalTiles: tiles.length,
      );
      rethrow;
    }
  }

  Future<List<OfflineMapRegionRecord>> listRegions() {
    final db = _db;
    if (db == null) return Future.value(const []);
    return db.loadOfflineMapRegions().then(
      (regions) => regions.map(_sanitizeRegion).toList(),
    );
  }

  Future<void> deleteRegion(OfflineMapRegionRecord region) {
    final db = _db;
    if (db == null) return Future.value();
    return db.deleteOfflineMapRegion(region.regionId, region.sourceId);
  }

  OfflineMapRegionRecord _region({
    required String regionId,
    required OfflinePlaceResult place,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
    required String status,
    required int tileCount,
    required int downloadedTileCount,
    required int sizeBytes,
    required String sourceId,
    String? downloadedAt,
    String? lastError,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return OfflineMapRegionRecord(
      regionId: regionId,
      label: place.title,
      centerLat: place.latitude,
      centerLng: place.longitude,
      radiusKm: radiusKm,
      minZoom: minZoom,
      maxZoom: maxZoom,
      status: status,
      downloadedAt: downloadedAt,
      updatedAt: now,
      tileCount: tileCount,
      downloadedTileCount: downloadedTileCount,
      sizeBytes: sizeBytes,
      sourceId: sourceId,
      lastError: lastError,
    );
  }

  String _regionIdForPlace(OfflinePlaceResult place) {
    final normalizedId = place.placeId.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '',
    );
    return normalizedId.isNotEmpty ? normalizedId : const Uuid().v4();
  }

  String _sourceId(String template, String regionId) {
    return '$template#region=$regionId';
  }

  OfflineMapRegionRecord _sanitizeRegion(OfflineMapRegionRecord region) {
    final zoomRange = _normalizedZoomRange(
      minZoom: region.minZoom,
      maxZoom: region.maxZoom,
    );
    final lastError = region.lastError;
    if (lastError == null &&
        zoomRange.minZoom == region.minZoom &&
        zoomRange.maxZoom == region.maxZoom) {
      return region;
    }
    return OfflineMapRegionRecord(
      regionId: region.regionId,
      label: region.label,
      centerLat: region.centerLat,
      centerLng: region.centerLng,
      radiusKm: region.radiusKm,
      minZoom: zoomRange.minZoom,
      maxZoom: zoomRange.maxZoom,
      status: region.status,
      downloadedAt: region.downloadedAt,
      updatedAt: region.updatedAt,
      tileCount: region.tileCount,
      downloadedTileCount: region.downloadedTileCount,
      sizeBytes: region.sizeBytes,
      sourceId: region.sourceId,
      lastError: lastError == null ? null : _shortError(lastError),
    );
  }

  _ZoomRange _normalizedZoomRange({
    required int minZoom,
    required int maxZoom,
  }) {
    final safeMin = minZoom.clamp(minDownloadZoom, maxDownloadZoom).toInt();
    final safeMax = maxZoom.clamp(minDownloadZoom, maxDownloadZoom).toInt();
    if (safeMin <= safeMax) {
      return _ZoomRange(safeMin, safeMax);
    }
    return _ZoomRange(safeMax, safeMax);
  }

  List<_TileCoord> _tilesForAdaptiveFieldDetail({
    required double latitude,
    required double longitude,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
  }) {
    final seen = <String>{};
    final tiles = <_TileCoord>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final effectiveRadius = _effectiveRadiusForZoom(radiusKm, z);
      for (final tile in _tilesForRadius(
        latitude: latitude,
        longitude: longitude,
        radiusKm: effectiveRadius,
        minZoom: z,
        maxZoom: z,
      )) {
        final key = '${tile.z}/${tile.x}/${tile.y}';
        if (seen.add(key)) tiles.add(tile);
      }
    }
    return tiles;
  }

  double _effectiveRadiusForZoom(double radiusKm, int zoom) {
    if (zoom <= 15) return radiusKm;
    if (zoom == 16) return min(radiusKm, 12);
    if (zoom == 17) return min(radiusKm, 6);
    if (zoom == 18) return min(radiusKm, 3);
    if (zoom == 19) return min(radiusKm, 1.5);
    return min(radiusKm, 0.75);
  }

  List<_TileCoord> _tilesForRadius({
    required double latitude,
    required double longitude,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
  }) {
    final latDelta = radiusKm / 111.32;
    final lngDelta = radiusKm / (111.32 * max(0.12, cos(_degToRad(latitude))));
    final south = (latitude - latDelta).clamp(-85.0, 85.0);
    final north = (latitude + latDelta).clamp(-85.0, 85.0);
    final west = (longitude - lngDelta).clamp(-180.0, 180.0);
    final east = (longitude + lngDelta).clamp(-180.0, 180.0);
    final tiles = <_TileCoord>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final minTile = _latLngToTile(north, west, z);
      final maxTile = _latLngToTile(south, east, z);
      for (var x = minTile.x; x <= maxTile.x; x++) {
        for (var y = minTile.y; y <= maxTile.y; y++) {
          tiles.add(_TileCoord(z, x, y));
        }
      }
    }
    return tiles;
  }

  _TileCoord _latLngToTile(double lat, double lng, int z) {
    final n = pow(2.0, z).toInt();
    final latRad = _degToRad(lat);
    final x = (((lng + 180.0) / 360.0) * n).floor().clamp(0, n - 1);
    final y = ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) / 2.0 * n)
        .floor()
        .clamp(0, n - 1);
    return _TileCoord(z, x, y);
  }

  String _tileUrl(String template, _TileCoord tile) {
    return template
        .replaceAll('{z}', tile.z.toString())
        .replaceAll('{x}', tile.x.toString())
        .replaceAll('{y}', tile.y.toString());
  }

  Future<_DownloadedTile> _downloadTileWithRetry({
    required _TileCoord tile,
    required Uri uri,
    required _TileRequestThrottle throttle,
  }) async {
    http.Response? lastResponse;
    for (var attempt = 0; attempt <= _tileMaxRetries; attempt++) {
      await throttle.wait();
      final response = await _client.get(
        uri,
        headers: const {'User-Agent': 'grainright.wrkfarm'},
      );
      lastResponse = response;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _DownloadedTile(
          bytes: Uint8List.fromList(response.bodyBytes),
          contentType: response.headers['content-type'] ?? 'image/png',
        );
      }

      final retryable = _isRetryableTileStatus(response.statusCode);
      if (!retryable || attempt == _tileMaxRetries) break;
      await Future<void>.delayed(_retryDelay(response, attempt));
    }

    final statusCode = lastResponse?.statusCode ?? 0;
    throw _TileDownloadException(
      tile: tile,
      statusCode: statusCode,
      rateLimited: statusCode == 429,
    );
  }

  Duration _retryDelay(http.Response response, int attempt) {
    final retryAfter = response.headers['retry-after'];
    final retryAfterSeconds = retryAfter == null
        ? null
        : int.tryParse(retryAfter.trim());
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      return Duration(seconds: retryAfterSeconds);
    }
    final multiplier = 1 << min(attempt, 4);
    return _tileRetryDelay * multiplier;
  }

  bool _isRetryableTileStatus(int statusCode) {
    return statusCode == 429 || statusCode == 408 || statusCode >= 500;
  }

  OfflinePlacePrediction? _mapTilerFeatureToPrediction(Map raw) {
    final center = raw['center'];
    final geometry = raw['geometry'];
    final geometryCoordinates = geometry is Map
        ? geometry['coordinates']
        : null;
    final coordinates = center is List ? center : geometryCoordinates;
    if (coordinates is! List || coordinates.length < 2) return null;

    final lng = _toDouble(coordinates[0]);
    final lat = _toDouble(coordinates[1]);
    if (lat == null || lng == null) return null;

    final title = _firstText([
      raw['text'],
      raw['matching_text'],
      raw['place_name'],
    ]);
    final address = _firstText([
      raw['place_name'],
      raw['matching_place_name'],
      raw['text'],
    ]);
    if (title == null || title.isEmpty) return null;

    return OfflinePlacePrediction(
      provider: mapTilerProvider,
      placeId: 'maptiler:${raw['id'] ?? '$lat,$lng'}',
      title: title,
      subtitle: address == title ? '' : address ?? '',
      address: address ?? title,
      latitude: lat,
      longitude: lng,
    );
  }

  Future<String> _offlineTileUrlTemplate() async {
    return (await _offlineTileUrlTemplateProvider()).trim();
  }

  String? _firstText(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  double _degToRad(double value) => value * pi / 180.0;

  String _downloadStatusFor(Object error) {
    if (error is _TileDownloadException && error.rateLimited) return 'paused';
    return 'failed';
  }

  String _shortError(Object error) {
    final text = _sanitizeErrorText(error.toString());
    return text.length <= 240 ? text : '${text.substring(0, 240)}...';
  }

  String _sanitizeErrorText(String text) {
    return text
        .replaceAll(RegExp(r'api_key=[^&\s,)]+'), 'api_key=REDACTED')
        .replaceAll(RegExp(r'key=[^&\s,)]+'), 'key=REDACTED')
        .replaceAll(RegExp(r'access_token=[^&\s,)]+'), 'access_token=REDACTED');
  }

  @mustCallSuper
  void dispose() {
    _client.close();
  }
}

class _DownloadedTile {
  final Uint8List bytes;
  final String contentType;

  const _DownloadedTile({required this.bytes, required this.contentType});
}

class _TileRequestThrottle {
  final Duration interval;
  DateTime? _lastRequestAt;

  _TileRequestThrottle(this.interval);

  Future<void> wait() async {
    if (interval <= Duration.zero) {
      _lastRequestAt = DateTime.now();
      return;
    }

    final lastRequestAt = _lastRequestAt;
    if (lastRequestAt != null) {
      final elapsed = DateTime.now().difference(lastRequestAt);
      if (elapsed < interval) {
        await Future<void>.delayed(interval - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }
}

class _TileDownloadException implements Exception {
  final _TileCoord tile;
  final int statusCode;
  final bool rateLimited;

  const _TileDownloadException({
    required this.tile,
    required this.statusCode,
    required this.rateLimited,
  });

  @override
  String toString() {
    if (rateLimited) {
      return 'Tile server rate limit reached while downloading tile ${tile.z}/${tile.x}/${tile.y}. Download paused; tap Resume later or reduce radius/zoom.';
    }
    return 'Tile ${tile.z}/${tile.x}/${tile.y} failed with HTTP $statusCode.';
  }
}
