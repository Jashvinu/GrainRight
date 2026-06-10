import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/survey_launch.dart';

void main() {
  group('SurveyLaunchArgs', () {
    test('defaults to resume draft for legacy empty route args', () {
      final args = SurveyLaunchArgs.from(null);

      expect(args.mode, SurveyLaunchMode.resumeDraft);
      expect(args.surveyId, isNull);
    });

    test('keeps legacy string arguments as edit survey ids', () {
      final args = SurveyLaunchArgs.from('survey-123');

      expect(args.mode, SurveyLaunchMode.edit);
      expect(args.surveyId, 'survey-123');
    });

    test('parses explicit new survey map arguments', () {
      final args = SurveyLaunchArgs.from({'mode': 'newSurvey'});

      expect(args.mode, SurveyLaunchMode.newSurvey);
      expect(args.surveyId, isNull);
    });

    test('preserves new survey mode when switching form layouts', () {
      final args = const SurveyLaunchArgs.newSurvey().forModeSwitch();

      expect(args.mode, SurveyLaunchMode.newSurvey);
      expect(args.surveyId, isNull);
    });

    test('preserves edit mode when switching form layouts', () {
      final args = const SurveyLaunchArgs.edit('survey-123').forModeSwitch();

      expect(args.mode, SurveyLaunchMode.edit);
      expect(args.surveyId, 'survey-123');
    });
  });
}
