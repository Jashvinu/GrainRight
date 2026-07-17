class FarmAssistantAnswer {
  final String answer;
  final String summary;
  final List<String> actions;
  final List<String> warnings;
  final String conditionSummary;
  final List<String> processSteps;
  final String farmUpdateSuggestion;
  final String followUpQuestion;
  final String priority;
  final String alertSuggestion;
  final List<String> missingData;
  final List<Map<String, dynamic>> sources;
  final Map<String, dynamic> farmContext;
  final String confidence;
  final String? model;

  const FarmAssistantAnswer({
    required this.answer,
    required this.summary,
    required this.actions,
    required this.warnings,
    this.conditionSummary = '',
    this.processSteps = const <String>[],
    this.farmUpdateSuggestion = '',
    this.followUpQuestion = '',
    this.priority = 'normal',
    this.alertSuggestion = '',
    this.missingData = const <String>[],
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
      conditionSummary: '${root['condition_summary'] ?? ''}'.trim(),
      processSteps: _strings(root['process_steps']),
      farmUpdateSuggestion: '${root['farm_update_suggestion'] ?? ''}'.trim(),
      followUpQuestion: '${root['follow_up_question'] ?? ''}'.trim(),
      priority: _priority(root['priority']),
      alertSuggestion: '${root['alert_suggestion'] ?? ''}'.trim(),
      missingData: _strings(root['missing_data']),
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

  static String _priority(dynamic raw) {
    final value = '${raw ?? ''}'.trim().toLowerCase();
    if (value == 'urgent' || value == 'watch' || value == 'normal') {
      return value;
    }
    return 'normal';
  }

  static List<Map<String, dynamic>> _maps(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
