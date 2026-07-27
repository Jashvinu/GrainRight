import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final completeMigration = File(
    'supabase/migrations/20260718231718_complete_fpc_operating_backend.sql',
  );
  final farmHardening = File(
    'supabase/migrations/20260718232238_harden_farms_tenant_access.sql',
  );
  final fieldHardening = File(
    'supabase/migrations/20260718233803_harden_fpc_policies_and_indexes.sql',
  );

  test('complete FPC backend keeps every transactional operation', () {
    final sql = completeMigration.readAsStringSync();
    const operations = <String>[
      'create_harvest_plan',
      'create_collection_center',
      'create_procurement_schedule',
      'transition_procurement_schedule',
      'create_vehicle_assignment',
      'set_farmer_status',
      'approve_quality',
      'create_warehouse',
      'create_warehouse_location',
      'post_stock_movement',
      'transfer_stock',
      'create_production_run',
      'start_production',
      'complete_production',
      'create_packaging_batch',
      'create_buyer',
      'create_sales_order',
      'cancel_sales_order',
      'invoice_sales_order',
      'cancel_invoiced_order',
      'dispatch_sales_order',
      'deliver_dispatch',
      'cancel_dispatch',
      'transition_farmer_payment',
      'correct_farmer_payment',
      'record_sales_payment',
      'reverse_sales_payment',
      'generate_ai_insights',
      'record_report_export',
      'create_notification',
    ];

    for (final operation in operations) {
      expect(sql, contains("operation_name = '$operation'"));
    }
  });

  test('packaging balance excludes production input consumption', () {
    final sql = completeMigration.readAsStringSync();
    expect(
      sql,
      contains(
        "s.reference_id=run_row.id::text and s.item_type='work_in_progress'",
      ),
    );
  });

  test('farm and Field Officer scope remain hardened', () {
    final farmSql = farmHardening.readAsStringSync();
    final fieldSql = fieldHardening.readAsStringSync();

    expect(farmSql, contains('Allow public read access to farms'));
    expect(farmSql, contains('revoke all on table public.farms from anon'));
    expect(fieldSql, contains('guard_field_assignment_update'));
    expect(
      fieldSql,
      contains('Field Officers can update only assignment status'),
    );
    expect(fieldSql, contains('Assignment version conflict'));
  });
}
