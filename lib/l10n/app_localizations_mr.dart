// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class AppLocalizationsMr extends AppLocalizations {
  AppLocalizationsMr([String locale = 'mr']) : super(locale);

  @override
  String get surveyAssistantWelcome =>
      'नमस्कार, मी तुमचा सर्वेक्षण सहाय्यक आहे';

  @override
  String get continueLabel => 'पुढे';

  @override
  String get back => 'मागे';

  @override
  String get skip => 'वगळा';

  @override
  String get saveDraft => 'मसुदा जतन करा';

  @override
  String get submit => 'सबमिट करा';

  @override
  String get drawFarmBoundary => 'तुमच्या शेताची सीमा काढा';

  @override
  String get tapAndDragToDraw => 'काढण्यासाठी टॅप करून ड्रॅग करा';

  @override
  String get clear => 'साफ करा';

  @override
  String get done => 'पूर्ण';

  @override
  String get locatingYou => 'तुमचे स्थान शोधत आहे...';

  @override
  String get permissionDenied => 'परवानगी नाकारली';

  @override
  String get tryAgain => 'पुन्हा प्रयत्न करा';

  @override
  String get required => 'आवश्यक';

  @override
  String get invalidMobile => '10 अंक आवश्यक';

  @override
  String get invalidAadhaar => '12 अंक आवश्यक';

  @override
  String get surveySubmittedDiagnostics =>
      'सर्वेक्षण सबमिट झाले. डायग्नोस्टिक्स आता उपलब्ध आहे.';
}
