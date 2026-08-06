import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260727114310_fpc_seed_to_sale_crop_program.sql',
  ).readAsStringSync();
  final marketplace = File(
    'supabase/functions/marketplace-listings/index.ts',
  ).readAsStringSync();
  final grants = File(
    'supabase/migrations/20260727114449_harden_fpc_crop_program_data_api_grants.sql',
  ).readAsStringSync();
  final identityGuard = File(
    'supabase/migrations/20260727120302_require_non_anonymous_crop_program_users.sql',
  ).readAsStringSync();
  final seedRequests = File(
    'supabase/migrations/20260730082220_fpc_farmer_seed_request_tracking.sql',
  ).readAsStringSync();
  final seedRequestHardening = File(
    'supabase/migrations/20260730082525_harden_fpc_seed_request_tracking.sql',
  ).readAsStringSync();
  final linkedFarmerAuthorization = File(
    'supabase/migrations/20260730093356_authorize_linked_farmer_seed_farms.sql',
  ).readAsStringSync();
  final farmerProgramDiscovery = File(
    'supabase/migrations/20260730100147_show_active_seed_programs_to_farmers.sql',
  ).readAsStringSync();
  final farmerSeedCatalog = File(
    'supabase/migrations/20260730103116_show_seed_catalog_across_farmer_farms.sql',
  ).readAsStringSync();

  test('migration persists the complete seed-to-sale chain', () {
    for (final table in const [
      'fpc_crop_programs',
      'fpc_seed_batches',
      'fpc_program_enrollments',
      'fpc_seed_issues',
      'fpc_program_checks',
      'fpc_compliance_evaluations',
    ]) {
      expect(migration, contains('create table public.$table'));
      expect(
        migration,
        contains('alter table public.$table enable row level security'),
      );
    }

    for (final operation in const [
      'create_crop_program',
      'activate_crop_program',
      'register_seed_batch',
      'enroll_farmer_program',
      'issue_program_seed',
      'review_program_compliance',
      'release_program_enrollment',
    ]) {
      expect(migration, contains("'$operation'"));
    }
  });

  test('policy gate preserves mandatory checks and release rules', () {
    expect(migration, contains('attempt_no between 0 and 4'));
    expect(migration, contains("now() + interval '7 days'"));
    expect(
      migration,
      contains('Released after four unsuccessful harvest rechecks'),
    );
    expect(migration, contains('Harvest failed a mandatory food-safety rule'));
    expect(migration, contains('required crop checkpoints are not verified'));
    expect(migration, contains('status = \'on_hold\''));
  });

  test('marketplace enforces sponsor exclusivity and protected floor', () {
    expect(
      migration,
      contains('This harvest is exclusive to its sponsoring FPC'),
    );
    expect(
      migration,
      contains('Final rate is below the protected crop-program floor rate'),
    );
    expect(marketplace, contains('crop_program_policy_blocked'));
    expect(marketplace, contains('crop_program_fpc_exclusive'));
    expect(marketplace, contains('crop_program_floor_rate_required'));
    expect(marketplace, contains('submit_crop_program_harvest'));
  });

  test('seed issue uses durable operation idempotency', () {
    expect(migration, contains('private.fpc_operation_requests'));
    expect(migration, contains('if existing_response is not null then return'));
    expect(migration, isNot(contains("interval '1 second'")));
  });

  test('authenticated Data API access is read-only', () {
    expect(grants, contains('from anon, authenticated'));
    expect(grants, contains('to authenticated'));
    expect(grants, contains('grant select on'));
    expect(
      grants,
      isNot(
        contains(
          'grant select, insert, update on\n  public.fpc_crop_programs,\n  public.fpc_seed_batches,\n  public.fpc_program_enrollments,\n  public.fpc_seed_issues,\n  public.fpc_program_checks,\n  public.fpc_compliance_evaluations\nto authenticated',
        ),
      ),
    );
  });

  test('anonymous Auth users cannot enroll in or read crop programs', () {
    expect(identityGuard, contains('guard_crop_program_farmer_identity'));
    expect(identityGuard, contains('user_account.is_anonymous'));
    expect(identityGuard, contains("auth.jwt()) ->> 'is_anonymous'"));
    expect(
      identityGuard,
      contains('before insert or update of farmer_user_id'),
    );
  });

  test('Farmer seed requests bridge FPC review to Field Officer delivery', () {
    expect(seedRequests, contains('create table public.fpc_seed_requests'));
    expect(
      seedRequests,
      contains(
        'alter table public.fpc_seed_requests enable row level security',
      ),
    );
    expect(seedRequests, contains('farmer_request_program_seed'));
    expect(seedRequests, contains("'approve_seed_request'"));
    expect(seedRequests, contains("'decline_seed_request'"));
    expect(migration, contains("'seed_delivery'"));
    expect(seedRequests, contains('sync_seed_request_delivery_status'));
    expect(seedRequests, contains('fpc_workspace_dashboard_snapshot'));
    expect(seedRequests, contains('farmer_user_id = (select auth.uid())'));
    expect(seedRequestHardening, contains("auth.jwt()) ->> 'is_anonymous'"));
    expect(seedRequestHardening, contains('security invoker'));
    expect(seedRequestHardening, contains('fpc_seed_requests_farm_id_idx'));
    expect(
      seedRequests,
      contains('revoke insert, update, delete on public.fpc_seed_requests'),
    );
  });

  test('linked Farmer identities can use their existing farm in seed flows', () {
    expect(
      linkedFarmerAuthorization,
      contains('private.farmer_can_access_farm'),
    );
    expect(linkedFarmerAuthorization, contains('farm.user_id = actor_user_id'));
    expect(
      linkedFarmerAuthorization,
      contains(
        'regexp_replace(\n                      coalesce(current_profile.phone',
      ),
    );
    expect(
      linkedFarmerAuthorization,
      contains('current_profile.farmer_id = owner_profile.farmer_id'),
    );
    expect(linkedFarmerAuthorization, contains('pg_get_functiondef'));
    expect(linkedFarmerAuthorization, contains('private.request_program_seed'));
    expect(
      linkedFarmerAuthorization,
      contains('public.farmer_crop_program_for_farm'),
    );
    expect(
      linkedFarmerAuthorization,
      contains('private.execute_seed_request_operation'),
    );
    expect(
      linkedFarmerAuthorization,
      contains(
        'private.farmer_can_access_farm(farm.id, request_row.farmer_user_id)',
      ),
    );
    expect(
      linkedFarmerAuthorization,
      contains(
        'revoke all on function private.farmer_can_access_farm(uuid, uuid)',
      ),
    );
  });

  test(
    'matching in-stock programs are discoverable before the first FPC link',
    () {
      expect(
        farmerProgramDiscovery,
        contains('private.fpc_seed_crop_key(program.crop)'),
      );
      expect(
        farmerProgramDiscovery,
        contains("'available_seed_kg', seed_stock.available_seed_kg"),
      );
      expect(farmerProgramDiscovery, contains("'request_allowed'"));
      expect(
        farmerProgramDiscovery,
        contains('private.ensure_seed_request_farmer_link'),
      );
      expect(
        farmerProgramDiscovery,
        contains("'source', 'farmer_seed_request'"),
      );
      expect(farmerProgramDiscovery, contains('request_row.farmer_user_id'));
      expect(farmerProgramDiscovery, contains("link_row.status <> 'active'"));
    },
  );

  test('Farmer catalogue stays visible across selected farm crops', () {
    expect(farmerSeedCatalog, contains("'farm_matches_crop'"));
    expect(farmerSeedCatalog, contains("'request_allowed'"));
    expect(farmerSeedCatalog, contains('old_crop_filter'));
    expect(
      farmerSeedCatalog,
      contains(
        "where program.status = 'active'\n"
        '        and seed_stock.available_seed_kg > 0',
      ),
    );
  });
}
