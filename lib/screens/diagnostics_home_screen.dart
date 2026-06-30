import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/satellite_config.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../controllers/diagnostics_home_controller.dart';
import '../models/satellite/diagnostics_model.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import '../widgets/satellite/problem_card.dart';
import '../widgets/satellite/satellite_map_view.dart';

// TODO(diagnostics-v2): wire Gemini advisory like web app.
class DiagnosticsHomeScreen extends StatefulWidget {
  const DiagnosticsHomeScreen({super.key});

  @override
  State<DiagnosticsHomeScreen> createState() => _DiagnosticsHomeScreenState();
}

class _DiagnosticsHomeScreenState extends State<DiagnosticsHomeScreen> {
  late final DiagnosticsHomeController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(DiagnosticsHomeController());
  }

  @override
  void dispose() {
    if (Get.isRegistered<DiagnosticsHomeController>()) {
      Get.delete<DiagnosticsHomeController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('farm_diagnostics')),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.green),
          );
        }
        if (controller.errorMessage.value.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.satellite_alt_outlined,
                    size: 48,
                    color: AppTheme.green,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    controller.errorMessage.value,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: controller.load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(UiStrings.t('try_again')),
                  ),
                ],
              ),
            ),
          );
        }

        final result = controller.result.value;
        final coords = controller.polygonCoords();
        final ring = _polygonPoints(coords);
        final selectedIndex = controller.selectedIndex.value;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SatelliteMapView(
              tileUrl: result?.analysis[selectedIndex]?.tileUrlFormat,
              rasterUrl: result?.rasterUrls[selectedIndex],
              rasterBounds: _rasterBounds(result),
              farmPolygon: ring,
              heatCircles: _buildHeatCircles(result, selectedIndex),
              height: 260,
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final index in controller.indexChoices)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: selectedIndex == index,
                        label: Text(
                          SatelliteConfig.indexLabels[index] ??
                              index.toUpperCase(),
                        ),
                        onSelected: (_) =>
                            controller.selectedIndex.value = index,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (result != null) ...[
              _IndexStats(
                index: controller.selectedIndex.value,
                analysis: result.analysis[controller.selectedIndex.value],
              ),
              const SizedBox(height: 16),
              const Text(
                'Issues Detected',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (result.problems.isEmpty)
                const Text(
                  'No major issues detected in the latest diagnostics run.',
                ),
              for (final problem in result.problems)
                ProblemCard(problem: problem),
            ],
          ],
        );
      }),
    );
  }

  List<LatLng> _polygonPoints(List<List<double>> coords) {
    return coords.map((pt) => LatLng(pt[1], pt[0])).toList();
  }

  List<CircleMarker>? _buildHeatCircles(
    DiagnosticsResult? result,
    String index,
  ) {
    if (result == null || result.rasterUrls[index]?.isNotEmpty == true) {
      return null;
    }
    final analysis = result.analysis[index];
    if (analysis == null) return null;
    final min = analysis.min;
    final max = analysis.max;
    return result.cellData.map((cell) {
      final value = cell.values[index] ?? analysis.mean;
      return CircleMarker(
        point: LatLng(cell.lat, cell.lng),
        radius: 10,
        color: _heatColor(value, min, max).withValues(alpha: 0.6),
      );
    }).toList();
  }

  Color _heatColor(double value, double min, double max) {
    if (max == min) return Colors.grey;
    final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Color.lerp(Colors.red, AppTheme.greenLight, t)!;
  }

  LatLngBounds? _rasterBounds(DiagnosticsResult? result) {
    final bounds = result?.rasterBounds;
    if (bounds == null || bounds.length < 2) return null;
    final sw = bounds[0];
    final ne = bounds[1];
    return LatLngBounds(LatLng(sw[0], sw[1]), LatLng(ne[0], ne[1]));
  }
}

class _IndexStats extends StatelessWidget {
  final String index;
  final IndexAnalysis? analysis;

  const _IndexStats({required this.index, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final data = analysis;
    if (data == null) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Stat(
              label: SatelliteConfig.indexLabels[index] ?? index.toUpperCase(),
              value: data.mean,
            ),
            _Stat(label: 'Min', value: data.min),
            _Stat(label: 'Max', value: data.max),
            _Stat(label: 'Std dev', value: data.stdDev),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final double value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
