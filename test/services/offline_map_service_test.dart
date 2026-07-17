import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kalsubai_farms/config/runtime_config.dart';
import 'package:kalsubai_farms/services/local_app_database.dart';
import 'package:kalsubai_farms/services/offline_map_service.dart';

const _template = String.fromEnvironment('OFFLINE_TILE_URL_TEMPLATE');
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADElEQVR42mP8z8BQDwAFgwJ/l2PlNwAAAABJRU5ErkJggg==';

void main() {
  test(
    'field-detail offline download defaults favor small high-zoom regions',
    () {
      expect(OfflineMapService.defaultRadiusKm, 2);
      expect(OfflineMapService.defaultMaxRadiusKm, 20);
      expect(OfflineMapService.defaultMinZoom, 15);
      expect(OfflineMapService.defaultMaxZoom, 20);
    },
  );

  test('loads MapTiler tile source from local .env for IO debug builds', () async {
    final originalDirectory = Directory.current;
    final tempDirectory = await Directory.systemTemp.createTemp(
      'grainright_runtime_config_test_',
    );

    try {
      Directory.current = tempDirectory;
      await File('.env').writeAsString('MAPTILER_API_KEY=local-maptiler-key\n');
      await RuntimeConfig.initialize();

      expect(RuntimeConfig.mapTilerApiKey, 'local-maptiler-key');
      expect(
        RuntimeConfig.offlineTileUrlTemplate,
        'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}@2x.jpg?key=local-maptiler-key',
      );
      expect(
        RuntimeConfig.onlineSatelliteTileUrlTemplate,
        'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}@2x.jpg?key=local-maptiler-key',
      );
    } finally {
      Directory.current = originalDirectory;
      await RuntimeConfig.initialize();
      await tempDirectory.delete(recursive: true);
    }
  });

  test('searches Indian places with MapTiler when key is configured', () async {
    final requests = <Uri>[];
    final service = OfflineMapService(
      client: _FakeClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'features': [
              {
                'id': 'place.123',
                'text': 'Akole',
                'place_name': 'Akole, Ahmednagar, Maharashtra, India',
                'center': [74.005, 19.541],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      mapTilerApiKeyProvider: () => 'test-maptiler-key',
    );
    addTearDown(service.dispose);

    final predictions = await service.searchPlaces(
      'Akole',
      languageCode: 'mr',
      proximityLatitude: 19.541,
      proximityLongitude: 74.005,
    );
    final place = await service.resolvePrediction(predictions.single);

    expect(requests.single.host, 'api.maptiler.com');
    expect(requests.single.path, '/geocoding/Akole.json');
    expect(requests.single.queryParameters['key'], 'test-maptiler-key');
    expect(requests.single.queryParameters['country'], 'in');
    expect(requests.single.queryParameters['language'], 'mr,en');
    expect(requests.single.queryParameters['proximity'], '74.005000,19.541000');
    expect(requests.single.queryParameters['types'], contains('postal_code'));
    expect(predictions.single.title, 'Akole');
    expect(place?.latitude, 19.541);
    expect(place?.longitude, 74.005);
  });

  test(
    'pauses downloads on tile server rate limit without storing secrets',
    () async {
      const secret = 'secret-maptiler-key';
      final database = LocalAppDatabase(NativeDatabase.memory());
      final service = OfflineMapService(
        database: database,
        client: _FakeClient((_) async => http.Response('', 429)),
        offlineTileUrlTemplateProvider: () =>
            'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}@2x.jpg?key=$secret',
        tileRequestInterval: Duration.zero,
        tileRetryDelay: Duration.zero,
        tileMaxRetries: 0,
      );
      addTearDown(() async {
        service.dispose();
        await database.close();
      });

      try {
        await service
            .downloadRegion(
              place: const OfflinePlaceResult(
                placeId: 'rate-limited-place',
                title: 'Rate Limited Place',
                address: 'Rate limited',
                latitude: 20.15604,
                longitude: 73.49257,
              ),
              radiusKm: 1,
              minZoom: 14,
              maxZoom: 14,
            )
            .toList();
        fail('Expected the rate-limited download to throw.');
      } catch (_) {
        // The service stores a paused region before rethrowing to the UI.
      }

      final regions = await service.listRegions();
      expect(regions.single.status, 'paused');
      expect(regions.single.downloadedTileCount, 0);
      expect(regions.single.sourceId, contains('#region=rate-limited-place'));
      expect(regions.single.lastError, contains('rate limit'));
      expect(regions.single.lastError, isNot(contains(secret)));
      expect(regions.single.lastError, isNot(contains('key=$secret')));
    },
  );

  test('redacts secrets from previously stored map errors', () async {
    const secret = 'old-secret-maptiler-key';
    final database = LocalAppDatabase(NativeDatabase.memory());
    final service = OfflineMapService(database: database);
    addTearDown(() async {
      service.dispose();
      await database.close();
    });

    await database.upsertOfflineMapRegion(
      region: const OfflineMapRegionRecord(
        regionId: 'old-failed-region',
        label: 'Old Failed Region',
        centerLat: 20.15604,
        centerLng: 73.49257,
        radiusKm: 10,
        minZoom: 14,
        maxZoom: 18,
        status: 'failed',
        tileCount: 1,
        downloadedTileCount: 0,
        sizeBytes: 0,
        sourceId: 'source',
        updatedAt: '2026-05-30T00:00:00Z',
        lastError:
            'ClientException: failed uri=https://api.maptiler.com/tile.jpg?key=$secret',
      ),
    );

    final regions = await service.listRegions();
    expect(regions.single.lastError, contains('key=REDACTED'));
    expect(regions.single.lastError, isNot(contains(secret)));
  });

  test('sanitizes impossible stored offline map zoom ranges', () async {
    final database = LocalAppDatabase(NativeDatabase.memory());
    final service = OfflineMapService(database: database);
    addTearDown(() async {
      service.dispose();
      await database.close();
    });

    await database.upsertOfflineMapRegion(
      region: const OfflineMapRegionRecord(
        regionId: 'bad-zoom-region',
        label: 'Bad Zoom Region',
        centerLat: 20.15604,
        centerLng: 73.49257,
        radiusKm: 20,
        minZoom: 10,
        maxZoom: 1146,
        status: 'ready',
        tileCount: 146,
        downloadedTileCount: 146,
        sizeBytes: 1024,
        sourceId: 'source',
        updatedAt: '2026-05-30T00:00:00Z',
      ),
    );

    final regions = await service.listRegions();
    expect(regions.single.minZoom, 10);
    expect(regions.single.maxZoom, OfflineMapService.maxDownloadZoom);
  });

  test(
    'downloads wide areas with high detail near the selected field',
    () async {
      final imageBytes = base64Decode(_pngBase64);
      var requests = 0;
      final database = LocalAppDatabase(NativeDatabase.memory());
      final service = OfflineMapService(
        database: database,
        client: _FakeClient((_) async {
          requests += 1;
          return http.Response.bytes(
            imageBytes,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
        offlineTileUrlTemplateProvider: () =>
            'https://tiles.example.test/{z}/{x}/{y}.png',
        tileRequestInterval: Duration.zero,
      );
      addTearDown(() async {
        service.dispose();
        await database.close();
      });

      final progress = await service
          .downloadRegion(
            place: const OfflinePlaceResult(
              placeId: 'wide-detail-place',
              title: 'Wide Detail Place',
              address: 'Wide detail',
              latitude: 20.15604,
              longitude: 73.49257,
            ),
            radiusKm: 20,
            minZoom: 15,
            maxZoom: 1146,
          )
          .toList();

      final ready = progress.last.region;
      expect(ready.status, 'ready');
      expect(ready.minZoom, 15);
      expect(ready.maxZoom, OfflineMapService.maxDownloadZoom);
      expect(ready.tileCount, lessThanOrEqualTo(12000));
      expect(ready.downloadedTileCount, ready.tileCount);
      expect(requests, ready.tileCount);
    },
  );

  test('downloads a map region into the local tile cache', () async {
    if (!_template.contains('127.0.0.1:18089')) {
      markTestSkipped('Run with local OFFLINE_TILE_URL_TEMPLATE test server.');
      return;
    }

    final imageBytes = base64Decode(_pngBase64);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18089);
    final serverDone = server.listen((request) {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(imageBytes);
      request.response.close();
    });

    final database = LocalAppDatabase(NativeDatabase.memory());
    final service = OfflineMapService(
      database: database,
      offlineTileUrlTemplateProvider: () => _template,
    );
    addTearDown(() async {
      service.dispose();
      await database.close();
      await serverDone.cancel();
      await server.close(force: true);
    });

    final progress = await service
        .downloadRegion(
          place: const OfflinePlaceResult(
            placeId: 'local-test-place',
            title: 'Local Tile Test',
            address: 'Local test',
            latitude: 12.3919,
            longitude: 77.7736,
          ),
          radiusKm: 1,
          minZoom: 14,
          maxZoom: 14,
        )
        .toList();

    final regions = await service.listRegions();
    expect(progress.last.region.status, 'ready');
    expect(progress.last.downloadedTiles, greaterThan(0));
    expect(regions.single.status, 'ready');
    expect(regions.single.sourceId, contains('#region=local-test-place'));
    expect(regions.single.downloadedTileCount, progress.last.downloadedTiles);
    expect(regions.single.sizeBytes, greaterThan(0));
  });
}

class _FakeClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  _FakeClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      request: request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
