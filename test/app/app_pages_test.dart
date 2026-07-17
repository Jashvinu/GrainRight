import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/app/routes/app_pages.dart';

void main() {
  test('active role and farmer-service routes are registered once', () {
    final names = AppPages.pages.map((page) => page.name).toList();

    expect(names.toSet(), hasLength(names.length));
    expect(
      names,
      containsAll(const [
        '/login',
        '/farmer/login',
        '/farmer/signup',
        '/farmer',
        '/farmer/ai-chat',
        '/farmer/ai-grading',
        '/farmer/harvest-qr',
        '/fpc/login',
        '/fpc/signup',
        '/fpo',
        '/fpo/scan-farmer',
        '/fpo/grading-review',
        '/fpo/grain-grading',
        '/fpo/marketplace',
        '/fpo/receiver',
        '/fpo/profile',
        '/fpo/settings',
        '/fpo/activity',
        '/fpo/help',
        '/stakeholder/login',
        '/stakeholder',
        '/stakeholder/plan',
        '/stakeholder/pan-kyc',
        '/stakeholder/land-record',
        '/stakeholder/bank-details',
        '/stakeholder/select-amount',
        '/stakeholder/status',
        '/stakeholder/profile',
        '/stakeholder/documents',
        '/stakeholder/help',
        '/admin/login',
        '/admin/signup',
        '/admin',
        '/diagnostics',
        '/offline-maps',
        '/satellite/login',
        '/satellite/signup',
        '/satellite/draw-polygon',
        '/satellite/shell',
      ]),
    );
  });
}
