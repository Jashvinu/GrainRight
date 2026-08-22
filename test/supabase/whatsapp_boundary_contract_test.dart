import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final function = File(
    'supabase/functions/whatsapp-onboarding-boundary/index.ts',
  ).readAsStringSync();
  final screen = File(
    'lib/screens/whatsapp_farm_boundary_screen.dart',
  ).readAsStringSync();

  test('boundary state reads the latest saved monitoring data', () {
    expect(function, contains('action === "load" || action === "refresh"'));
    expect(function, contains('monitoringSummary(supabase, farmId)'));
    expect(function, contains('farm_data_snapshots'));
    expect(function, contains('disease_scout_zones'));
    expect(function, contains('disease_risk_cells'));
    expect(function, contains('.eq("step", "boundary")'));
  });

  test(
    'WhatsApp boundary screen exposes refresh and saved farm monitoring',
    () {
      expect(screen, contains('whatsapp_farm_refresh'));
      expect(screen, contains("'action': 'refresh'"));
      expect(screen, contains('whatsapp_saved_farm_map'));
      expect(screen, contains('FarmerFarmSummary.fromJson'));
      expect(screen, contains('_riskCircles'));
    },
  );
}
