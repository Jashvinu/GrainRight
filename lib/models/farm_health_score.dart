class FarmHealthScore {
  const FarmHealthScore._();

  static int? calculate({
    double? ndvi,
    double? moisture,
    double? waterStress,
    double? weatherRisk,
    double? diseaseRisk,
    int highRiskCells = 0,
    String healthLabel = '',
  }) {
    final hasSignal =
        ndvi != null ||
        moisture != null ||
        waterStress != null ||
        weatherRisk != null ||
        diseaseRisk != null ||
        highRiskCells > 0 ||
        healthLabel.trim().isNotEmpty;
    if (!hasSignal) return null;

    var score = 82.0;
    if (ndvi != null) {
      score = 42 + ndvi.clamp(0.0, 1.0) * 56;
    } else {
      final label = healthLabel.trim().toLowerCase();
      if (label.contains('poor') ||
          label.contains('critical') ||
          label.contains('high')) {
        score = 46;
      } else if (label.contains('watch') ||
          label.contains('medium') ||
          label.contains('attention') ||
          label.contains('moderate') ||
          label.contains('fair')) {
        score = 68;
      } else if (label.contains('good') || label.contains('healthy')) {
        score = 84;
      }
    }

    if (moisture != null) {
      if (moisture < 0.24) {
        score -= 13;
      } else if (moisture < 0.34) {
        score -= 7;
      } else if (moisture > 0.80) {
        score -= 5;
      }
    }
    score -= (waterStress ?? 0).clamp(0.0, 1.0) * 10;
    score -= (weatherRisk ?? 0).clamp(0.0, 1.0) * 7;
    score -= (diseaseRisk ?? 0).clamp(0.0, 1.0) * 28;
    score -= highRiskCells.clamp(0, 6) * 2.5;
    return score.clamp(30.0, 98.0).round();
  }
}
