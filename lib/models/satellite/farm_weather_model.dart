class FarmWeatherSnapshot {
  final Map<String, dynamic> current;
  final List<Map<String, dynamic>> hourly24h;
  final List<Map<String, dynamic>> daily7d;
  final Map<String, dynamic> agroWeather;
  final Map<String, dynamic> waterStress;
  final Map<String, dynamic> cropHealthWeather;
  final String updatedAt;
  final String source;

  const FarmWeatherSnapshot({
    required this.current,
    required this.hourly24h,
    required this.daily7d,
    required this.agroWeather,
    required this.waterStress,
    required this.cropHealthWeather,
    required this.updatedAt,
    required this.source,
  });

  factory FarmWeatherSnapshot.fromJson(Map<String, dynamic> json) {
    final root = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final normalized = _normalizeOpenMeteo(root);
    final current = _map(root['current']).isNotEmpty
        ? _map(root['current'])
        : _map(normalized['current']);
    final hourly = _rows(root['hourly_24h']).isNotEmpty
        ? _rows(root['hourly_24h'])
        : _rows(normalized['hourly_24h']);
    final daily = _rows(root['daily_7d']).isNotEmpty
        ? _rows(root['daily_7d'])
        : _rows(normalized['daily_7d']);
    final waterStress = _map(root['water_stress']).isNotEmpty
        ? _map(root['water_stress'])
        : _buildWaterStress(current, daily);
    final cropHealth = _map(root['crop_health_weather']).isNotEmpty
        ? _map(root['crop_health_weather'])
        : _buildCropHealthWeather(current, daily);
    return FarmWeatherSnapshot(
      current: current,
      hourly24h: hourly,
      daily7d: daily,
      agroWeather: _map(root['agro_weather']).isNotEmpty
          ? _map(root['agro_weather'])
          : _buildAgroWeather(root, waterStress, cropHealth),
      waterStress: waterStress,
      cropHealthWeather: cropHealth,
      updatedAt: '${root['updated_at'] ?? ''}',
      source: '${root['source'] ?? 'open-meteo'}',
    );
  }

  static Map<String, dynamic> _map(dynamic raw) {
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _rows(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static double? readDouble(Map<String, dynamic> row, String key) {
    final raw = row[key];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static Map<String, dynamic> _normalizeOpenMeteo(Map<String, dynamic> root) {
    final hourlyRaw = _map(root['hourly']);
    final dailyRaw = _map(root['daily']);
    final source = '${root['source']}'.toLowerCase();
    final fromEnd = source.contains('archive');
    final hourly = _seriesRows(
      hourlyRaw,
      limit: 24,
      fromEnd: fromEnd,
      mapper: (series, index) => {
        'time': _pick(series, 'time', index),
        'temperature_c': _pick(series, 'temperature_2m', index),
        'humidity_percent': _pick(series, 'relative_humidity_2m', index),
        'apparent_temperature_c': _pick(
          series,
          'apparent_temperature',
          index,
        ),
        'rain_mm': _pick(series, 'precipitation', index),
        'wind_kmh': _pick(series, 'wind_speed_10m', index),
        'cloud_percent': _pick(series, 'cloud_cover', index),
        'weather_code': _pick(series, 'weather_code', index),
        'condition': _condition(_pick(series, 'weather_code', index)),
      },
    );
    final daily = _seriesRows(
      dailyRaw,
      limit: 7,
      fromEnd: fromEnd,
      mapper: (series, index) => {
        'date': _pick(series, 'time', index),
        'temp_max_c': _pick(series, 'temperature_2m_max', index),
        'temp_min_c': _pick(series, 'temperature_2m_min', index),
        'rain_mm': _pick(series, 'precipitation_sum', index),
        'rain_probability_percent': _pick(
          series,
          'precipitation_probability_max',
          index,
        ),
      },
    );
    final current = _map(root['current']).isNotEmpty
        ? _map(root['current'])
        : (hourly.isNotEmpty ? hourly.last : <String, dynamic>{});
    return {
      'current': current,
      'hourly_24h': hourly,
      'daily_7d': daily,
    };
  }

  static List<Map<String, dynamic>> _seriesRows(
    Map<String, dynamic> series, {
    required int limit,
    required bool fromEnd,
    required Map<String, dynamic> Function(Map<String, dynamic>, int) mapper,
  }) {
    final length = _seriesLength(series);
    if (length == 0) return const <Map<String, dynamic>>[];
    final count = length < limit ? length : limit;
    final start = fromEnd ? length - count : 0;
    return List<Map<String, dynamic>>.generate(
      count,
      (offset) => mapper(series, start + offset),
      growable: false,
    );
  }

  static int _seriesLength(Map<String, dynamic> series) {
    var length = 0;
    for (final value in series.values) {
      if (value is List && value.length > length) length = value.length;
    }
    return length;
  }

  static dynamic _pick(Map<String, dynamic> series, String key, int index) {
    final values = series[key];
    if (values is List && index >= 0 && index < values.length) {
      return values[index];
    }
    return null;
  }

  static Map<String, dynamic> _buildWaterStress(
    Map<String, dynamic> current,
    List<Map<String, dynamic>> daily,
  ) {
    final rain = daily.fold<double>(
      0,
      (sum, row) => sum + (readDouble(row, 'rain_mm') ?? 0),
    );
    final temp = readDouble(current, 'temperature_c') ?? 0;
    final label = rain < 5 && temp >= 30
        ? 'high'
        : rain < 20
        ? 'medium'
        : 'low';
    final score = label == 'high'
        ? 0.78
        : label == 'medium'
        ? 0.48
        : 0.18;
    return {
      'label': label,
      'score': score,
      'recommendation': label == 'high'
          ? 'Check soil moisture and irrigate if the root zone is dry.'
          : label == 'medium'
          ? 'Monitor soil moisture before the next irrigation decision.'
          : 'Water stress is low; continue normal field observation.',
    };
  }

  static Map<String, dynamic> _buildCropHealthWeather(
    Map<String, dynamic> current,
    List<Map<String, dynamic>> daily,
  ) {
    final rain = daily.fold<double>(
      0,
      (sum, row) => sum + (readDouble(row, 'rain_mm') ?? 0),
    );
    final temp = readDouble(current, 'temperature_c') ?? 0;
    final humidity = readDouble(current, 'humidity_percent') ?? 0;
    final wetRisk = rain >= 30 || humidity >= 82;
    final heatRisk = temp >= 35 && rain < 10;
    final label = wetRisk || heatRisk ? 'watch' : 'stable';
    return {
      'label': label,
      'score': label == 'watch' ? 0.62 : 0.24,
      'summary': wetRisk
          ? 'Wet weather can raise disease risk. Scout leaves and panicles.'
          : heatRisk
          ? 'Heat and dry weather can stress the crop. Check moisture.'
          : 'Weather is manageable. Continue routine crop scouting.',
    };
  }

  static Map<String, dynamic> _buildAgroWeather(
    Map<String, dynamic> root,
    Map<String, dynamic> waterStress,
    Map<String, dynamic> cropHealth,
  ) {
    return {
      'crop': '${root['crop'] ?? 'millet'}',
      'growth_stage': '${root['growth_stage'] ?? ''}',
      'irrigation_signal': waterStress['label'],
      'disease_weather_signal': cropHealth['label'],
      'next_action':
          waterStress['recommendation'] ?? cropHealth['summary'] ?? '',
    };
  }

  static String _condition(dynamic code) {
    final value = code is num ? code.toInt() : int.tryParse('$code');
    if (value == null) return 'Weather';
    if (value == 0) return 'Clear';
    if (value <= 3) return 'Cloudy';
    if (value <= 67) return 'Rain';
    if (value <= 77) return 'Showers';
    if (value >= 95) return 'Thunderstorm';
    return 'Weather';
  }
}

class CropLifecycleAdvice {
  final String crop;
  final String growthStage;
  final String stageWindow;
  final String waterNeed;
  final String diseaseWatch;
  final String scoutTask;
  final String nextAction;
  final List<CropLifecycleStage> timeline;
  final List<Map<String, dynamic>> knowledge;

  const CropLifecycleAdvice({
    required this.crop,
    required this.growthStage,
    required this.stageWindow,
    required this.waterNeed,
    required this.diseaseWatch,
    required this.scoutTask,
    required this.nextAction,
    required this.timeline,
    required this.knowledge,
  });

  factory CropLifecycleAdvice.fromJson(Map<String, dynamic> json) {
    final root = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    return CropLifecycleAdvice(
      crop: '${root['crop'] ?? ''}',
      growthStage: '${root['growth_stage'] ?? ''}',
      stageWindow: '${root['stage_window'] ?? ''}',
      waterNeed: '${root['water_need'] ?? ''}',
      diseaseWatch: '${root['disease_watch'] ?? ''}',
      scoutTask: '${root['scout_task'] ?? ''}',
      nextAction: '${root['next_action'] ?? ''}',
      timeline: (root['timeline'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => CropLifecycleStage.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .toList(growable: false),
      knowledge: (root['knowledge'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false),
    );
  }
}

class CropLifecycleStage {
  final String stage;
  final int startDay;
  final int endDay;
  final String detail;

  const CropLifecycleStage({
    required this.stage,
    required this.startDay,
    required this.endDay,
    required this.detail,
  });

  factory CropLifecycleStage.fromJson(Map<String, dynamic> json) {
    int readInt(String key, int fallback) {
      final value = json[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    return CropLifecycleStage(
      stage: '${json['stage'] ?? json['growth_stage'] ?? ''}',
      startDay: readInt('start_day', readInt('das_start', 0)),
      endDay: readInt('end_day', readInt('das_end', 9999)),
      detail: '${json['detail'] ?? json['content'] ?? ''}',
    );
  }
}
