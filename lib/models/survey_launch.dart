enum SurveyLaunchMode { newSurvey, resumeDraft, edit }

class SurveyLaunchArgs {
  final SurveyLaunchMode mode;
  final String? surveyId;

  const SurveyLaunchArgs._({required this.mode, this.surveyId});

  const SurveyLaunchArgs.newSurvey() : this._(mode: SurveyLaunchMode.newSurvey);

  const SurveyLaunchArgs.resumeDraft()
    : this._(mode: SurveyLaunchMode.resumeDraft);

  const SurveyLaunchArgs.edit(String surveyId)
    : this._(mode: SurveyLaunchMode.edit, surveyId: surveyId);

  factory SurveyLaunchArgs.from(Object? value) {
    if (value is SurveyLaunchArgs) return value;

    // Preserve the legacy route contract where a string meant "edit this id".
    if (value is String && value.trim().isNotEmpty) {
      return SurveyLaunchArgs.edit(value);
    }

    if (value is Map) {
      final modeName = value['mode']?.toString();
      final surveyId = value['surveyId']?.toString();
      final mode = SurveyLaunchMode.values.firstWhere(
        (item) => item.name == modeName,
        orElse: () => SurveyLaunchMode.resumeDraft,
      );
      if (mode == SurveyLaunchMode.edit && surveyId != null) {
        return SurveyLaunchArgs.edit(surveyId);
      }
      return SurveyLaunchArgs._(mode: mode);
    }

    return const SurveyLaunchArgs.resumeDraft();
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    if (surveyId != null) 'surveyId': surveyId,
  };

  SurveyLaunchArgs forModeSwitch() {
    if (mode == SurveyLaunchMode.edit && surveyId != null) {
      return SurveyLaunchArgs.edit(surveyId!);
    }
    if (mode == SurveyLaunchMode.newSurvey) {
      return const SurveyLaunchArgs.newSurvey();
    }
    return const SurveyLaunchArgs.resumeDraft();
  }
}
