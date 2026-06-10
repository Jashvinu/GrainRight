import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';

class WeatherPage extends StatelessWidget {
  final String? farmName;
  final String? farmLocation;

  const WeatherPage({
    super.key,
    this.farmName,
    this.farmLocation,
  });

  static const List<Map<String, Object>> _forecast = [
    {
      'day': 'Today',
      'condition': 'Sunny',
      'high': '31°',
      'low': '22°',
      'rain': '12%',
      'wind': '8 km/h',
      'aqi': '55',
      'icon': Icons.wb_sunny_rounded,
    },
    {
      'day': 'Tomorrow',
      'condition': 'Partly Cloudy',
      'high': '29°',
      'low': '21°',
      'rain': '18%',
      'wind': '10 km/h',
      'aqi': '60',
      'icon': Icons.wb_cloudy_rounded,
    },
    {
      'day': 'Wed',
      'condition': 'Light showers',
      'high': '27°',
      'low': '20°',
      'rain': '45%',
      'wind': '14 km/h',
      'aqi': '68',
      'icon': Icons.grain,
    },
    {
      'day': 'Thu',
      'condition': 'Humid',
      'high': '30°',
      'low': '21°',
      'rain': '9%',
      'wind': '6 km/h',
      'aqi': '62',
      'icon': Icons.opacity,
    },
    {
      'day': 'Fri',
      'condition': 'Cloudy',
      'high': '28°',
      'low': '20°',
      'rain': '22%',
      'wind': '11 km/h',
      'aqi': '64',
      'icon': Icons.cloud,
    },
    {
      'day': 'Sat',
      'condition': 'Dry',
      'high': '31°',
      'low': '19°',
      'rain': '8%',
      'wind': '9 km/h',
      'aqi': '52',
      'icon': Icons.wb_sunny_rounded,
    },
  ];

  static const List<Map<String, String>> _agroSignals = [
    {
      'type': 'Irrigation',
      'action': 'Light irrigation after sunset',
      'reason': 'Soil profile suggests top 10cm moisture dip.',
      'tone': 'Good',
    },
    {
      'type': 'Disease risk',
      'action': 'Monitor leaf spot by evening',
      'reason': 'Humidity above 70% after 2–3 days.',
      'tone': 'Watch',
    },
    {
      'type': 'Crop stage',
      'action': 'Hold watering window',
      'reason': 'Field is in grain-filling window, avoid water stress.',
      'tone': 'Important',
    },
  ];

  static const List<String> _weatherTips = [
    'Cover harvested produce if rain alert crosses 35%.',
    'Shift heavy spray work to morning or late evening.',
    'Keep irrigation low-volume and frequent during warm dry spell.',
  ];

