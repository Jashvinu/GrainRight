// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get surveyAssistantWelcome => 'नमस्ते, मैं आपका सर्वे सहायक हूं';

  @override
  String get continueLabel => 'जारी रखें';

  @override
  String get back => 'वापस';

  @override
  String get skip => 'छोड़ें';

  @override
  String get saveDraft => 'ड्राफ्ट सेव करें';

  @override
  String get submit => 'सबमिट';

  @override
  String get drawFarmBoundary => 'अपने खेत की सीमा बनाएं';

  @override
  String get tapAndDragToDraw => 'बनाने के लिए टैप करके खींचें';

  @override
  String get clear => 'साफ करें';

  @override
  String get done => 'पूर्ण';

  @override
  String get locatingYou => 'आपका स्थान ढूंढ रहे हैं...';

  @override
  String get permissionDenied => 'अनुमति अस्वीकार की गई';

  @override
  String get tryAgain => 'फिर कोशिश करें';

  @override
  String get required => 'आवश्यक';

  @override
  String get invalidMobile => '10 अंक आवश्यक';

  @override
  String get invalidAadhaar => '12 अंक आवश्यक';

  @override
  String get surveySubmittedDiagnostics =>
      'सर्वे सबमिट हो गया। डायग्नोस्टिक्स अब उपलब्ध है।';
}
