import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final farmerSeeds = File(
    'lib/widgets/farmer_seeds_page.dart',
  ).readAsStringSync();
  final programCard = File(
    'lib/widgets/farmer_crop_program_card.dart',
  ).readAsStringSync();
  final farmerHome = File(
    'lib/screens/farmer_home_screen.dart',
  ).readAsStringSync();
  final fpcSeeds = File('lib/screens/fpc_seeds_screen.dart').readAsStringSync();
  final fpcShell = File('lib/widgets/fpc_bottom_nav.dart').readAsStringSync();
  final fpcModule = File(
    'lib/widgets/fpc_module_workspace.dart',
  ).readAsStringSync();
  final pushService = File(
    'lib/services/push_notification_service.dart',
  ).readAsStringSync();

  test('Farmer Seeds uses cards and excludes sown farms from buying', () {
    expect(farmerSeeds, contains('FarmerSeedFarmCard'));
    expect(farmerSeeds, isNot(contains('DropdownButtonFormField<int>')));
    expect(farmerHome, contains('_isSeedBuyingEligible'));
    expect(farmerHome, contains('sowingDate'));
    expect(programCard, contains('unit_price_paise'));
    expect(programCard, contains("UiStrings.f('seed_pay_securely'"));
  });

  test('Farmer Inventory renders paid delivered seeds separately', () {
    expect(farmerHome, contains('farmer_seed_inventory'));
    expect(farmerHome, contains('Purchased seeds'));
    expect(farmerHome, contains('_FarmerSeedInventoryCard'));
    expect(farmerHome, contains('Not for marketplace sale'));
  });

  test('FPC Seeds separates the requested operational views', () {
    for (final label in const [
      'Overview',
      'Requests',
      'Available Stock',
      'Programs',
      'Distribution',
      'Analyses',
    ]) {
      expect(fpcSeeds, contains("'$label'"));
    }
    expect('$fpcSeeds\n$fpcModule', contains('price_seed_batch'));
    expect('$fpcSeeds\n$fpcModule', contains('refund_seed_request'));
  });

  test('FPC shell provides realtime popup and persistent inbox', () {
    expect(fpcShell, contains('FpcNotificationRealtimeService'));
    expect(fpcShell, contains('fpc-notification-inbox'));
    expect(fpcShell, contains('showDialog'));
    expect(fpcShell, contains('markNotificationRead'));
  });

  test('Android push registers and refreshes FCM tokens', () {
    expect(pushService, contains('FirebaseMessaging.instance'));
    expect(pushService, contains('requestPermission'));
    expect(pushService, contains('getToken'));
    expect(pushService, contains('onTokenRefresh'));
    expect(pushService, contains('fpc_push_tokens'));
  });
}
