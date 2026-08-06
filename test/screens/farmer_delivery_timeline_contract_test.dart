import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final farmerHome = File(
    'lib/screens/farmer_home_screen.dart',
  ).readAsStringSync();
  final farmerDelivery = File(
    'lib/widgets/farmer_delivery_page.dart',
  ).readAsStringSync();
  final fpcDirectory = File(
    'lib/screens/fpc_farmer_directory_screen.dart',
  ).readAsStringSync();
  final fpcService = File(
    'lib/services/fpc_operating_service.dart',
  ).readAsStringSync();
  final farmerService = File(
    'lib/services/farmer_delivery_timeline_service.dart',
  ).readAsStringSync();

  test('Farmer shell exposes Delivery without changing mobile bottom nav', () {
    expect(farmerHome, contains('static const _deliveryTabIndex'));
    expect(farmerHome, contains("case 'delivery':"));
    expect(farmerHome, contains('return const FarmerDeliveryPage();'));
    expect(farmerHome, contains('onOpenDelivery: _openDeliveryTab'));
    expect(farmerHome, contains("UiStrings.fromEnglish('Delivery')"));
    expect(
      File('lib/widgets/farmer_floating_bottom_nav.dart').readAsStringSync(),
      isNot(contains('FarmerBottomNavItem.delivery')),
    );
  });

  test('Farmer Delivery page shows timeline groups and acknowledgement', () {
    expect(farmerDelivery, contains('farmer-delivery-timeline-page'));
    expect(farmerDelivery, contains('loadForCurrentFarmer()'));
    expect(farmerDelivery, contains('acknowledgeSeed('));
    expect(farmerDelivery, contains('Seeds'));
    expect(farmerDelivery, contains('Procurement'));
    expect(farmerDelivery, contains('Payments'));
    expect(farmerDelivery, contains('Sales dispatch'));
  });

  test('FPC Farmer Directory loads selected farmer delivery timeline', () {
    expect(fpcDirectory, contains('_FarmerDeliveryTimelineSection'));
    expect(fpcDirectory, contains('Delivery and payments'));
    expect(fpcService, contains('loadFarmerDeliveryTimeline'));
    expect(fpcService, contains(".from('farmer_delivery_timeline')"));
    expect(fpcService, contains(".eq('farmer_id', id)"));
  });

  test('Farmer timeline service is remote Supabase only', () {
    expect(farmerService, contains(".from('farmer_delivery_timeline')"));
    expect(farmerService, contains('farmer_acknowledge_crop_program_seed'));
    expect(farmerService, isNot(contains('LocalAppDatabase')));
    expect(farmerService, isNot(contains('supabase start')));
  });
}
