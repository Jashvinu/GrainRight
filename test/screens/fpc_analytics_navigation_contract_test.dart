import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final navigation = File('lib/widgets/fpc_bottom_nav.dart').readAsStringSync();
  final routes = File('lib/app/routes/app_pages.dart').readAsStringSync();
  final service = File(
    'lib/services/fpc_operating_service.dart',
  ).readAsStringSync();
  final analytics = File(
    'lib/screens/fpc_analytics_screen.dart',
  ).readAsStringSync();

  test('FPC analytics is routed and placed immediately before profile', () {
    expect(routes, contains("name: '/fpo/analytics'"));
    expect(navigation, contains('FpcNavTab.analytics'));
    expect(
      navigation.indexOf("title: 'Analytics'"),
      lessThan(navigation.indexOf("title: 'FPC profile'")),
    );
  });

  test('Operating System navigation exposes a history-aware back action', () {
    expect(navigation, contains('current == FpcNavTab.operations'));
    expect(navigation, contains('Get.previousRoute.isNotEmpty'));
    expect(navigation, contains("Get.offNamed('/fpo')"));
  });

  test('analytics queries existing FPC-scoped operational sources by date', () {
    expect(service, contains('Future<FpcAnalyticsSnapshot> loadAnalytics'));
    expect(service, contains(".from('fpc_procurement_records')"));
    expect(service, contains(".from('sales_orders')"));
    expect(service, contains(".from('stock_ledger')"));
    expect(service, contains(".from('farmer_payment_ledger')"));
    expect(analytics, contains('showDateRangePicker'));
    expect(analytics, contains('FpcNavTab.analytics'));
  });
}
