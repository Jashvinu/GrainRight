import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final navSource = File('lib/widgets/fpc_bottom_nav.dart').readAsStringSync();
  final hubSource = File(
    'lib/screens/fpc_qr_hub_screen.dart',
  ).readAsStringSync();
  final homeSource = File(
    'lib/screens/fpo_home_screen.dart',
  ).readAsStringSync();
  final dashboardServiceSource = File(
    'lib/services/fpc_dashboard_service.dart',
  ).readAsStringSync();
  final farmerHomeSource = File(
    'lib/screens/farmer_home_screen.dart',
  ).readAsStringSync();
  final farmerScanSource = File(
    'lib/screens/fpo_farmer_qr_scan_screen.dart',
  ).readAsStringSync();
  final receiverSource = File(
    'lib/screens/fpo_receiver_screen.dart',
  ).readAsStringSync();

  test('FPC mobile navigation moves QR scanning to one floating action', () {
    final mobileNavStart = navSource.indexOf('class FpcBottomNavBar');
    final mobileNavEnd = navSource.indexOf('void _go(', mobileNavStart);
    final mobileNav = navSource.substring(mobileNavStart, mobileNavEnd);

    expect(mobileNav, isNot(contains('FpcNavTab.farmerScan')));
    expect(navSource, contains("Get.toNamed('/fpo/qr')"));
    expect(navSource, contains("key: const Key('fpc-qr-floating-action')"));
    expect(navSource, contains("UiStrings.fromEnglish('Scan QR')"));
  });

  test('QR Hub keeps farmer and harvest scans visibly separate', () {
    expect(hubSource, contains("key: const Key('farmer-profile-qr-flow')"));
    expect(hubSource, contains("key: const Key('harvest-lot-qr-flow')"));
    expect(hubSource, contains("Get.toNamed('/fpo/scan-farmer')"));
    expect(hubSource, contains("Get.toNamed('/fpo/receiver')"));
    expect(hubSource, contains('Farmer profile QR'));
    expect(hubSource, contains('Harvest / lot QR'));

    expect(farmerScanSource, contains('FarmerProfileQrParser.parse(payload)'));
    expect(receiverSource, contains('FpcReceiveQrParser.parse(raw)'));
  });

  test('dashboard uses the regional procurement snapshot and workflow', () {
    expect(homeSource, contains('FpcDashboardService'));
    expect(homeSource, contains('FpcProcurementDashboard'));
    expect(homeSource, contains('_openClusterManager'));
    expect(homeSource, contains("'module': 'harvest_planning'"));
    expect(
      dashboardServiceSource,
      contains('fpc_procurement_dashboard_snapshot'),
    );
    expect(homeSource, isNot(contains('Open marketplace')));
  });

  test('Farmer Home and procurement dashboard share one health scorer', () {
    expect(farmerHomeSource, contains('FarmHealthScore.calculate('));
    expect(
      farmerHomeSource,
      contains("import '../models/farm_health_score.dart';"),
    );
  });
}
