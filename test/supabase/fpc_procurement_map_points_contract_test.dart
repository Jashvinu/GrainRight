import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260806191959_fpc_procurement_map_points.sql',
  ).readAsStringSync();
  final service = File(
    'lib/services/fpc_dashboard_service.dart',
  ).readAsStringSync();

  test('map points keep FPC authorization and return marker-only data', () {
    expect(migration, contains('fpc_procurement_map_points'));
    expect(migration, contains('security invoker'));
    expect(migration, contains('private.active_fpc_id()'));
    expect(migration, contains('private.can_manage_fpc(v_fpc_id)'));
    expect(migration, contains("'centroid_lat'"));
    expect(migration, contains("'centroid_lng'"));
    expect(migration, isNot(contains("'geometry'")));
    expect(migration, contains('to authenticated'));
    expect(service, contains('loadFarmMapPoints'));
    expect(service, contains('FpcFarmMapPoint.fromFarm'));
    expect(service, contains('if (_isUnavailable(error))'));
  });
}
