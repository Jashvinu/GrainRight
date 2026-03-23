import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../config/satellite_config.dart';
import '../../config/theme.dart';

class SatelliteMapView extends StatelessWidget {
  final String? tileUrl;
  final bool isLoading;
  final List<LatLng>? farmPolygon;
  final List<CircleMarker>? heatCircles;
  final double height;

  const SatelliteMapView({
    super.key,
    this.tileUrl,
    this.isLoading = false,
    this.farmPolygon,
    this.heatCircles,
    this.height = 260,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: SatelliteConfig.defaultCenter,
                initialZoom: SatelliteConfig.defaultZoom,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.wrkfarm.milletsnow',
                ),
                if (tileUrl != null && tileUrl!.isNotEmpty)
                  TileLayer(urlTemplate: tileUrl!),
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
                      Text('Loading satellite data…',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
