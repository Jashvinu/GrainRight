import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260824195222_repair_daily_whatsapp_farm_monitoring.sql',
  ).readAsStringSync();
  final weatherAuthorizationMigration = File(
    'supabase/migrations/20260824195622_repair_farm_monitoring_weather_authorization.sql',
  ).readAsStringSync();
  final farmBoundsMigration = File(
    'supabase/migrations/20260824200155_backfill_farm_bounds_from_saved_geometry.sql',
  ).readAsStringSync();
  final dispatcher = File(
    'supabase/functions/whatsapp-notification-dispatch/index.ts',
  ).readAsStringSync();
  final weather = File(
    'supabase/functions/weather/index.ts',
  ).readAsStringSync();

  test(
    'daily WhatsApp health uses verified snapshots and never invents health',
    () {
      expect(migration, contains('run_daily_farmer_health_digest'));
      expect(migration, contains("condition_key := 'daily_healthy'"));
      expect(migration, contains("condition_key := 'daily_active_risk'"));
      expect(
        migration,
        contains("condition_key := 'daily_monitoring_pending'"),
      );
      expect(migration, contains("snapshot_date < target_date - 1"));
      expect(migration, contains("'0 1 * * *'"));
      expect(
        migration,
        contains('notifications_enabled is distinct from false'),
      );
    },
  );

  test(
    'dispatcher localizes daily facts and weather validates coordinates',
    () {
      expect(dispatcher, contains('daily_healthy'));
      expect(dispatcher, contains('daily_active_risk'));
      expect(dispatcher, contains('daily_monitoring_pending'));
      expect(weather, contains('latitude or longitude is out of range'));
      expect(weather, contains('isAuthorizedRequest'));
      expect(weather, contains('x-farm-monitoring-token'));
      expect(
        weatherAuthorizationMigration,
        contains('farmer_push_dispatch_control'),
      );
      expect(
        weatherAuthorizationMigration,
        contains('x-farm-monitoring-token'),
      );
      expect(farmBoundsMigration, contains('ensure_farm_bounds_from_geometry'));
      expect(farmBoundsMigration, contains('st_envelope(geometry)'));
    },
  );
}
