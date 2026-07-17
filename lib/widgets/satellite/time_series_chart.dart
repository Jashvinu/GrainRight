import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../../models/satellite/timeline_entry_model.dart';

class TimeSeriesChart extends StatelessWidget {
  final List<TimelineEntry> data;
  final String label;
  final List<TimelineEntry>? secondData;
  final String? secondLabel;
  final double height;

  const TimeSeriesChart({
    super.key,
    required this.data,
    required this.label,
    this.secondData,
    this.secondLabel,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            UiStrings.t('no_data_available'),
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    final spots1 = _toSpots(data);
    final allValues = data.map((e) => e.meanValue).toList();
    double minY = allValues.reduce((a, b) => a < b ? a : b);
    double maxY = allValues.reduce((a, b) => a > b ? a : b);

    if (secondData != null && secondData!.isNotEmpty) {
      final v2 = secondData!.map((e) => e.meanValue);
      final mn = v2.reduce((a, b) => a < b ? a : b);
      final mx = v2.reduce((a, b) => a > b ? a : b);
      if (mn < minY) minY = mn;
      if (mx > maxY) maxY = mx;
    }

    final padding = (maxY - minY) * 0.1;
    minY = (minY - padding);
    maxY = (maxY + padding);

    final bars = <LineChartBarData>[
      LineChartBarData(
        spots: spots1,
        isCurved: true,
        color: AppTheme.green,
        barWidth: 2.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: AppTheme.green.withValues(alpha: 0.08),
        ),
      ),
      if (secondData != null && secondData!.isNotEmpty)
        LineChartBarData(
          spots: _toSpots(secondData!),
          isCurved: true,
          color: AppTheme.greenLight,
          barWidth: 2.0,
          dotData: const FlDotData(show: false),
        ),
    ];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          lineBarsData: bars,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: spots1.length > 6
                    ? (spots1.length / 4).ceilToDouble()
                    : 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= data.length) {
                    return const SizedBox.shrink();
                  }
                  final dateStr = data[idx].date;
                  if (dateStr.length < 7) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dateStr.substring(5), // "MM-DD"
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
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
            drawHorizontalLine: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 4,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      s.y.toStringAsFixed(3),
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  List<FlSpot> _toSpots(List<TimelineEntry> entries) {
    return entries.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.meanValue);
    }).toList();
  }
}
