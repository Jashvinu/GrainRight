import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';

void main() {
  test('every UI string has complete English Hindi and Marathi copy', () {
    final failures = <String>[];
    for (final entry in UiStrings.translationCatalog.entries) {
      for (final language in const ['en', 'hi', 'mr']) {
        if (entry.value[language]?.trim().isNotEmpty != true) {
          failures.add('${entry.key} is missing $language');
        }
      }

      final englishPlaceholders = _placeholders(entry.value['en']!);
      for (final language in const ['hi', 'mr']) {
        final localizedPlaceholders = _placeholders(entry.value[language]!);
        if (!_sameSet(englishPlaceholders, localizedPlaceholders)) {
          failures.add(
            '${entry.key} has different placeholders in $language: '
            '$englishPlaceholders vs $localizedPlaceholders',
          );
        }
      }
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('screens and widgets do not add direct English Text literals', () {
    final roots = [
      Directory('lib/screens'),
      Directory('lib/widgets'),
      Directory('lib/features'),
    ];
    final directText = RegExp(
      r'''\bText\(\s*(?:const\s+)?['"]([A-Za-z][^'"]*)['"]''',
      multiLine: true,
    );
    final directDecoration = RegExp(
      r'''(?:tooltip|labelText|hintText|semanticLabel):\s*['"]([A-Za-z][^'"]*)['"]''',
    );
    final allowedCopy = <String>{'Kalsubai Farms', 'wrkfarm'};
    final violations = <String>[];

    for (final root in roots) {
      for (final file
          in root
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        for (final pattern in [directText, directDecoration]) {
          for (final match in pattern.allMatches(source)) {
            final copy = match.group(1)!.trim();
            if (!allowedCopy.contains(copy)) {
              violations.add('${file.path}: $copy');
            }
          }
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('configured English UI copy has translation catalog entries', () {
    final roots = [
      Directory('lib/screens'),
      Directory('lib/widgets'),
      Directory('lib/features'),
    ];
    final configuredCopy = RegExp(
      r'''\b(?:title|subtitle|label|helperText|message|description|body|caption|text):\s*['"]([A-Za-z][^'"]*)['"]''',
    );
    final localizedHelperCopy = RegExp(
      r'''\b(?:_AdminDetailRow|_StakeholderDocumentData|_MetricData|_Label|_tr)\(\s*['"]([A-Za-z][^'"]*)['"]''',
    );
    final filterOptionCopy = RegExp(
      r'''\b_StakeholderFilterOption\(\s*['"][^'"]+['"]\s*,\s*['"]([A-Za-z][^'"]*)['"]''',
    );
    final englishCatalog = UiStrings.translationCatalog.values
        .map((copy) => copy['en'])
        .whereType<String>()
        .map(_normalizeCopy)
        .toSet();
    final allowedCopy = <String>{
      'Kalsubai Farms',
      'wrkfarm',
      'MapTiler',
      'OpenStreetMap contributors',
      'Esri',
    };
    final violations = <String>[];

    for (final root in roots) {
      for (final file
          in root
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        for (final pattern in [
          configuredCopy,
          localizedHelperCopy,
          filterOptionCopy,
        ]) {
          for (final match in pattern.allMatches(source)) {
            final copy = match.group(1)!.trim();
            if (copy.contains(r'$') ||
                copy.length == 1 ||
                allowedCopy.contains(copy)) {
              continue;
            }
            if (!englishCatalog.contains(_normalizeCopy(copy))) {
              violations.add('${file.path}: $copy');
            }
          }
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  testWidgets('disease names and risk labels follow Hindi', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        locale: const Locale('hi'),
        home: _localizedDiseaseProbe(),
      ),
    );

    expect(find.text('धान ब्लास्ट रोग'), findsOneWidget);
    expect(find.text('जीवाणु पत्ती झुलसा'), findsOneWidget);
    expect(find.text('कम'), findsOneWidget);
    expect(find.text('उच्च'), findsOneWidget);
  });

  testWidgets('disease names and risk labels follow Marathi', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        locale: const Locale('mr'),
        home: _localizedDiseaseProbe(),
      ),
    );
    await tester.pump();

    expect(find.text('भात करपा'), findsOneWidget);
    expect(find.text('जिवाणूजन्य पान करपा'), findsOneWidget);
    expect(find.text('कमी'), findsOneWidget);
    expect(find.text('जास्त'), findsOneWidget);
  });
}

Widget _localizedDiseaseProbe() {
  return Builder(
    builder: (_) => Scaffold(
      body: Column(
        children: [
          Text(UiStrings.diseaseName('rice_blast')),
          Text(UiStrings.diseaseName('bacterial_leaf_blight')),
          Text(UiStrings.riskLevel('low')),
          Text(UiStrings.riskLevel('high')),
        ],
      ),
    ),
  );
}

Set<String> _placeholders(String value) {
  return RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}')
      .allMatches(value)
      .map((match) => match.group(1)!)
      .where((placeholder) => placeholder != 'plural')
      .toSet();
}

bool _sameSet(Set<String> a, Set<String> b) {
  return a.length == b.length && a.containsAll(b);
}

String _normalizeCopy(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
