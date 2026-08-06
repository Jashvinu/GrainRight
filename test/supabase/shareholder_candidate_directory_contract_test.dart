import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260729182210_shareholder_candidate_directory.sql',
  ).readAsStringSync();
  final mergedDirectoryMigration = File(
    'supabase/migrations/20260730020555_merge_shareholder_admin_directory.sql',
  ).readAsStringSync();

  test('candidate roster is distinct from legal shareholder allotments', () {
    expect(migration, contains('shareholder_candidate_roster'));
    expect(migration, contains("candidate_status <> 'allotted'"));
    expect(migration, contains('consent_verified_at is not null'));
    expect(migration, contains('kyc_verified_at is not null'));
    expect(migration, contains('payment_verified_at is not null'));
    expect(migration, contains('linked_application_id is not null'));
    expect(migration, contains("farmer_status = 'verified'"));
  });

  test('admin candidate directory keeps RLS and function grants explicit', () {
    expect(
      migration,
      contains(
        'alter table public.shareholder_candidate_roster enable row level security',
      ),
    );
    expect(migration, contains("public.has_server_role(array['admin'])"));
    expect(migration, contains('security invoker'));
    expect(migration, contains("message = 'admin_role_required'"));
    expect(
      migration,
      contains('revoke all on table public.shareholder_candidate_roster'),
    );
    expect(
      migration,
      contains('grant select on table public.shareholder_candidate_roster'),
    );
    expect(
      migration,
      contains(
        'revoke all on function public.admin_shareholder_candidate_directory',
      ),
    );
  });

  test('one proposed share remains fixed at one hundred rupees', () {
    expect(migration, contains('check (proposed_share_count = 1)'));
    expect(migration, contains('check (share_unit_value = 100.00)'));
    expect(migration, contains('proposed_total_amount'));
  });

  test('merged admin directory includes both protected source tables', () {
    expect(
      mergedDirectoryMigration,
      contains('public.admin_shareholder_directory'),
    );
    expect(
      mergedDirectoryMigration,
      contains('from public.shareholder_register shareholder'),
    );
    expect(
      mergedDirectoryMigration,
      contains('from public.shareholder_candidate_roster candidate'),
    );
    expect(mergedDirectoryMigration, contains('union all'));
    expect(
      mergedDirectoryMigration,
      contains('admins can read shareholder register'),
    );
    expect(mergedDirectoryMigration, contains('security invoker'));
    expect(
      mergedDirectoryMigration,
      contains("message = 'admin_role_required'"),
    );
  });

  test('no-KYC promotion is explicit without weakening legal gates', () {
    expect(mergedDirectoryMigration, contains('admin_promoted'));
    expect(mergedDirectoryMigration, contains('admin_override_without_kyc'));
    expect(mergedDirectoryMigration, contains('verified_shareholder_override'));
    expect(mergedDirectoryMigration, contains("'pendingKyc'"));
    expect(
      mergedDirectoryMigration,
      isNot(contains("candidate_status = 'allotted'")),
    );
    expect(
      mergedDirectoryMigration,
      isNot(contains("set farmer_status = 'verified'")),
    );
  });
}
