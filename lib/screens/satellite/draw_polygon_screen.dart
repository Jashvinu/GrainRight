import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../../config/satellite_config.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/farm_controller.dart';

class DrawPolygonScreen extends StatefulWidget {
  const DrawPolygonScreen({super.key});

  @override
  State<DrawPolygonScreen> createState() => _DrawPolygonScreenState();
}

class _DrawPolygonScreenState extends State<DrawPolygonScreen> {
  final List<LatLng> _points = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final auth = Get.find<AuthController>();
    if (!auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAllNamed('/satellite/login');
      });
    }
  }

  void _addPoint(TapPosition _, LatLng latLng) {
    setState(() => _points.add(latLng));
  }

  void _removeLastPoint() {
    if (_points.isNotEmpty) setState(() => _points.removeLast());
  }

  void _clearPoints() {
    setState(() => _points.clear());
  }

  Future<void> _onSave() async {
    if (_points.length < 3) {
      Get.snackbar(
        'Too few points',
        'Draw at least 3 points to define your farm boundary.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Name your farm',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Farm name',
                prefixIcon: Icon(Icons.grass_outlined),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Farm'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final name = nameCtrl.text.trim().isEmpty
        ? 'My Farm'
        : nameCtrl.text.trim();

    setState(() => _isSaving = true);
    final farmCtrl = Get.find<FarmController>();
    final success = await farmCtrl.saveFarm(name: name, points: _points);
    setState(() => _isSaving = false);

    if (success) {
      Get.offAllNamed('/satellite/shell');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw Your Farm'),
        actions: [
          if (_points.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo last point',
              onPressed: _removeLastPoint,
            ),
          if (_points.length >= 3)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _onSave,
                    child: const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: SatelliteConfig.defaultCenter,
              initialZoom: SatelliteConfig.defaultZoom,
              onTap: _addPoint,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'grainright.wrkfarm',
              ),
              if (_points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _points,
                      color: AppTheme.green.withValues(alpha: 0.22),
                      borderColor: AppTheme.green,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
              CircleLayer(
                circles: _points
                    .map(
                      (p) => CircleMarker(
                        point: p,
                        radius: 7,
                        color: AppTheme.greenDark,
                        borderColor: Colors.white,
                        borderStrokeWidth: 1.5,
                        useRadiusInMeter: false,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),

          // Bottom instruction card
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      color: AppTheme.green,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _points.isEmpty
                                ? 'Tap the map to add boundary points'
                                : '${_points.length} point${_points.length == 1 ? '' : 's'} added'
                                      '${_points.length >= 3 ? ' · Tap "Save" when done' : ' · Add ${3 - _points.length} more'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textDark,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_points.isNotEmpty)
                      TextButton(
                        onPressed: _clearPoints,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(40, 32),
                        ),
                        child: Text(
                          'Clear',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
