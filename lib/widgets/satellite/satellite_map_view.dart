import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../config/satellite_config.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../../services/map_tile_provider.dart';

class SatelliteMapView extends StatelessWidget {
  final String? tileUrl;
  final String? rasterUrl;
  final LatLngBounds? rasterBounds;
  final bool isLoading;
  final List<LatLng>? farmPolygon;
  final List<Polygon>? overlayPolygons;
  final List<CircleMarker>? heatCircles;
  final List<Marker>? markers;
  final ValueChanged<LatLng>? onTap;
  final double height;
  final bool showZoomControls;
  final bool autoFitContent;
  final bool showReferenceLabels;

  /// Fallback center when there is no polygon (e.g. a point-only farm). Used
  /// before [SatelliteConfig.defaultCenter] so the map opens on the farm.
  final LatLng? center;

  const SatelliteMapView({
    super.key,
    this.tileUrl,
    this.rasterUrl,
    this.rasterBounds,
    this.isLoading = false,
    this.farmPolygon,
    this.overlayPolygons,
    this.heatCircles,
    this.markers,
    this.onTap,
    this.height = 260,
    this.showZoomControls = false,
    this.autoFitContent = true,
    this.showReferenceLabels = true,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return _SatelliteMapViewInternal(
      tileUrl: tileUrl,
      rasterUrl: rasterUrl,
      rasterBounds: rasterBounds,
      isLoading: isLoading,
      farmPolygon: farmPolygon,
      overlayPolygons: overlayPolygons,
      heatCircles: heatCircles,
      markers: markers,
      onTap: onTap,
      height: height,
      showZoomControls: showZoomControls,
      autoFitContent: autoFitContent,
      showReferenceLabels: showReferenceLabels,
      center: center,
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
  final List<Polygon>? overlayPolygons;
  final List<CircleMarker>? heatCircles;
  final List<Marker>? markers;
  final ValueChanged<LatLng>? onTap;
  final double height;
  final bool showZoomControls;
  final bool autoFitContent;
  final bool showReferenceLabels;
  final LatLng? center;

  const _SatelliteMapViewInternal({
    super.key,
    this.tileUrl,
    this.rasterUrl,
    this.rasterBounds,
    this.isLoading = false,
    this.farmPolygon,
    this.overlayPolygons,
    this.heatCircles,
    this.markers,
    this.onTap,
    this.height = 260,
    this.showZoomControls = false,
    this.autoFitContent = true,
    this.showReferenceLabels = true,
    this.center,
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
      final lat =
          widget.farmPolygon!
              .map((point) => point.latitude)
              .reduce((a, b) => a + b) /
          widget.farmPolygon!.length;
      final lng =
          widget.farmPolygon!
              .map((point) => point.longitude)
              .reduce((a, b) => a + b) /
          widget.farmPolygon!.length;
      return LatLng(lat, lng);
    }
    final markerPoints = _contentPoints();
    if (markerPoints.isNotEmpty) {
      return markerPoints.first;
    }
    if (widget.center != null) return widget.center!;
    if (widget.rasterBounds != null) {
      return widget.rasterBounds!.center;
    }
    return SatelliteConfig.defaultCenter;
  }

  double _initialZoom() {
    if (widget.farmPolygon?.isNotEmpty == true) return 17;
    if (widget.center != null || _contentPoints().isNotEmpty) return 16;
    return SatelliteConfig.defaultZoom;
  }

  /// Every on-map point we want visible: farm boundary, issue markers, and
  /// heat/scout circles. Used to fit the camera so issues are never off-screen.
  List<LatLng> _contentPoints() {
    return [
      ...?widget.farmPolygon,
      ...?widget.overlayPolygons?.expand((polygon) => polygon.points),
      ...?widget.markers?.map((m) => m.point),
      ...?widget.heatCircles?.map((c) => c.point),
    ];
  }

  /// After the map is ready, frame all content so markers placed away from the
  /// farm centroid (or a point-only farm) are brought into view.
  void _fitToContent() {
    final points = _contentPoints();
    if (points.isEmpty) return;
    if (points.length == 1) {
      try {
        _mapController.move(points.first, 16);
      } catch (_) {}
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(32),
          maxZoom: 17,
        ),
      );
    } catch (_) {}
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    try {
      final camera = _mapController.camera;
      final nextZoom = (camera.zoom + delta)
          .clamp(mapTileMinZoom, mapTileMaxZoom)
          .toDouble();
      _mapController.move(camera.center, nextZoom);
    } catch (_) {}
  }

  void _zoomIn() => _zoomBy(0.9);

  void _zoomOut() => _zoomBy(-0.9);

  void _locate() => _fitToContent();

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
                onTap: (_, point) => widget.onTap?.call(point),
                onMapReady: () {
                  _mapReady = true;
                  if (widget.autoFitContent) _fitToContent();
                  setState(() {});
                },
              ),
              children: [
                OfflineMapBackground(
                  message: UiStrings.t('offline_map_saved_boundary'),
                ),
                ...fieldImageryTileLayers(includeReferenceLabels: false),
                if (widget.tileUrl != null && widget.tileUrl!.isNotEmpty)
                  OfflineAwareTileLayer(
                    urlTemplate: widget.tileUrl!,
                    maxNativeZoom: fieldImageryMaxNativeZoom,
                  ),
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
                if (widget.showReferenceLabels &&
                    shouldShowFieldReferenceLabels(fieldImageryTileUrl))
                  ...fieldReferenceTileLayers(),
                if (widget.farmPolygon != null &&
                    widget.farmPolygon!.length >= 3)
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
                if (widget.overlayPolygons != null &&
                    widget.overlayPolygons!.isNotEmpty)
                  PolygonLayer(polygons: widget.overlayPolygons!),
                if (widget.heatCircles != null &&
                    widget.heatCircles!.isNotEmpty)
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
                    Tooltip(
                      message: UiStrings.t('zoom_in'),
                      child: _ZoomControlButton(
                        icon: Icons.add,
                        onTap: _zoomIn,
                        semanticLabel: UiStrings.t('zoom_in'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Tooltip(
                      message: UiStrings.t('zoom_out'),
                      child: _ZoomControlButton(
                        icon: Icons.remove,
                        onTap: _zoomOut,
                        semanticLabel: UiStrings.t('zoom_out'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Tooltip(
                      message: UiStrings.t('locate_farm_area'),
                      child: _ZoomControlButton(
                        icon: Icons.my_location_rounded,
                        onTap: _locate,
                        semanticLabel: UiStrings.t('locate_farm_area'),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.isLoading)
              Container(
                color: AppTheme.greenPale.withValues(alpha: 0.7),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: AppTheme.green,
                        strokeWidth: 2.5,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        UiStrings.t('loading_satellite_data'),
                        style: const TextStyle(
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
  final String semanticLabel;

  const _ZoomControlButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                icon,
                color: Colors.white,
                size: 22,
                shadows: const [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
