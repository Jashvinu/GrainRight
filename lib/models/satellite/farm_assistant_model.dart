class FarmAssistantAnswer {
  final String answer;
  final String summary;
  final List<String> actions;
  final List<String> warnings;
  final List<Map<String, dynamic>> sources;
  final Map<String, dynamic> farmContext;
  final String confidence;
  final String? model;

  const FarmAssistantAnswer({
    required this.answer,
    required this.summary,
    required this.actions,
    required this.warnings,
    required this.sources,
    required this.farmContext,
    required this.confidence,
    this.model,
  });

  factory FarmAssistantAnswer.fromJson(Map<String, dynamic> json) {
    final root = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    return FarmAssistantAnswer(
      answer: '${root['answer'] ?? ''}'.trim(),
      summary: '${root['summary'] ?? ''}'.trim(),
      actions: _strings(root['actions'] ?? root['next_actions']),
      warnings: _strings(root['warnings'] ?? root['cautions']),
      sources: _maps(root['sources']),
      farmContext: root['farm_context'] is Map
          ? Map<String, dynamic>.from(root['farm_context'] as Map)
          : <String, dynamic>{},
      confidence: '${root['confidence'] ?? 'medium'}',
      model: root['model'] == null ? null : '${root['model']}',
    );
  }

  static List<String> _strings(dynamic raw) {
    return (raw as List? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _maps(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
