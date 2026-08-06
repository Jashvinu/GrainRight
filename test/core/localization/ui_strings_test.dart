import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/widgets/brand_text.dart';
import 'package:kalsubai_farms/widgets/farmer_floating_bottom_nav.dart';

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

  testWidgets('requested farmer shell copy follows Marathi exactly', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        key: const ValueKey('requested-marathi-copy'),
        locale: const Locale('mr'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                Text(UiStrings.t('apmc_market')),
                Text(UiStrings.t('grain_grading')),
                Text(UiStrings.t('offline_maps')),
                Text(UiStrings.t('farm_history')),
                Text(UiStrings.t('inventory')),
                Text(UiStrings.t('profile')),
                Text(UiStrings.t('opt_south_plot')),
                Text(UiStrings.t('irrigation')),
                Text(UiStrings.t('irrigation_skip_today')),
                Text(UiStrings.t('monitor')),
                Text(UiStrings.f('mapped_spots_count', {'count': 2})),
                Text(UiStrings.t('heavy_rain')),
                Text(UiStrings.t('advice_skip_irrigation_today')),
                Text(UiStrings.t('humidity')),
                Text(UiStrings.f('temperature_celsius', {'value': 23})),
                Text(UiStrings.f('rain_today_value', {'value': 33.4})),
                Text(UiStrings.t('last_screen_label')),
                Text(UiStrings.t('ai_chat_confidence')),
                Text(UiStrings.t('images')),
                Text(UiStrings.t('refresh_scan')),
                Text(UiStrings.t('full_map_view')),
                Text(UiStrings.t('status')),
                Text(UiStrings.t('active_fpc_listings')),
                Text(UiStrings.t('no_active_fpc_listings')),
                Text(UiStrings.t('no_sellable_products')),
                Text(UiStrings.t('sale_plan')),
                Text(UiStrings.t('contact')),
                Text(UiStrings.apmcMarketName('Nashik APMC')),
                Text(UiStrings.apmcMarketName('Pune APMC')),
                Text(UiStrings.apmcMarketName('Rahuri APMC')),
                Text(UiStrings.apmcMarketName('Akole APMC')),
                Text(UiStrings.apmcMarketName('Sangamner APMC')),
                Text(UiStrings.t('update')),
              ],
            ),
          ),
        ),
      ),
    );

    for (final copy in const [
      'बाजारपेठ',
      'धान्य दर्जा तपासणी',
      'इंटरनेटशिवाय नकाशे',
      'शेताची नोंद',
      'साठा व्यवस्थापन',
      'स्वतःची माहिती',
      'दक्षिण शेत',
      'पाणी देणे',
      'आज पाणी देऊ नका',
      'निगराणी',
      '२ ठिकाणे तपासली',
      'मुसळधार पाऊस',
      'सल्ला : आज पाणी देऊ नका',
      'हवेतील आर्द्रता',
      '२३°से.',
      'आज ३३.४ मिमी पाऊस',
      'शेवटची तपासणी',
      'खात्री',
      'छायाचित्रे',
      'पुन्हा तपासा',
      'संपूर्ण नकाशा',
      'स्थिती',
      'सक्रिय FPC नोंदणी',
      'सक्रिय FPC नोंदणी उपलब्ध नाही',
      'विक्रीसाठी उत्पादन उपलब्ध नाही',
      'विक्री करा',
      'संपर्क साधा',
      'नाशिक बाजार समिती',
      'पुणे बाजार समिती',
      'राहुरी बाजार समिती',
      'अकोले बाजार समिती',
      'संगमनेर बाजार समिती',
      'अद्ययावत',
    ]) {
      expect(find.text(copy), findsOneWidget);
    }
  });

  testWidgets('requested FPO drawer copy follows Marathi exactly', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        key: const ValueKey('requested-fpo-drawer-copy'),
        locale: const Locale('mr'),
        home: Scaffold(
          body: Column(
            children: [
              Text(UiStrings.t('fpc_workspace_label')),
              Text(UiStrings.t('fpc_account_label')),
              Text(UiStrings.f('role_access', {'role': 'FPC'})),
              Text(UiStrings.t('dashboard')),
              Text(UiStrings.t('fpc_overview')),
              Text(UiStrings.t('farmer_verification')),
              Text(UiStrings.t('scan_verified_farmer_qr')),
              Text(UiStrings.t('apmc_market')),
              Text(UiStrings.t('buyer_listings')),
              Text(UiStrings.t('receive_center')),
              Text(UiStrings.t('received_lot_ledger')),
              Text(UiStrings.t('grain_grading')),
              Text(UiStrings.t('counter_grading_flow')),
              Text(UiStrings.t('review_queue')),
              Text(UiStrings.t('approve_grading_jobs')),
              Text(UiStrings.t('fpc_profile')),
              Text(UiStrings.t('account_role_details')),
              Text(UiStrings.t('settings')),
              Text(UiStrings.t('workspace_preferences')),
              Text(UiStrings.t('tasks')),
              Text(UiStrings.t('operational_checklist')),
              Text(UiStrings.t('help')),
              Text(UiStrings.t('support_and_sops')),
              Text(UiStrings.t('sign_out')),
            ],
          ),
        ),
      ),
    );

    for (final copy in const [
      'FPC कार्यक्षेत्र',
      'FPC खाते',
      'FPC प्रवेश',
      'डॅशबोर्ड',
      'FPC चे मुख्य डॅशबोर्ड',
      'शेतकरी पडताळणी',
      'पडताळणी केलेल्या शेतकऱ्याचा QR स्कॅन करा',
      'बाजारपेठ',
      'खरेदीदारांची यादी',
      'स्वीकृती केंद्र',
      'स्वीकृत लॉट नोंदवही',
      'धान्य दर्जा तपासणी',
      'धान्य दर्जा तपासणी प्रक्रिया',
      'तपासणी प्रलंबित यादी',
      'ग्रेडिंगची प्रलंबित कामे मंजूर करा',
      'FPC खाते माहिती',
      'खाते व भूमिकेची माहिती',
      'सेटिंग्ज',
      'कार्यक्षेत्र प्राधान्ये',
      'कार्ये',
      'कार्यांची तपासणी यादी',
      'मदत',
      'मदत व कार्यपद्धती',
      'बाहेर पडा',
    ]) {
      expect(find.text(copy), findsOneWidget);
    }
  });

  testWidgets('brand and bottom navigation follow Marathi and Hindi', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        key: const ValueKey('marathi-brand-navigation'),
        locale: const Locale('mr'),
        home: Scaffold(
          body: const BrandText(),
          bottomNavigationBar: FarmerFloatingBottomNav(
            selectedItem: FarmerBottomNavItem.home,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('कळसुबाई फार्म्स', findRichText: true), findsOneWidget);
    expect(find.text('माझे शेत'), findsOneWidget);
    expect(find.text('कृषी सहाय्यक'), findsOneWidget);

    Get.updateLocale(const Locale('hi'));
    await tester.pumpWidget(
      GetMaterialApp(
        key: const ValueKey('hindi-brand-navigation'),
        locale: const Locale('hi'),
        home: Scaffold(
          body: const BrandText(),
          bottomNavigationBar: FarmerFloatingBottomNav(
            selectedItem: FarmerBottomNavItem.home,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('कलसुबाई फार्म्स', findRichText: true), findsOneWidget);
    expect(find.text('मेरा खेत'), findsOneWidget);
    expect(find.text('कृषि सहायक'), findsOneWidget);
  });

  testWidgets('marketplace orders follow Marathi and Hindi', (tester) async {
    Get.updateLocale(const Locale('mr'));
    await tester.pumpWidget(
      GetMaterialApp(
        key: const ValueKey('marathi-marketplace-orders'),
        locale: const Locale('mr'),
        home: _marketplaceOrderProbe(),
      ),
    );

    for (final copy in const [
      'ऑर्डर',
      'आवक, दर्जा तपासणी, अंतिम दर, खरेदी आणि देयक यांचा मागोवा घ्या',
      'आवक प्रतीक्षेत',
      'अंतिम दर प्रलंबित',
      'खरेदी स्वीकारली',
      'किलो',
      'अंतिम दर निश्चित करा',
    ]) {
      expect(find.text(copy), findsOneWidget);
    }

    Get.updateLocale(const Locale('hi'));
    await tester.pumpWidget(
      GetMaterialApp(
        key: const ValueKey('hindi-marketplace-orders'),
        locale: const Locale('hi'),
        home: _marketplaceOrderProbe(),
      ),
    );
    await tester.pump();

    for (final copy in const [
      'ऑर्डर',
      'आवक, गुणवत्ता जांच, अंतिम भाव, खरीद और भुगतान पर नज़र रखें',
      'आवक की प्रतीक्षा',
      'अंतिम भाव बाकी',
      'खरीद स्वीकार की गई',
      'किलो',
      'अंतिम भाव की पुष्टि करें',
    ]) {
      expect(find.text(copy), findsOneWidget);
    }
  });
}

Widget _marketplaceOrderProbe() {
  return Builder(
    builder: (_) => Scaffold(
      body: Column(
        children: [
          Text(UiStrings.t('marketplace_orders')),
          Text(UiStrings.t('marketplace_track_order_help')),
          Text(UiStrings.marketplaceStatus('awaiting_arrival')),
          Text(UiStrings.marketplaceStatus('final_rate_pending')),
          Text(UiStrings.marketplaceStatus('procurement_accepted')),
          Text(UiStrings.marketplaceUnit('kg')),
          Text(UiStrings.t('marketplace_confirm_final_rate')),
        ],
      ),
    ),
  );
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
