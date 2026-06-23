import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../config/ui_strings.dart';
import '../../controllers/satellite_controller.dart';
import '../../models/satellite/timeline_entry_model.dart';
import '../../widgets/satellite/time_series_chart.dart';

class YieldScreen extends StatelessWidget {
  const YieldScreen({super.key});

  double _predictYield(List<TimelineEntry> ndviEntries) {
    if (ndviEntries.isEmpty) return 0.0;
    final mean = ndviEntries.map((e) => e.meanValue).reduce((a, b) => a + b) /
        ndviEntries.length;
    return (4.8 * mean - 0.5).clamp(0.0, 10.0);
  }

  String _recommendation(double ndvi) {
    if (ndvi > 0.6) {
      return UiStrings.t('ndvi_recommendation_good');
    } else if (ndvi > 0.3) {
      return UiStrings.t('ndvi_recommendation_moderate');
    } else {
      return UiStrings.t('ndvi_recommendation_low');
    }
  }

  Color _ndviColor(double ndvi) {
    if (ndvi > 0.6) return AppTheme.green;
    if (ndvi > 0.3) return Colors.orange;
    return Colors.red.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final satCtrl = Get.find<SatelliteController>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Obx(() {
        final ndviData = satCtrl.entriesForIndex('ndvi');
        final eviData = satCtrl.entriesForIndex('evi');
        final currentNdvi = ndviData.isNotEmpty
            ? ndviData.last.meanValue
            : 0.0;
        final predictedYield = _predictYield(ndviData);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Predicted yield hero card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.greenDark, AppTheme.green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    UiStrings.t('predicted_yield'),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        UiStrings.localizedValue(
                          predictedYield.toStringAsFixed(1),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 52,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -2,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(UiStrings.t('tonnes_per_hectare'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 18)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    UiStrings.f('based_on_ndvi', {
                      'value': currentNdvi.toStringAsFixed(3),
                    }),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // NDVI + EVI chart
            Text(UiStrings.t('vegetation_index_history'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark)),
            const SizedBox(height: 4),
            Row(
              children: [
                _Legend(color: AppTheme.green, label: UiStrings.t('ndvi')),
                const SizedBox(width: 16),
                _Legend(color: AppTheme.greenLight, label: UiStrings.t('evi')),
              ],
            ),
            const SizedBox(height: 10),
            if (satCtrl.timelineIsLoading.value)
              const SizedBox(
                height: 160,
                child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.green)),
              )
            else
              TimeSeriesChart(
                data: ndviData,
                label: UiStrings.t('ndvi'),
                secondData: eviData,
                secondLabel: UiStrings.t('evi'),
              ),
            const SizedBox(height: 20),

            // Recommendation card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tips_and_updates_outlined,
                      color: _ndviColor(currentNdvi), size: 26),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(UiStrings.t('recommendation'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppTheme.textDark)),
                        const SizedBox(height: 6),
                        Text(
                          _recommendation(currentNdvi),
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textMuted,
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      }),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ],
    );
  }
}
