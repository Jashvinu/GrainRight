/// Crop + variety catalog returned by the grading service `GET /api/crops`.
/// See docs/11_grain_grading_integration.md §4.
class CropVariety {
  final String value;
  final String label;

  const CropVariety({required this.value, required this.label});

  factory CropVariety.fromJson(Map<String, dynamic> json) {
    final value = '${json['value'] ?? ''}';
    final label = '${json['label'] ?? ''}';
    return CropVariety(
      value: value,
      label: label.isEmpty ? value : label,
    );
  }
}

class CropOption {
  final String value;
  final String label;
  final List<String> aliases;
  final List<String> ruleSummary;
  final List<CropVariety> varieties;

  const CropOption({
    required this.value,
    required this.label,
    this.aliases = const [],
    this.ruleSummary = const [],
    this.varieties = const [],
  });

  factory CropOption.fromJson(Map<String, dynamic> json) {
    final value = '${json['value'] ?? ''}';
    final label = '${json['label'] ?? ''}';
    return CropOption(
      value: value,
      label: label.isEmpty ? value : label,
      aliases: _stringList(json['aliases']),
      ruleSummary: _stringList(json['rule_summary']),
      varieties: (json['varieties'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CropVariety.fromJson)
          .toList(),
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }
}
