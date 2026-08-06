-- Trace one FPC-issued seed batch through farmer acceptance, field checks,
-- harvest compliance, exclusive procurement, and eventual farmer release.

create table public.fpc_crop_programs (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  code text not null,
  name text not null,
  crop text not null,
  variety text not null default '',
  season text not null,
  policy_version integer not null default 1 check (policy_version > 0),
  policy_rules jsonb not null default '{}'::jsonb
    check (jsonb_typeof(policy_rules) = 'object'),
  required_checkpoints jsonb not null default '[]'::jsonb
    check (jsonb_typeof(required_checkpoints) = 'array'),
  price_formula jsonb not null default '{}'::jsonb
    check (jsonb_typeof(price_formula) = 'object'),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'closed', 'cancelled')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (fpc_id, code)
);

create table public.fpc_seed_batches (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  program_id uuid not null references public.fpc_crop_programs(id) on delete restrict,
  batch_code text not null,
  seed_name text not null,
  crop text not null,
  variety text not null default '',
  supplier_name text not null default '',
  certification_number text not null default '',
  received_quantity_kg numeric(14,3) not null check (received_quantity_kg > 0),
  available_quantity_kg numeric(14,3) not null check (available_quantity_kg >= 0),
  manufactured_on date,
  expires_on date,
  evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(evidence) = 'object'),
  status text not null default 'active'
    check (status in ('active', 'depleted', 'quarantined', 'expired', 'cancelled')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (fpc_id, batch_code),
  check (available_quantity_kg <= received_quantity_kg),
  check (expires_on is null or manufactured_on is null or expires_on >= manufactured_on)
);

create table public.fpc_program_enrollments (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  program_id uuid not null references public.fpc_crop_programs(id) on delete restrict,
  farmer_link_id uuid not null references public.fpc_farmer_links(id) on delete restrict,
  farmer_user_id uuid not null references auth.users(id) on delete restrict,
  farmer_id text not null,
  farm_id uuid not null references public.farms(id) on delete restrict,
  crop text not null,
  variety text not null default '',
  policy_version integer not null check (policy_version > 0),
  policy_snapshot jsonb not null check (jsonb_typeof(policy_snapshot) = 'object'),
  checkpoint_snapshot jsonb not null check (jsonb_typeof(checkpoint_snapshot) = 'array'),
  price_formula_snapshot jsonb not null check (jsonb_typeof(price_formula_snapshot) = 'object'),
  status text not null default 'pending_farmer_acceptance'
    check (status in (
      'pending_farmer_acceptance', 'accepted', 'seed_issued', 'awaiting_seed_ack',
      'active', 'harvest_review', 'on_hold', 'compliant', 'exclusive_sale',
      'procured', 'released', 'completed', 'cancelled'
    )),
  terms_accepted_at timestamptz,
  terms_version integer,
  assigned_officer_id uuid references auth.users(id) on delete set null,
  release_reason text not null default '',
  released_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (program_id, farm_id)
);

create table public.fpc_seed_issues (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  enrollment_id uuid not null references public.fpc_program_enrollments(id) on delete restrict,
  seed_batch_id uuid not null references public.fpc_seed_batches(id) on delete restrict,
  quantity_kg numeric(14,3) not null check (quantity_kg > 0),
  status text not null default 'issued'
    check (status in ('issued', 'delivered', 'acknowledged', 'cancelled')),
  assigned_officer_id uuid references auth.users(id) on delete set null,
  scheduled_for timestamptz,
  delivered_at timestamptz,
  delivery_evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(delivery_evidence) = 'object'),
  acknowledged_by uuid references auth.users(id) on delete set null,
  acknowledged_at timestamptz,
  client_request_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (fpc_id, client_request_id)
);

create table public.fpc_program_checks (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  enrollment_id uuid not null references public.fpc_program_enrollments(id) on delete cascade,
  checkpoint_code text not null,
  checkpoint_name text not null,
  sequence integer not null check (sequence > 0),
  required boolean not null default true,
  farmer_status text not null default 'pending'
    check (farmer_status in ('pending', 'submitted', 'not_required')),
  farmer_evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(farmer_evidence) = 'object'),
  farmer_submitted_at timestamptz,
  officer_status text not null default 'pending'
    check (officer_status in ('pending', 'verified', 'failed', 'not_required')),
  officer_evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(officer_evidence) = 'object'),
  officer_verified_by uuid references auth.users(id) on delete set null,
  officer_verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (enrollment_id, checkpoint_code)
);

create table public.fpc_compliance_evaluations (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  enrollment_id uuid not null references public.fpc_program_enrollments(id) on delete restrict,
  inventory_item_id uuid not null references public.farmer_inventory_items(id) on delete restrict,
  analysis_job_id uuid references public.analysis_jobs(id) on delete restrict,
  attempt_no integer not null check (attempt_no between 0 and 4),
  status text not null
    check (status in ('pending_fpc_review', 'passed', 'failed', 'released')),
  reasons jsonb not null default '[]'::jsonb check (jsonb_typeof(reasons) = 'array'),
  automated_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(automated_snapshot) = 'object'),
  protected_floor_rate numeric(14,2) not null default 0
    check (protected_floor_rate >= 0),
  decision_due_at timestamptz not null,
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  decision_note text not null default '',
  created_at timestamptz not null default now(),
  unique (enrollment_id, attempt_no),
  unique (inventory_item_id)
);

alter table public.field_assignments
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null,
  add column if not exists crop_program_check_id uuid
    references public.fpc_program_checks(id) on delete set null,
  add column if not exists seed_issue_id uuid
    references public.fpc_seed_issues(id) on delete set null;

alter table public.field_visits
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null,
  add column if not exists crop_program_check_id uuid
    references public.fpc_program_checks(id) on delete set null,
  add column if not exists seed_issue_id uuid
    references public.fpc_seed_issues(id) on delete set null;

alter table public.harvest_plans
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null;

alter table public.analysis_jobs
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null;

alter table public.farmer_inventory_items
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null;

alter table public.marketplace_harvest_lots
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null,
  add column if not exists exclusive_fpc_id uuid
    references public.fpcs(id) on delete restrict;

alter table public.marketplace_listings
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null,
  add column if not exists exclusive_fpc_id uuid
    references public.fpcs(id) on delete restrict,
  add column if not exists sale_channel text not null default 'open_market'
    check (sale_channel in ('open_market', 'fpc_exclusive')),
  add column if not exists protected_floor_rate numeric(14,2)
    check (protected_floor_rate is null or protected_floor_rate >= 0);

alter table public.marketplace_orders
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null,
  add column if not exists protected_floor_rate numeric(14,2)
    check (protected_floor_rate is null or protected_floor_rate >= 0);

