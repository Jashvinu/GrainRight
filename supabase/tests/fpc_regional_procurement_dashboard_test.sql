begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(13);

insert into auth.users (id, aud, role, email)
values
  ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'cluster-admin@test.invalid');

insert into public.fpcs (id, name, status)
values
  ('20000000-0000-4000-8000-000000000001', 'Dashboard Test FPC', 'active'),
  ('20000000-0000-4000-8000-000000000002', 'Other Tenant FPC', 'active');

insert into public.fpc_memberships (fpc_id, user_id, role, status)
values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'fpc_admin',
  'active'
);

insert into public.fpc_operating_clusters (
  id,
  fpc_id,
  name,
  district,
  preferred_apmc_market,
  created_by
)
values
  (
    '30000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'North belt',
    'Nashik',
    'Nashik APMC',
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000001',
    'Empty belt',
    'Nashik',
    'Nashik APMC',
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '30000000-0000-4000-8000-000000000003',
    '20000000-0000-4000-8000-000000000002',
    'Other tenant belt',
    'Pune',
    'Pune APMC',
    '10000000-0000-4000-8000-000000000001'
  );

insert into public.fpc_farmer_links (
  id,
  fpc_id,
  farmer_id,
  farmer_name,
  farm_id,
  farm_name,
  village,
  crop,
  cluster_id,
  linked_by
)
values
  (
    '40000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'TEST-FARMER-1',
    'Cluster farmer',
    'TEST-FARM-1',
    'Cluster plot',
    'Nashik',
    'Pearl millet',
    '30000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '40000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000001',
    'TEST-FARMER-2',
    'Unassigned farmer',
    'TEST-FARM-2',
    'Unassigned plot',
    'Nashik',
    'Finger millet',
    null,
    '10000000-0000-4000-8000-000000000001'
  );

insert into public.harvest_plans (
  fpc_id,
  farmer_link_id,
  farm_id,
  crop,
  village,
  expected_harvest_date,
  expected_quantity_kg,
  expected_grade,
  readiness,
  status
)
values (
  '20000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  'TEST-FARM-1',
  'Pearl millet',
  'Nashik',
  current_date + 7,
  1250,
  'A',
  'ready',
  'planned'
);

insert into public.analysis_jobs (
  crop_type,
  status,
  final_grade,
  farmer_id,
  farm_id,
  review_status,
  actor_role,
  fpc_organization_id,
  source,
  completed_at
)
values
  (
    'Pearl millet',
    'completed',
    'B',
    'TEST-FARMER-1',
    'TEST-FARM-1',
    'approved',
    'fpc',
    '20000000-0000-4000-8000-000000000001',
    'test',
    now() - interval '2 hours'
  ),
  (
    'Pearl millet',
    'completed',
    'Premium',
    'TEST-FARMER-1',
    'TEST-FARM-1',
    'pending',
    'fpc',
    '20000000-0000-4000-8000-000000000001',
    'test',
    now() - interval '1 hour'
  );

insert into public.procurement_lots (
  fpc_id,
  batch_id,
  traceability_code,
  farmer_id,
  farm_id,
  crop,
  variety,
  bags,
  gross_weight_kg,
  net_weight_kg,
  grade,
  status
)
values (
  '20000000-0000-4000-8000-000000000001',
  'TEST-BATCH-1',
  'TEST-TRACE-1',
  'TEST-FARMER-1',
  'TEST-FARM-1',
  'Pearl millet',
  'Local',
  10,
  500,
  490,
  'A',
  'received'
);

set local role authenticated;
set local "request.jwt.claim.sub" =
  '10000000-0000-4000-8000-000000000001';

select is(
  (
    public.fpc_procurement_dashboard_snapshot(null)
      #>> '{summary,network_farms}'
  )::integer,
  2,
  'All clusters includes assigned and unassigned farms'
);

select is(
  (
    public.fpc_procurement_dashboard_snapshot(
      '30000000-0000-4000-8000-000000000001'
    ) #>> '{summary,network_farms}'
  )::integer,
  1,
  'Selected cluster includes only assigned farms'
);

select is(
  (
    public.fpc_procurement_dashboard_snapshot(
      '30000000-0000-4000-8000-000000000001'
    ) #>> '{summary,ready_farms}'
  )::integer,
  1,
  'Readiness is sourced from the active harvest plan'
);

select is(
  (
    public.fpc_procurement_dashboard_snapshot(
      '30000000-0000-4000-8000-000000000001'
    ) #>> '{summary,expected_procurement_kg}'
  )::numeric,
  1250::numeric,
  'Expected quantity is scoped to the selected cluster'
);

select is(
  (
    public.fpc_procurement_dashboard_snapshot(
      '30000000-0000-4000-8000-000000000001'
    ) #>> '{summary,open_lots}'
  )::integer,
  1,
  'Open procurement lots are counted'
);

select is(
  (
    public.fpc_procurement_dashboard_snapshot(
      '30000000-0000-4000-8000-000000000001'
    ) #>> '{summary,needs_review}'
  )::integer,
  1,
  'Pending grading review is counted'
);

select is(
  (
    public.fpc_procurement_dashboard_snapshot(
      '30000000-0000-4000-8000-000000000001'
    ) #>> '{summary,grade_mix,0,grade}'
  ),
  'Grade A',
  'Latest completed grading result drives normalized grade mix'
);

select is(
  (
    public.fpc_procurement_dashboard_snapshot(
      '30000000-0000-4000-8000-000000000002'
    ) #>> '{summary,network_farms}'
  )::integer,
  0,
  'Empty cluster returns zero totals'
);

select is(
  (
    select count(*)::integer
    from public.fpc_operating_clusters
    where fpc_id = '20000000-0000-4000-8000-000000000002'
  ),
  0,
  'RLS hides another FPC tenant clusters'
);

select throws_ok(
  $$
    select public.fpc_procurement_dashboard_snapshot(
      '30000000-0000-4000-8000-000000000003'
    )
  $$,
  '22023',
  null,
  'Invalid cross-FPC cluster selection is rejected'
);

select throws_ok(
  $$
    update public.fpc_farmer_links
    set cluster_id = '30000000-0000-4000-8000-000000000003'
    where id = '40000000-0000-4000-8000-000000000001'
  $$,
  '23503',
  null,
  'Composite foreign key rejects cross-FPC assignment'
);

select col_type_is(
  'public',
  'fpc_farmer_links',
  'cluster_id',
  'uuid',
  'One nullable UUID stores at most one cluster per farmer link'
);

select is(
  (
    public.fpc_procurement_dashboard_snapshot(null)
      #>> '{unassigned_farm_count}'
  )::integer,
  1,
  'All clusters reports unassigned farms explicitly'
);

select * from finish();

rollback;
