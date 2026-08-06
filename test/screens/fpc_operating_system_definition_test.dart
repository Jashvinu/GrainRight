import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/screens/fpc_operating_system_screen.dart';

void main() {
  test('operating system exposes every blueprint module', () {
    final keys = fpcModuleDefinitions.map((module) => module.key).toSet();

    expect(fpcModuleDefinitions, hasLength(16));
    expect(
      keys,
      containsAll({
        'farmer_network',
        'crop_programs',
        'farm_monitoring',
        'harvest_planning',
        'procurement',
        'collection_center',
        'quality',
        'warehouse',
        'production',
        'packaging',
        'inventory',
        'sales',
        'logistics',
        'farmer_payments',
        'reports',
        'ai_insights',
      }),
    );
  });
}