alter table public.fpc_procurement_records
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null;

alter table public.procurement_lots
  add column if not exists crop_program_enrollment_id uuid
    references public.fpc_program_enrollments(id) on delete set null;

create index fpc_crop_programs_fpc_status_idx
  on public.fpc_crop_programs(fpc_id, status, season);
create index fpc_seed_batches_program_status_idx
  on public.fpc_seed_batches(program_id, status, expires_on);
create index fpc_program_enrollments_fpc_status_idx
  on public.fpc_program_enrollments(fpc_id, status, updated_at desc);
create index fpc_program_enrollments_farmer_farm_idx
  on public.fpc_program_enrollments(farmer_user_id, farm_id, status);
create index fpc_program_enrollments_link_idx
  on public.fpc_program_enrollments(farmer_link_id);
create index fpc_seed_issues_enrollment_idx
  on public.fpc_seed_issues(enrollment_id, status, created_at desc);
create index fpc_seed_issues_batch_idx
  on public.fpc_seed_issues(seed_batch_id);
create index fpc_program_checks_enrollment_idx
  on public.fpc_program_checks(enrollment_id, sequence);
create index fpc_program_checks_officer_idx
  on public.fpc_program_checks(officer_verified_by)
  where officer_verified_by is not null;
create index fpc_compliance_enrollment_idx
  on public.fpc_compliance_evaluations(enrollment_id, attempt_no desc);
create index fpc_compliance_analysis_idx
  on public.fpc_compliance_evaluations(analysis_job_id)
  where analysis_job_id is not null;
