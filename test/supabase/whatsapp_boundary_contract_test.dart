import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final function = File(
    'supabase/functions/whatsapp-onboarding-boundary/index.ts',
  ).readAsStringSync();
  final screen = File(
    'lib/screens/whatsapp_farm_boundary_screen.dart',
  ).readAsStringSync();
  final map = File(
    'lib/widgets/satellite/satellite_map_view.dart',
  ).readAsStringSync();
  final tiles = File('lib/services/map_tile_provider.dart').readAsStringSync();

  test('boundary state reads the latest saved monitoring data', () {
    expect(function, contains('action === "load" || action === "refresh"'));
    expect(function, contains('monitoringSummary(supabase, farmId)'));
    expect(function, contains('farm_data_snapshots'));
    expect(function, contains('disease_scout_zones'));
    expect(function, contains('disease_risk_cells'));
    expect(function, contains('draftMonitoringSummary'));
    expect(
      function,
      contains('summary: draftMonitoringSummary(updatedDraft.farm)'),
    );
    expect(
      function,
      contains(
        'step: onboarding.flow_type === "existing_farmer_farm" ? "boundary_saved" : "review"',
      ),
    );
    expect(function, contains('.eq("step", "boundary")'));
    expect(function, contains('coordinates: [[...openRing, openRing[0]]]'));
  });

  test(
    'WhatsApp boundary screen exposes refresh and saved farm monitoring',
    () {
      expect(screen, contains('whatsapp_farm_refresh'));
      expect(screen, contains("'action': 'refresh'"));
      expect(screen, contains('whatsapp_saved_farm_map'));
      expect(screen, contains('_boundarySyncCard'));
      expect(screen, contains('FarmerFarmSummary.fromJson'));
      expect(screen, contains('_monitoringHotspotCard'));
      expect(screen, contains('_riskCircles(_monitoring!)'));
      expect(screen, contains('fitToFarmPolygonOnly: true'));
      expect(screen, contains('forceOnlineTiles: true'));
      expect(screen, contains('_farmCenterMarker(center)'));
      expect(screen, contains('Farm boundary map'));
      expect(
        screen,
        contains("_setupComplete = data['status'] == 'completed'"),
      );
      expect(screen, contains("body: {'token': _token, 'action': 'load'}"));
      expect(screen, contains('void initState()'));
      expect(screen, contains('_loadSavedFarm();'));
      expect(screen, contains('final hasBoundary'));
      expect(screen, contains('_friendlyLoadError(error)'));
      expect(screen, contains('Your farm monitor'));
      expect(screen, contains(".timeout(const Duration(seconds: 25))"));
      expect(map, contains('fitToFarmPolygonOnly'));
      expect(map, contains('final points = _cameraPoints()'));
      expect(tiles, contains('final bool forceOnline'));
      expect(tiles, contains('widget.forceOnline || _online'));
    },
  );
}
