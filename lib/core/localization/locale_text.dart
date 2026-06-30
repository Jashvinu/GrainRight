import 'package:get/get.dart';
import 'package:intl/intl.dart' as intl;

import '../../controllers/language_controller.dart';

class LocaleText {
  LocaleText._();

  static const _devanagariDigits = <String>[
    '०',
    '१',
    '२',
    '३',
    '४',
    '५',
    '६',
    '७',
    '८',
    '९',
  ];

  static String languageCode() {
    var code = Get.locale?.languageCode ?? 'en';
    if (Get.isRegistered<LanguageController>()) {
      code = Get.find<LanguageController>().language.value;
    }
    return code == 'hi' || code == 'mr' ? code : 'en';
  }

  static String digits(String value) {
    if (languageCode() == 'en') return value;
    return value.replaceAllMapped(
      RegExp(r'\d'),
      (match) => _devanagariDigits[int.parse(match[0]!)],
    );
  }

  static String number(num value, {int? fractionDigits}) {
    final locale = languageCode();
    final formatter = fractionDigits == null
        ? intl.NumberFormat.decimalPattern(locale)
        : (intl.NumberFormat.decimalPattern(locale)
          ..minimumFractionDigits = fractionDigits
          ..maximumFractionDigits = fractionDigits);
    return digits(formatter.format(value));
  }

  static String date(
    DateTime value, {
    String pattern = 'dd MMM yyyy',
  }) {
    return digits(intl.DateFormat(pattern, languageCode()).format(value));
  }

  static String time(
    DateTime value, {
    String pattern = 'HH:mm',
  }) {
    return digits(intl.DateFormat(pattern, languageCode()).format(value));
  }

  static String localizedValue(Object? value) {
    if (value == null) return '';
    if (value is num) return number(value);
    return digits(value.toString());
  }
}
