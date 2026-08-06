import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../services/fpc_operating_service.dart';
import '../widgets/fpc_bottom_nav.dart';

class FpcAnalyticsScreen extends StatefulWidget {
  const FpcAnalyticsScreen({super.key});

  @override
  State<FpcAnalyticsScreen> createState() => _FpcAnalyticsScreenState();
}

class _FpcAnalyticsScreenState extends State<FpcAnalyticsScreen> {
  final _service = FpcOperatingService();
  late DateTime _start;
  late DateTime _end;
  FpcAnalyticsSnapshot? _snapshot;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _end = DateTime.now();
    _start = _end.subtract(const Duration(days: 29));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final snapshot = await _service.loadAnalytics(start: _start, end: _end);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _start = selected.start;
      _end = selected.end;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return FpcWorkspaceScaffold(
      current: FpcNavTab.analytics,
      title: 'Analytics',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? _AnalyticsError(message: _error, onRetry: _load)
          : _AnalyticsBody(snapshot: _snapshot!, onSelectRange: _selectRange),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  final FpcAnalyticsSnapshot snapshot;
  final VoidCallback onSelectRange;

  const _AnalyticsBody({required this.snapshot, required this.onSelectRange});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMM yyyy');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 112),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.greenDark,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UiStrings.fromEnglish('Performance overview'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 21,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dateFormat.format(snapshot.start.toLocal())} – '
                      '${dateFormat.format(snapshot.end.toLocal())}',
                      style: const TextStyle(color: Color(0xFFD7E9D3)),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onSelectRange,
                icon: const Icon(Icons.date_range_rounded),
                label: Text(UiStrings.fromEnglish('Date range')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _MetricGrid(snapshot: snapshot),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final procurement = _TrendCard(
              title: 'Procurement trend',
              subtitle: 'Daily received quantity (kg)',
              icon: Icons.scale_rounded,
              values: snapshot.daily.map((item) => item.procurementKg).toList(),
              days: snapshot.daily,
              color: AppTheme.greenDark,
            );
            final sales = _TrendCard(
              title: 'Sales trend',
              subtitle: 'Daily order value',
              icon: Icons.trending_up_rounded,
              values: snapshot.daily.map((item) => item.salesAmount).toList(),
              days: snapshot.daily,
              color: const Color(0xFFB26A00),
            );
            if (constraints.maxWidth < 760) {
              return Column(
                children: [procurement, const SizedBox(height: 12), sales],
              );
            }
            return Row(
              children: [
                Expanded(child: procurement),
                const SizedBox(width: 12),
                Expanded(child: sales),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _ActivityCard(snapshot: snapshot),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final FpcAnalyticsSnapshot snapshot;

  const _MetricGrid({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final values = [
      ('Procurement', _kg(snapshot.procurementKg), Icons.scale_rounded),
      ('Sales value', _money(snapshot.salesAmount), Icons.payments_rounded),
      ('Stock moved', _kg(snapshot.stockMovementKg), Icons.swap_horiz_rounded),
      (
        'Farmer payouts',
        _money(snapshot.farmerPayoutAmount),
        Icons.account_balance_wallet_rounded,
      ),
      ('Active farmers', '${snapshot.activeFarmers}', Icons.groups_rounded),
      ('Sales orders', '${snapshot.salesOrders}', Icons.receipt_long_rounded),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 840 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: values.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 3 ? 2.25 : 1.75,
          ),
          itemBuilder: (context, index) {
            final item = values[index];
            return Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE3E9DD)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.greenPale,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.$3, color: AppTheme.greenDark, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          UiStrings.fromEnglish(item.$1),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TrendCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<double> values;
  final List<FpcAnalyticsDay> days;
  final Color color;

  const _TrendCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.values,
    required this.days,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = values.any((value) => value > 0);
    final visibleIndexes = _visibleIndexes(values.length);
    return Container(
      height: 236,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: hasData
                ? BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: values.reduce((a, b) => a > b ? a : b) * 1.15,
                      barTouchData: BarTouchData(enabled: true),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (!visibleIndexes.contains(index) ||
                                  index >= days.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  DateFormat('d MMM').format(days[index].date),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var index = 0; index < values.length; index++)
                          BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: values[index],
                                color: color,
                                width: values.length > 40 ? 4 : 7,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  )
                : const Center(
                    child: Text(
                      'No activity in this date range.',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Set<int> _visibleIndexes(int length) {
    if (length <= 5) {
      return {for (var index = 0; index < length; index++) index};
    }
    return {0, length ~/ 2, length - 1};
  }
}

class _ActivityCard extends StatelessWidget {
  final FpcAnalyticsSnapshot snapshot;

  const _ActivityCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final activity = snapshot.daily.fold<int>(
      0,
      (sum, day) => sum + day.activityCount,
    );
    final values = snapshot.daily
        .map((day) => day.activityCount.toDouble())
        .toList(growable: false);
    final hasData = values.any((value) => value > 0);
    return Container(
      height: 224,
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: AppTheme.greenDark),
              const SizedBox(width: 8),
              Text(
                UiStrings.fromEnglish('Operational activity'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                '$activity events',
                style: const TextStyle(
                  color: AppTheme.greenDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${snapshot.pendingPayments} farmer payment(s) still need attention.',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: hasData
                ? LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: values.reduce((a, b) => a > b ? a : b) + 1,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 1,
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: Color(0xFFEAF0E6),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      lineTouchData: const LineTouchData(enabled: true),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var index = 0; index < values.length; index++)
                              FlSpot(index.toDouble(), values[index]),
                          ],
                          isCurved: true,
                          color: AppTheme.greenDark,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppTheme.green.withValues(alpha: 0.16),
                          ),
                        ),
                      ],
                    ),
                  )
                : const Center(
                    child: Text(
                      'No activity in this date range.',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AnalyticsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44),
          const SizedBox(height: 10),
          Text(UiStrings.authError(message), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: Text(UiStrings.fromEnglish('Try again')),
          ),
        ],
      ),
    ),
  );
}

String _kg(double value) => '${NumberFormat.decimalPattern().format(value)} kg';

String _money(double value) => NumberFormat.compactCurrency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
).format(value);
