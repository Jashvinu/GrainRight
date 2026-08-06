import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final farmerHome = File(
    'lib/screens/farmer_home_screen.dart',
  ).readAsStringSync();
  final migration = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .firstWhere(
        (file) => file.path.endsWith('_farmer_government_schemes.sql'),
      )
      .readAsStringSync();

  test('farmer profile omits synced count and last sync details', () {
    final settingsStart = farmerHome.indexOf('class _SettingsPage');
    final stakeholderStart = farmerHome.indexOf(
      'class _FarmerStakeholderShareCard',
      settingsStart,
    );
    final settingsSource = farmerHome.substring(
      settingsStart,
      stakeholderStart,
    );

    expect(
      settingsSource,
      isNot(contains("UiStrings.t('synced_farms_count')")),
    );
    expect(settingsSource, isNot(contains("UiStrings.t('last_sync')")));
    expect(settingsSource, isNot(contains("'synced_farm'")));
    expect(settingsSource, isNot(contains("'synced_farms'")));
  });

  test('schemes use a refreshable remote feed with a safe fallback', () {
    expect(farmerHome, contains('class SchemesPage extends StatefulWidget'));
    expect(farmerHome, contains(".from('government_schemes')"));
    expect(farmerHome, contains("eq('is_active', true)"));
    expect(farmerHome, contains('RefreshIndicator('));
    expect(farmerHome, contains('_fallbackSchemes()'));
    expect(migration, contains('create table public.government_schemes'));
    expect(migration, contains('enable row level security'));
    expect(migration, contains('for select'));
  });

  test('scheme cards open detail before scheme-specific application', () {
    expect(farmerHome, contains('class _SchemeDetailPage'));
    expect(farmerHome, contains('Get.to(() => _SchemeDetailPage('));
    expect(farmerHome, contains('scheme.applicationUrl'));
    expect(farmerHome, contains('LaunchMode.externalApplication'));
    expect(farmerHome, contains("UiStrings.t('scheme_apply_now')"));
  });
}
