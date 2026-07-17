import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/services/map_tile_provider.dart';

void main() {
  test('field map layers use the requested smooth tile settings', () {
    const tileDisplay = TileDisplay.fadeIn(
      duration: Duration(milliseconds: 80),
      startOpacity: 0.35,
      reloadStartOpacity: 0.35,
    );

    final imageryLayers = fieldImageryTileLayers(
      keepBuffer: 3,
      panBuffer: 1,
      tileDisplay: tileDisplay,
    );
    final imageryLayer = imageryLayers.first as OfflineAwareTileLayer;
    expect(imageryLayer.keepBuffer, 3);
    expect(imageryLayer.panBuffer, 1);
    expect(imageryLayer.tileDisplay, same(tileDisplay));

    final referenceLayers = fieldReferenceTileLayers(
      keepBuffer: 3,
      panBuffer: 1,
      tileDisplay: tileDisplay,
    );
    expect(referenceLayers, hasLength(2));
    for (final layer in referenceLayers.cast<OfflineAwareTileLayer>()) {
      expect(layer.keepBuffer, 3);
      expect(layer.panBuffer, 1);
      expect(layer.tileDisplay, same(tileDisplay));
    }
  });
}
