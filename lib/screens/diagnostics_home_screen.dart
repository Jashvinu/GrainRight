import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/satellite_config.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../controllers/diagnostics_home_controller.dart';
import '../models/satellite/diagnostics_model.dart';
import '../models/satellite/farm_alert_model.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import '../widgets/satellite/problem_card.dart';
import '../widgets/satellite/satellite_map_view.dart';

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
              _DiagnosticsAdvisory(
                advice: controller.advice.value,
                loading: controller.isAdviceLoading.value,
                error: controller.adviceError.value,
                onRetry: controller.loadAdvice,
              ),
              const SizedBox(height: 10),
              Text(
                UiStrings.t('issues_detected'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (result.problems.isEmpty)
                Text(UiStrings.t('no_major_diagnostic_issues')),
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

class _DiagnosticsAdvisory extends StatelessWidget {
  final FarmAlertAdvice? advice;
  final bool loading;
  final String error;
  final Future<void> Function() onRetry;

  const _DiagnosticsAdvisory({
    required this.advice,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppTheme.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    UiStrings.t('farm_guidance'),
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading && advice == null)
              Text(UiStrings.t('preparing_farm_guidance'))
            else if (error.isNotEmpty && advice == null) ...[
              Text(UiStrings.t('farm_guidance_unavailable')),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(UiStrings.t('try_again')),
              ),
            ] else if (advice == null ||
                (advice!.importantAlerts.isEmpty &&
                    advice!.weatherAlerts.isEmpty &&
                    advice!.nextActions.isEmpty))
              Text(UiStrings.t('no_farm_guidance'))
            else ...[
              for (final alert in [
                ...advice!.importantAlerts,
                ...advice!.weatherAlerts,
              ])
                _AdvisoryAlertRow(alert: alert),
              if (advice!.nextActions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  UiStrings.t('next_actions'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                for (var index = 0; index < advice!.nextActions.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${index + 1}. ${advice!.nextActions[index]}',
                      style: const TextStyle(height: 1.35),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _AdvisoryAlertRow extends StatelessWidget {
  final FarmAlertItem alert;

  const _AdvisoryAlertRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.severity.toLowerCase()) {
      'high' => AppTheme.error,
      'low' => AppTheme.green,
      _ => const Color(0xFFE07800),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(Icons.circle, size: 9, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(alert.detail, style: const TextStyle(height: 1.35)),
                if (alert.action.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    alert.action,
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
            _Stat(label: UiStrings.t('minimum_short'), value: data.min),
            _Stat(label: UiStrings.t('maximum_short'), value: data.max),
            _Stat(
              label: UiStrings.t('standard_deviation_short'),
              value: data.stdDev,
            ),
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
