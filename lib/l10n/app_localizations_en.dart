// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get surveyAssistantWelcome => 'Welcome, I\'m your survey assistant';

  @override
  String get continueLabel => 'Continue';

  @override
  String get back => 'Back';

  @override
  String get skip => 'Skip';

  @override
  String get saveDraft => 'Save draft';

  @override
  String get submit => 'Submit';

  @override
  String get drawFarmBoundary => 'Draw your farm boundary';

  @override
  String get tapAndDragToDraw => 'Tap and drag to draw';

  @override
  String get clear => 'Clear';

  @override
  String get done => 'Done';

  @override
  String get locatingYou => 'Locating you...';

  @override
  String get permissionDenied => 'Permission denied';

  @override
  String get tryAgain => 'Try again';

  @override
  String get required => 'Required';

  @override
  String get invalidMobile => '10 digits required';

  @override
  String get invalidAadhaar => '12 digits required';

  @override
  String get surveySubmittedDiagnostics =>
      'Survey submitted. Diagnostics now available.';
}
