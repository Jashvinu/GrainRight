import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:millets_now/services/local_app_database.dart';
import 'package:millets_now/services/offline_map_service.dart';

const _template = String.fromEnvironment('OFFLINE_TILE_URL_TEMPLATE');
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADElEQVR42mP8z8BQDwAFgwJ/l2PlNwAAAABJRU5ErkJggg==';

void main() {
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
    final service = OfflineMapService(database: database);
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
          minZoom: 10,
          maxZoom: 10,
        )
        .toList();

    final regions = await service.listRegions();
    expect(progress.last.region.status, 'ready');
    expect(progress.last.downloadedTiles, greaterThan(0));
    expect(regions.single.status, 'ready');
    expect(regions.single.downloadedTileCount, progress.last.downloadedTiles);
    expect(regions.single.sizeBytes, greaterThan(0));
  });
}
