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

  const OfflinePlacePrediction({
    required this.placeId,
    required this.title,
    required this.subtitle,
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

class OfflineMapService {
  static const defaultRadiusKm = 15.0;
  static const defaultMinZoom = 10;
  static const defaultMaxZoom = 16;
  static const _maxTilesPerRegion = 6500;

  final http.Client _client;
  final LocalAppDatabase _db;

  OfflineMapService({http.Client? client, LocalAppDatabase? database})
    : _client = client ?? http.Client(),
      _db = database ?? LocalAppDatabase.instance;

  bool get hasOfflineTileSource =>
      RuntimeConfig.offlineTileUrlTemplate.trim().isNotEmpty;

  String get offlineTileSourceLabel => RuntimeConfig.offlineTileSourceLabel;

  Future<List<OfflinePlacePrediction>> searchPlaces(String input) async {
    final query = input.trim();
    if (query.length < 2) return const [];
    final apiKey = await RuntimeConfig.googleMapsApiKey();
    if (apiKey.trim().isEmpty) return const [];

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'components': 'country:in',
        'types': 'geocode',
        'key': apiKey,
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Places search failed with ${response.statusCode}',
        uri,
      );
    }
    final decoded = jsonDecode(response.body);
    final predictions = decoded is Map ? decoded['predictions'] : null;
    if (predictions is! List) return const [];
    return predictions
        .whereType<Map>()
        .map((raw) {
          final formatting = raw['structured_formatting'];
          final title = formatting is Map
              ? formatting['main_text']?.toString()
              : null;
          final subtitle = formatting is Map
              ? formatting['secondary_text']?.toString()
              : null;
          return OfflinePlacePrediction(
            placeId: raw['place_id']?.toString() ?? '',
            title: title?.isNotEmpty == true
                ? title!
                : raw['description']?.toString() ?? 'Place',
            subtitle: subtitle ?? raw['description']?.toString() ?? '',
          );
        })
        .where((place) => place.placeId.isNotEmpty)
        .toList();
  }

  Future<OfflinePlaceResult?> resolvePrediction(
    OfflinePlacePrediction prediction,
  ) async {
    final apiKey = await RuntimeConfig.googleMapsApiKey();
    if (apiKey.trim().isEmpty) return null;

    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': prediction.placeId,
          'fields': 'place_id,name,formatted_address,geometry',
          'key': apiKey,
        });
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Place details failed with ${response.statusCode}',
        uri,
      );
    }
    final decoded = jsonDecode(response.body);
    final result = decoded is Map ? decoded['result'] : null;
    final geometry = result is Map ? result['geometry'] : null;
    final location = geometry is Map ? geometry['location'] : null;
    if (result is! Map || location is! Map) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return OfflinePlaceResult(
      placeId: result['place_id']?.toString() ?? prediction.placeId,
      title: result['name']?.toString() ?? prediction.title,
      address: result['formatted_address']?.toString() ?? prediction.subtitle,
      latitude: lat,
      longitude: lng,
    );
  }

  Stream<OfflineMapDownloadProgress> downloadRegion({
    required OfflinePlaceResult place,
    double radiusKm = defaultRadiusKm,
    int minZoom = defaultMinZoom,
    int maxZoom = defaultMaxZoom,
  }) async* {
    final template = RuntimeConfig.offlineTileUrlTemplate.trim();
    if (template.isEmpty) {
      throw StateError(
        'Offline tile source is not configured. Set OFFLINE_TILE_URL_TEMPLATE.',
      );
    }
    final tiles = _tilesForRadius(
      latitude: place.latitude,
      longitude: place.longitude,
      radiusKm: radiusKm,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
    if (tiles.length > _maxTilesPerRegion) {
      throw StateError(
        'This region has ${tiles.length} tiles. Lower the zoom range or radius.',
      );
    }

    var downloaded = 0;
    var bytes = 0;
    var region = _region(
      place: place,
      radiusKm: radiusKm,
      minZoom: minZoom,
      maxZoom: maxZoom,
      status: 'downloading',
      tileCount: tiles.length,
      downloadedTileCount: 0,
      sizeBytes: 0,
      sourceId: template,
    );
    await _db.upsertOfflineMapRegion(region: region);
    yield OfflineMapDownloadProgress(
      region: region,
      downloadedTiles: downloaded,
      totalTiles: tiles.length,
    );

    try {
      for (final tile in tiles) {
        final tileUrl = _tileUrl(template, tile);
        final response = await _client.get(
          Uri.parse(tileUrl),
          headers: const {'User-Agent': 'grainright.wrkfarm'},
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw http.ClientException(
            'Tile ${tile.z}/${tile.x}/${tile.y} failed with ${response.statusCode}',
            Uri.parse(tileUrl),
          );
        }
        final body = Uint8List.fromList(response.bodyBytes);
        await _db.writeTile(
          sourceId: template,
          z: tile.z,
          x: tile.x,
          y: tile.y,
          bytes: body,
          contentType: response.headers['content-type'] ?? 'image/png',
        );
        downloaded += 1;
        bytes += body.lengthInBytes;
        if (downloaded == tiles.length || downloaded % 12 == 0) {
          region = _region(
            place: place,
            radiusKm: radiusKm,
            minZoom: minZoom,
            maxZoom: maxZoom,
            status: 'downloading',
            tileCount: tiles.length,
            downloadedTileCount: downloaded,
            sizeBytes: bytes,
            sourceId: template,
          );
          await _db.upsertOfflineMapRegion(region: region);
          yield OfflineMapDownloadProgress(
            region: region,
            downloadedTiles: downloaded,
            totalTiles: tiles.length,
          );
        }
      }

      final readyRegion = _region(
        place: place,
        radiusKm: radiusKm,
        minZoom: minZoom,
        maxZoom: maxZoom,
        status: 'ready',
        tileCount: tiles.length,
        downloadedTileCount: downloaded,
        sizeBytes: bytes,
        sourceId: template,
        downloadedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await _db.upsertOfflineMapRegion(region: readyRegion);
      yield OfflineMapDownloadProgress(
        region: readyRegion,
        downloadedTiles: downloaded,
        totalTiles: tiles.length,
      );
    } catch (e) {
      final failedRegion = _region(
        place: place,
        radiusKm: radiusKm,
        minZoom: minZoom,
        maxZoom: maxZoom,
        status: 'failed',
        tileCount: tiles.length,
        downloadedTileCount: downloaded,
        sizeBytes: bytes,
        sourceId: template,
        lastError: _shortError(e),
      );
      await _db.upsertOfflineMapRegion(region: failedRegion);
      yield OfflineMapDownloadProgress(
        region: failedRegion,
        downloadedTiles: downloaded,
        totalTiles: tiles.length,
      );
      rethrow;
    }
  }

  Future<List<OfflineMapRegionRecord>> listRegions() {
    return _db.loadOfflineMapRegions();
  }

  Future<void> deleteRegion(OfflineMapRegionRecord region) {
    return _db.deleteOfflineMapRegion(region.regionId, region.sourceId);
  }

  OfflineMapRegionRecord _region({
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
    final normalizedId = place.placeId.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '',
    );
    return OfflineMapRegionRecord(
      regionId: normalizedId.isNotEmpty ? normalizedId : const Uuid().v4(),
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

  double _degToRad(double value) => value * pi / 180.0;

  String _shortError(Object error) {
    final text = error.toString();
    return text.length <= 240 ? text : '${text.substring(0, 240)}...';
  }

  @mustCallSuper
  void dispose() {
    _client.close();
  }
}
