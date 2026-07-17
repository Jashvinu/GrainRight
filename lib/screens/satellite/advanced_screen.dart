import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../config/satellite_config.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../../controllers/farm_controller.dart';
import '../../controllers/satellite_controller.dart';
import '../../models/satellite/advanced_monitoring_model.dart';
import '../../widgets/satellite/algorithm_selector.dart';

class AdvancedScreen extends StatelessWidget {
  const AdvancedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final satCtrl = Get.find<SatelliteController>();
    final farmCtrl = Get.find<FarmController>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UiStrings.t('algorithm_selection'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Obx(
            () => AlgorithmSelector(
              selected: satCtrl.selectedAlgorithms.toList(),
              onChanged: (list) {
                satCtrl.selectedAlgorithms.assignAll(list);
              },
            ),
          ),
          const SizedBox(height: 18),

          // Date range
          Text(
            UiStrings.t('date_range'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Obx(
            () => Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      satCtrl.advancedStartDate.value.isEmpty
                          ? UiStrings.t('start_date')
                          : satCtrl.advancedStartDate.value,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.green,
                      side: const BorderSide(color: AppTheme.green),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.tryParse(
                              satCtrl.advancedStartDate.value,
                            ) ??
                            DateTime.now().subtract(const Duration(days: 180)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        satCtrl.advancedStartDate.value = _fmt(picked);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      satCtrl.advancedEndDate.value.isEmpty
                          ? UiStrings.t('end_date')
                          : satCtrl.advancedEndDate.value,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.green,
                      side: const BorderSide(color: AppTheme.green),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.tryParse(satCtrl.advancedEndDate.value) ??
                            DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        satCtrl.advancedEndDate.value = _fmt(picked);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Run button
          Obx(
            () => SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: satCtrl.advancedIsLoading.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  satCtrl.advancedIsLoading.value
                      ? UiStrings.t('analysing')
                      : UiStrings.t('run_analysis'),
                ),
                onPressed: satCtrl.advancedIsLoading.value
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
                        satCtrl.runAdvancedMonitoring(farm.id, farm.geometry);
                      },
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Error
          Obx(
            () => satCtrl.advancedError.isNotEmpty
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      satCtrl.advancedError.value,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Results
          Obx(() {
            final result = satCtrl.advancedResult.value;
            if (result == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  UiStrings.t('results'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                ...result.timeseries.map((ts) {
                  final trend = satCtrl.trendFor(ts.algorithm);
                  return _AlgorithmCard(timeSeries: ts, trend: trend);
                }),
              ],
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _AlgorithmCard extends StatelessWidget {
  final AlgorithmTimeSeries timeSeries;
  final TrendResult? trend;

  const _AlgorithmCard({required this.timeSeries, this.trend});

  Color _trendColor(String? dir) {
    switch (dir) {
      case 'Increasing':
        return AppTheme.green;
      case 'Decreasing':
        return Colors.red.shade600;
      default:
        return AppTheme.textMuted;
    }
  }

  IconData _trendIcon(String? dir) {
    switch (dir) {
      case 'Increasing':
        return Icons.trending_up;
      case 'Decreasing':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label =
        SatelliteConfig.algorithmLabels[timeSeries.algorithm] ??
        timeSeries.algorithm;
    final unit = SatelliteConfig.algorithmUnits[timeSeries.algorithm] ?? '';
    final spots = timeSeries.windows.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.mean);
    }).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _trendColor(
                      trend?.trendDirection,
                    ).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _trendIcon(trend?.trendDirection),
                        size: 14,
                        color: _trendColor(trend?.trendDirection),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        trend!.trendDirection,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _trendColor(trend?.trendDirection),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (trend != null) ...[
            const SizedBox(height: 4),
            Text(
              UiStrings.f('trend_slope_r_squared', {
                'slope': LocaleText.number(
                  trend!.theilsenSlope,
                  fractionDigits: 4,
                ),
                'unit': UiStrings.option(unit),
                'rSquared': LocaleText.number(
                  trend!.rSquared,
                  fractionDigits: 2,
                ),
              }),
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(height: 14),
          if (spots.isNotEmpty)
            SizedBox(
              height: 120,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: AppTheme.green,
                      barWidth: 2.0,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.green.withValues(alpha: 0.06),
                      ),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
