import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workspace = File(
    'lib/widgets/fpc_module_workspace.dart',
  ).readAsStringSync();

  test('FPC operational date fields use calendar-backed input types', () {
    expect(
      workspace,
      contains('enum _InputType { text, number, date, dateTime }'),
    );
    expect(workspace, contains('showDatePicker('));
    expect(workspace, contains('showTimePicker('));
    expect(workspace, contains("'manufactured_on'"));
    expect(workspace, contains("'expected_harvest_date'"));
    expect(workspace, contains("'scheduled_at'"));
    expect(workspace, contains('type: _InputType.dateTime'));
  });
}
