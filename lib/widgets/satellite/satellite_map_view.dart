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
  final List<Marker>? markers;
  final double height;
  final bool showZoomControls;

  const SatelliteMapView({
    super.key,
    this.tileUrl,
    this.rasterUrl,
    this.rasterBounds,
    this.isLoading = false,
    this.farmPolygon,
    this.heatCircles,
    this.markers,
    this.height = 260,
    this.showZoomControls = false,
  });

  @override
  Widget build(BuildContext context) {
    return _SatelliteMapViewInternal(
      tileUrl: tileUrl,
      rasterUrl: rasterUrl,
      rasterBounds: rasterBounds,
      isLoading: isLoading,
      farmPolygon: farmPolygon,
      heatCircles: heatCircles,
      markers: markers,
      height: height,
      showZoomControls: showZoomControls,
      key: key,
    );
  }
}

class _SatelliteMapViewInternal extends StatefulWidget {
  final String? tileUrl;
  final String? rasterUrl;
  final LatLngBounds? rasterBounds;
  final bool isLoading;
  final List<LatLng>? farmPolygon;
  final List<CircleMarker>? heatCircles;
  final List<Marker>? markers;
  final double height;
  final bool showZoomControls;

  const _SatelliteMapViewInternal({
    super.key,
    this.tileUrl,
    this.rasterUrl,
    this.rasterBounds,
    this.isLoading = false,
    this.farmPolygon,
    this.heatCircles,
    this.markers,
    this.height = 260,
    this.showZoomControls = false,
  });

  @override
  State<_SatelliteMapViewInternal> createState() =>
      _SatelliteMapViewInternalState();
}

class _SatelliteMapViewInternalState extends State<_SatelliteMapViewInternal> {
  final MapController _mapController = MapController();
  bool _mapReady = false;

  LatLng get _initialCenter {
    if (widget.farmPolygon != null && widget.farmPolygon!.isNotEmpty) {
      final lat = widget.farmPolygon!.map((point) => point.latitude).reduce((a, b) => a + b) /
          widget.farmPolygon!.length;
      final lng = widget.farmPolygon!
              .map((point) => point.longitude)
              .reduce((a, b) => a + b) /
          widget.farmPolygon!.length;
      return LatLng(lat, lng);
    }
    if (widget.rasterBounds != null) {
      return widget.rasterBounds!.center;
    }
    return SatelliteConfig.defaultCenter;
  }

  double _initialZoom() {
    return widget.farmPolygon?.isNotEmpty == true
        ? 17
        : SatelliteConfig.defaultZoom;
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    try {
      final camera = _mapController.camera;
      final nextZoom =
          (camera.zoom + delta).clamp(mapTileMinZoom, mapTileMaxZoom).toDouble();
      _mapController.move(camera.center, nextZoom);
    } catch (_) {}
  }

  void _zoomIn() => _zoomBy(0.9);

  void _zoomOut() => _zoomBy(-0.9);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: _initialZoom(),
                minZoom: mapTileMinZoom,
                maxZoom: mapTileMaxZoom,
                onMapReady: () {
                  _mapReady = true;
                  setState(() {});
                },
              ),
              children: [
                const OfflineMapBackground(
                  message: 'Offline map\nSaved farm boundary visible',
                ),
                OfflineAwareTileLayer(urlTemplate: fieldImageryTileUrl),
                if (widget.tileUrl != null && widget.tileUrl!.isNotEmpty)
                  OfflineAwareTileLayer(urlTemplate: widget.tileUrl!),
                if (widget.rasterUrl != null &&
                    widget.rasterUrl!.isNotEmpty &&
                    widget.rasterBounds != null)
                  OverlayImageLayer(
                    overlayImages: [
                      OverlayImage(
                        bounds: widget.rasterBounds!,
                        imageProvider: NetworkImage(widget.rasterUrl!),
                        opacity: 0.72,
                      ),
                    ],
                  ),
                if (widget.farmPolygon != null && widget.farmPolygon!.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: widget.farmPolygon!,
                        color: AppTheme.green.withValues(alpha: 0.15),
                        borderColor: AppTheme.green,
                        borderStrokeWidth: 2.0,
                      ),
                    ],
                  ),
                if (widget.heatCircles != null && widget.heatCircles!.isNotEmpty)
                  CircleLayer(circles: widget.heatCircles!),
                if (widget.markers != null && widget.markers!.isNotEmpty)
                  MarkerLayer(markers: widget.markers!),
              ],
            ),
            if (widget.showZoomControls)
              Positioned(
                right: 12,
                top: 12,
                child: Column(
                  children: [
                    _ZoomControlButton(
                      icon: Icons.add,
                      onTap: _zoomIn,
                    ),
                    const SizedBox(height: 6),
                    _ZoomControlButton(
                      icon: Icons.remove,
                      onTap: _zoomOut,
                    ),
                  ],
                ),
              ),
            if (widget.isLoading)
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
}

class _ZoomControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ZoomControlButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: AppTheme.greenDark, size: 18),
        ),
      ),
    );
  }
}