create index field_assignments_program_idx
  on public.field_assignments(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;
create index field_assignments_program_check_idx
  on public.field_assignments(crop_program_check_id)
  where crop_program_check_id is not null;
create index field_assignments_seed_issue_idx
  on public.field_assignments(seed_issue_id)
  where seed_issue_id is not null;
create index field_visits_program_idx
  on public.field_visits(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;
create index field_visits_program_check_idx
  on public.field_visits(crop_program_check_id)
  where crop_program_check_id is not null;
create index field_visits_seed_issue_idx
  on public.field_visits(seed_issue_id)
  where seed_issue_id is not null;
create index harvest_plans_program_idx
  on public.harvest_plans(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;
create index analysis_jobs_program_idx
  on public.analysis_jobs(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;
create index farmer_inventory_program_idx
  on public.farmer_inventory_items(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;
create index marketplace_harvest_program_idx
  on public.marketplace_harvest_lots(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;
create index marketplace_harvest_exclusive_idx
  on public.marketplace_harvest_lots(exclusive_fpc_id, status)
  where exclusive_fpc_id is not null;
create index marketplace_listing_program_idx
  on public.marketplace_listings(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;
create index marketplace_listing_exclusive_idx
  on public.marketplace_listings(exclusive_fpc_id, status)
  where exclusive_fpc_id is not null;
create index marketplace_order_program_idx
  on public.marketplace_orders(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;
create index fpc_procurement_program_idx
  on public.fpc_procurement_records(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;
create index procurement_lot_program_idx
  on public.procurement_lots(crop_program_enrollment_id)
  where crop_program_enrollment_id is not null;

alter table public.fpc_crop_programs enable row level security;
alter table public.fpc_seed_batches enable row level security;
alter table public.fpc_program_enrollments enable row level security;
alter table public.fpc_seed_issues enable row level security;
alter table public.fpc_program_checks enable row level security;
alter table public.fpc_compliance_evaluations enable row level security;

grant select on
  public.fpc_crop_programs,
  public.fpc_seed_batches,
  public.fpc_program_enrollments,
  public.fpc_seed_issues,
  public.fpc_program_checks,
  public.fpc_compliance_evaluations
to authenticated;

grant select, insert, update on
  public.fpc_crop_programs,
  public.fpc_seed_batches,
  public.fpc_program_enrollments,
  public.fpc_seed_issues,
  public.fpc_program_checks,
  public.fpc_compliance_evaluations
to service_role;

create or replace function private.can_read_crop_program_enrollment(
  target_enrollment_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.fpc_program_enrollments enrollment
    where enrollment.id = target_enrollment_id
      and (
        enrollment.farmer_user_id = (select auth.uid())
        or private.can_manage_fpc(enrollment.fpc_id)
        or exists (
          select 1
          from public.field_assignments assignment
          where assignment.crop_program_enrollment_id = enrollment.id
            and assignment.officer_user_id = (select auth.uid())
            and assignment.status <> 'cancelled'
        )
      )
  );
$$;

create policy "crop programs related read"
on public.fpc_crop_programs for select to authenticated
using (
  private.can_manage_fpc(fpc_id)
  or exists (
    select 1 from public.fpc_program_enrollments enrollment
    where enrollment.program_id = fpc_crop_programs.id
      and private.can_read_crop_program_enrollment(enrollment.id)
  )
);

create policy "seed batches related read"
on public.fpc_seed_batches for select to authenticated
using (
  private.can_manage_fpc(fpc_id)
  or exists (
    select 1 from public.fpc_seed_issues issue
    where issue.seed_batch_id = fpc_seed_batches.id
      and private.can_read_crop_program_enrollment(issue.enrollment_id)
  )
);

create policy "program enrollments related read"
on public.fpc_program_enrollments for select to authenticated
using (private.can_read_crop_program_enrollment(id));

create policy "seed issues related read"
on public.fpc_seed_issues for select to authenticated
using (private.can_read_crop_program_enrollment(enrollment_id));

create policy "program checks related read"
on public.fpc_program_checks for select to authenticated
using (private.can_read_crop_program_enrollment(enrollment_id));

create policy "compliance evaluations related read"
on public.fpc_compliance_evaluations for select to authenticated
using (private.can_read_crop_program_enrollment(enrollment_id));

create or replace function private.crop_program_grade_rank(value text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case upper(coalesce(value, ''))
    when 'A' then 3
    when 'B' then 2
    when 'C' then 1
    else 0
  end;
$$;

create or replace function private.crop_program_floor_rate(
  target_enrollment_id uuid,
  grade text
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    0,
    coalesce(nullif(enrollment.price_formula_snapshot->>'reference_rate_per_kg', '')::numeric, 0)
      + coalesce(
          nullif(
            enrollment.price_formula_snapshot->'grade_adjustments'->>upper(coalesce(grade, '')),
            ''
          )::numeric,
          0
        )
  )
  from public.fpc_program_enrollments enrollment
  where enrollment.id = target_enrollment_id;
$$;

create or replace function private.refresh_crop_program_release(
  target_enrollment_id uuid
)
returns public.fpc_program_enrollments
language plpgsql
security definer
set search_path = ''
as $$
declare
  saved public.fpc_program_enrollments;
begin
  update public.fpc_program_enrollments enrollment
  set status = 'released',
      release_reason = 'FPC decision window expired after 7 days',
      released_at = now(),
      updated_at = now()
  where enrollment.id = target_enrollment_id
    and enrollment.status = 'harvest_review'
    and exists (
      select 1
      from public.fpc_compliance_evaluations evaluation
      where evaluation.enrollment_id = enrollment.id
        and evaluation.status = 'pending_fpc_review'
        and evaluation.decision_due_at <= now()
    );

  update public.fpc_compliance_evaluations evaluation
  set status = 'released',
      decided_at = now(),
      decision_note = 'Released automatically after the 7-day FPC decision window'
  where evaluation.enrollment_id = target_enrollment_id
    and evaluation.status = 'pending_fpc_review'
    and evaluation.decision_due_at <= now();

  select * into saved
  from public.fpc_program_enrollments
  where id = target_enrollment_id;
  return saved;
end;
$$;

create or replace function private.link_crop_program_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  linked_enrollment_id uuid;
begin
  if new.crop_program_enrollment_id is not null then
    return new;
  end if;

  if tg_table_name = 'analysis_jobs' then
    if nullif(new.farm_id, '') is null or new.operator_id is null then return new; end if;
    select enrollment.id into linked_enrollment_id
    from public.fpc_program_enrollments enrollment
    where enrollment.farm_id::text = new.farm_id
      and enrollment.farmer_user_id = new.operator_id
      and enrollment.status not in ('released', 'completed', 'cancelled')
    order by enrollment.created_at desc
    limit 1;
  else
    if new.farm_id is null or new.user_id is null then return new; end if;
    select enrollment.id into linked_enrollment_id
    from public.fpc_program_enrollments enrollment
    where enrollment.farm_id = new.farm_id
      and enrollment.farmer_user_id = new.user_id
      and enrollment.status not in ('released', 'completed', 'cancelled')
    order by enrollment.created_at desc
    limit 1;
  end if;

  new.crop_program_enrollment_id := linked_enrollment_id;
  return new;
end;
$$;

drop trigger if exists link_analysis_crop_program on public.analysis_jobs;
create trigger link_analysis_crop_program
before insert or update of farm_id, operator_id on public.analysis_jobs
for each row execute function private.link_crop_program_context();

drop trigger if exists link_inventory_crop_program on public.farmer_inventory_items;
create trigger link_inventory_crop_program
before insert or update of farm_id, user_id on public.farmer_inventory_items
for each row execute function private.link_crop_program_context();

create or replace function private.sync_crop_program_field_visit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment public.field_assignments;
  issue public.fpc_seed_issues;
  delivered_quantity numeric;
  outcome text;
begin
  if new.assignment_id is null then return new; end if;
  select * into assignment
  from public.field_assignments
  where id = new.assignment_id;
  if assignment.id is null then return new; end if;

  new.crop_program_enrollment_id := assignment.crop_program_enrollment_id;
  new.crop_program_check_id := assignment.crop_program_check_id;
  new.seed_issue_id := assignment.seed_issue_id;

  if assignment.seed_issue_id is not null then
    select * into issue
    from public.fpc_seed_issues
    where id = assignment.seed_issue_id;
    delivered_quantity := nullif(
      new.evidence->>'delivered_quantity_kg',
      ''
    )::numeric;
    if delivered_quantity is null or delivered_quantity <> issue.quantity_kg then
      raise exception 'Delivered seed quantity must match the issued quantity';
    end if;
    if cardinality(new.photos) = 0 then
      raise exception 'Seed delivery requires photo evidence';
    end if;
    if not (
      new.check_in ? 'latitude'
      and new.check_in ? 'longitude'
    ) then
      raise exception 'Seed delivery requires captured location';
    end if;

    update public.fpc_seed_issues
    set status = case when status = 'issued' then 'delivered' else status end,
        delivered_at = coalesce(delivered_at, now()),
        delivery_evidence = coalesce(new.evidence, '{}'::jsonb)
          || jsonb_build_object(
            'visit_id', new.id,
            'photos', new.photos,
            'check_in', new.check_in,
            'check_out', new.check_out
          ),
        updated_at = now()
    where id = assignment.seed_issue_id;

    update public.fpc_program_enrollments
    set status = 'awaiting_seed_ack', updated_at = now()
    where id = assignment.crop_program_enrollment_id
      and status = 'seed_issued';
  end if;

  if assignment.crop_program_check_id is not null then
    outcome := lower(coalesce(new.evidence->>'checkpoint_outcome', 'verified'));
    if outcome not in ('verified', 'failed') then
      raise exception 'Crop checkpoint result must be verified or failed';
    end if;
    if cardinality(new.photos) = 0 then
      raise exception 'Crop checkpoint requires photo evidence';
    end if;
    update public.fpc_program_checks
    set officer_status = case when outcome = 'failed' then 'failed' else 'verified' end,
        officer_evidence = coalesce(new.evidence, '{}'::jsonb)
          || jsonb_build_object(
            'visit_id', new.id,
            'photos', new.photos,
            'notes', new.notes,
            'recommendation', new.recommendation
          ),
        officer_verified_by = new.officer_user_id,
        officer_verified_at = now(),
        updated_at = now()
    where id = assignment.crop_program_check_id;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_crop_program_field_visit on public.field_visits;
create trigger sync_crop_program_field_visit
before insert or update on public.field_visits
for each row execute function private.sync_crop_program_field_visit();

create or replace function private.sync_farmer_program_status_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_check_id uuid;
begin
  select check_row.id into target_check_id
  from public.fpc_program_checks check_row
  join public.fpc_program_enrollments enrollment
    on enrollment.id = check_row.enrollment_id
  where enrollment.farm_id = new.farm_id
    and enrollment.status in ('active', 'on_hold')
    and check_row.farmer_status = 'pending'
    and (
      lower(check_row.checkpoint_code) = lower(replace(new.growth_stage, ' ', '_'))
      or lower(check_row.checkpoint_name) = lower(new.growth_stage)
    )
  order by check_row.sequence
  limit 1;

  if target_check_id is not null then
    update public.fpc_program_checks
    set farmer_status = 'submitted',
        farmer_evidence = jsonb_build_object(
          'farm_status_update_id', new.id,
          'growth_stage', new.growth_stage,
          'status_text', new.status_text,
          'days_after_sowing', new.days_after_sowing,
          'source', new.source
        ),
        farmer_submitted_at = new.created_at,
        updated_at = now()
    where id = target_check_id;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_farmer_program_status_update on public.farm_status_updates;
create trigger sync_farmer_program_status_update
after insert on public.farm_status_updates
for each row execute function private.sync_farmer_program_status_update();

create or replace function private.execute_crop_program_operation(
  operation_name text,
  payload jsonb,
  request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target_fpc_id uuid;
  existing_response jsonb;
  saved record;
  program_row public.fpc_crop_programs;
  batch_row public.fpc_seed_batches;
  enrollment_row public.fpc_program_enrollments;
  evaluation_row public.fpc_compliance_evaluations;
  link_row public.fpc_farmer_links;
  farm_row public.farms;
  issue_row public.fpc_seed_issues;
  checkpoint jsonb;
  checkpoint_id uuid;
  sequence_value integer := 0;
  decision text;
  result jsonb;
begin
  if actor_id is null then raise exception 'Login required'; end if;
  select membership.fpc_id into target_fpc_id
  from public.fpc_memberships membership
  join public.fpcs fpc on fpc.id = membership.fpc_id and fpc.status = 'active'
  where membership.user_id = actor_id
    and membership.role = 'fpc_admin'
    and membership.status = 'active'
  limit 1;
  if target_fpc_id is null then
    raise exception 'Active FPC Admin membership required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('crop-program:' || target_fpc_id::text || ':' || request_id::text, 0)
  );
  perform pg_advisory_xact_lock(
    hashtextextended('fpc-operation:' || target_fpc_id::text, 0)
  );

  select operation_request.response into existing_response
  from private.fpc_operation_requests operation_request
  where operation_request.fpc_id = target_fpc_id
    and operation_request.client_request_id = request_id;
  if existing_response is not null then return existing_response; end if;
  perform set_config('app.fpc_operation', '1', true);

  if operation_name = 'create_crop_program' then
    if coalesce(nullif(payload->>'name', ''), '') = ''
      or coalesce(nullif(payload->>'crop', ''), '') = ''
      or coalesce(nullif(payload->>'season', ''), '') = '' then
      raise exception 'Program name, crop and season are required';
    end if;
    insert into public.fpc_crop_programs(
      fpc_id, code, name, crop, variety, season, policy_rules,
      required_checkpoints, price_formula, created_by
    ) values (
      target_fpc_id,
      coalesce(nullif(payload->>'code', ''), 'PROGRAM-' || upper(substr(gen_random_uuid()::text, 1, 8))),
      payload->>'name',
      payload->>'crop',
      coalesce(payload->>'variety', ''),
      payload->>'season',
      coalesce(payload->'policy_rules', '{}'::jsonb),
      coalesce(payload->'required_checkpoints', '[]'::jsonb),
      coalesce(payload->'price_formula', '{}'::jsonb),
      actor_id
    ) returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'activate_crop_program' then
    update public.fpc_crop_programs
    set status = 'active', updated_at = now()
    where id = (payload->>'program_id')::uuid
      and fpc_id = target_fpc_id
      and status = 'draft'
    returning * into saved;
    if saved.id is null then raise exception 'Draft crop program not found'; end if;
    result := to_jsonb(saved);

  elsif operation_name = 'register_seed_batch' then
    select * into program_row
    from public.fpc_crop_programs
    where id = (payload->>'program_id')::uuid
      and fpc_id = target_fpc_id
      and status = 'active';
    if program_row.id is null then raise exception 'Active crop program not found'; end if;
    insert into public.fpc_seed_batches(
      fpc_id, program_id, batch_code, seed_name, crop, variety,
      supplier_name, certification_number, received_quantity_kg,
      available_quantity_kg, manufactured_on, expires_on, evidence, created_by
    ) values (
      target_fpc_id, program_row.id, payload->>'batch_code',
      coalesce(nullif(payload->>'seed_name', ''), program_row.crop || ' seed'),
      program_row.crop, program_row.variety,
      coalesce(payload->>'supplier_name', ''),
      coalesce(payload->>'certification_number', ''),
      (payload->>'received_quantity_kg')::numeric,
      (payload->>'received_quantity_kg')::numeric,
      nullif(payload->>'manufactured_on', '')::date,
      nullif(payload->>'expires_on', '')::date,
      coalesce(payload->'evidence', '{}'::jsonb),
      actor_id
    ) returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'enroll_farmer_program' then
    select * into program_row
    from public.fpc_crop_programs
    where id = (payload->>'program_id')::uuid
      and fpc_id = target_fpc_id
      and status = 'active';
    if program_row.id is null then raise exception 'Active crop program not found'; end if;

    select * into link_row
    from public.fpc_farmer_links
    where id = (payload->>'farmer_link_id')::uuid
      and fpc_id = target_fpc_id
      and status = 'active';
    if link_row.id is null then raise exception 'Active linked farmer not found'; end if;
    if nullif(link_row.farm_id, '') is null
      or link_row.farm_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'Linked farmer does not have a valid synced farm';
    end if;

    select * into farm_row
    from public.farms
    where id = link_row.farm_id::uuid
      and user_id is not null;
    if farm_row.id is null then raise exception 'Linked farmer farm is not available'; end if;
    if lower(coalesce(farm_row.crop, link_row.crop, '')) <> lower(program_row.crop) then
      raise exception 'Program crop does not match the linked farm crop';
    end if;
    if nullif(payload->>'assigned_officer_id', '') is null then
      raise exception 'A Field Officer is required for crop-program tracking';
    end if;
    if not exists (
      select 1 from public.fpc_memberships membership
      where membership.fpc_id = target_fpc_id
        and membership.user_id = (payload->>'assigned_officer_id')::uuid
        and membership.role = 'field_officer'
        and membership.status = 'active'
    ) then
      raise exception 'Assigned Field Officer is not active in this FPC';
    end if;

    insert into public.fpc_program_enrollments(
      fpc_id, program_id, farmer_link_id, farmer_user_id, farmer_id, farm_id,
      crop, variety, policy_version, policy_snapshot, checkpoint_snapshot,
      price_formula_snapshot, assigned_officer_id, created_by
    ) values (
      target_fpc_id, program_row.id, link_row.id, farm_row.user_id,
      link_row.farmer_id, farm_row.id, program_row.crop, program_row.variety,
      program_row.policy_version, program_row.policy_rules,
      program_row.required_checkpoints, program_row.price_formula,
      nullif(payload->>'assigned_officer_id', '')::uuid, actor_id
    ) returning * into enrollment_row;

    for checkpoint in
      select value from jsonb_array_elements(program_row.required_checkpoints)
    loop
      sequence_value := sequence_value + 1;
      insert into public.fpc_program_checks(
        fpc_id, enrollment_id, checkpoint_code, checkpoint_name, sequence, required
      ) values (
        target_fpc_id,
        enrollment_row.id,
        coalesce(nullif(checkpoint->>'code', ''), 'checkpoint_' || sequence_value),
        coalesce(nullif(checkpoint->>'name', ''), 'Checkpoint ' || sequence_value),
        sequence_value,
        coalesce((checkpoint->>'required')::boolean, true)
      ) returning id into checkpoint_id;

      if enrollment_row.assigned_officer_id is not null then
        insert into public.field_assignments(
          fpc_id, officer_user_id, assignment_type, farmer_id, farm_id,
          title, instructions, scheduled_for, created_by,
          crop_program_enrollment_id, crop_program_check_id
        ) values (
          target_fpc_id, enrollment_row.assigned_officer_id, 'crop_program_check',
          enrollment_row.farmer_id, enrollment_row.farm_id::text,
          'Verify ' || coalesce(nullif(checkpoint->>'name', ''), 'crop checkpoint'),
          coalesce(checkpoint->>'instructions', 'Verify the crop stage and attach field evidence.'),
          nullif(checkpoint->>'scheduled_for', '')::timestamptz,
          actor_id, enrollment_row.id, checkpoint_id
        );
      end if;
    end loop;
    result := to_jsonb(enrollment_row);

  elsif operation_name = 'issue_program_seed' then
    select * into enrollment_row
    from public.fpc_program_enrollments
    where id = (payload->>'enrollment_id')::uuid
      and fpc_id = target_fpc_id
      and status = 'accepted'
    for update;
    if enrollment_row.id is null then
      raise exception 'Farmer must accept the crop program before seed issue';
    end if;

    select * into batch_row
    from public.fpc_seed_batches
    where id = (payload->>'seed_batch_id')::uuid
      and fpc_id = target_fpc_id
      and program_id = enrollment_row.program_id
      and status = 'active'
    for update;
    if batch_row.id is null then raise exception 'Active program seed batch not found'; end if;
    if batch_row.expires_on is not null and batch_row.expires_on < current_date then
      raise exception 'Seed batch is expired';
    end if;
    if batch_row.available_quantity_kg < (payload->>'quantity_kg')::numeric then
      raise exception 'Insufficient seed quantity';
    end if;
    if enrollment_row.assigned_officer_id is null then
      raise exception 'A Field Officer is required for seed delivery';
    end if;

    insert into public.fpc_seed_issues(
      fpc_id, enrollment_id, seed_batch_id, quantity_kg, assigned_officer_id,
      scheduled_for, client_request_id, created_by
    ) values (
      target_fpc_id, enrollment_row.id, batch_row.id,
      (payload->>'quantity_kg')::numeric,
      enrollment_row.assigned_officer_id,
      nullif(payload->>'scheduled_for', '')::timestamptz,
      request_id, actor_id
    )
    returning * into issue_row;

    update public.fpc_seed_batches
    set available_quantity_kg = available_quantity_kg - issue_row.quantity_kg,
        status = case
          when available_quantity_kg - issue_row.quantity_kg = 0 then 'depleted'
          else status
        end,
        updated_at = now()
    where id = batch_row.id;

    insert into public.stock_ledger(
      fpc_id, movement_type, item_type, item_name, quantity_kg,
      reference_type, reference_id, reason, posted_by, client_request_id,
      expires_on
    ) values (
      target_fpc_id, 'issue', 'seed',
      batch_row.seed_name || ' / ' || batch_row.batch_code,
      -issue_row.quantity_kg, 'seed_issue', issue_row.id::text,
      'Seed issued under crop program', actor_id, request_id,
      batch_row.expires_on
    );

    update public.fpc_program_enrollments
    set status = 'seed_issued', updated_at = now()
    where id = enrollment_row.id;

    insert into public.field_assignments(
      fpc_id, officer_user_id, assignment_type, farmer_id, farm_id,
      title, instructions, scheduled_for, created_by,
      crop_program_enrollment_id, seed_issue_id
    ) values (
      target_fpc_id, issue_row.assigned_officer_id, 'seed_delivery',
      enrollment_row.farmer_id, enrollment_row.farm_id::text,
      'Deliver FPC seed batch ' || batch_row.batch_code,
      'Verify batch, quantity, farmer, farm, location and delivery evidence.',
      issue_row.scheduled_for, actor_id, enrollment_row.id, issue_row.id
    );
    result := to_jsonb(issue_row);

  elsif operation_name = 'review_program_compliance' then
    select * into evaluation_row
    from public.fpc_compliance_evaluations
    where id = (payload->>'evaluation_id')::uuid
      and fpc_id = target_fpc_id
    for update;
    if evaluation_row.id is null or evaluation_row.status <> 'pending_fpc_review' then
      raise exception 'Pending compliance review not found';
    end if;
    perform private.refresh_crop_program_release(evaluation_row.enrollment_id);
    select * into enrollment_row
    from public.fpc_program_enrollments
    where id = evaluation_row.enrollment_id
    for update;
    if enrollment_row.status = 'released' then
      raise exception 'Farmer was released after the FPC decision window expired';
    end if;

    decision := lower(payload->>'decision');
    if decision not in ('passed', 'failed') then
      raise exception 'Compliance decision must be passed or failed';
    end if;

    update public.fpc_compliance_evaluations
    set status = decision,
        decided_by = actor_id,
        decided_at = now(),
        decision_note = coalesce(payload->>'decision_note', '')
    where id = evaluation_row.id
    returning * into saved;

    if decision = 'passed' then
      update public.fpc_program_enrollments
      set status = 'compliant', updated_at = now()
      where id = evaluation_row.enrollment_id;
    elsif evaluation_row.attempt_no >= 4 then
      update public.fpc_program_enrollments
      set status = 'released',
          release_reason = 'Released after four unsuccessful harvest rechecks',
          released_at = now(),
          updated_at = now()
      where id = evaluation_row.enrollment_id;
      update public.fpc_compliance_evaluations
      set status = 'released'
      where id = evaluation_row.id
      returning * into saved;
    else
      update public.fpc_program_enrollments
      set status = 'on_hold', updated_at = now()
      where id = evaluation_row.enrollment_id;
    end if;
    result := to_jsonb(saved);

  elsif operation_name = 'release_program_enrollment' then
    update public.fpc_program_enrollments
    set status = 'released',
        release_reason = coalesce(nullif(payload->>'reason', ''), 'FPC final decline'),
        released_at = now(),
        updated_at = now()
    where id = (payload->>'enrollment_id')::uuid
      and fpc_id = target_fpc_id
      and status not in ('procured', 'completed', 'cancelled', 'released')
    returning * into saved;
    if saved.id is null then raise exception 'Releasable crop program enrollment not found'; end if;
    update public.fpc_compliance_evaluations
    set status = 'released',
        decided_by = actor_id,
        decided_at = now(),
        decision_note = coalesce(nullif(payload->>'reason', ''), 'FPC final decline')
    where enrollment_id = saved.id
      and status = 'pending_fpc_review';
    result := to_jsonb(saved);

  else
    raise exception 'Unsupported crop program operation: %', operation_name;
  end if;

  perform private.record_fpc_audit(
    target_fpc_id, operation_name, 'crop_program',
    coalesce(result->>'id', ''), '{}'::jsonb, result, request_id
  );
  insert into private.fpc_operation_requests(
    fpc_id, client_request_id, operation, response
  ) values (
    target_fpc_id, request_id, operation_name, result
  );
  return result;
end;
$$;

create or replace function public.fpc_execute_operation(
  operation_name text,
  payload jsonb default '{}'::jsonb,
  client_request_id uuid default gen_random_uuid()
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select case
    when operation_name in (
      'create_crop_program', 'activate_crop_program', 'register_seed_batch',
      'enroll_farmer_program', 'issue_program_seed',
      'review_program_compliance', 'release_program_enrollment'
    ) then private.execute_crop_program_operation(operation_name, payload, client_request_id)
    else private.execute_fpc_operation(operation_name, payload, client_request_id)
  end;
$$;

create or replace function public.farmer_accept_crop_program(
  p_enrollment_id uuid,
  p_terms_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  saved public.fpc_program_enrollments;
begin
  update public.fpc_program_enrollments
  set status = 'accepted',
      terms_accepted_at = now(),
      terms_version = p_terms_version,
      updated_at = now()
  where id = p_enrollment_id
    and farmer_user_id = (select auth.uid())
    and status = 'pending_farmer_acceptance'
    and policy_version = p_terms_version
  returning * into saved;
  if saved.id is null then raise exception 'Pending crop program terms not found'; end if;
  return to_jsonb(saved);
end;
$$;

create or replace function public.farmer_acknowledge_crop_program_seed(
  p_seed_issue_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  issue_row public.fpc_seed_issues;
  saved public.fpc_program_enrollments;
begin
  select issue.* into issue_row
  from public.fpc_seed_issues issue
  join public.fpc_program_enrollments enrollment
    on enrollment.id = issue.enrollment_id
  where issue.id = p_seed_issue_id
    and enrollment.farmer_user_id = (select auth.uid())
    and issue.status = 'delivered'
  for update of issue;
  if issue_row.id is null then raise exception 'Delivered seed issue not found'; end if;

  update public.fpc_seed_issues
  set status = 'acknowledged',
      acknowledged_by = (select auth.uid()),
      acknowledged_at = now(),
      updated_at = now()
  where id = issue_row.id;

  update public.fpc_program_enrollments
  set status = 'active', updated_at = now()
  where id = issue_row.enrollment_id
  returning * into saved;
  return to_jsonb(saved);
end;
$$;

create or replace function private.submit_crop_program_harvest(
  target_inventory_item_id uuid,
  actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  item public.farmer_inventory_items;
  enrollment public.fpc_program_enrollments;
  analysis public.analysis_jobs;
  existing public.fpc_compliance_evaluations;
  saved public.fpc_compliance_evaluations;
  reasons jsonb := '[]'::jsonb;
  attempt integer;
  minimum_grade text;
  max_moisture numeric;
  floor_rate numeric;
  missing_check_count integer;
begin
  select * into item
  from public.farmer_inventory_items
  where id = target_inventory_item_id
    and user_id = actor_user_id;
  if item.id is null then raise exception 'Farmer inventory item not found'; end if;
  if item.crop_program_enrollment_id is null then
    return jsonb_build_object('enrolled', false, 'status', 'open_market');
  end if;

  perform private.refresh_crop_program_release(item.crop_program_enrollment_id);
  select * into enrollment
  from public.fpc_program_enrollments
  where id = item.crop_program_enrollment_id
  for update;
  if enrollment.farmer_user_id <> actor_user_id then
    raise exception 'Crop program enrollment does not belong to this farmer';
  end if;
  if enrollment.status = 'released' then
    return jsonb_build_object(
      'enrolled', true, 'status', 'released',
      'enrollment_id', enrollment.id, 'sale_channel', 'open_market'
    );
  end if;
  if enrollment.status not in ('active', 'on_hold') then
    raise exception 'Crop program is not ready for harvest review';
  end if;

  select * into existing
  from public.fpc_compliance_evaluations
  where inventory_item_id = item.id;
  if existing.id is not null then return to_jsonb(existing) || jsonb_build_object('enrolled', true); end if;

  select * into analysis
  from public.analysis_jobs job
  where job.operator_id = actor_user_id
    and job.farm_id = item.farm_id::text
    and job.batch_id = coalesce(nullif(item.harvest_batch_id, ''), item.inventory_id)
  order by job.created_at desc
  limit 1;

  select count(*) into attempt
  from public.fpc_compliance_evaluations evaluation
  where evaluation.enrollment_id = enrollment.id;
  if attempt > 4 then raise exception 'The crop program has exhausted all harvest checks'; end if;

  if not exists (
    select 1 from public.fpc_seed_issues issue
    where issue.enrollment_id = enrollment.id
      and issue.status = 'acknowledged'
  ) then
    reasons := reasons || jsonb_build_array('FPC seed delivery is not acknowledged');
  end if;

  select count(*) into missing_check_count
  from public.fpc_program_checks check_row
  where check_row.enrollment_id = enrollment.id
    and check_row.required
    and (
      check_row.farmer_status <> 'submitted'
      or check_row.officer_status <> 'verified'
    );
  if missing_check_count > 0 then
    reasons := reasons || jsonb_build_array(
      missing_check_count || ' required crop checkpoints are not verified'
    );
  end if;

  if lower(item.crop) <> lower(enrollment.crop)
    or (
      enrollment.variety <> ''
      and lower(item.variety) <> lower(enrollment.variety)
    ) then
    reasons := reasons || jsonb_build_array('Harvest crop or variety does not match the FPC seed program');
  end if;

  if analysis.id is null then
    reasons := reasons || jsonb_build_array('Approved harvest grading evidence is required');
  else
    if analysis.status <> 'completed'
      or analysis.review_status not in ('not_required', 'approved') then
      reasons := reasons || jsonb_build_array('Harvest grading review is incomplete');
    end if;
    if analysis.reject_recommended
      or analysis.moisture_risk = 'CRITICAL'
      or coalesce((analysis.quality_metrics->>'mold_visible')::boolean, false) then
      reasons := reasons || jsonb_build_array('Harvest failed a mandatory food-safety rule');
    end if;
  end if;

  minimum_grade := coalesce(nullif(enrollment.policy_snapshot->>'minimum_grade', ''), 'C');
  max_moisture := coalesce(
    nullif(enrollment.policy_snapshot->>'max_moisture_percent', '')::numeric,
    14
  );
  if private.crop_program_grade_rank(coalesce(analysis.final_grade, item.grade))
      < private.crop_program_grade_rank(minimum_grade) then
    reasons := reasons || jsonb_build_array('Harvest grade is below the FPC program minimum');
  end if;
  if coalesce(analysis.moisture_percent, item.moisture_percent, 101) > max_moisture then
    reasons := reasons || jsonb_build_array('Harvest moisture is above the FPC program limit');
  end if;

  floor_rate := private.crop_program_floor_rate(
    enrollment.id,
    coalesce(analysis.final_grade, item.grade)
  );

  insert into public.fpc_compliance_evaluations(
    fpc_id, enrollment_id, inventory_item_id, analysis_job_id, attempt_no,
    status, reasons, automated_snapshot, protected_floor_rate, decision_due_at
  ) values (
    enrollment.fpc_id, enrollment.id, item.id, analysis.id, attempt,
    case when jsonb_array_length(reasons) = 0 then 'pending_fpc_review' else 'failed' end,
    reasons,
    jsonb_build_object(
      'program_policy_version', enrollment.policy_version,
      'program_policy', enrollment.policy_snapshot,
      'price_formula', enrollment.price_formula_snapshot,
      'inventory', to_jsonb(item),
      'analysis', case when analysis.id is null then null else to_jsonb(analysis) end,
      'evaluated_at', now()
    ),
    floor_rate,
    now() + interval '7 days'
  ) returning * into saved;

  if saved.status = 'pending_fpc_review' then
    update public.fpc_program_enrollments
    set status = 'harvest_review', updated_at = now()
    where id = enrollment.id;
  elsif saved.attempt_no >= 4 then
    update public.fpc_compliance_evaluations
    set status = 'released',
        decided_at = now(),
        decision_note = 'Released after four unsuccessful harvest rechecks'
    where id = saved.id
    returning * into saved;
    update public.fpc_program_enrollments
    set status = 'released',
        release_reason = 'Released after four unsuccessful harvest rechecks',
        released_at = now(),
        updated_at = now()
    where id = enrollment.id;
  else
    update public.fpc_program_enrollments
    set status = 'on_hold', updated_at = now()
    where id = enrollment.id;
  end if;
  return to_jsonb(saved) || jsonb_build_object('enrolled', true);
end;
$$;

create or replace function public.submit_crop_program_harvest(
  p_inventory_item_id uuid,
  p_actor_user_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.role()) <> 'service_role'
    and p_actor_user_id <> (select auth.uid()) then
    raise exception 'Actor does not match the authenticated user';
  end if;
  return private.submit_crop_program_harvest(p_inventory_item_id, p_actor_user_id);
end;
$$;

create or replace function public.farmer_crop_program_for_farm(p_farm_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  enrollment public.fpc_program_enrollments;
begin
  select * into enrollment
  from public.fpc_program_enrollments
  where farm_id = p_farm_id
    and farmer_user_id = (select auth.uid())
  order by created_at desc
  limit 1;
  if enrollment.id is null then return '{}'::jsonb; end if;
  enrollment := private.refresh_crop_program_release(enrollment.id);
  return jsonb_build_object(
    'enrollment', to_jsonb(enrollment),
    'program', (
      select to_jsonb(program) from public.fpc_crop_programs program
      where program.id = enrollment.program_id
    ),
    'fpc', (
      select jsonb_build_object('id', fpc.id, 'name', fpc.name)
      from public.fpcs fpc where fpc.id = enrollment.fpc_id
    ),
    'seed_issue', (
      select to_jsonb(issue) || jsonb_build_object(
        'seed_batch', (
          select to_jsonb(batch) from public.fpc_seed_batches batch
          where batch.id = issue.seed_batch_id
        )
      )
      from public.fpc_seed_issues issue
      where issue.enrollment_id = enrollment.id
      order by issue.created_at desc
      limit 1
    ),
    'checks', coalesce((
      select jsonb_agg(to_jsonb(check_row) order by check_row.sequence)
      from public.fpc_program_checks check_row
      where check_row.enrollment_id = enrollment.id
    ), '[]'::jsonb),
    'evaluations', coalesce((
      select jsonb_agg(to_jsonb(evaluation) order by evaluation.attempt_no desc)
      from public.fpc_compliance_evaluations evaluation
      where evaluation.enrollment_id = enrollment.id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function private.guard_crop_program_marketplace()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  enrollment public.fpc_program_enrollments;
  latest_evaluation public.fpc_compliance_evaluations;
  inventory_program_id uuid;
begin
  if tg_table_name = 'marketplace_harvest_lots' then
    if new.inventory_item_id is not null then
      select crop_program_enrollment_id into inventory_program_id
      from public.farmer_inventory_items where id = new.inventory_item_id;
      new.crop_program_enrollment_id := coalesce(new.crop_program_enrollment_id, inventory_program_id);
    end if;
  else
    if new.inventory_item_id is not null then
      select crop_program_enrollment_id into inventory_program_id
      from public.farmer_inventory_items where id = new.inventory_item_id;
      new.crop_program_enrollment_id := coalesce(new.crop_program_enrollment_id, inventory_program_id);
    end if;
  end if;

  if new.crop_program_enrollment_id is null then
    if tg_table_name = 'marketplace_listings' then
      new.exclusive_fpc_id := null;
      new.sale_channel := 'open_market';
      new.protected_floor_rate := null;
    else
      new.exclusive_fpc_id := null;
    end if;
    return new;
  end if;

  enrollment := private.refresh_crop_program_release(new.crop_program_enrollment_id);
  if enrollment.id is null then raise exception 'Crop program enrollment not found'; end if;

  if enrollment.status = 'released' then
    new.exclusive_fpc_id := null;
    if tg_table_name = 'marketplace_listings' then
      new.sale_channel := 'open_market';
      new.protected_floor_rate := null;
    end if;
    return new;
  end if;

  if enrollment.status not in ('compliant', 'exclusive_sale') then
    raise exception 'Harvest is blocked until the FPC crop policy is approved';
  end if;

  select * into latest_evaluation
  from public.fpc_compliance_evaluations
  where enrollment_id = enrollment.id
    and status = 'passed'
  order by attempt_no desc
  limit 1;
  if latest_evaluation.id is null then
    raise exception 'Passed crop compliance evaluation is required';
  end if;

  new.exclusive_fpc_id := enrollment.fpc_id;
  if tg_table_name = 'marketplace_listings' then
    new.sale_channel := 'fpc_exclusive';
    new.protected_floor_rate := latest_evaluation.protected_floor_rate;
  end if;
  update public.fpc_program_enrollments
  set status = 'exclusive_sale', updated_at = now()
  where id = enrollment.id and status = 'compliant';
  return new;
end;
$$;

drop trigger if exists guard_crop_program_harvest_lot on public.marketplace_harvest_lots;
create trigger guard_crop_program_harvest_lot
before insert or update on public.marketplace_harvest_lots
for each row execute function private.guard_crop_program_marketplace();

drop trigger if exists guard_crop_program_listing on public.marketplace_listings;
create trigger guard_crop_program_listing
before insert or update on public.marketplace_listings
for each row execute function private.guard_crop_program_marketplace();

create or replace function private.guard_crop_program_negotiation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  listing public.marketplace_listings;
begin
  select * into listing
  from public.marketplace_listings
  where id = new.listing_id;
  if listing.exclusive_fpc_id is null then return new; end if;
  if new.fpc_id is distinct from listing.exclusive_fpc_id then
    raise exception 'This harvest is exclusive to its sponsoring FPC';
  end if;
  if tg_table_name = 'marketplace_offer_events'
    and new.price_per_unit < coalesce(listing.protected_floor_rate, 0) then
    raise exception 'Offer is below the protected crop-program floor rate';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_crop_program_purchase_request
  on public.marketplace_purchase_requests;
create trigger guard_crop_program_purchase_request
before insert or update on public.marketplace_purchase_requests
for each row execute function private.guard_crop_program_negotiation();

drop trigger if exists guard_crop_program_offer
  on public.marketplace_offer_events;
create trigger guard_crop_program_offer
before insert or update on public.marketplace_offer_events
for each row execute function private.guard_crop_program_negotiation();

create or replace function private.guard_crop_program_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  listing public.marketplace_listings;
begin
  select * into listing
  from public.marketplace_listings
  where id = new.listing_id;
  if tg_op = 'INSERT' then
    new.crop_program_enrollment_id := listing.crop_program_enrollment_id;
    new.protected_floor_rate := listing.protected_floor_rate;
  end if;
  if new.crop_program_enrollment_id is not null
    and new.final_rate is not null
    and new.final_rate < coalesce(new.protected_floor_rate, 0) then
    raise exception 'Final rate is below the protected crop-program floor rate';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_crop_program_order on public.marketplace_orders;
create trigger guard_crop_program_order
before insert or update of final_rate on public.marketplace_orders
for each row execute function private.guard_crop_program_order();

create or replace function private.sync_crop_program_procurement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.crop_program_enrollment_id is null then return new; end if;
  if new.status in ('procurement_accepted', 'payment_pending', 'completed') then
    update public.fpc_program_enrollments
    set status = case when new.status = 'completed' then 'completed' else 'procured' end,
        updated_at = now()
    where id = new.crop_program_enrollment_id;
    if new.procurement_record_id is not null then
      update public.fpc_procurement_records
      set crop_program_enrollment_id = new.crop_program_enrollment_id
      where id = new.procurement_record_id;
    end if;
    if new.procurement_lot_id is not null then
      update public.procurement_lots
      set crop_program_enrollment_id = new.crop_program_enrollment_id
      where id = new.procurement_lot_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_crop_program_procurement on public.marketplace_orders;
create trigger sync_crop_program_procurement
after update of status on public.marketplace_orders
for each row execute function private.sync_crop_program_procurement();

drop policy if exists "marketplace harvest lots select own or listed"
  on public.marketplace_harvest_lots;
create policy "marketplace harvest lots select permitted"
on public.marketplace_harvest_lots for select to authenticated
using (
  owner_id = (select auth.uid())
  or (
    exclusive_fpc_id is null
    and status in ('listed', 'fpo_verified', 'ordered', 'dispatched', 'closed')
  )
  or (
    exclusive_fpc_id is not null
    and exists (
      select 1 from public.fpc_memberships membership
      where membership.fpc_id = marketplace_harvest_lots.exclusive_fpc_id
        and membership.user_id = (select auth.uid())
        and membership.role = 'fpc_admin'
        and membership.status = 'active'
    )
  )
);

drop policy if exists "marketplace listings browse or own"
  on public.marketplace_listings;
create policy "marketplace listings browse own or permitted"
on public.marketplace_listings for select to authenticated
using (
  coalesce(farmer_user_id, owner_id) = (select auth.uid())
  or (
    exclusive_fpc_id is null
    and status in (
      'active', 'listed', 'rfq', 'order_accepted', 'dispatch_due',
      'dispatched', 'closed'
    )
  )
  or (
    exclusive_fpc_id is not null
    and exists (
      select 1 from public.fpc_memberships membership
      where membership.fpc_id = marketplace_listings.exclusive_fpc_id
        and membership.user_id = (select auth.uid())
        and membership.role = 'fpc_admin'
        and membership.status = 'active'
    )
  )
);

revoke all on function private.can_read_crop_program_enrollment(uuid)
  from public, anon;
revoke all on function private.crop_program_floor_rate(uuid,text)
  from public, anon, authenticated;
revoke all on function private.refresh_crop_program_release(uuid)
  from public, anon, authenticated;
revoke all on function private.link_crop_program_context()
  from public, anon, authenticated;
revoke all on function private.sync_crop_program_field_visit()
  from public, anon, authenticated;
revoke all on function private.sync_farmer_program_status_update()
  from public, anon, authenticated;
revoke all on function private.execute_crop_program_operation(text,jsonb,uuid)
  from public, anon, authenticated;
revoke all on function private.submit_crop_program_harvest(uuid,uuid)
  from public, anon, authenticated;
revoke all on function private.guard_crop_program_marketplace()
  from public, anon, authenticated;
revoke all on function private.guard_crop_program_negotiation()
  from public, anon, authenticated;
revoke all on function private.guard_crop_program_order()
  from public, anon, authenticated;
revoke all on function private.sync_crop_program_procurement()
  from public, anon, authenticated;

revoke all on function public.fpc_execute_operation(text,jsonb,uuid)
  from public, anon;
revoke all on function public.farmer_accept_crop_program(uuid,integer)
  from public, anon;
revoke all on function public.farmer_acknowledge_crop_program_seed(uuid)
  from public, anon;
revoke all on function public.submit_crop_program_harvest(uuid,uuid)
  from public, anon;
revoke all on function public.farmer_crop_program_for_farm(uuid)
  from public, anon;

grant execute on function private.can_read_crop_program_enrollment(uuid)
  to authenticated;
grant execute on function public.fpc_execute_operation(text,jsonb,uuid)
  to authenticated;
grant execute on function public.farmer_accept_crop_program(uuid,integer)
  to authenticated;
grant execute on function public.farmer_acknowledge_crop_program_seed(uuid)
  to authenticated;
grant execute on function public.submit_crop_program_harvest(uuid,uuid)
  to authenticated, service_role;
grant execute on function public.farmer_crop_program_for_farm(uuid)
  to authenticated;
