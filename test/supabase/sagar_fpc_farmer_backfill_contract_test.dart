import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260806060619_backfill_sagar_fpc_farmer_links.sql',
  ).readAsStringSync();

  test('targets exactly one active Sagar FPC by email', () {
    expect(migration, contains("lower(trim(fpc.email)) = 'atharva@gmail.com'"));
    expect(migration, contains("and fpc.status = 'active'"));
    expect(migration, contains('active_match_count <> 1'));
    expect(
      migration,
      contains(
        'Expected exactly one active Sagar FPC with email atharva@gmail.com',
      ),
    );
  });

  test('backfills FPC links from Farmer profiles without owner rewrites', () {
    expect(migration, contains('from public.farmer_phone_profiles profile'));
    expect(migration, contains('left join lateral'));
    expect(migration, contains('from public.farms farm'));
    expect(migration, contains('where farm.user_id = profile.user_id'));
    expect(migration, contains('insert into public.fpc_farmer_links'));
    expect(migration, isNot(contains('update public.farmer_phone_profiles')));
    expect(migration, isNot(contains('update public.farms')));
    expect(migration, isNot(contains('update auth.users')));
    expect(migration, isNot(contains('insert into public.fpcs')));
  });

  test('supports directory-only links and skips blank farmer IDs', () {
    expect(
      migration,
      contains("nullif(trim(coalesce(profile.farmer_id, '')), '') is not null"),
    );
    expect(migration, contains("coalesce(source_profiles.farm_id::text, '')"));
    expect(
      migration,
      contains("'directoryOnly', source_profiles.farm_id is null"),
    );
    expect(migration, contains('skipped_missing_farmer_id_count'));
    expect(migration, contains("status = 'active'"));
  });

  test('is idempotent per FPC and Farmer identity', () {
    expect(migration, contains('row_number() over'));
    expect(migration, contains('partition by raw_source_profiles.farmer_id'));
    expect(migration, contains('source_rank = 1'));
    expect(migration, contains('skipped_duplicate_farmer_id_count'));
    expect(migration, contains('on conflict (fpc_id, farmer_id) do update'));
    expect(migration, contains('lastBackfilledAt'));
    expect(
      migration,
      contains('source_payload = public.fpc_farmer_links.source_payload ||'),
    );
    expect(migration, contains('Sagar FPC farmer link backfill complete'));
  });
}
