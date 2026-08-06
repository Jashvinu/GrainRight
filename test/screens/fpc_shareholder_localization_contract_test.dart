import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/screens/fpc_operating_system_screen.dart';

void main() {
  final targetFiles = [
    'lib/screens/fpc_operating_system_screen.dart',
    'lib/screens/fpc_workspace_screen.dart',
    'lib/screens/fpc_farmer_directory_screen.dart',
    'lib/screens/fpc_team_screen.dart',
    'lib/screens/field_officer_home_screen.dart',
    'lib/screens/fpo_home_screen.dart',
    'lib/widgets/farmer_crop_program_card.dart',
    'lib/screens/fpc_qr_hub_screen.dart',
    'lib/screens/platform_fpc_admin_panel.dart',
    'lib/widgets/fpc_module_workspace.dart',
    'lib/widgets/fpc_bottom_nav.dart',
    'lib/screens/stakeholder_home_screen.dart',
    'lib/screens/stakeholder_login_screen.dart',
    'lib/controllers/stakeholder_controller.dart',
    'lib/controllers/main_auth_controller.dart',
    'lib/models/stakeholder_plan.dart',
    'lib/services/stakeholder_service.dart',
    'lib/services/admin_service.dart',
  ];
  final sources = {
    for (final path in targetFiles) path: File(path).readAsStringSync(),
  };
  final catalogEnglish = UiStrings.translationCatalog.values
      .map((row) => row['en']?.trim().toLowerCase())
      .whereType<String>()
      .toSet();

  test('FPC and Shareholder scaffolds use the shared language selector', () {
    final fpcScaffold = sources['lib/widgets/fpc_bottom_nav.dart']!;
    final shareholderScaffold =
        sources['lib/screens/stakeholder_home_screen.dart']!;
    final fpcDashboard =
        sources['lib/screens/fpc_operating_system_screen.dart']!;

    expect(fpcScaffold, contains('LanguageSelectorButton('));
    expect(shareholderScaffold, contains('LanguageSelectorButton('));
    expect(fpcDashboard, isNot(contains('Icons.refresh_rounded')));
    expect(
      shareholderScaffold.substring(0, 4000),
      isNot(contains('Icons.refresh_rounded')),
    );
  });

  test('all literal fromEnglish calls have complete catalog entries', () {
    final pattern = RegExp(
      r'''UiStrings\.fromEnglish\(\s*['"]([^'"]+)['"]''',
      multiLine: true,
    );
    final failures = <String>[];

    for (final entry in sources.entries) {
      for (final match in pattern.allMatches(entry.value)) {
        final copy = match.group(1)!.trim().toLowerCase();
        if (!catalogEnglish.contains(copy)) {
          failures.add('${entry.key}: ${match.group(1)}');
        }
      }
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('Shareholder copy no longer exposes the Stakeholder role name', () {
    final failures = <String>[];
    for (final entry in UiStrings.translationCatalog.entries) {
      for (final language in const ['en', 'hi', 'mr']) {
        final copy = entry.value[language] ?? '';
        if (copy.toLowerCase().contains('stakeholder') ||
            copy.contains('हितधारक')) {
          failures.add('${entry.key}[$language]: $copy');
        }
      }
    }

    expect(failures, isEmpty, reason: failures.join('\n'));
    expect(
      UiStrings.translationCatalog['role_stakeholder']?['en'],
      'Shareholder',
    );
    expect(UiStrings.translationCatalog['role_stakeholder']?['hi'], 'शेयरधारक');
    expect(UiStrings.translationCatalog['role_stakeholder']?['mr'], 'भागधारक');
  });

  test('runtime Shareholder fallbacks have Hindi and Marathi copy', () {
    const runtimeCopy = [
      'Kalsubai Farms Shareholder Plan',
      'Kalsubai Farms Farmer Shareholder Plan',
      'Shareholder plan sync failed.',
      'Shareholder interest submission failed.',
      'Shareholder plan setup is not available yet. Try again later.',
      'Shareholder interest submission failed. Try again later.',
      'Shareholder document storage is not configured.',
      'Shareholder plan sync is not available yet. Try again later.',
      'Shareholder review failed.',
      'Shareholder admin sync failed.',
      'Shareholder application was not found.',
    ];
    final catalogByEnglish = {
      for (final row in UiStrings.translationCatalog.values) row['en']: row,
    };

    for (final copy in runtimeCopy) {
      final row = catalogByEnglish[copy];
      expect(row, isNotNull, reason: copy);
      expect(row?['hi'], isNotEmpty, reason: '$copy [hi]');
      expect(row?['mr'], isNotEmpty, reason: '$copy [mr]');
    }

    final runtimeSources = [
      sources['lib/controllers/stakeholder_controller.dart'],
      sources['lib/controllers/main_auth_controller.dart'],
      sources['lib/models/stakeholder_plan.dart'],
      sources['lib/services/stakeholder_service.dart'],
      sources['lib/services/admin_service.dart'],
    ].join('\n');
    for (final oldCopy in const [
      'Stakeholder plan sync failed.',
      'Stakeholder interest submission failed.',
      'Stakeholder document storage is not configured.',
      'Stakeholder review failed.',
      'Stakeholder admin sync failed.',
      'Stakeholder application was not found.',
    ]) {
      expect(runtimeSources, isNot(contains(oldCopy)));
    }
  });

  testWidgets('every FPC module definition localizes in Hindi and Marathi', (
    tester,
  ) async {
    final copy = <String>{
      'FPC Operating System',
      'FPC workspace',
      'Ready farms',
      'Expected kg',
      'Today kg',
      'Open lots',
      'Stock kg',
      'Pending payments',
      for (final definition in fpcModuleDefinitions) ...[
        definition.title,
        definition.itemLabel,
        definition.description,
      ],
    };

    for (final language in const ['hi', 'mr']) {
      Get.updateLocale(Locale(language));
      await tester.pumpWidget(
        GetMaterialApp(
          key: ValueKey('fpc-$language'),
          locale: Locale(language),
          home: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      final failures = [
        for (final value in copy)
          if (UiStrings.fromEnglish(value) == value) value,
      ];
      expect(
        failures,
        isEmpty,
        reason: '$language remained English: ${failures.join(', ')}',
      );
    }
  });

  testWidgets('seed request and Field Officer copy localizes end to end', (
    tester,
  ) async {
    const keys = [
      'seed_request_from_fpc',
      'seed_request_intro',
      'seed_request_submitted_message',
      'crop_program_confirm_seed',
      'fpc_seed_requests_title',
      'fpc_seed_pending_review',
      'fpc_approve_farmer_seed_request',
      'fpc_issue_requested_seed',
      'field_delivered_seed_quantity_kg',
      'field_add_delivery_photo',
      'field_capture_delivery_location',
    ];

    for (final language in const ['hi', 'mr']) {
      Get.updateLocale(Locale(language));
      await tester.pumpWidget(
        GetMaterialApp(
          key: ValueKey('seed-field-$language'),
          locale: Locale(language),
          home: const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      for (final key in keys) {
        final row = UiStrings.translationCatalog[key]!;
        expect(UiStrings.t(key), row[language], reason: '$key [$language]');
        expect(UiStrings.t(key), isNot(row['en']), reason: '$key [$language]');
      }
    }
  });
}
