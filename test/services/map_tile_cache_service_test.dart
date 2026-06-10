import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/services/map_tile_cache_service.dart';

void main() {
  test('core offline map regions cover the active field areas', () {
    final ids = MapTileCacheService.coreRegions
        .map((region) => region.id)
        .toSet();

    expect(ids, containsAll(['nashik', 'akole', 'sangamner']));
  });

  test('fallback map center is in Maharashtra', () {
    expect(
      MapTileCacheService.fallbackCenterLatitude,
      inInclusiveRange(15, 23),
    );
    expect(
      MapTileCacheService.fallbackCenterLongitude,
      inInclusiveRange(72, 81),
    );
  });
}
