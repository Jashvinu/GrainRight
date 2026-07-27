-- Complete the tenant boundary and transactional operating workflows.

create table if not exists public.fpc_report_exports (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  report_type text not null,
  format text not null check (format in ('pdf', 'xlsx')),
  parameters jsonb not null default '{}'::jsonb,
  file_name text not null,
  storage_path text not null default '',
  row_count integer not null default 0 check (row_count >= 0),
  generated_by uuid not null references auth.users(id) on delete restrict,
  generated_at timestamptz not null default now()
);

create table if not exists public.sales_payment_ledger (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  sales_order_id uuid not null references public.sales_orders(id) on delete restrict,
  amount numeric(14,2) not null check (amount <> 0),
  payment_mode text not null check (payment_mode in ('upi', 'bank_transfer', 'cash', 'cheque')),
  reference text not null,
  proof_path text not null default '',
  entry_type text not null default 'receipt' check (entry_type in ('receipt', 'reversal')),
  reversal_of uuid references public.sales_payment_ledger(id) on delete restrict,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  recorded_at timestamptz not null default now()
);

create table if not exists public.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  sales_order_id uuid not null references public.sales_orders(id) on delete restrict,
  packaging_batch_id uuid not null references public.packaging_batches(id) on delete restrict,
  quantity_kg numeric(14,3) not null check (quantity_kg > 0),
  allocation_method text not null check (allocation_method in ('fifo', 'fefo', 'manual')),
  status text not null default 'reserved' check (status in ('reserved', 'fulfilled', 'released')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sales_credit_notes (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  sales_order_id uuid not null references public.sales_orders(id) on delete restrict,
  credit_note_number text not null,
  original_invoice_number text not null,
  reason text not null,
  amount numeric(14,2) not null check (amount > 0),
  immutable_snapshot jsonb not null,
  issued_by uuid not null references auth.users(id) on delete restrict,
  issued_at timestamptz not null default now(),
  unique(fpc_id, credit_note_number),
  unique(sales_order_id)
);

create table if not exists public.platform_report_exports (
  id uuid primary key default gen_random_uuid(),
  report_type text not null,
  format text not null check (format in ('pdf','xlsx')),
  fpc_filter uuid references public.fpcs(id) on delete set null,
  parameters jsonb not null default '{}'::jsonb,
  file_name text not null,
  row_count integer not null default 0 check (row_count>=0),
  generated_by uuid not null references auth.users(id) on delete restrict,
  generated_at timestamptz not null default now()
);

create table if not exists public.fpc_process_templates (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid references public.fpcs(id) on delete cascade,
  code text not null,
  name text not null,
  stages jsonb not null check (jsonb_typeof(stages)='array'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists fpc_process_templates_global_code_idx
  on public.fpc_process_templates(code) where fpc_id is null;
create unique index if not exists fpc_process_templates_tenant_code_idx
  on public.fpc_process_templates(fpc_id,code) where fpc_id is not null;

insert into public.fpc_process_templates(fpc_id,code,name,stages)
values
  (null,'millet','Millet processing','["Cleaning","Destoning","Dehusking","Grading","Sorting","Packaging"]'::jsonb),
  (null,'rice','Rice processing','["Cleaning","Destoning","Dehusking","Whitening","Polishing","Grading","Packaging"]'::jsonb)
on conflict do nothing;

alter table public.stock_ledger
  add column if not exists client_request_id uuid,
  add column if not exists expires_on date,
  add column if not exists reversal_of uuid references public.stock_ledger(id) on delete restrict;

alter table public.dispatches
  add column if not exists client_request_id uuid;

alter table public.field_visits
  add column if not exists evidence jsonb not null default '{}'::jsonb;

alter table public.procurement_lots
  add column if not exists procurement_schedule_id uuid
    references public.procurement_schedules(id) on delete set null;

alter table public.harvest_plans
  add column if not exists status text not null default 'planned';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname='harvest_plans_status_check'
      and conrelid='public.harvest_plans'::regclass
  ) then
    alter table public.harvest_plans add constraint harvest_plans_status_check
      check (status in ('planned','scheduled','in_collection','quality_review',
        'lot_created','warehoused','completed','cancelled'));
  end if;
end $$;

alter table public.farmer_payment_ledger
  add column if not exists entry_type text not null default 'payment',
  add column if not exists supersedes uuid references public.farmer_payment_ledger(id) on delete restrict;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'farmer_payment_entry_type_check'
      and conrelid = 'public.farmer_payment_ledger'::regclass
  ) then
    alter table public.farmer_payment_ledger
      add constraint farmer_payment_entry_type_check
      check (entry_type in ('payment', 'reversal', 'replacement'));
  end if;
end $$;

alter table public.production_runs
  add column if not exists recovery_percent numeric(7,3)
  generated always as (
    case when input_kg > 0 then round((output_kg / input_kg * 100)::numeric, 3) else 0 end
  ) stored;

alter table public.fpc_report_exports enable row level security;
alter table public.sales_payment_ledger enable row level security;
alter table public.stock_reservations enable row level security;
alter table public.sales_credit_notes enable row level security;
alter table public.platform_report_exports enable row level security;
alter table public.fpc_process_templates enable row level security;

grant select on public.fpc_report_exports to authenticated;
grant select on public.sales_payment_ledger to authenticated;
grant select on public.stock_reservations to authenticated;
grant select on public.sales_credit_notes to authenticated;
grant select, insert on public.platform_report_exports to authenticated;
grant select on public.fpc_process_templates to authenticated;

create index if not exists fpc_report_exports_fpc_generated_idx
  on public.fpc_report_exports(fpc_id, generated_at desc);
create index if not exists sales_payment_ledger_order_idx
  on public.sales_payment_ledger(fpc_id, sales_order_id, recorded_at desc);
create index if not exists stock_reservations_order_idx
  on public.stock_reservations(fpc_id, sales_order_id, status);
create index if not exists stock_reservations_batch_idx
  on public.stock_reservations(packaging_batch_id, status);
create index if not exists sales_credit_notes_fpc_issued_idx
  on public.sales_credit_notes(fpc_id, issued_at desc);
create index if not exists platform_report_exports_generated_idx
  on public.platform_report_exports(generated_at desc);
create unique index if not exists stock_ledger_client_request_idx
  on public.stock_ledger(fpc_id, client_request_id, movement_type)
  where client_request_id is not null;
create unique index if not exists dispatch_client_request_idx
  on public.dispatches(fpc_id, client_request_id)
  where client_request_id is not null;

drop index if exists public.stock_ledger_reference_movement_idx;
create unique index stock_ledger_reference_movement_idx
  on public.stock_ledger(
    fpc_id, reference_type, reference_id, movement_type,
    coalesce(lot_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(packaging_batch_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(location_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) where reference_id <> '';

-- Index tenant filters and foreign-key joins used throughout the workspace.
create index if not exists fpc_farmer_links_fpc_status_idx on public.fpc_farmer_links(fpc_id, status);
create index if not exists harvest_plans_fpc_date_idx on public.harvest_plans(fpc_id, expected_harvest_date);
create index if not exists harvest_plans_assigned_idx on public.harvest_plans(assigned_to) where assigned_to is not null;
create index if not exists collection_centers_fpc_idx on public.collection_centers(fpc_id);
create index if not exists procurement_schedules_fpc_date_idx on public.procurement_schedules(fpc_id, scheduled_at);
create index if not exists procurement_schedules_officer_idx on public.procurement_schedules(assigned_officer_id) where assigned_officer_id is not null;
create index if not exists vehicle_assignments_schedule_idx on public.vehicle_assignments(procurement_schedule_id);
create index if not exists field_assignments_officer_status_idx on public.field_assignments(officer_user_id, status, scheduled_for);
create index if not exists field_assignments_fpc_idx on public.field_assignments(fpc_id);
create index if not exists field_visits_assignment_idx on public.field_visits(assignment_id) where assignment_id is not null;
create index if not exists field_visits_fpc_officer_idx on public.field_visits(fpc_id, officer_user_id, created_at desc);
create index if not exists procurement_lots_fpc_status_idx on public.procurement_lots(fpc_id, status, received_at);
create index if not exists procurement_lots_schedule_idx on public.procurement_lots(procurement_schedule_id) where procurement_schedule_id is not null;
create index if not exists quality_certificates_lot_idx on public.quality_certificates(lot_id);
create index if not exists quality_certificates_analysis_idx on public.quality_certificates(analysis_job_id) where analysis_job_id is not null;
create index if not exists warehouses_fpc_idx on public.warehouses(fpc_id);
create index if not exists warehouse_locations_fpc_warehouse_idx on public.warehouse_locations(fpc_id, warehouse_id);
create index if not exists stock_ledger_fpc_lot_idx on public.stock_ledger(fpc_id, lot_id, occurred_at) where lot_id is not null;
create index if not exists stock_ledger_fpc_package_idx on public.stock_ledger(fpc_id, packaging_batch_id, occurred_at) where packaging_batch_id is not null;
create index if not exists production_runs_fpc_status_idx on public.production_runs(fpc_id, status, created_at desc);
create index if not exists production_runs_input_lot_idx on public.production_runs(input_lot_id) where input_lot_id is not null;
create index if not exists packaging_batches_fpc_status_idx on public.packaging_batches(fpc_id, status, expires_on);
create index if not exists packaging_batches_run_idx on public.packaging_batches(production_run_id) where production_run_id is not null;
create index if not exists buyers_fpc_active_idx on public.buyers(fpc_id, active);
create index if not exists sales_orders_fpc_status_idx on public.sales_orders(fpc_id, status, ordered_at desc);
create index if not exists sales_orders_buyer_idx on public.sales_orders(buyer_id);
create index if not exists sales_order_items_order_idx on public.sales_order_items(sales_order_id);
create index if not exists sales_order_items_batch_idx on public.sales_order_items(packaging_batch_id) where packaging_batch_id is not null;
create index if not exists dispatches_order_idx on public.dispatches(sales_order_id);
create index if not exists farmer_payment_fpc_status_idx on public.farmer_payment_ledger(fpc_id, status, created_at desc);
create index if not exists notification_outbox_status_idx on public.notification_outbox(status, created_at);
create index if not exists ai_insights_fpc_type_idx on public.ai_insights(fpc_id, insight_type, generated_at desc);
create index if not exists audit_events_fpc_created_idx on public.audit_events(fpc_id, created_at desc) where fpc_id is not null;

-- Field Officers may only read work explicitly assigned to them. All other
-- operating domains require FPC Admin or Platform Admin membership.
drop policy if exists "tenant read" on public.fpc_farmer_links;
create policy "fpc admins or assigned officers read farmer links"
on public.fpc_farmer_links for select to authenticated
using (
  private.can_manage_fpc(fpc_id)
  or exists (
    select 1 from public.field_assignments a
    where a.fpc_id = fpc_farmer_links.fpc_id
      and a.officer_user_id = (select auth.uid())
      and a.status <> 'cancelled'
      and (a.farmer_id = fpc_farmer_links.farmer_id or a.farm_id = fpc_farmer_links.farm_id)
  )
);

drop policy if exists "tenant read" on public.harvest_plans;
create policy "fpc admins or assigned officers read harvest plans"
on public.harvest_plans for select to authenticated
using (private.can_manage_fpc(fpc_id) or assigned_to = (select auth.uid()));

drop policy if exists "tenant read" on public.collection_centers;
create policy "fpc admins or scheduled officers read centers"
on public.collection_centers for select to authenticated
using (
  private.can_manage_fpc(fpc_id)
  or exists (
    select 1 from public.procurement_schedules s
    where s.collection_center_id = collection_centers.id
      and s.assigned_officer_id = (select auth.uid())
      and s.status <> 'cancelled'
  )
);

drop policy if exists "tenant read" on public.procurement_schedules;
create policy "fpc admins or assigned officers read schedules"
on public.procurement_schedules for select to authenticated
using (private.can_manage_fpc(fpc_id) or assigned_officer_id = (select auth.uid()));

drop policy if exists "tenant read" on public.vehicle_assignments;
create policy "fpc admins or scheduled officers read vehicles"
on public.vehicle_assignments for select to authenticated
using (
  private.can_manage_fpc(fpc_id)
  or exists (
    select 1 from public.procurement_schedules s
    where s.id = vehicle_assignments.procurement_schedule_id
      and s.assigned_officer_id = (select auth.uid())
  )
);

create or replace function private.is_assigned_field_work(
  target_assignment_id uuid,
  target_fpc_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_assignment_id is not null and exists (
    select 1 from public.field_assignments a
    where a.id=target_assignment_id and a.fpc_id=target_fpc_id
      and a.officer_user_id=(select auth.uid()) and a.status<>'cancelled'
  );
$$;

create or replace function private.is_assigned_field_farm(target_farm_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_farm_id is not null and exists (
    select 1 from public.field_assignments a
    where a.officer_user_id=(select auth.uid()) and a.status<>'cancelled'
      and (
        a.farm_id=target_farm_id::text
        or exists (
          select 1 from public.fpc_farmer_links l
          where l.fpc_id=a.fpc_id and l.farm_id=target_farm_id::text
            and l.farmer_id=a.farmer_id
        )
      )
  );
$$;

create or replace function private.can_read_linked_fpc_farm(target_farm_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_platform_admin() or exists (
    select 1 from public.fpc_farmer_links l
    where l.farm_id=target_farm_id::text and l.status='active'
      and private.can_manage_fpc(l.fpc_id)
  );
$$;

do $$
declare
  target_table text;
  farm_column text;
begin
  foreach target_table in array array[
    'farms', 'farm_data_snapshots', 'satellite_observations',
    'disease_risk_cells', 'disease_scout_zones', 'farm_timeline_events'
  ] loop
    farm_column := case when target_table = 'farms' then 'id' else 'farm_id' end;
    execute format('alter table public.%I enable row level security',target_table);
    execute format('grant select on public.%I to authenticated',target_table);
    execute format('drop policy if exists "assigned field officers read" on public.%I',target_table);
    execute format(
      'create policy "assigned field officers read" on public.%I for select to authenticated using (private.is_assigned_field_farm(%I))',
      target_table,
      farm_column
    );
    execute format('drop policy if exists "fpc admins read linked farms" on public.%I',target_table);
    execute format(
      'create policy "fpc admins read linked farms" on public.%I for select to authenticated using (private.can_read_linked_fpc_farm(%I))',
      target_table,
      farm_column
    );
  end loop;
end $$;

drop policy if exists "field users create visits" on public.field_visits;
create policy "field users create assigned visits"
on public.field_visits for insert to authenticated
with check (
  officer_user_id=(select auth.uid())
  and fpc_id=private.active_fpc_id()
  and private.is_assigned_field_work(assignment_id,fpc_id)
);
drop policy if exists "field users update visits" on public.field_visits;
create policy "field users update assigned visits"
on public.field_visits for update to authenticated
using (officer_user_id=(select auth.uid()))
with check (
  officer_user_id=(select auth.uid())
  and fpc_id=private.active_fpc_id()
  and private.is_assigned_field_work(assignment_id,fpc_id)
);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'procurement_lots', 'quality_certificates', 'warehouses',
    'warehouse_locations', 'production_runs', 'packaging_batches',
    'buyers', 'sales_orders', 'sales_order_items', 'dispatches',
    'farmer_payment_ledger', 'notification_outbox', 'ai_insights',
    'fpc_operational_records'
  ] loop
    execute format('drop policy if exists "tenant read" on public.%I', table_name);
    execute format(
      'create policy "fpc and platform admins read" on public.%I for select to authenticated using (private.can_manage_fpc(fpc_id))',
      table_name
    );
  end loop;
end $$;

drop policy if exists "tenant read" on public.stock_ledger;
create policy "fpc and platform admins read"
on public.stock_ledger for select to authenticated
using (private.can_manage_fpc(fpc_id));

drop policy if exists "tenant read" on public.fpc_notifications;
create policy "admins or recipients read notifications"
on public.fpc_notifications for select to authenticated
using (
  private.can_manage_fpc(fpc_id)
  or recipient_user_id=(select auth.uid())
);
drop policy if exists "recipients update notifications" on public.fpc_notifications;
create policy "recipients update notifications"
on public.fpc_notifications for update to authenticated
using (recipient_user_id=(select auth.uid()))
with check (recipient_user_id=(select auth.uid()) and fpc_id=private.active_fpc_id());

drop policy if exists "tenant users read procurement records" on public.fpc_procurement_records;
create policy "fpc admins read procurement records"
on public.fpc_procurement_records for select to authenticated
using (
  private.is_platform_admin()
  or (fpc_organization_id is not null and private.can_manage_fpc(fpc_organization_id))
  or (fpc_organization_id is null and fpc_id = (select auth.uid()))
);

drop policy if exists "tenant users read grading review jobs" on public.analysis_jobs;
create policy "fpc admins read grading review jobs"
on public.analysis_jobs for select to authenticated
using (
  private.is_platform_admin()
  or (fpc_organization_id is not null and private.can_manage_fpc(fpc_organization_id))
  or (fpc_organization_id is null and fpc_id = (select auth.uid()))
);

drop policy if exists "platform users read subscriptions" on public.fpc_subscriptions;
create policy "platform and fpc admins read subscriptions"
on public.fpc_subscriptions for select to authenticated
using (private.can_manage_fpc(fpc_id));

drop policy if exists "platform users read subscription invoices" on public.fpc_subscription_invoices;
create policy "platform and fpc admins read subscription invoices"
on public.fpc_subscription_invoices for select to authenticated
using (private.can_manage_fpc(fpc_id));

drop policy if exists "authorized users read audit" on public.audit_events;
create policy "authorized users read audit"
on public.audit_events for select to authenticated
using (
  private.is_platform_admin()
  or actor_user_id = (select auth.uid())
  or (fpc_id is not null and private.can_manage_fpc(fpc_id))
);

create policy "fpc and platform admins read reports"
on public.fpc_report_exports for select to authenticated
using (private.can_manage_fpc(fpc_id));
create policy "fpc and platform admins read sales payments"
on public.sales_payment_ledger for select to authenticated
using (private.can_manage_fpc(fpc_id));
create policy "fpc and platform admins read reservations"
on public.stock_reservations for select to authenticated
using (private.can_manage_fpc(fpc_id));
create policy "fpc and platform admins read credit notes"
on public.sales_credit_notes for select to authenticated
using (private.can_manage_fpc(fpc_id));
create policy "platform admins read report exports"
on public.platform_report_exports for select to authenticated
using (private.is_platform_admin());
create policy "platform admins create report exports"
on public.platform_report_exports for insert to authenticated
with check (private.is_platform_admin() and generated_by=(select auth.uid()));
create policy "fpc admins read process templates"
on public.fpc_process_templates for select to authenticated
using (
  private.is_platform_admin()
  or exists (
    select 1 from public.fpc_memberships m
    where m.user_id=(select auth.uid()) and m.role='fpc_admin' and m.status='active'
      and (fpc_process_templates.fpc_id is null or m.fpc_id=fpc_process_templates.fpc_id)
  )
);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'fpc-field-evidence','fpc-field-evidence',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict(id) do update set
  public=excluded.public,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "field evidence tenant read" on storage.objects;
create policy "field evidence tenant read"
on storage.objects for select to authenticated
using (
  bucket_id='fpc-field-evidence'
  and (
    private.is_platform_admin()
    or private.can_manage_fpc(nullif((storage.foldername(name))[1],'')::uuid)
    or (storage.foldername(name))[2]=(select auth.uid())::text
  )
);
drop policy if exists "field officers upload own evidence" on storage.objects;
create policy "field officers upload own evidence"
on storage.objects for insert to authenticated
with check (
  bucket_id='fpc-field-evidence'
  and (storage.foldername(name))[1]=private.active_fpc_id()::text
  and (storage.foldername(name))[2]=(select auth.uid())::text
  and exists (
    select 1 from public.fpc_memberships m
    where m.fpc_id=private.active_fpc_id() and m.user_id=(select auth.uid())
      and m.role='field_officer' and m.status='active'
  )
);
drop policy if exists "field officers update own evidence" on storage.objects;
create policy "field officers update own evidence"
on storage.objects for update to authenticated
using (
  bucket_id='fpc-field-evidence'
  and (storage.foldername(name))[1]=private.active_fpc_id()::text
  and (storage.foldername(name))[2]=(select auth.uid())::text
)
with check (
  bucket_id='fpc-field-evidence'
  and (storage.foldername(name))[1]=private.active_fpc_id()::text
  and (storage.foldername(name))[2]=(select auth.uid())::text
);

create table if not exists private.fpc_operation_requests (
  fpc_id uuid not null,
  client_request_id uuid not null,
  operation text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (fpc_id, client_request_id)
);

create table if not exists private.fpc_document_counters (
  fpc_id uuid not null,
  document_type text not null,
  document_year integer not null,
  last_number integer not null default 0,
  primary key (fpc_id, document_type, document_year)
);

create or replace function private.next_fpc_document_number(
  target_fpc_id uuid,
  document_kind text,
  document_prefix text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare next_number integer;
declare year_number integer := extract(year from current_date)::integer;
begin
  insert into private.fpc_document_counters(fpc_id, document_type, document_year, last_number)
  values (target_fpc_id, document_kind, year_number, 1)
  on conflict (fpc_id, document_type, document_year)
  do update set last_number = private.fpc_document_counters.last_number + 1
  returning last_number into next_number;
  return document_prefix || '-' || year_number::text || '-' || lpad(next_number::text, 6, '0');
end;
$$;

create or replace function private.record_fpc_audit(
  target_fpc_id uuid,
  operation text,
  target_type text,
  target_id text,
  before_value jsonb default '{}'::jsonb,
  after_value jsonb default '{}'::jsonb,
  request_id uuid default gen_random_uuid()
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_events(
    fpc_id, actor_user_id, actor_role, action, target_type, target_id,
    before_data, after_data, correlation_id
  ) values (
    target_fpc_id, (select auth.uid()), 'fpc_admin', operation, target_type,
    coalesce(target_id, ''), coalesce(before_value, '{}'::jsonb),
    coalesce(after_value, '{}'::jsonb), request_id
  );
$$;

create or replace function private.queue_fpc_notification(
  target_fpc_id uuid,
  recipient uuid,
  event_name text,
  notification_title text,
  notification_body text,
  notification_data jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare notification_id uuid;
begin
  insert into public.fpc_notifications(
    fpc_id, recipient_user_id, event_key, title, body, data
  ) values (
    target_fpc_id, recipient, event_name, notification_title,
    notification_body, coalesce(notification_data, '{}'::jsonb)
  ) returning id into notification_id;
  insert into public.notification_outbox(fpc_id, notification_id, channel, status)
  values (target_fpc_id, notification_id, 'in_app', 'sent');
  return notification_id;
end;
$$;

create or replace function private.notify_field_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.queue_fpc_notification(new.fpc_id,new.officer_user_id,'field_assignment',
    'New field assignment',new.title,jsonb_build_object('assignment_id',new.id));
  return new;
end;
$$;

drop trigger if exists notify_field_assignment on public.field_assignments;
create trigger notify_field_assignment after insert on public.field_assignments
for each row execute function private.notify_field_assignment();

create or replace function private.enforce_fpc_farmer_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare farmer_limit integer;
declare active_count integer;
begin
  if new.status<>'active' then return new; end if;
  select coalesce((s.limits->>'farmers')::integer,(f.limits->>'farmers')::integer,5000)
  into farmer_limit
  from public.fpcs f
  left join public.fpc_subscriptions s on s.fpc_id=f.id and s.status in ('trial','active')
  where f.id=new.fpc_id
  order by s.created_at desc nulls last
  limit 1;
  select count(*) into active_count from public.fpc_farmer_links l
  where l.fpc_id=new.fpc_id and l.status='active'
    and (tg_op='INSERT' or l.id<>new.id);
  if active_count>=coalesce(farmer_limit,5000) then
    raise exception 'This FPC has reached its active farmer subscription limit';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_fpc_farmer_limit on public.fpc_farmer_links;
create trigger enforce_fpc_farmer_limit before insert or update of status on public.fpc_farmer_links
for each row execute function private.enforce_fpc_farmer_limit();

create or replace function private.audit_fpc_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare before_value jsonb := case when tg_op = 'INSERT' then '{}'::jsonb else to_jsonb(old) end;
declare after_value jsonb := case when tg_op = 'DELETE' then '{}'::jsonb else to_jsonb(new) end;
declare target_fpc_id uuid;
declare actor_id uuid := auth.uid();
declare actor_membership_role text;
declare target_value text;
begin
  if current_setting('app.fpc_operation', true) = '1' or actor_id is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  target_fpc_id := nullif(coalesce(after_value->>'fpc_id', before_value->>'fpc_id'), '')::uuid;
  if target_fpc_id is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  select m.role into actor_membership_role
  from public.fpc_memberships m
  where m.fpc_id = target_fpc_id and m.user_id = actor_id and m.status = 'active'
  limit 1;
  target_value := coalesce(after_value->>'id', before_value->>'id', '');
  insert into public.audit_events(
    fpc_id, actor_user_id, actor_role, action, target_type, target_id,
    before_data, after_data, correlation_id
  ) values (
    target_fpc_id, actor_id, coalesce(actor_membership_role, 'authenticated'),
    lower(tg_op) || '_' || tg_table_name, tg_table_name, target_value,
    before_value, after_value, gen_random_uuid()
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'fpc_farmer_links', 'harvest_plans', 'collection_centers',
    'procurement_schedules', 'vehicle_assignments', 'field_assignments',
    'field_visits', 'procurement_lots', 'quality_certificates', 'warehouses',
    'warehouse_locations', 'stock_ledger', 'production_runs',
    'packaging_batches', 'buyers', 'sales_orders', 'sales_order_items',
    'dispatches', 'farmer_payment_ledger', 'fpc_notifications',
    'notification_outbox', 'ai_insights', 'fpc_report_exports',
    'sales_payment_ledger', 'stock_reservations', 'sales_credit_notes'
  ] loop
    execute format('drop trigger if exists audit_fpc_row_change on public.%I', target_table);
    execute format(
      'create trigger audit_fpc_row_change after insert or update or delete on public.%I for each row execute function private.audit_fpc_row_change()',
      target_table
    );
  end loop;
end $$;

create or replace function private.audit_platform_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare before_value jsonb := case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;
declare after_value jsonb := case when tg_op='DELETE' then '{}'::jsonb else to_jsonb(new) end;
declare actor_id uuid := auth.uid();
begin
  if actor_id is null then return case when tg_op='DELETE' then old else new end; end if;
  insert into public.audit_events(actor_user_id,actor_role,action,target_type,target_id,
    before_data,after_data,correlation_id)
  values(actor_id,'admin',lower(tg_op)||'_'||tg_table_name,tg_table_name,
    coalesce(after_value->>'id',after_value->>'key',after_value->>'event_key',
      before_value->>'id',before_value->>'key',before_value->>'event_key',''),
    before_value,after_value,gen_random_uuid());
  return case when tg_op='DELETE' then old else new end;
end;
$$;

drop trigger if exists audit_platform_setting_change on public.platform_settings;
create trigger audit_platform_setting_change after insert or update or delete on public.platform_settings
for each row execute function private.audit_platform_row_change();
drop trigger if exists audit_notification_template_change on public.notification_templates;
create trigger audit_notification_template_change after insert or update or delete on public.notification_templates
for each row execute function private.audit_platform_row_change();
drop trigger if exists audit_platform_report_export on public.platform_report_exports;
create trigger audit_platform_report_export after insert on public.platform_report_exports
for each row execute function private.audit_platform_row_change();

create or replace function private.guard_fpc_immutable_rows()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_setting('app.fpc_operation', true) = '1' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_table_name = 'stock_ledger' then
    raise exception 'Stock ledger rows are immutable; post a compensating movement';
  end if;
  if tg_table_name = 'quality_certificates' and old.status = 'approved' then
    raise exception 'Approved quality certificates are immutable';
  end if;
  if tg_table_name = 'farmer_payment_ledger' and old.status in ('paid', 'reversed') then
    raise exception 'Issued payment entries are immutable; create a correction';
  end if;
  if tg_table_name = 'sales_orders'
     and coalesce(old.invoice_number, '') <> ''
     and (
       tg_op = 'DELETE'
       or new.invoice_number is distinct from old.invoice_number
       or new.subtotal is distinct from old.subtotal
       or new.cgst is distinct from old.cgst
       or new.sgst is distinct from old.sgst
       or new.igst is distinct from old.igst
       or new.total is distinct from old.total
       or new.immutable_invoice_snapshot is distinct from old.immutable_invoice_snapshot
     ) then
    raise exception 'Issued invoice values are immutable';
  end if;
  if tg_table_name = 'sales_payment_ledger' then
    raise exception 'Sales payment ledger rows are immutable';
  end if;
  if tg_table_name in ('fpc_subscription_invoices','sales_credit_notes') then
    raise exception 'Issued financial documents are immutable';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists stock_ledger_immutable on public.stock_ledger;
create trigger stock_ledger_immutable before update or delete on public.stock_ledger
for each row execute function private.guard_fpc_immutable_rows();
drop trigger if exists quality_certificate_immutable on public.quality_certificates;
create trigger quality_certificate_immutable before update or delete on public.quality_certificates
for each row execute function private.guard_fpc_immutable_rows();
drop trigger if exists farmer_payment_immutable on public.farmer_payment_ledger;
create trigger farmer_payment_immutable before update or delete on public.farmer_payment_ledger
for each row execute function private.guard_fpc_immutable_rows();
drop trigger if exists sales_payment_immutable on public.sales_payment_ledger;
create trigger sales_payment_immutable before update or delete on public.sales_payment_ledger
for each row execute function private.guard_fpc_immutable_rows();
drop trigger if exists sales_order_invoice_immutable on public.sales_orders;
create trigger sales_order_invoice_immutable before update or delete on public.sales_orders
for each row execute function private.guard_fpc_immutable_rows();
drop trigger if exists subscription_invoice_immutable on public.fpc_subscription_invoices;
create trigger subscription_invoice_immutable before update or delete on public.fpc_subscription_invoices
for each row execute function private.guard_fpc_immutable_rows();
drop trigger if exists sales_credit_note_immutable on public.sales_credit_notes;
create trigger sales_credit_note_immutable before update or delete on public.sales_credit_notes
for each row execute function private.guard_fpc_immutable_rows();

revoke update, delete on public.fpc_subscription_invoices from authenticated;

create or replace function private.link_received_lot_to_schedule()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.procurement_schedule_id is null then
    select s.id into new.procurement_schedule_id
    from public.procurement_schedules s
    join public.harvest_plans h on h.id=s.harvest_plan_id and h.fpc_id=s.fpc_id
    where s.fpc_id=new.fpc_id and s.status in ('scheduled','in_collection')
      and (h.farm_id='' or h.farm_id=new.farm_id)
      and (h.crop='' or lower(h.crop)=lower(new.crop))
    order by s.scheduled_at
    limit 1;
  end if;
  if new.procurement_schedule_id is not null then
    update public.procurement_schedules set status='quality_review',updated_at=now()
    where id=new.procurement_schedule_id and fpc_id=new.fpc_id
      and status in ('scheduled','in_collection');
    update public.harvest_plans h set status='quality_review',updated_at=now()
    from public.procurement_schedules s
    where s.id=new.procurement_schedule_id and s.harvest_plan_id=h.id
      and h.fpc_id=new.fpc_id and h.status in ('scheduled','in_collection');
  end if;
  return new;
end;
$$;

drop trigger if exists procurement_lot_schedule_link on public.procurement_lots;
create trigger procurement_lot_schedule_link before insert on public.procurement_lots
for each row execute function private.link_received_lot_to_schedule();

create or replace function private.execute_fpc_operation(
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
  result jsonb;
  saved record;
  source_row record;
  order_row record;
  run_row record;
  lot_row record;
  payment_row record;
  quantity_value numeric;
  available_value numeric;
  total_value numeric;
  subtotal_value numeric;
  tax_value numeric;
  remaining_value numeric;
  allocated_value numeric;
  doc_number text;
  item jsonb;
  allocation_row record;
begin
  if actor_id is null then raise exception 'Login required'; end if;
  select m.fpc_id into target_fpc_id
  from public.fpc_memberships m
  join public.fpcs f on f.id = m.fpc_id and f.status = 'active'
  where m.user_id = actor_id and m.role = 'fpc_admin' and m.status = 'active'
  limit 1;
  if target_fpc_id is null then raise exception 'Active FPC Admin membership required'; end if;

  perform pg_advisory_xact_lock(
    hashtextextended(target_fpc_id::text || ':' || request_id::text, 0)
  );
  perform pg_advisory_xact_lock(hashtextextended('fpc-operation:' || target_fpc_id::text, 0));

  select r.response into existing_response
  from private.fpc_operation_requests r
  where r.fpc_id = target_fpc_id and r.client_request_id = request_id;
  if existing_response is not null then return existing_response; end if;
  perform set_config('app.fpc_operation', '1', true);

  if operation_name = 'create_harvest_plan' then
    if nullif(payload->>'farmer_link_id','') is not null and not exists (
      select 1 from public.fpc_farmer_links l
      where l.id=(payload->>'farmer_link_id')::uuid and l.fpc_id=target_fpc_id
    ) then raise exception 'Farmer link does not belong to this FPC'; end if;
    if nullif(payload->>'assigned_to','') is not null and not exists (
      select 1 from public.fpc_memberships m where m.fpc_id=target_fpc_id
        and m.user_id=(payload->>'assigned_to')::uuid and m.role='field_officer' and m.status='active'
    ) then raise exception 'Assigned Field Officer is not active in this FPC'; end if;
    insert into public.harvest_plans(
      fpc_id, farmer_link_id, farm_id, crop, village, expected_harvest_date,
      expected_quantity_kg, expected_grade, readiness, priority, assigned_to,
      notes, created_by
    ) values (
      target_fpc_id, nullif(payload->>'farmer_link_id','')::uuid,
      coalesce(payload->>'farm_id',''), payload->>'crop', coalesce(payload->>'village',''),
      nullif(payload->>'expected_harvest_date','')::date,
      nullif(payload->>'expected_quantity_kg','')::numeric,
      coalesce(payload->>'expected_grade',''), coalesce(payload->>'readiness','planned'),
      coalesce(payload->>'priority','normal'), nullif(payload->>'assigned_to','')::uuid,
      coalesce(payload->>'notes',''), actor_id
    ) returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'create_collection_center' then
    insert into public.collection_centers(fpc_id,name,village,address,capacity_kg)
    values (target_fpc_id,payload->>'name',coalesce(payload->>'village',''),
      coalesce(payload->>'address',''),coalesce(nullif(payload->>'capacity_kg','')::numeric,0))
    returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'create_procurement_schedule' then
    if not exists (
      select 1 from public.harvest_plans h
      where h.id=(payload->>'harvest_plan_id')::uuid and h.fpc_id=target_fpc_id
    ) then raise exception 'Harvest plan does not belong to this FPC'; end if;
    if not exists (
      select 1 from public.collection_centers c
      where c.id=(payload->>'collection_center_id')::uuid and c.fpc_id=target_fpc_id and c.active
    ) then raise exception 'Collection center does not belong to this FPC'; end if;
    if not exists (
      select 1 from public.fpc_memberships m where m.fpc_id=target_fpc_id
        and m.user_id=(payload->>'assigned_officer_id')::uuid and m.role='field_officer' and m.status='active'
    ) then raise exception 'Assigned Field Officer is not active in this FPC'; end if;
    insert into public.procurement_schedules(
      fpc_id,harvest_plan_id,collection_center_id,scheduled_at,status,
      assigned_officer_id,vehicle_details,notes
    ) values (
      target_fpc_id,nullif(payload->>'harvest_plan_id','')::uuid,
      nullif(payload->>'collection_center_id','')::uuid,
      (payload->>'scheduled_at')::timestamptz,'scheduled',
      nullif(payload->>'assigned_officer_id','')::uuid,
      coalesce(payload->'vehicle_details','{}'::jsonb),coalesce(payload->>'notes','')
    ) returning * into saved;
    update public.harvest_plans set status='scheduled',updated_at=now()
    where id=saved.harvest_plan_id and fpc_id=target_fpc_id and status='planned';
    if saved.assigned_officer_id is not null then
      perform private.queue_fpc_notification(target_fpc_id,saved.assigned_officer_id,
        'procurement_schedule','Procurement schedule assigned',
        'A collection visit has been assigned to you.',jsonb_build_object('schedule_id',saved.id));
    end if;
    result := to_jsonb(saved);

  elsif operation_name = 'transition_procurement_schedule' then
    select * into source_row from public.procurement_schedules
    where id=(payload->>'procurement_schedule_id')::uuid and fpc_id=target_fpc_id for update;
    if source_row.id is null then raise exception 'Procurement schedule not found'; end if;
    if not (
      (source_row.status='planned' and payload->>'status' in ('scheduled','cancelled'))
      or (source_row.status='scheduled' and payload->>'status' in ('in_collection','cancelled'))
      or (source_row.status='in_collection' and payload->>'status' in ('quality_review','cancelled'))
      or (source_row.status='quality_review' and payload->>'status' in ('lot_created','cancelled'))
      or (source_row.status='lot_created' and payload->>'status' in ('warehoused','cancelled'))
      or (source_row.status='warehoused' and payload->>'status' in ('completed','cancelled'))
    ) then raise exception 'Invalid procurement schedule transition'; end if;
    update public.procurement_schedules set status=payload->>'status',updated_at=now()
    where id=source_row.id returning * into saved;
    update public.harvest_plans set status=payload->>'status',updated_at=now()
    where id=source_row.harvest_plan_id and fpc_id=target_fpc_id;
    result := to_jsonb(saved);

  elsif operation_name = 'create_vehicle_assignment' then
    if not exists (
      select 1 from public.procurement_schedules s
      where s.id=(payload->>'procurement_schedule_id')::uuid and s.fpc_id=target_fpc_id
    ) then raise exception 'Procurement schedule does not belong to this FPC'; end if;
    insert into public.vehicle_assignments(
      fpc_id,procurement_schedule_id,vehicle_number,driver_name,driver_phone,route_notes
    ) values (
      target_fpc_id,nullif(payload->>'procurement_schedule_id','')::uuid,
      payload->>'vehicle_number',coalesce(payload->>'driver_name',''),
      coalesce(payload->>'driver_phone',''),coalesce(payload->>'route_notes','')
    ) returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'set_farmer_status' then
    update public.fpc_farmer_links
    set status = payload->>'status', updated_at = now()
    where id = (payload->>'farmer_link_id')::uuid and fpc_id = target_fpc_id
    returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'approve_quality' then
    select * into lot_row from public.procurement_lots
    where id = (payload->>'lot_id')::uuid and fpc_id = target_fpc_id for update;
    if lot_row.id is null then raise exception 'Procurement lot not found'; end if;
    if nullif(payload->>'analysis_job_id','') is not null and not exists (
      select 1 from public.analysis_jobs j
      where j.id=(payload->>'analysis_job_id')::uuid
        and (
          j.fpc_organization_id=target_fpc_id
          or (j.fpc_organization_id is null and j.fpc_id=actor_id)
        )
    ) then raise exception 'Grading analysis does not belong to this FPC'; end if;
    doc_number := private.next_fpc_document_number(target_fpc_id,'quality','QC');
    insert into public.quality_certificates(
      fpc_id,lot_id,analysis_job_id,certificate_number,status,grade,results,
      immutable_snapshot,approved_by,approved_at
    ) values (
      target_fpc_id,lot_row.id,nullif(payload->>'analysis_job_id','')::uuid,
      doc_number,'approved',payload->>'grade',coalesce(payload->'results','{}'::jsonb),
      jsonb_build_object('lot',to_jsonb(lot_row),'grade',payload->>'grade',
        'results',coalesce(payload->'results','{}'::jsonb),'approved_at',now()),actor_id,now()
    ) returning * into saved;
    update public.procurement_lots set grade = saved.grade,status='quality_approved',updated_at=now()
    where id=lot_row.id;
    update public.procurement_schedules set status='lot_created',updated_at=now()
    where id=lot_row.procurement_schedule_id and fpc_id=target_fpc_id
      and status='quality_review';
    update public.harvest_plans h set status='lot_created',updated_at=now()
    from public.procurement_schedules s
    where s.id=lot_row.procurement_schedule_id and h.id=s.harvest_plan_id
      and h.fpc_id=target_fpc_id;
    perform private.queue_fpc_notification(target_fpc_id,null,'quality_status',
      'Quality certificate approved','Lot '||lot_row.batch_id||' was approved as grade '||saved.grade||'.',
      jsonb_build_object('lot_id',lot_row.id,'certificate_id',saved.id,'grade',saved.grade));
    result := to_jsonb(saved);

  elsif operation_name = 'create_warehouse' then
    insert into public.warehouses(fpc_id,name,address,capacity_kg)
    values(target_fpc_id,payload->>'name',coalesce(payload->>'address',''),
      coalesce(nullif(payload->>'capacity_kg','')::numeric,0)) returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'create_warehouse_location' then
    if not exists (
      select 1 from public.warehouses w
      where w.id=(payload->>'warehouse_id')::uuid and w.fpc_id=target_fpc_id and w.active
    ) then raise exception 'Warehouse does not belong to this FPC'; end if;
    insert into public.warehouse_locations(fpc_id,warehouse_id,code,location_type,capacity_kg)
    values(target_fpc_id,(payload->>'warehouse_id')::uuid,payload->>'code',
      coalesce(payload->>'location_type','bin'),coalesce(nullif(payload->>'capacity_kg','')::numeric,0))
    returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'post_stock_movement' then
    if nullif(payload->>'warehouse_id','') is not null and not exists (
      select 1 from public.warehouses w
      where w.id=(payload->>'warehouse_id')::uuid and w.fpc_id=target_fpc_id and w.active
    ) then raise exception 'Warehouse does not belong to this FPC'; end if;
    if nullif(payload->>'location_id','') is not null and not exists (
      select 1 from public.warehouse_locations l
      where l.id=(payload->>'location_id')::uuid and l.fpc_id=target_fpc_id and l.active
        and (nullif(payload->>'warehouse_id','') is null or l.warehouse_id=(payload->>'warehouse_id')::uuid)
    ) then raise exception 'Storage location does not belong to the selected warehouse'; end if;
    if nullif(payload->>'lot_id','') is not null and not exists (
      select 1 from public.procurement_lots l
      where l.id=(payload->>'lot_id')::uuid and l.fpc_id=target_fpc_id
    ) then raise exception 'Procurement lot does not belong to this FPC'; end if;
    if nullif(payload->>'packaging_batch_id','') is not null and not exists (
      select 1 from public.packaging_batches b
      where b.id=(payload->>'packaging_batch_id')::uuid and b.fpc_id=target_fpc_id
    ) then raise exception 'Packaging batch does not belong to this FPC'; end if;
    quantity_value := abs((payload->>'quantity_kg')::numeric);
    if payload->>'movement_type' in ('transfer_out','adjustment_out','damage','consumption','dispatch') then
      quantity_value := -quantity_value;
    end if;
    if payload->>'movement_type' in ('adjustment_in','adjustment_out','damage')
       and length(trim(coalesce(payload->>'reason',''))) < 4 then
      raise exception 'A clear stock adjustment reason is required';
    end if;
    if quantity_value < 0 then
      select coalesce(sum(s.quantity_kg),0) into available_value
      from public.stock_ledger s
      where s.fpc_id=target_fpc_id
        and s.item_type=payload->>'item_type'
        and s.item_name=payload->>'item_name'
        and (nullif(payload->>'location_id','') is null or s.location_id=(payload->>'location_id')::uuid)
        and (nullif(payload->>'lot_id','') is null or s.lot_id=(payload->>'lot_id')::uuid)
        and (nullif(payload->>'packaging_batch_id','') is null or s.packaging_batch_id=(payload->>'packaging_batch_id')::uuid);
      if available_value + quantity_value < 0 then raise exception 'Stock movement would create a negative balance'; end if;
    end if;
    if quantity_value > 0 and nullif(payload->>'warehouse_id','') is not null then
      select w.capacity_kg - coalesce((
        select sum(s.quantity_kg) from public.stock_ledger s
        where s.fpc_id=target_fpc_id and s.warehouse_id=w.id
      ),0) into available_value
      from public.warehouses w
      where w.id=(payload->>'warehouse_id')::uuid and w.fpc_id=target_fpc_id;
      if available_value < quantity_value then raise exception 'Warehouse capacity would be exceeded'; end if;
    end if;
    insert into public.stock_ledger(
      fpc_id,warehouse_id,location_id,lot_id,packaging_batch_id,movement_type,
      item_type,item_name,quantity_kg,reference_type,reference_id,reason,
      posted_by,client_request_id,expires_on
    ) values (
      target_fpc_id,nullif(payload->>'warehouse_id','')::uuid,
      nullif(payload->>'location_id','')::uuid,nullif(payload->>'lot_id','')::uuid,
      nullif(payload->>'packaging_batch_id','')::uuid,payload->>'movement_type',
      payload->>'item_type',payload->>'item_name',quantity_value,
      coalesce(payload->>'reference_type','manual'),coalesce(payload->>'reference_id',request_id::text),
      coalesce(payload->>'reason',''),actor_id,request_id,nullif(payload->>'expires_on','')::date
    ) returning * into saved;
    if quantity_value > 0 and nullif(payload->>'warehouse_id','') is not null
       and nullif(payload->>'lot_id','') is not null then
      update public.procurement_schedules s set status='warehoused',updated_at=now()
      from public.procurement_lots l
      where l.id=(payload->>'lot_id')::uuid and l.procurement_schedule_id=s.id
        and s.fpc_id=target_fpc_id and s.status='lot_created';
      update public.harvest_plans h set status='warehoused',updated_at=now()
      from public.procurement_schedules s
      join public.procurement_lots l on l.procurement_schedule_id=s.id
      where l.id=(payload->>'lot_id')::uuid and h.id=s.harvest_plan_id
        and h.fpc_id=target_fpc_id;
    end if;
    result := to_jsonb(saved);

  elsif operation_name = 'transfer_stock' then
    quantity_value := abs((payload->>'quantity_kg')::numeric);
    if nullif(payload->>'source_location_id','') is null or nullif(payload->>'destination_location_id','') is null then
      raise exception 'Source and destination locations are required';
    end if;
    if not exists (
      select 1 from public.warehouse_locations l
      where l.id=(payload->>'source_location_id')::uuid and l.fpc_id=target_fpc_id and l.active
        and l.warehouse_id=(payload->>'source_warehouse_id')::uuid
    ) or not exists (
      select 1 from public.warehouse_locations l
      where l.id=(payload->>'destination_location_id')::uuid and l.fpc_id=target_fpc_id and l.active
        and l.warehouse_id=(payload->>'destination_warehouse_id')::uuid
    ) then raise exception 'Transfer locations must belong to this FPC and selected warehouses'; end if;
    if nullif(payload->>'lot_id','') is not null and not exists (
      select 1 from public.procurement_lots l where l.id=(payload->>'lot_id')::uuid and l.fpc_id=target_fpc_id
    ) then raise exception 'Procurement lot does not belong to this FPC'; end if;
    if nullif(payload->>'packaging_batch_id','') is not null and not exists (
      select 1 from public.packaging_batches b where b.id=(payload->>'packaging_batch_id')::uuid and b.fpc_id=target_fpc_id
    ) then raise exception 'Packaging batch does not belong to this FPC'; end if;
    select w.capacity_kg - coalesce((
      select sum(s.quantity_kg) from public.stock_ledger s
      where s.fpc_id=target_fpc_id and s.warehouse_id=w.id
    ),0) into available_value
    from public.warehouses w
    where w.id=(payload->>'destination_warehouse_id')::uuid and w.fpc_id=target_fpc_id;
    if available_value < quantity_value then raise exception 'Destination warehouse capacity would be exceeded'; end if;
    select coalesce(sum(s.quantity_kg),0) into available_value from public.stock_ledger s
    where s.fpc_id=target_fpc_id
      and s.location_id=(payload->>'source_location_id')::uuid
      and (nullif(payload->>'lot_id','') is null or s.lot_id=(payload->>'lot_id')::uuid)
      and (nullif(payload->>'packaging_batch_id','') is null or s.packaging_batch_id=(payload->>'packaging_batch_id')::uuid);
    if available_value < quantity_value then raise exception 'Insufficient stock at source location'; end if;
    insert into public.stock_ledger(fpc_id,warehouse_id,location_id,lot_id,packaging_batch_id,
      movement_type,item_type,item_name,quantity_kg,reference_type,reference_id,reason,posted_by,client_request_id)
    values(target_fpc_id,nullif(payload->>'source_warehouse_id','')::uuid,
      (payload->>'source_location_id')::uuid,nullif(payload->>'lot_id','')::uuid,
      nullif(payload->>'packaging_batch_id','')::uuid,'transfer_out',payload->>'item_type',
      payload->>'item_name',-quantity_value,'stock_transfer',request_id::text,
      coalesce(payload->>'reason','Transfer'),actor_id,request_id);
    insert into public.stock_ledger(fpc_id,warehouse_id,location_id,lot_id,packaging_batch_id,
      movement_type,item_type,item_name,quantity_kg,reference_type,reference_id,reason,posted_by)
    values(target_fpc_id,nullif(payload->>'destination_warehouse_id','')::uuid,
      (payload->>'destination_location_id')::uuid,nullif(payload->>'lot_id','')::uuid,
      nullif(payload->>'packaging_batch_id','')::uuid,'transfer_in',payload->>'item_type',
      payload->>'item_name',quantity_value,'stock_transfer',request_id::text,
      coalesce(payload->>'reason','Transfer'),actor_id) returning * into saved;
    result := jsonb_build_object('transfer_id',request_id,'destination_entry',to_jsonb(saved));

  elsif operation_name = 'create_production_run' then
    quantity_value := (payload->>'input_kg')::numeric;
    if not exists (
      select 1 from public.fpc_process_templates t
      where t.code=payload->>'process_type' and t.active
        and (t.fpc_id=target_fpc_id or t.fpc_id is null)
    ) then raise exception 'Active production process template not found'; end if;
    select coalesce(sum(s.quantity_kg),0) into available_value from public.stock_ledger s
    where s.fpc_id=target_fpc_id and s.lot_id=(payload->>'input_lot_id')::uuid;
    if available_value < quantity_value then raise exception 'Insufficient raw stock for production'; end if;
    doc_number := private.next_fpc_document_number(target_fpc_id,'production','PR');
    insert into public.production_runs(fpc_id,run_number,process_type,input_lot_id,input_kg,
      stages,machine,operator_name,status)
    values(target_fpc_id,doc_number,payload->>'process_type',(payload->>'input_lot_id')::uuid,
      quantity_value,(select t.stages from public.fpc_process_templates t
        where t.code=payload->>'process_type' and t.active
          and (t.fpc_id=target_fpc_id or t.fpc_id is null)
        order by (t.fpc_id is not null) desc limit 1),coalesce(payload->>'machine',''),
      coalesce(payload->>'operator_name',''),'planned') returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'start_production' then
    update public.production_runs set status='in_progress',started_at=coalesce(started_at,now()),updated_at=now()
    where id=(payload->>'production_run_id')::uuid and fpc_id=target_fpc_id and status='planned'
    returning * into saved;
    if saved.id is null then raise exception 'Only planned production can be started'; end if;
    result := to_jsonb(saved);

  elsif operation_name = 'complete_production' then
    select * into run_row from public.production_runs
    where id=(payload->>'production_run_id')::uuid and fpc_id=target_fpc_id for update;
    if run_row.status not in ('planned','in_progress') then raise exception 'Production run is already closed'; end if;
    quantity_value := (payload->>'output_kg')::numeric;
    total_value := coalesce(nullif(payload->>'waste_kg','')::numeric,0);
    if quantity_value <= 0 or total_value < 0 or quantity_value + total_value > run_row.input_kg then
      raise exception 'Output and waste must fit within production input';
    end if;
    select coalesce(sum(s.quantity_kg),0) into available_value from public.stock_ledger s
    where s.fpc_id=target_fpc_id and s.lot_id=run_row.input_lot_id;
    if available_value < run_row.input_kg then raise exception 'Raw stock changed; refresh the run'; end if;
    insert into public.stock_ledger(fpc_id,lot_id,movement_type,item_type,item_name,quantity_kg,
      reference_type,reference_id,reason,posted_by,client_request_id)
    values(target_fpc_id,run_row.input_lot_id,'consumption','raw_material',run_row.process_type,
      -run_row.input_kg,'production_run',run_row.id::text,'Production consumption',actor_id,request_id);
    insert into public.stock_ledger(fpc_id,movement_type,item_type,item_name,quantity_kg,
      reference_type,reference_id,reason,posted_by)
    values(target_fpc_id,'production_output','work_in_progress',coalesce(payload->>'product_name',run_row.process_type),
      quantity_value,'production_run',run_row.id::text,'Production output',actor_id);
    update public.production_runs set output_kg=quantity_value,waste_kg=total_value,
      status='completed',started_at=coalesce(started_at,now()),completed_at=now(),updated_at=now()
    where id=run_row.id returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'create_packaging_batch' then
    select * into run_row from public.production_runs
    where id=(payload->>'production_run_id')::uuid and fpc_id=target_fpc_id and status='completed' for update;
    if run_row.id is null then raise exception 'Completed production run required'; end if;
    quantity_value := ((payload->>'package_size_grams')::numeric * (payload->>'package_count')::numeric) / 1000;
    select coalesce(sum(s.quantity_kg),0) into available_value from public.stock_ledger s
    where s.fpc_id=target_fpc_id and s.reference_type='production_run'
      and s.reference_id=run_row.id::text and s.item_type='work_in_progress';
    if available_value < quantity_value then raise exception 'Insufficient production output for packaging'; end if;
    doc_number := private.next_fpc_document_number(target_fpc_id,'packaging','PK');
    insert into public.packaging_batches(fpc_id,production_run_id,batch_number,product_name,
      package_size_grams,package_count,total_weight_kg,qr_payload,barcode_value,
      manufactured_on,expires_on,status)
    values(target_fpc_id,run_row.id,doc_number,payload->>'product_name',
      (payload->>'package_size_grams')::integer,(payload->>'package_count')::integer,quantity_value,
      jsonb_build_object('type','kalsubai_finished_goods','batch',doc_number,'fpc_id',target_fpc_id,
        'product',payload->>'product_name','weight_kg',quantity_value),doc_number,
      coalesce(nullif(payload->>'manufactured_on','')::date,current_date),nullif(payload->>'expires_on','')::date,'posted')
    returning * into saved;
    insert into public.stock_ledger(fpc_id,movement_type,item_type,item_name,quantity_kg,
      reference_type,reference_id,reason,posted_by,client_request_id)
    values(target_fpc_id,'packaging_consumption','work_in_progress',saved.product_name,-quantity_value,
      'production_run',run_row.id::text,'Packaging consumption',actor_id,request_id);
    insert into public.stock_ledger(fpc_id,packaging_batch_id,movement_type,item_type,item_name,
      quantity_kg,reference_type,reference_id,reason,posted_by,expires_on)
    values(target_fpc_id,saved.id,'packaging_output','finished_goods',saved.product_name,quantity_value,
      'packaging_batch',saved.id::text,'Finished goods created',actor_id,saved.expires_on);
    result := to_jsonb(saved);

  elsif operation_name = 'create_buyer' then
    insert into public.buyers(fpc_id,buyer_type,name,phone,email,gstin,address)
    values(target_fpc_id,payload->>'buyer_type',payload->>'name',coalesce(payload->>'phone',''),
      coalesce(payload->>'email',''),coalesce(payload->>'gstin',''),coalesce(payload->'address','{}'::jsonb))
    returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'create_sales_order' then
    quantity_value := (payload->>'quantity_kg')::numeric;
    if quantity_value <= 0 then raise exception 'Sales quantity must be greater than zero'; end if;
    if not exists (
      select 1 from public.buyers b
      where b.id=(payload->>'buyer_id')::uuid and b.fpc_id=target_fpc_id and b.active
    ) then raise exception 'Buyer does not belong to this FPC'; end if;
    subtotal_value := round(quantity_value * (payload->>'rate')::numeric,2);
    tax_value := round(subtotal_value * coalesce(nullif(payload->>'tax_rate','')::numeric,0) / 100,2);
    doc_number := private.next_fpc_document_number(target_fpc_id,'sales_order','SO');
    insert into public.sales_orders(fpc_id,buyer_id,order_number,quotation_number,status,subtotal,
      cgst,sgst,igst,total)
    values(target_fpc_id,(payload->>'buyer_id')::uuid,doc_number,
      replace(doc_number,'SO-','QT-'),'quotation',subtotal_value,
      case when coalesce((payload->>'interstate')::boolean,false) then 0 else tax_value/2 end,
      case when coalesce((payload->>'interstate')::boolean,false) then 0 else tax_value/2 end,
      case when coalesce((payload->>'interstate')::boolean,false) then tax_value else 0 end,
      subtotal_value+tax_value) returning * into order_row;

    remaining_value := quantity_value;
    if nullif(payload->>'packaging_batch_id','') is not null then
      select b.id,b.product_name,
        coalesce((select sum(s.quantity_kg) from public.stock_ledger s
          where s.fpc_id=target_fpc_id and s.packaging_batch_id=b.id),0)
        - coalesce((select sum(r.quantity_kg) from public.stock_reservations r
          where r.fpc_id=target_fpc_id and r.packaging_batch_id=b.id and r.status='reserved'),0) as available
      into allocation_row
      from public.packaging_batches b
      where b.id=(payload->>'packaging_batch_id')::uuid and b.fpc_id=target_fpc_id
      for update;
      if allocation_row.id is null then raise exception 'Packaging batch does not belong to this FPC'; end if;
      if nullif(trim(payload->>'item_name'),'') is not null
         and lower(allocation_row.product_name) <> lower(trim(payload->>'item_name')) then
        raise exception 'Selected packaging batch does not match the product name';
      end if;
      if allocation_row.available < remaining_value then raise exception 'Insufficient unreserved finished goods stock'; end if;
      insert into public.sales_order_items(fpc_id,sales_order_id,packaging_batch_id,description,
        quantity,unit,rate,tax_rate,line_total)
      values(target_fpc_id,order_row.id,allocation_row.id,
        coalesce(nullif(payload->>'description',''),allocation_row.product_name),remaining_value,'kg',
        (payload->>'rate')::numeric,coalesce(nullif(payload->>'tax_rate','')::numeric,0),
        round(remaining_value*(payload->>'rate')::numeric*(1+coalesce(nullif(payload->>'tax_rate','')::numeric,0)/100),2));
      insert into public.stock_reservations(fpc_id,sales_order_id,packaging_batch_id,quantity_kg,
        allocation_method,status,created_by)
      values(target_fpc_id,order_row.id,allocation_row.id,remaining_value,'manual','reserved',actor_id);
      remaining_value := 0;
    else
      if coalesce(payload->>'allocation_method','fefo') not in ('fifo','fefo') then
        raise exception 'Allocation method must be FIFO or FEFO';
      end if;
      for allocation_row in
        select b.id,b.product_name,b.expires_on,b.created_at,
          coalesce((select sum(s.quantity_kg) from public.stock_ledger s
            where s.fpc_id=target_fpc_id and s.packaging_batch_id=b.id),0)
          - coalesce((select sum(r.quantity_kg) from public.stock_reservations r
            where r.fpc_id=target_fpc_id and r.packaging_batch_id=b.id and r.status='reserved'),0) as available
        from public.packaging_batches b
        where b.fpc_id=target_fpc_id and b.status='posted'
          and (nullif(trim(payload->>'item_name'),'') is null or lower(b.product_name)=lower(trim(payload->>'item_name')))
        order by
          case when coalesce(payload->>'allocation_method','fefo')='fefo' then b.expires_on end asc nulls last,
          b.created_at asc
        for update
      loop
        exit when remaining_value <= 0;
        if allocation_row.available > 0 then
          allocated_value := least(remaining_value,allocation_row.available);
          insert into public.sales_order_items(fpc_id,sales_order_id,packaging_batch_id,description,
            quantity,unit,rate,tax_rate,line_total)
          values(target_fpc_id,order_row.id,allocation_row.id,
            coalesce(nullif(payload->>'description',''),allocation_row.product_name),allocated_value,'kg',
            (payload->>'rate')::numeric,coalesce(nullif(payload->>'tax_rate','')::numeric,0),
            round(allocated_value*(payload->>'rate')::numeric*(1+coalesce(nullif(payload->>'tax_rate','')::numeric,0)/100),2));
          insert into public.stock_reservations(fpc_id,sales_order_id,packaging_batch_id,quantity_kg,
            allocation_method,status,created_by)
          values(target_fpc_id,order_row.id,allocation_row.id,allocated_value,
            coalesce(payload->>'allocation_method','fefo'),'reserved',actor_id);
          remaining_value := remaining_value-allocated_value;
        end if;
      end loop;
      if remaining_value > 0 then raise exception 'Insufficient unreserved finished goods stock'; end if;
    end if;
    result := to_jsonb(order_row);

  elsif operation_name = 'cancel_sales_order' then
    select * into order_row from public.sales_orders
    where id=(payload->>'sales_order_id')::uuid and fpc_id=target_fpc_id for update;
    if order_row.status not in ('quotation','confirmed') then
      raise exception 'Only a quotation or confirmed order can be cancelled before invoicing';
    end if;
    if length(trim(coalesce(payload->>'reason',''))) < 4 then raise exception 'A cancellation reason is required'; end if;
    update public.stock_reservations set status='released',updated_at=now()
    where fpc_id=target_fpc_id and sales_order_id=order_row.id and status='reserved';
    update public.sales_orders set status='cancelled',updated_at=now()
    where id=order_row.id returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'invoice_sales_order' then
    select * into order_row from public.sales_orders
    where id=(payload->>'sales_order_id')::uuid and fpc_id=target_fpc_id for update;
    if order_row.status not in ('quotation','confirmed') then raise exception 'Order cannot be invoiced in its current state'; end if;
    doc_number := private.next_fpc_document_number(target_fpc_id,'invoice','INV');
    update public.sales_orders set status='invoiced',invoice_number=doc_number,
      immutable_invoice_snapshot=jsonb_build_object('order',to_jsonb(order_row),
        'items',(select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) from public.sales_order_items i where i.sales_order_id=order_row.id),
        'issued_at',now()),updated_at=now()
    where id=order_row.id returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'cancel_invoiced_order' then
    select * into order_row from public.sales_orders
    where id=(payload->>'sales_order_id')::uuid and fpc_id=target_fpc_id for update;
    if order_row.status <> 'invoiced' then raise exception 'Only an undispatched invoice can be cancelled here'; end if;
    if length(trim(coalesce(payload->>'reason',''))) < 4 then raise exception 'A credit note reason is required'; end if;
    doc_number := private.next_fpc_document_number(target_fpc_id,'credit_note','CN');
    insert into public.sales_credit_notes(fpc_id,sales_order_id,credit_note_number,
      original_invoice_number,reason,amount,immutable_snapshot,issued_by)
    values(target_fpc_id,order_row.id,doc_number,order_row.invoice_number,payload->>'reason',
      order_row.total,jsonb_build_object('order',to_jsonb(order_row),'reason',payload->>'reason',
        'credited_at',now()),actor_id) returning * into saved;
    update public.stock_reservations set status='released',updated_at=now()
    where fpc_id=target_fpc_id and sales_order_id=order_row.id and status='reserved';
    update public.sales_orders set status='cancelled',updated_at=now() where id=order_row.id;
    result := to_jsonb(saved);

  elsif operation_name = 'dispatch_sales_order' then
    select * into order_row from public.sales_orders
    where id=(payload->>'sales_order_id')::uuid and fpc_id=target_fpc_id for update;
    if order_row.status <> 'invoiced' then raise exception 'Invoice the order before dispatch'; end if;
    insert into public.dispatches(fpc_id,sales_order_id,vehicle_number,driver_name,route_notes,
      status,dispatched_at,client_request_id)
    values(target_fpc_id,order_row.id,coalesce(payload->>'vehicle_number',''),
      coalesce(payload->>'driver_name',''),coalesce(payload->>'route_notes',''),
      'dispatched',now(),request_id) returning * into saved;
    for item in select to_jsonb(i) from public.sales_order_items i where i.sales_order_id=order_row.id loop
      select coalesce(sum(s.quantity_kg),0) into available_value from public.stock_ledger s
      where s.fpc_id=target_fpc_id and s.packaging_batch_id=(item->>'packaging_batch_id')::uuid;
      if available_value < (item->>'quantity')::numeric then raise exception 'Finished stock changed before dispatch'; end if;
      insert into public.stock_ledger(fpc_id,packaging_batch_id,movement_type,item_type,item_name,
        quantity_kg,reference_type,reference_id,reason,posted_by)
      values(target_fpc_id,(item->>'packaging_batch_id')::uuid,'dispatch','finished_goods',item->>'description',
        -(item->>'quantity')::numeric,'dispatch',saved.id::text,'Sales dispatch',actor_id);
    end loop;
    update public.stock_reservations set status='fulfilled',updated_at=now()
    where fpc_id=target_fpc_id and sales_order_id=order_row.id and status='reserved';
    update public.sales_orders set status='dispatched',updated_at=now() where id=order_row.id;
    result := to_jsonb(saved);

  elsif operation_name = 'deliver_dispatch' then
    update public.dispatches set status='delivered',delivered_at=now(),
      proof_of_delivery=coalesce(payload->'proof_of_delivery','{}'::jsonb),updated_at=now()
    where id=(payload->>'dispatch_id')::uuid and fpc_id=target_fpc_id and status in ('dispatched','in_transit')
    returning * into saved;
    if saved.id is null then raise exception 'Dispatch cannot be delivered'; end if;
    update public.sales_orders set status='delivered',updated_at=now() where id=saved.sales_order_id;
    perform private.queue_fpc_notification(target_fpc_id,null,'delivery_status',
      'Delivery completed','Dispatch '||saved.id::text||' was marked delivered.',
      jsonb_build_object('dispatch_id',saved.id,'sales_order_id',saved.sales_order_id));
    result := to_jsonb(saved);

  elsif operation_name = 'cancel_dispatch' then
    select * into source_row from public.dispatches
    where id=(payload->>'dispatch_id')::uuid and fpc_id=target_fpc_id for update;
    if source_row.status = 'delivered' then raise exception 'Delivered dispatch cannot be cancelled'; end if;
    if source_row.status in ('dispatched','in_transit') then
      for item in select to_jsonb(s) from public.stock_ledger s
        where s.fpc_id=target_fpc_id and s.reference_type='dispatch' and s.reference_id=source_row.id::text loop
        insert into public.stock_ledger(fpc_id,packaging_batch_id,movement_type,item_type,item_name,
          quantity_kg,reference_type,reference_id,reason,posted_by,reversal_of)
        values(target_fpc_id,nullif(item->>'packaging_batch_id','')::uuid,'dispatch_reversal',
          item->>'item_type',item->>'item_name',abs((item->>'quantity_kg')::numeric),
          'dispatch_cancellation',source_row.id::text,coalesce(payload->>'reason','Dispatch cancelled'),
          actor_id,(item->>'id')::uuid);
      end loop;
    end if;
    update public.dispatches set status='cancelled',updated_at=now() where id=source_row.id returning * into saved;
    update public.stock_reservations set status='released',updated_at=now()
    where fpc_id=target_fpc_id and sales_order_id=source_row.sales_order_id;
    select * into order_row from public.sales_orders
    where id=source_row.sales_order_id and fpc_id=target_fpc_id;
    if coalesce(order_row.invoice_number,'') <> '' and not exists (
      select 1 from public.sales_credit_notes c where c.sales_order_id=order_row.id
    ) then
      doc_number := private.next_fpc_document_number(target_fpc_id,'credit_note','CN');
      insert into public.sales_credit_notes(fpc_id,sales_order_id,credit_note_number,
        original_invoice_number,reason,amount,immutable_snapshot,issued_by)
      values(target_fpc_id,order_row.id,doc_number,order_row.invoice_number,
        coalesce(payload->>'reason','Dispatch cancelled'),order_row.total,
        jsonb_build_object('order',to_jsonb(order_row),'dispatch',to_jsonb(source_row),
          'reason',coalesce(payload->>'reason','Dispatch cancelled'),'credited_at',now()),actor_id);
    end if;
    update public.sales_orders set status='cancelled',updated_at=now() where id=source_row.sales_order_id;
    result := to_jsonb(saved);

  elsif operation_name = 'transition_farmer_payment' then
    select * into payment_row from public.farmer_payment_ledger
    where id=(payload->>'payment_id')::uuid and fpc_id=target_fpc_id for update;
    if payment_row.id is null then raise exception 'Payment entry not found'; end if;
    if not ((payment_row.status='draft' and payload->>'status'='verified')
      or (payment_row.status='verified' and payload->>'status'='approved')
      or (payment_row.status='approved' and payload->>'status'='paid')) then
      raise exception 'Invalid farmer payment transition';
    end if;
    if payload->>'status'='paid' and (length(trim(coalesce(payload->>'payment_reference','')))<3
      or payload->>'payment_mode' not in ('upi','bank_transfer')) then
      raise exception 'Payment mode and transfer reference are required';
    end if;
    update public.farmer_payment_ledger set status=payload->>'status',verified_by=actor_id,
      payment_mode=case when payload->>'status'='paid' then payload->>'payment_mode' else payment_mode end,
      payment_reference=case when payload->>'status'='paid' then payload->>'payment_reference' else payment_reference end,
      payment_proof_path=case when payload->>'status'='paid' then coalesce(payload->>'payment_proof_path','') else payment_proof_path end,
      paid_at=case when payload->>'status'='paid' then now() else paid_at end,updated_at=now()
    where id=payment_row.id returning * into saved;
    perform private.queue_fpc_notification(target_fpc_id,null,'payment_verification',
      'Farmer payment status updated','Payment '||saved.id::text||' is now '||saved.status||'.',
      jsonb_build_object('payment_id',saved.id,'status',saved.status));
    result := to_jsonb(saved);

  elsif operation_name = 'correct_farmer_payment' then
    select * into payment_row from public.farmer_payment_ledger
    where id=(payload->>'payment_id')::uuid and fpc_id=target_fpc_id for update;
    if payment_row.status not in ('verified','approved','paid') then raise exception 'Only issued payments can be corrected'; end if;
    update public.farmer_payment_ledger set status='reversed',updated_at=now() where id=payment_row.id;
    insert into public.farmer_payment_ledger(fpc_id,lot_id,farmer_id,net_weight_kg,rate_per_kg,
      bonus,deductions,status,entry_type,reversal_of,verified_by)
    values(target_fpc_id,payment_row.lot_id,payment_row.farmer_id,-payment_row.net_weight_kg,
      payment_row.rate_per_kg,-payment_row.bonus,-payment_row.deductions,'reversed','reversal',payment_row.id,actor_id);
    insert into public.farmer_payment_ledger(fpc_id,lot_id,farmer_id,net_weight_kg,rate_per_kg,
      bonus,deductions,status,entry_type,supersedes)
    values(target_fpc_id,payment_row.lot_id,payment_row.farmer_id,
      (payload->>'net_weight_kg')::numeric,(payload->>'rate_per_kg')::numeric,
      coalesce(nullif(payload->>'bonus','')::numeric,0),coalesce(nullif(payload->>'deductions','')::numeric,0),
      'draft','replacement',payment_row.id) returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'record_sales_payment' then
    select * into order_row from public.sales_orders
    where id=(payload->>'sales_order_id')::uuid and fpc_id=target_fpc_id for update;
    if order_row.status not in ('delivered','paid') then raise exception 'Only delivered orders can receive payment'; end if;
    insert into public.sales_payment_ledger(fpc_id,sales_order_id,amount,payment_mode,reference,
      proof_path,recorded_by)
    values(target_fpc_id,order_row.id,(payload->>'amount')::numeric,payload->>'payment_mode',
      payload->>'reference',coalesce(payload->>'proof_path',''),actor_id) returning * into saved;
    select coalesce(sum(p.amount),0) into total_value from public.sales_payment_ledger p
    where p.sales_order_id=order_row.id;
    if total_value >= order_row.total then
      update public.sales_orders set status='paid',payment_reference=payload->>'reference',updated_at=now()
      where id=order_row.id;
    end if;
    result := to_jsonb(saved);

  elsif operation_name = 'reverse_sales_payment' then
    select * into payment_row from public.sales_payment_ledger
    where id=(payload->>'sales_payment_id')::uuid and fpc_id=target_fpc_id for update;
    if payment_row.id is null or payment_row.entry_type <> 'receipt' then
      raise exception 'Sales payment receipt not found';
    end if;
    if exists (select 1 from public.sales_payment_ledger p where p.reversal_of=payment_row.id) then
      raise exception 'Sales payment is already reversed';
    end if;
    if length(trim(coalesce(payload->>'reason',''))) < 4 then raise exception 'A reversal reason is required'; end if;
    insert into public.sales_payment_ledger(fpc_id,sales_order_id,amount,payment_mode,reference,
      proof_path,entry_type,reversal_of,recorded_by)
    values(target_fpc_id,payment_row.sales_order_id,-abs(payment_row.amount),payment_row.payment_mode,
      payload->>'reason','', 'reversal',payment_row.id,actor_id) returning * into saved;
    select * into order_row from public.sales_orders where id=payment_row.sales_order_id for update;
    if order_row.status='paid' then
      update public.sales_orders set status='delivered',payment_reference='',updated_at=now()
      where id=order_row.id;
    end if;
    result := to_jsonb(saved);

  elsif operation_name = 'generate_ai_insights' then
    delete from public.ai_insights where fpc_id=target_fpc_id and engine='rules';
    insert into public.ai_insights(fpc_id,insight_type,title,summary,source_period,engine,model_version,confidence,evidence)
    select target_fpc_id,'harvest_forecast','Harvest forecast',
      coalesce(round(sum(coalesce(h.expected_quantity_kg,0)))::text,'0') || ' kg expected from active harvest plans.',
      daterange(current_date,current_date+30,'[]'),'rules','deterministic-v2',0.90,
      jsonb_build_object('plans',count(*),'period_days',30)
    from public.harvest_plans h where h.fpc_id=target_fpc_id and h.readiness<>'cancelled';
    insert into public.ai_insights(fpc_id,insight_type,title,summary,source_period,engine,model_version,confidence,evidence)
    select target_fpc_id,'warehouse_risk','Warehouse risk',
      case when coalesce(sum(w.capacity_kg),0)=0 then 'Warehouse capacity is not configured.'
        when coalesce((select sum(s.quantity_kg) from public.stock_ledger s where s.fpc_id=target_fpc_id),0)
          >= sum(w.capacity_kg)*0.85 then 'Warehouse usage is above 85%. Plan dispatch or additional storage.'
        else 'Warehouse capacity is within the configured operating range.' end,
      daterange(current_date-30,current_date,'[]'),'rules','deterministic-v2',0.95,
      jsonb_build_object('capacity_kg',coalesce(sum(w.capacity_kg),0))
    from public.warehouses w where w.fpc_id=target_fpc_id and w.active;
    insert into public.ai_insights(fpc_id,insight_type,title,summary,source_period,engine,model_version,confidence,evidence)
    select target_fpc_id,'payment_risk','Farmer payment position',count(*)::text || ' farmer payments need verification or approval.',
      daterange(current_date-30,current_date,'[]'),'rules','deterministic-v2',0.99,jsonb_build_object('pending',count(*))
    from public.farmer_payment_ledger p where p.fpc_id=target_fpc_id and p.status in ('draft','verified','approved');
    insert into public.ai_insights(fpc_id,insight_type,title,summary,source_period,engine,model_version,confidence,evidence)
    select target_fpc_id,'market_trend','Demand and market trend',
      coalesce(count(o.id),0)::text || ' orders worth ₹' || coalesce(round(sum(o.total),2),0)::text ||
        ' were recorded in the last 30 days.',daterange(current_date-30,current_date,'[]'),
      'rules','deterministic-v2',0.82,jsonb_build_object('orders',count(o.id),
        'sales_value',coalesce(sum(o.total),0),'average_rate',coalesce((
          select avg(i.rate) from public.sales_order_items i
          join public.sales_orders so on so.id=i.sales_order_id
          where so.fpc_id=target_fpc_id and so.status<>'cancelled' and so.ordered_at>=current_date-30
        ),0))
    from public.sales_orders o
    where o.fpc_id=target_fpc_id and o.status<>'cancelled' and o.ordered_at>=current_date-30;
    insert into public.ai_insights(fpc_id,insight_type,title,summary,source_period,engine,model_version,confidence,evidence)
    select target_fpc_id,'production_optimization','Production optimization',
      case when count(*)=0 then 'No completed production runs are available for optimization.'
        else 'Average recovery is '||round(avg(r.recovery_percent),1)::text||'%. Review runs below this level.' end,
      daterange(current_date-90,current_date,'[]'),'rules','deterministic-v2',0.88,
      jsonb_build_object('runs',count(*),'average_recovery',coalesce(avg(r.recovery_percent),0),
        'waste_kg',coalesce(sum(r.waste_kg),0))
    from public.production_runs r where r.fpc_id=target_fpc_id and r.status='completed'
      and r.completed_at>=current_date-90;
    insert into public.ai_insights(fpc_id,insight_type,title,summary,source_period,engine,model_version,confidence,evidence)
    select target_fpc_id,'executive_recommendation','Executive recommendation',
      case
        when (select count(*) from public.farmer_payment_ledger p where p.fpc_id=target_fpc_id and p.status in ('draft','verified','approved'))>0
          then 'Prioritize farmer payment verification before adding non-essential procurement.'
        when coalesce((select sum(s.quantity_kg) from public.stock_ledger s where s.fpc_id=target_fpc_id),0)>0
          then 'Stock is available. Review demand and dispatch readiness for the next sales cycle.'
        else 'Complete harvest planning and warehouse setup to establish an operating baseline.' end,
      daterange(current_date-30,current_date,'[]'),'rules','deterministic-v2',0.91,
      jsonb_build_object('rule_version','executive-v2');
    for allocation_row in
      select b.id,b.batch_number,b.product_name,b.expires_on,
        coalesce(sum(s.quantity_kg),0) as available
      from public.packaging_batches b
      left join public.stock_ledger s on s.packaging_batch_id=b.id and s.fpc_id=b.fpc_id
      where b.fpc_id=target_fpc_id and b.status='posted'
      group by b.id,b.batch_number,b.product_name,b.expires_on
    loop
      if allocation_row.available > 0 and allocation_row.available < 10
         and not exists (
           select 1 from public.fpc_notifications n
           where n.fpc_id=target_fpc_id and n.event_key='low_stock' and n.read_at is null
             and n.data->>'batch_id'=allocation_row.id::text
         ) then
        perform private.queue_fpc_notification(target_fpc_id,null,'low_stock','Low finished-goods stock',
          allocation_row.product_name||' has '||round(allocation_row.available,2)::text||' kg available.',
          jsonb_build_object('batch_id',allocation_row.id,'available_kg',allocation_row.available));
      end if;
      if allocation_row.available > 0 and allocation_row.expires_on is not null
         and allocation_row.expires_on<=current_date+30
         and not exists (
           select 1 from public.fpc_notifications n
           where n.fpc_id=target_fpc_id and n.event_key='expiry_alert' and n.read_at is null
             and n.data->>'batch_id'=allocation_row.id::text
         ) then
        perform private.queue_fpc_notification(target_fpc_id,null,'expiry_alert','Finished goods nearing expiry',
          allocation_row.product_name||' batch '||allocation_row.batch_number||' expires on '||allocation_row.expires_on::text||'.',
          jsonb_build_object('batch_id',allocation_row.id,'expires_on',allocation_row.expires_on));
      end if;
    end loop;
    result := jsonb_build_object('generated',6,'engine','rules','model_version','deterministic-v2');

  elsif operation_name = 'record_report_export' then
    insert into public.fpc_report_exports(fpc_id,report_type,format,parameters,file_name,
      storage_path,row_count,generated_by)
    values(target_fpc_id,payload->>'report_type',payload->>'format',coalesce(payload->'parameters','{}'::jsonb),
      payload->>'file_name',coalesce(payload->>'storage_path',''),
      coalesce(nullif(payload->>'row_count','')::integer,0),actor_id) returning * into saved;
    result := to_jsonb(saved);

  elsif operation_name = 'create_notification' then
    result := jsonb_build_object('notification_id',private.queue_fpc_notification(
      target_fpc_id,nullif(payload->>'recipient_user_id','')::uuid,payload->>'event_key',
      payload->>'title',payload->>'body',coalesce(payload->'data','{}'::jsonb)));

  else
    raise exception 'Unsupported FPC operation: %', operation_name;
  end if;

  perform private.record_fpc_audit(target_fpc_id,operation_name,
    coalesce(payload->>'target_type',operation_name),coalesce(result->>'id',''),
    '{}'::jsonb,result,request_id);
  insert into private.fpc_operation_requests(fpc_id,client_request_id,operation,response)
  values(target_fpc_id,request_id,operation_name,result);
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
  select private.execute_fpc_operation(operation_name,payload,client_request_id);
$$;

revoke all on function private.next_fpc_document_number(uuid,text,text) from public, anon, authenticated;
revoke all on function private.record_fpc_audit(uuid,text,text,text,jsonb,jsonb,uuid) from public, anon, authenticated;
revoke all on function private.queue_fpc_notification(uuid,uuid,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function private.execute_fpc_operation(text,jsonb,uuid) from public, anon, authenticated;
revoke all on function private.audit_fpc_row_change() from public, anon, authenticated;
revoke all on function private.notify_field_assignment() from public, anon, authenticated;
revoke all on function private.enforce_fpc_farmer_limit() from public, anon, authenticated;
revoke all on function private.audit_platform_row_change() from public, anon, authenticated;
revoke all on function private.guard_fpc_immutable_rows() from public, anon, authenticated;
revoke all on function private.link_received_lot_to_schedule() from public, anon, authenticated;
revoke all on function public.fpc_execute_operation(text,jsonb,uuid) from public, anon;
revoke all on function private.is_assigned_field_work(uuid,uuid) from public, anon;
grant execute on function private.is_assigned_field_work(uuid,uuid) to authenticated;
revoke all on function private.is_assigned_field_farm(uuid) from public, anon;
grant execute on function private.is_assigned_field_farm(uuid) to authenticated;
revoke all on function private.can_read_linked_fpc_farm(uuid) from public, anon;
grant execute on function private.can_read_linked_fpc_farm(uuid) to authenticated;
grant execute on function public.fpc_execute_operation(text,jsonb,uuid) to authenticated;
