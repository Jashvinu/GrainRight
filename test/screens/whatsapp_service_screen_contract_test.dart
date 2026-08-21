import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('grain grading web link keeps farm context in the quality header', () {
    final source = File(
      'lib/screens/whatsapp_service_screen.dart',
    ).readAsStringSync();

    expect(source, contains("_service == 'grading'"));
    expect(source, contains('_gradingIntroCard()'));
    expect(source, contains('_gradingContextItem('));
    expect(source, contains("Icons.location_on_outlined"));
    expect(source, contains('_farmLocation()'));
  });

  test('grain grading photo actions do not depend on a popup picker', () {
    final source = File(
      'lib/screens/whatsapp_service_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('showModalBottomSheet')));
    expect(source, contains('ImageSource.camera'));
    expect(source, contains('ImageSource.gallery'));
    expect(source, contains('_photoSourceActions('));
  });
}
