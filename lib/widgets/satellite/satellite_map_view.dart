import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../config/satellite_config.dart';
import '../../config/theme.dart';
import '../../services/map_tile_provider.dart';

class SatelliteMapView extends StatelessWidget {
  final String? tileUrl;
  final String? rasterUrl;
  final LatLngBounds? rasterBounds;
  final bool isLoading;
  final List<LatLng>? farmPolygon;
  final List<CircleMarker>? heatCircles;
  final double height;

  const SatelliteMapView({
    super.key,
    this.tileUrl,
    this.rasterUrl,
    this.rasterBounds,
    this.isLoading = false,
    this.farmPolygon,
    this.heatCircles,
    this.height = 260,
  });

  @override
  Widget build(BuildContext context) {
    final center = _initialCenter;
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: farmPolygon?.isNotEmpty == true
                    ? 17
                    : SatelliteConfig.defaultZoom,
              ),
              children: [
                const OfflineMapBackground(
                  message: 'Offline map\nSaved farm boundary visible',
                ),
                const OfflineAwareTileLayer(urlTemplate: openStreetMapTileUrl),
                if (tileUrl != null && tileUrl!.isNotEmpty)
                  OfflineAwareTileLayer(urlTemplate: tileUrl!),
                if (rasterUrl != null &&
                    rasterUrl!.isNotEmpty &&
                    rasterBounds != null)
                  OverlayImageLayer(
                    overlayImages: [
                      OverlayImage(
                        bounds: rasterBounds!,
                        imageProvider: NetworkImage(rasterUrl!),
                        opacity: 0.72,
                      ),
                    ],
                  ),
                if (farmPolygon != null && farmPolygon!.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: farmPolygon!,
                        color: AppTheme.green.withValues(alpha: 0.15),
                        borderColor: AppTheme.green,
                        borderStrokeWidth: 2.0,
                      ),
                    ],
                  ),
                if (heatCircles != null && heatCircles!.isNotEmpty)
                  CircleLayer(circles: heatCircles!),
              ],
            ),
            if (isLoading)
              Container(
                color: AppTheme.greenPale.withValues(alpha: 0.7),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: AppTheme.green,
                        strokeWidth: 2.5,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Loading satellite data…',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  LatLng get _initialCenter {
    if (farmPolygon != null && farmPolygon!.isNotEmpty) {
      final lat =
          farmPolygon!.map((point) => point.latitude).reduce((a, b) => a + b) /
          farmPolygon!.length;
      final lng =
          farmPolygon!.map((point) => point.longitude).reduce((a, b) => a + b) /
          farmPolygon!.length;
      return LatLng(lat, lng);
    }
    if (rasterBounds != null) return rasterBounds!.center;
    return SatelliteConfig.defaultCenter;
  }
}
