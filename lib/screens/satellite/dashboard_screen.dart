import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../../config/satellite_config.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../../controllers/farm_controller.dart';
import '../../controllers/satellite_controller.dart';
import '../../widgets/satellite/satellite_map_view.dart';
import '../../widgets/satellite/farm_selector.dart';
import '../../widgets/satellite/date_chip_row.dart';
import '../../widgets/satellite/index_selector.dart';
import '../../widgets/satellite/kpi_card.dart';
import '../../widgets/satellite/time_series_chart.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    final farmCtrl = Get.find<FarmController>();
    final satCtrl = Get.find<SatelliteController>();

    return RefreshIndicator(
      color: AppTheme.green,
      onRefresh: () async {
        final farm = farmCtrl.selectedFarm.value;
        if (farm != null) satCtrl.onFarmChanged(farm);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Farm + Index selectors
            Obx(
              () => FarmSelector(
                farms: farmCtrl.farms,
                selected: farmCtrl.selectedFarm.value,
                onChanged: farmCtrl.selectFarm,
                onAddFarm: () => Get.toNamed('/satellite/draw-polygon'),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Get.toNamed('/farms/manage'),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Manage farms'),
              ),
            ),
            const SizedBox(height: 10),
            Obx(
              () => IndexSelector(
                value: satCtrl.selectedIndex.value,
                onChanged: satCtrl.selectIndex,
              ),
            ),
            const SizedBox(height: 14),

            // Date chips
            _SectionHeader(
              label: 'Observation Date',
              child: Obx(
                () => satCtrl.datesLoading.value
                    ? const SizedBox(
                        height: 40,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.green,
                          ),
                        ),
                      )
                    : DateChipRow(
                        dates: satCtrl.availableDates,
                        selected: satCtrl.selectedDate.value,
                        onSelected: satCtrl.selectDate,
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Map
            _SectionHeader(
              label: 'Satellite View',
              child: Obx(() {
                final polygonPts = _polygonPoints(
                  farmCtrl.selectedFarm.value?.geometry,
                );
                return SatelliteMapView(
                  tileUrl: satCtrl.tileUrl.value,
                  isLoading: satCtrl.tileIsLoading.value,
                  farmPolygon: polygonPts,
                );
              }),
            ),
            const SizedBox(height: 16),

            // KPI cards
            Obx(() {
              final tile = satCtrl.currentTileResult.value;
              if (tile == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label('Index Statistics'),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        KpiCard(
                          label: 'Mean',
                          value: tile.meanValue?.toStringAsFixed(3) ?? '–',
                          icon: Icons.show_chart,
                        ),
                        const SizedBox(width: 10),
                        KpiCard(
                          label: 'Min',
                          value: tile.minValue?.toStringAsFixed(3) ?? '–',
                          icon: Icons.arrow_downward,
                          iconColor: Colors.orange,
                        ),
                        const SizedBox(width: 10),
                        KpiCard(
                          label: 'Max',
                          value: tile.maxValue?.toStringAsFixed(3) ?? '–',
                          icon: Icons.arrow_upward,
                          iconColor: AppTheme.greenLight,
                        ),
                        const SizedBox(width: 10),
                        KpiCard(
                          label: 'Std Dev',
                          value: tile.stdDev?.toStringAsFixed(3) ?? '–',
                          icon: Icons.stacked_line_chart,
                          iconColor: AppTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            }),

            // Time series chart
            _SectionHeader(
              label: 'Historical Trend',
              child: Obx(() {
                if (satCtrl.timelineIsLoading.value) {
                  return const SizedBox(
                    height: 160,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.green,
                      ),
                    ),
                  );
                }
                final entries = satCtrl.entriesForIndex(
                  satCtrl.selectedIndex.value,
                );
                return TimeSeriesChart(
                  data: entries,
                  label:
                      SatelliteConfig.indexLabels[satCtrl
                          .selectedIndex
                          .value] ??
                      satCtrl.selectedIndex.value.toUpperCase(),
                );
              }),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Widget child;
  const _SectionHeader({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_Label(label), const SizedBox(height: 8), child],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textMuted,
        letterSpacing: 0.3,
      ),
    );
  }
}
