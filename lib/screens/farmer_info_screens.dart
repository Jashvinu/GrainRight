import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/locale_text.dart';
import '../config/theme.dart';
import '../config/ui_strings.dart';
import '../controllers/auth_controller.dart';
import '../models/satellite/farm_weather_model.dart';
import '../services/satellite_service.dart';
import '../widgets/app_back_button.dart';

class WeatherPage extends StatefulWidget {
  final String? farmId;
  final String? farmName;
  final String? farmLocation;
  final String? crop;
  final String? growthStage;
  final int? daysAfterSowing;
  final double? latitude;
  final double? longitude;
  final double? satelliteMoisture;
  final Map<String, dynamic>? fallbackWeatherContext;
  final FarmWeatherSnapshot? initialSnapshot;
  final ValueChanged<FarmWeatherSnapshot>? onSnapshotLoaded;

  const WeatherPage({
    super.key,
    this.farmId,
    this.farmName,
    this.farmLocation,
    this.crop,
    this.growthStage,
    this.daysAfterSowing,
    this.latitude,
    this.longitude,
    this.satelliteMoisture,
    this.fallbackWeatherContext,
    this.initialSnapshot,
    this.onSnapshotLoaded,
  });

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final SatelliteService _satelliteService = SatelliteService();
  FarmWeatherSnapshot? _snapshot;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
    unawaited(_load());
  }

  String _jwt() {
    if (!Get.isRegistered<AuthController>()) return '';
    return Get.find<AuthController>().accessToken.value;
  }

  Future<void> _load() async {
    if (widget.latitude == null || widget.longitude == null) {
      setState(() {
        _error = UiStrings.t('live_weather_location_required');
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _satelliteService.getLiveWeather(
        latitude: widget.latitude!,
        longitude: widget.longitude!,
        crop: widget.crop,
        growthStage: widget.growthStage,
        daysAfterSowing: widget.daysAfterSowing,
        satelliteMoisture: widget.satelliteMoisture,
        language: LocaleText.languageCode(),
        jwt: _jwt(),
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });
      widget.onSnapshotLoaded?.call(snapshot);
    } catch (e) {
      if (!mounted) return;
      final message = '$e'.replaceFirst('SatelliteApiException: ', '');
      final lowerMessage = message.toLowerCase();
      setState(() {
        _snapshot = null;
        _error =
            lowerMessage.contains('start_date') ||
                lowerMessage.contains('end_date') ||
                lowerMessage.contains('date_range')
            ? UiStrings.t('live_weather_refreshing')
            : message;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contextTitle =
        widget.farmName == null || widget.farmName!.trim().isEmpty
        ? UiStrings.t('weather_forecast')
        : '${UiStrings.t('weather')} • ${widget.farmName!}';

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
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            color: AppTheme.greenDark,
            tooltip: UiStrings.t('refresh'),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
            children: [
              _WeatherContextCard(
                farmName: widget.farmName,
                farmLocation: widget.farmLocation,
                crop: widget.crop,
                growthStage: widget.growthStage,
                daysAfterSowing: widget.daysAfterSowing,
              ),
              const SizedBox(height: 14),
              if (_loading && _snapshot == null)
                const _WeatherLoadingCard()
              else if (_snapshot != null)
                ..._liveWeatherCards(_snapshot!)
              else
                _WeatherErrorCard(
                  error: _error ?? UiStrings.t('live_weather_unavailable'),
                  fallbackWeatherContext: widget.fallbackWeatherContext,
                  onRetry: _load,
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _liveWeatherCards(FarmWeatherSnapshot snapshot) {
    final current = snapshot.current;
    final waterStress = snapshot.waterStress;
    final cropHealth = snapshot.cropHealthWeather;
    return [
      _CurrentWeatherCard(current: current, updatedAt: snapshot.updatedAt),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _SignalTile(
              icon: Icons.water_drop_rounded,
              title: UiStrings.t('water_stress'),
              value: _labelValue(waterStress['label']),
              detail: _percentValue(waterStress['score']),
              color: _stressColor(waterStress['label']),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SignalTile(
              icon: Icons.eco_rounded,
              title: UiStrings.t('crop_health'),
              value: _labelValue(cropHealth['label']),
              detail: _percentValue(cropHealth['score']),
              color: _healthColor(cropHealth['label']),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _HourlyWeatherCard(rows: snapshot.hourly24h),
      const SizedBox(height: 14),
      _DailyWeatherCard(rows: snapshot.daily7d),
      const SizedBox(height: 14),
      _AgroWeatherCard(
        agro: snapshot.agroWeather,
        waterStress: waterStress,
        cropHealth: cropHealth,
      ),
    ];
  }
}

class _WeatherContextCard extends StatelessWidget {
  final String? farmName;
  final String? farmLocation;
  final String? crop;
  final String? growthStage;
  final int? daysAfterSowing;

  const _WeatherContextCard({
    required this.farmName,
    required this.farmLocation,
    required this.crop,
    required this.growthStage,
    required this.daysAfterSowing,
  });

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      tint: const Color(0xFFECF6E8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on_rounded, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                      if (farmName != null && farmName!.trim().isNotEmpty)
                        farmName!.trim(),
                      if (farmLocation != null &&
                          farmLocation!.trim().isNotEmpty)
                        farmLocation!.trim(),
                    ].join(' • '),
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChipText(label: UiStrings.option(crop ?? 'Millet')),
                if (growthStage != null && growthStage!.trim().isNotEmpty)
                  _ChipText(label: UiStrings.option(growthStage!)),
                if (daysAfterSowing != null)
                  _ChipText(
                    label: UiStrings.f('day_value', {'day': daysAfterSowing!}),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentWeatherCard extends StatelessWidget {
  final Map<String, dynamic> current;
  final String updatedAt;

  const _CurrentWeatherCard({required this.current, required this.updatedAt});

  @override
  Widget build(BuildContext context) {
    final temp = _num(current['temperature_c']);
    final rawCondition = '${current['condition'] ?? ''}'.trim();
    final condition = rawCondition.isEmpty
        ? UiStrings.t('weather')
        : UiStrings.option(rawCondition);
    return _InfoPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppTheme.greenPale,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.cloud_queue_rounded,
                    color: AppTheme.green,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        temp == null
                            ? '--'
                            : '${LocaleText.number(temp, fractionDigits: 1)}°C',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        condition,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _MetricText(
                  label: UiStrings.t('humidity'),
                  value: _suffix(current['humidity_percent'], '%'),
                ),
                _MetricText(
                  label: UiStrings.t('rain'),
                  value: _suffix(current['rain_mm'], ' mm'),
                ),
                _MetricText(
                  label: UiStrings.t('wind'),
                  value: _suffix(current['wind_kmh'], ' km/h'),
                ),
              ],
            ),
            if (updatedAt.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                UiStrings.f('updated_at', {
                  'time': LocaleText.digits(updatedAt),
                }),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HourlyWeatherCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _HourlyWeatherCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelTitle(
              icon: Icons.schedule_rounded,
              title: UiStrings.t('next_24_hours'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: rows.take(24).length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return Container(
                    width: 84,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8F2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hourLabel(row['time']),
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.thermostat_rounded,
                          color: AppTheme.green,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _suffix(row['temperature_c'], '°'),
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          UiStrings.f('rain_amount_value', {
                            'amount': _suffix(row['rain_mm'], 'mm'),
                          }),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyWeatherCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _DailyWeatherCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelTitle(
              icon: Icons.calendar_month_rounded,
              title: UiStrings.t('seven_day_forecast'),
            ),
            const SizedBox(height: 10),
            ...rows
                .take(7)
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _dayLabel(row['date']),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          '${_suffix(row['temp_min_c'], '°')} / ${_suffix(row['temp_max_c'], '°')}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: 72,
                          child: Text(
                            _suffix(row['rain_mm'], ' mm'),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _AgroWeatherCard extends StatelessWidget {
  final Map<String, dynamic> agro;
  final Map<String, dynamic> waterStress;
  final Map<String, dynamic> cropHealth;

  const _AgroWeatherCard({
    required this.agro,
    required this.waterStress,
    required this.cropHealth,
  });

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      tint: const Color(0xFFF0F8E8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelTitle(
              icon: Icons.agriculture_rounded,
              title: UiStrings.t('farm_weather_advice'),
            ),
            const SizedBox(height: 12),
            _AdviceLine(
              icon: Icons.water_drop_outlined,
              text: _weatherSentence(
                waterStress['recommendation'] ?? agro['next_action'],
              ),
            ),
            const SizedBox(height: 10),
            _AdviceLine(
              icon: Icons.eco_outlined,
              text: _weatherSentence(
                cropHealth['summary'] ??
                    UiStrings.t('scout_selected_crop_forecast'),
              ),
            ),
            if (agro['next_action'] != null) ...[
              const SizedBox(height: 10),
              _AdviceLine(
                icon: Icons.check_circle_outline_rounded,
                text: _weatherSentence(agro['next_action']),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeatherErrorCard extends StatelessWidget {
  final String error;
  final Map<String, dynamic>? fallbackWeatherContext;
  final VoidCallback onRetry;

  const _WeatherErrorCard({
    required this.error,
    required this.fallbackWeatherContext,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final hasFallback =
        fallbackWeatherContext != null && fallbackWeatherContext!.isNotEmpty;
    return _InfoPanel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelTitle(
              icon: Icons.cloud_off_rounded,
              title: UiStrings.t('weather_sync_needed'),
            ),
            const SizedBox(height: 10),
            Text(
              hasFallback ? UiStrings.t('live_weather_failed_fallback') : error,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            if (hasFallback) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fallbackWeatherContext!.entries
                    .take(5)
                    .map(
                      (entry) => _ChipText(
                        label:
                            '${UiStrings.option(entry.key.replaceAll('_', ' '))}: ${LocaleText.localizedValue(entry.value)}',
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(UiStrings.t('try_again')),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherLoadingCard extends StatelessWidget {
  const _WeatherLoadingCard();

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                UiStrings.t('loading_live_farm_weather'),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;

  const _SignalTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return _InfoPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              detail,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricText extends StatelessWidget {
  final String label;
  final String value;

  const _MetricText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PanelTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.greenDark, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _AdviceLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdviceLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.green, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppTheme.textDark,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChipText extends StatelessWidget {
  final String label;

  const _ChipText({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.greenDark,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final Widget child;
  final Color tint;

  const _InfoPanel({required this.child, this.tint = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

double? _num(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String _suffix(dynamic value, String suffix) {
  final number = _num(value);
  if (number == null) return '--';
  return '${LocaleText.number(number, fractionDigits: number % 1 == 0 ? 0 : 1)}$suffix';
}

String _percentValue(dynamic value) {
  final number = _num(value);
  if (number == null) return '--';
  return '${LocaleText.number(number * 100, fractionDigits: 0)}%';
}

String _labelValue(dynamic value) {
  final text = '${value ?? '--'}';
  if (text.isEmpty) return '--';
  return UiStrings.option(text);
}

String _weatherSentence(dynamic value) {
  final text = '${value ?? ''}'.trim();
  final key = switch (text.toLowerCase()) {
    'irrigate in a cool window and inspect dry patches.' =>
      'weather_rec_irrigate_cool',
    'monitor soil moisture and prepare irrigation if rain misses.' =>
      'weather_rec_monitor_moisture',
    'water stress is currently controlled.' => 'weather_rec_controlled',
    'check soil moisture and irrigate if the root zone is dry.' =>
      'weather_rec_check_root_zone',
    'monitor soil moisture before the next irrigation decision.' =>
      'weather_rec_monitor_before_irrigation',
    'water stress is low; continue normal field observation.' =>
      'weather_rec_low_observation',
    'weather is supportive for current crop growth.' =>
      'weather_summary_supportive',
    'weather needs scouting attention this week.' =>
      'weather_summary_attention',
    'weather stress is elevated; prioritize field inspection.' =>
      'weather_summary_stress_elevated',
    'wet weather can raise disease risk. scout leaves and panicles.' =>
      'weather_summary_wet_disease',
    'heat and dry weather can stress the crop. check moisture.' =>
      'weather_summary_heat_dry',
    'weather is manageable. continue routine crop scouting.' =>
      'weather_summary_manageable',
    'check water stress before midday and irrigate if soil is dry.' =>
      'weather_next_check_midday',
    'scout the crop during the next field round.' => 'weather_next_scout_round',
    _ => null,
  };
  return key == null ? LocaleText.digits(text) : UiStrings.t(key);
}

Color _stressColor(dynamic label) {
  final text = '$label'.toLowerCase();
  if (text.contains('high')) return const Color(0xFFD32F2F);
  if (text.contains('medium')) return const Color(0xFFF57C00);
  return const Color(0xFF2EAF4A);
}

Color _healthColor(dynamic label) {
  final text = '$label'.toLowerCase();
  if (text.contains('stress')) return const Color(0xFFD32F2F);
  if (text.contains('watch')) return const Color(0xFFF57C00);
  return const Color(0xFF2EAF4A);
}

String _hourLabel(dynamic raw) {
  final text = '$raw';
  if (text.length >= 13) return text.substring(11, 13);
  return text;
}

String _dayLabel(dynamic raw) {
  final parsed = DateTime.tryParse('$raw');
  if (parsed == null) return '$raw';
  return LocaleText.date(parsed, pattern: 'dd/MM');
}