  @override
  Widget build(BuildContext context) {
    final contextTitle = farmName == null || farmName!.trim().isEmpty
        ? 'Weather Forecast'
        : 'Weather • ${farmName!}';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          contextTitle,
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.greenDark),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            if (farmName != null || farmLocation != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _InfoPanel(
                  tint: const Color(0xFFECF6E8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: AppTheme.green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            farmName == null
                                ? (farmLocation ?? 'Local weather')
                                : (farmLocation == null || farmLocation!.trim().isEmpty
                                    ? '${farmName!} • weather panel'
                                    : '${farmName!} • ${farmLocation!}'),
                            style: const TextStyle(
                              color: AppTheme.greenDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const _RevealSection(delayMs: 0, child: _WeatherHeroCard()),
            const SizedBox(height: 16),
            _RevealSection(
              delayMs: 35,
              child: _InfoPanel(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hourly Temperature Trend',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.greenDark),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Expected daily variations in temperature over the next 12 hours.',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      const _HourlyTempChart(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _WeatherMetricTile(
                            icon: Icons.wb_sunny_rounded,
                            title: 'Condition',
                            value: _forecast[0]['condition'] as String,
                            tint: AppTheme.greenPale,
                          ),
                          const SizedBox(width: 8),
                          _WeatherMetricTile(
                            icon: Icons.air,
                            title: 'Wind',
                            value: _forecast[0]['wind'] as String,
                            tint: const Color(0xFFE8F5FF),
                          ),
                          const SizedBox(width: 8),
                          _WeatherMetricTile(
                            icon: Icons.opacity,
                            title: 'Rain Prob.',
                            value: _forecast[0]['rain'] as String,
                            tint: const Color(0xFFF3E8FF),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _RevealSection(
              delayMs: 70,
              child: _InfoPanel(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '7-Day Weather Forecast',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.greenDark),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 190,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _forecast.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final day = _forecast[index];
                            return _WeatherForecastCard(
                              day: day['day'] as String,
                              condition: day['condition'] as String,
                              high: day['high'] as String,
                              low: day['low'] as String,
                              rain: day['rain'] as String,
                              wind: day['wind'] as String,
                              aqi: day['aqi'] as String,
                              icon: day['icon'] as IconData,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _RevealSection(
              delayMs: 95,
              child: _InfoPanel(
                tint: const Color(0xFFECF6E8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.grass_outlined, color: AppTheme.green),
                          SizedBox(width: 8),
                          Text(
                            'Agro-watch signals',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: AppTheme.greenDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._agroSignals.map(
                        (signal) => _WeatherSignalCard(
                          type: signal['type']!,
                          action: signal['action']!,
                          reason: signal['reason']!,
                          tone: signal['tone']!,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _RevealSection(
              delayMs: 115,
              child: _InfoPanel(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: AppTheme.greenDark),
                          SizedBox(width: 8),
                          Text(
                            'Farmer field tips',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppTheme.greenDark),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._weatherTips.map(
                        (tip) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle_outline_rounded, color: AppTheme.green, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tip,
                                  style: const TextStyle(color: AppTheme.textDark, height: 1.4, fontSize: 13),
                                ),
                              ),
                            ],
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
      ),
    );
  }
}

class _HourlyTempChart extends StatelessWidget {
  const _HourlyTempChart();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: CustomPaint(
        painter: _CurveChartPainter(),
      ),
    );
  }
}

class _CurveChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.green.withValues(alpha: 0.25),
          AppTheme.green.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.7);
    path.cubicTo(
      size.width * 0.25, size.height * 0.25,
      size.width * 0.5, size.height * 0.15,
      size.width * 0.75, size.height * 0.65,
    );
    path.lineTo(size.width, size.height * 0.4);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    final dotPaint = Paint()
      ..color = AppTheme.greenDark
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    void drawTemp(String text, double x, double y) {
      canvas.drawCircle(Offset(x, y), 4.5, dotPaint);
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(
          color: AppTheme.greenDark,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - 12, y - 18));
    }

    drawTemp('22°', 0, size.height * 0.7);
    drawTemp('31°', size.width * 0.45, size.height * 0.2);
    drawTemp('27°', size.width * 0.75, size.height * 0.65);
    drawTemp('29°', size.width, size.height * 0.4);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WeatherHeroCard extends StatelessWidget {
  const _WeatherHeroCard();

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      tint: const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.wb_sunny_rounded, color: AppTheme.green, size: 26),
                SizedBox(width: 8),
                Text(
                  'Current Conditions',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.greenDark),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: const [
                      Positioned(
                        top: 14,
                        child: Icon(Icons.wb_cloudy_outlined, size: 36, color: AppTheme.green),
                      ),
                      Positioned(
                        bottom: 12,
                        child: Text(
                          '31°C',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clear and Warm',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.textDark),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Humidity: 45% • UV Index: 8 (Very High)\nVisibility: 7 km • Pressure: 1012 hPa',
                        style: TextStyle(color: AppTheme.textMuted, height: 1.35, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: const [
                          _FarmMetric(label: 'Soil Temp', value: '26°C'),
                          _FarmMetric(label: 'Solar Rad', value: '820 W/m²'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherMetricTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color tint;

  const _WeatherMetricTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.greenDark),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherForecastCard extends StatelessWidget {
  final String day;
  final String condition;
  final String high;
  final String low;
  final String rain;
  final String wind;
  final String aqi;
  final IconData icon;

  const _WeatherForecastCard({
    required this.day,
    required this.condition,
    required this.high,
    required this.low,
    required this.rain,
    required this.wind,
    required this.aqi,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 2, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              day,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.greenDark),
            ),
            const SizedBox(height: 6),
            Icon(icon, color: AppTheme.green, size: 24),
            const SizedBox(height: 6),
            Text(
              condition,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.textDark),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Max: $high', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                Text('Min: $low', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              ],
            ),
            const Divider(height: 10),
            Row(
              children: [
                const Icon(Icons.opacity, size: 10, color: Colors.blueAccent),
                const SizedBox(width: 2),
                Text('Rain: $rain', style: const TextStyle(fontSize: 9)),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.air, size: 10, color: Colors.grey),
                const SizedBox(width: 2),
                Text('Wind: $wind', style: const TextStyle(fontSize: 9)),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.wb_cloudy_outlined, size: 10, color: AppTheme.green),
                const SizedBox(width: 2),
                Text('AQI: $aqi', style: const TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmMetric extends StatelessWidget {
  final String label;
  final String value;

  const _FarmMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 9, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherSignalCard extends StatelessWidget {
  final String type;
  final String action;
  final String reason;
  final String tone;

  const _WeatherSignalCard({
    required this.type,
    required this.action,
    required this.reason,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final toneColor = tone == 'Important'
        ? const Color(0xFFFFF3E0)
        : tone == 'Watch'
            ? const Color(0xFFFFF8E1)
            : const Color(0xFFE8F5E9);
    final toneText = tone == 'Important'
        ? Colors.deepOrange
        : tone == 'Watch'
            ? const Color(0xFFB36B00)
            : AppTheme.greenDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: toneColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.sensors_rounded, color: toneText, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$type • $action',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reason,
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tone,
                style: TextStyle(
                  color: toneText,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final Widget child;
  final Color? tint;

  const _InfoPanel({
    required this.child,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tint ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RevealSection extends StatelessWidget {
  final Widget child;
  final int delayMs;

  const _RevealSection({
    required this.child,
    required this.delayMs,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(delayMs),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 420 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
