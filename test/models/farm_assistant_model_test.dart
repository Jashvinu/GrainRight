import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/satellite/farm_assistant_model.dart';

void main() {
  test('FarmAssistantAnswer parses guided farm process fields', () {
    final answer = FarmAssistantAnswer.fromJson(const {
      'answer': 'Check the yellow leaves before watering.',
      'summary': 'Yellowing can come from stress or disease.',
      'condition_summary': 'The selected farm is in watch condition.',
      'process_steps': [
        'Walk the lower patch.',
        'Check soil moisture.',
        'Send a clear photo.',
      ],
      'farm_update_suggestion': 'Yellow leaves seen in lower patch.',
      'follow_up_question': 'Is yellowing spreading across the field?',
      'priority': 'watch',
      'alert_suggestion': 'Recheck yellowing tomorrow morning.',
      'missing_data': ['fresh leaf photo', 'soil moisture'],
      'actions': ['Update farm status'],
      'warnings': ['Do not spray without confirmation.'],
      'confidence': 'medium',
      'model': 'qwen/test',
    });

    expect(answer.answer, 'Check the yellow leaves before watering.');
    expect(answer.conditionSummary, 'The selected farm is in watch condition.');
    expect(answer.processSteps, hasLength(3));
    expect(answer.farmUpdateSuggestion, 'Yellow leaves seen in lower patch.');
    expect(answer.followUpQuestion, 'Is yellowing spreading across the field?');
    expect(answer.priority, 'watch');
    expect(answer.alertSuggestion, 'Recheck yellowing tomorrow morning.');
    expect(answer.missingData, ['fresh leaf photo', 'soil moisture']);
    expect(answer.actions, ['Update farm status']);
    expect(answer.warnings, ['Do not spray without confirmation.']);
  });

  test('FarmAssistantAnswer defaults invalid priority to normal', () {
    final answer = FarmAssistantAnswer.fromJson(const {
      'answer': 'Keep monitoring.',
      'priority': 'high',
    });

    expect(answer.priority, 'normal');
    expect(answer.processSteps, isEmpty);
    expect(answer.missingData, isEmpty);
  });
}
