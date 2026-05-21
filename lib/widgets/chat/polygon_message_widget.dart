import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../config/theme.dart';
import '../../models/form_config.dart';
import '../../screens/pencil_polygon_screen.dart';
import '../../utils/polygon_geometry.dart';

class PolygonPromptWidget extends StatelessWidget {
  final FormFieldConfig field;
  final ValueChanged<List<List<double>>> onSaved;
  final VoidCallback? onSkip;

  const PolygonPromptWidget({
    super.key,
    required this.field,
    required this.onSaved,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              field.localizedLabel(context),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap and drag on the map to draw your farm boundary.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await Get.to<List<List<double>>>(
                    () => const PencilPolygonScreen(),
                  );
                  if (result != null) onSaved(result);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.edit_location_alt_rounded, size: 22),
                label: const Text('Draw farm boundary'),
              ),
            ),
            if (onSkip != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onSkip,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Skip — I will do this later'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PolygonAnswerWidget extends StatelessWidget {
  final List<List<double>> coords;
  final double areaHectares;

  const PolygonAnswerWidget({
    super.key,
    required this.coords,
    required this.areaHectares,
  });

  @override
  Widget build(BuildContext context) {
    final ring = PolygonGeometry.fromGeoJsonRing(coords);
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 260,
        height: 180,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GoogleMap(
                mapType: MapType.satellite,
                initialCameraPosition: CameraPosition(
                  target: ring.isEmpty ? const LatLng(20.5937, 78.9629) : ring.first,
                  zoom: 17,
                ),
                liteModeEnabled: true,
                zoomControlsEnabled: false,
                scrollGesturesEnabled: false,
                zoomGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                polygons: {
                  if (ring.length >= 4)
                    Polygon(
                      polygonId: const PolygonId('answer_polygon'),
                      points: ring,
                      strokeColor: AppTheme.green,
                      strokeWidth: 3,
                      fillColor: AppTheme.green.withValues(alpha: 0.25),
                    ),
                },
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Text('${areaHectares.toStringAsFixed(2)} ha'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
