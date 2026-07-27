import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260719122428_harvest_three_region_field_grade_v2.sql',
  ).readAsStringSync();
  final zoneFunction = File(
    'supabase/functions/harvest-zone-plan/index.ts',
  ).readAsStringSync();
  final gradingFunction = File(
    'supabase/functions/grain-grade/index.ts',
  ).readAsStringSync();

  test('zone migration creates exactly three relative farm regions', () {
    expect(migration, contains('field-grade-v2-three-region'));
    expect(migration, contains('ST_ClusterKMeans(point, 3)'));
    expect(migration, contains('ST_VoronoiPolygons'));
    expect(migration, contains('ST_Intersection(part.geom, farm.geom)'));
    expect(migration, contains("when 1 then 'A'"));
    expect(migration, contains("when 2 then 'B'"));
    expect(migration, contains("else 'C'"));
    expect(migration, contains("'relative_spatial_rank'"));
    expect(migration, contains('if v_cell_count < 3 then'));
    expect(migration, contains("coverage_percent"));
    expect(migration, contains("to service_role"));
  });

  test('zone service scopes plans to the authenticated farm owner', () {
    expect(zoneFunction, contains('auth.getUser(token)'));
    expect(zoneFunction, contains('assertLinkedFarm'));
    expect(zoneFunction, contains('.eq("user_id", ownerUserId)'));
    expect(zoneFunction, contains('field-grade-v2-three-region'));
    expect(zoneFunction, contains('generate_harvest_zone_plan'));
    expect(zoneFunction, contains('farm_geometry: farmGeometry'));
  });

  test('grain grading accepts only a canonical saved zone trace', () {
    expect(gradingFunction, contains('harvest_zone_plan_id'));
    expect(gradingFunction, contains('harvest_zone_id'));
    expect(gradingFunction, contains('farm_harvest_zones'));
    expect(gradingFunction, contains('assertLinkedFarm'));
    expect(gradingFunction, contains('fieldGrade = String(zone.field_grade)'));
    expect(gradingFunction, contains('field_score'));
  });

  test('FPC grain grading requires an active admin membership', () {
    expect(gradingFunction, contains('.eq("role", "fpc_admin")'));
    expect(gradingFunction, contains('.eq("fpcs.status", "active")'));
    expect(gradingFunction, contains('Active FPC Admin membership required'));
  });
}
