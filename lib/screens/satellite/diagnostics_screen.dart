import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../../config/satellite_config.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../../controllers/farm_controller.dart';
import '../../controllers/satellite_controller.dart';
import '../../models/satellite/diagnostics_model.dart';
import '../../widgets/satellite/problem_card.dart';
import '../../widgets/satellite/satellite_map_view.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  List<LatLng> _polygonPoints(Map<String, dynamic>? geometry) {
    if (geometry == null) return [];
    try {
      final coords = geometry['coordinates'] as List?;
      if (coords == null || coords.isEmpty) return [];
      final ring = coords[0] as List;
      return ring.map((pt) {
        final p = pt as List;
        return LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble());
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Color _heatColor(double value, double min, double max) {
    if (max == min) return Colors.grey;
    final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Color.lerp(Colors.red, AppTheme.greenLight, t)!;
  }

  List<CircleMarker> _buildHeatCircles(DiagnosticsResult result, String index) {
    final analysis = result.analysis[index];
    if (analysis == null) return [];

    final min = analysis.min;
    final max = analysis.max;

    return result.cellData.map((cell) {
      final val = cell.values[index] ?? 0.0;
      return CircleMarker(
        point: LatLng(cell.lat, cell.lng),
        radius: 10,
        color: _heatColor(val, min, max).withValues(alpha: 0.6),
        useRadiusInMeter: false,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final satCtrl = Get.find<SatelliteController>();
    final farmCtrl = Get.find<FarmController>();

    return Column(
      children: [
        // Map (fixed height)
        Obx(() {
          final farm = farmCtrl.selectedFarm.value;
          final result = satCtrl.diagnosticsResult.value;
          final polygonPts = _polygonPoints(farm?.geometry);
          final heatCircles = result != null
              ? _buildHeatCircles(result, satCtrl.diagnosticsIndex.value)
              : null;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SatelliteMapView(
              tileUrl: result
                  ?.analysis[satCtrl.diagnosticsIndex.value]
                  ?.tileUrlFormat,
              rasterUrl: result?.rasterUrls[satCtrl.diagnosticsIndex.value],
              rasterBounds: _rasterBounds(result),
              isLoading: satCtrl.diagnosticsIsLoading.value,
              farmPolygon: polygonPts,
              heatCircles: heatCircles,
              height: 250,
            ),
          );
        }),

        // Scrollable panel
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Index selector for heatmap
                Obx(
                  () => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children:
                          [
                            'ndvi',
                            'nitrogen',
                            'phosphorus',
                            'potassium',
                            'moisture',
                          ].map((idx) {
                            final isSelected =
                                satCtrl.diagnosticsIndex.value == idx;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  UiStrings.option(
                                    SatelliteConfig.indexLabels[idx] ?? idx,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected
                                        ? AppTheme.greenDark
                                        : AppTheme.textMuted,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: AppTheme.greenPale,
                                onSelected: (_) =>
                                    satCtrl.diagnosticsIndex.value = idx,
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Run diagnostics button
                Obx(
                  () => SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: satCtrl.diagnosticsIsLoading.value
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.biotech_outlined),
                      label: Text(
                        satCtrl.diagnosticsIsLoading.value
                            ? UiStrings.t('analysing')
                            : UiStrings.t('run_diagnostics'),
                      ),
                      onPressed: satCtrl.diagnosticsIsLoading.value
                          ? null
                          : () {
                              final farm = farmCtrl.selectedFarm.value;
                              if (farm == null) {
                                Get.snackbar(
                                  UiStrings.t('no_farm'),
                                  UiStrings.t('select_farm_first'),
                                  snackPosition: SnackPosition.BOTTOM,
                                );
                                return;
                              }
                              satCtrl.loadDiagnostics(farm.id, farm.geometry);
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Results
                Obx(() {
                  final result = satCtrl.diagnosticsResult.value;
                  if (result == null) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Season + metadata
                      if (result.metadata.season.isNotEmpty)
                        _MetaBadge(
                          label: UiStrings.f('season_value', {
                            'value': UiStrings.option(result.metadata.season),
                          }),
                        ),
                      const SizedBox(height: 14),

                      // Problems
                      if (result.problems.isNotEmpty) ...[
                        Text(
                          UiStrings.t('issues_detected'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...result.problems.map((p) => ProblemCard(problem: p)),
                        const SizedBox(height: 16),
                      ],

                      // Per-index stats
                      Text(
                        UiStrings.t('index_statistics'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: result.analysis.entries.map((entry) {
                            final label = UiStrings.option(
                              SatelliteConfig.indexLabels[entry.key] ??
                                  entry.key.toUpperCase(),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: _StatCard(
                                label: label,
                                analysis: entry.value,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LatLngBounds? _rasterBounds(DiagnosticsResult? result) {
    final bounds = result?.rasterBounds;
    if (bounds == null || bounds.length < 2) return null;
    final sw = bounds[0];
    final ne = bounds[1];
    return LatLngBounds(LatLng(sw[0], sw[1]), LatLng(ne[0], ne[1]));
  }
}

class _MetaBadge extends StatelessWidget {
  final String label;
  const _MetaBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.greenDark,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final IndexAnalysis analysis;

  const _StatCard({required this.label, required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: analysis.belowThreshold
              ? Colors.orange.shade200
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppTheme.textDark,
            ),
          ),
          const Divider(height: 12),
          _StatRow(label: 'Mean', value: analysis.mean.toStringAsFixed(2)),
          _StatRow(label: 'Min', value: analysis.min.toStringAsFixed(2)),
          _StatRow(label: 'Max', value: analysis.max.toStringAsFixed(2)),
          _StatRow(label: 'σ', value: analysis.stdDev.toStringAsFixed(2)),
          if (analysis.belowThreshold)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '⚠ ${UiStrings.t('below_threshold')}',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            UiStrings.fromEnglish(label),
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
