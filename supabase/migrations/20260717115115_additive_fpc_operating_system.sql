create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.fpcs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text not null default '',
  registration_number text not null default '',
  gstin text not null default '',
  phone text not null default '',
  email text not null default '',
  address jsonb not null default '{}'::jsonb,
  branding jsonb not null default '{}'::jsonb,
  limits jsonb not null default '{}'::jsonb,
  status text not null default 'active'
    check (status in ('pending', 'active', 'suspended', 'inactive')),
  legacy_owner_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.fpc_registration_applications (
  id uuid primary key default gen_random_uuid(),
  applicant_user_id uuid references auth.users(id) on delete set null,
  email text not null,
  display_name text not null,
  organization_name text not null,
  phone text not null,
  legal_details jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'under_review', 'approved', 'rejected')),
  admin_note text not null default '',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  approved_fpc_id uuid references public.fpcs(id) on delete set null,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists fpc_registration_pending_email_idx
  on public.fpc_registration_applications(lower(email))
  where status in ('pending', 'under_review');

create table if not exists public.fpc_memberships (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('fpc_admin', 'field_officer')),
  status text not null default 'active'
    check (status in ('active', 'disabled')),
  must_change_password boolean not null default false,
  display_name text not null default '',
  email text not null default '',
  phone text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(fpc_id, user_id)
);

create unique index if not exists fpc_memberships_active_user_idx
  on public.fpc_memberships(user_id) where status = 'active';

create table if not exists public.fpc_subscriptions (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  plan_code text not null default 'managed-prototype',
  status text not null default 'active'
    check (status in ('trial', 'active', 'past_due', 'suspended', 'cancelled')),
  starts_on date not null default current_date,
  ends_on date,
  amount numeric(14,2) not null default 0 check (amount >= 0),
  tax_rate numeric(5,2) not null default 18 check (tax_rate between 0 and 100),
  limits jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.fpc_subscription_invoices (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  subscription_id uuid references public.fpc_subscriptions(id) on delete set null,
  invoice_number text not null unique,
  issued_on date not null default current_date,
  subtotal numeric(14,2) not null default 0,
  cgst numeric(14,2) not null default 0,
  sgst numeric(14,2) not null default 0,
  igst numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  status text not null default 'issued'
    check (status in ('draft', 'issued', 'paid', 'void')),
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.platform_settings (
  key text primary key,
  category text not null,
  enabled boolean not null default false,
  config jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.notification_templates (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  title_template text not null,
  body_template text not null,
  channels text[] not null default array['in_app']::text[],
  enabled boolean not null default true,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid references public.fpcs(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role text not null default '',
  action text not null,
  target_type text not null,
  target_id text not null default '',
  before_data jsonb not null default '{}'::jsonb,
  after_data jsonb not null default '{}'::jsonb,
  correlation_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists public.fpc_farmer_links (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  farmer_id text not null,
  farmer_phone text not null default '',
  farmer_name text not null default '',
  farm_id text not null default '',
  farm_name text not null default '',
  village text not null default '',
  crop text not null default '',
  kyc_status text not null default 'verified',
  status text not null default 'active' check (status in ('active', 'inactive')),
  source_payload jsonb not null default '{}'::jsonb,
  linked_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(fpc_id, farmer_id)
);

create table if not exists public.harvest_plans (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  farmer_link_id uuid references public.fpc_farmer_links(id) on delete set null,
  farm_id text not null default '',
  crop text not null,
  village text not null default '',
  expected_harvest_date date,
  expected_quantity_kg numeric(14,3) check (expected_quantity_kg >= 0),
  expected_grade text not null default '',
  readiness text not null default 'planned',
  priority text not null default 'normal',
  assigned_to uuid references auth.users(id) on delete set null,
  notes text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.collection_centers (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  name text not null,
  village text not null default '',
  address text not null default '',
  capacity_kg numeric(14,3) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.procurement_schedules (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  harvest_plan_id uuid references public.harvest_plans(id) on delete set null,
  collection_center_id uuid references public.collection_centers(id) on delete set null,
  scheduled_at timestamptz not null,
  status text not null default 'scheduled'
    check (status in ('planned', 'scheduled', 'in_collection', 'quality_review', 'lot_created', 'warehoused', 'completed', 'cancelled')),
  assigned_officer_id uuid references auth.users(id) on delete set null,
  vehicle_details jsonb not null default '{}'::jsonb,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vehicle_assignments (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  procurement_schedule_id uuid references public.procurement_schedules(id) on delete cascade,
  vehicle_number text not null,
  driver_name text not null default '',
  driver_phone text not null default '',
  route_notes text not null default '',
  status text not null default 'assigned',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.field_assignments (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  officer_user_id uuid not null references auth.users(id) on delete cascade,
  assignment_type text not null,
  farmer_id text not null default '',
  farm_id text not null default '',
  title text not null,
  instructions text not null default '',
  scheduled_for timestamptz,
  status text not null default 'assigned'
    check (status in ('assigned', 'in_progress', 'completed', 'cancelled')),
  server_version integer not null default 1,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.field_visits (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  assignment_id uuid references public.field_assignments(id) on delete set null,
  officer_user_id uuid not null references auth.users(id) on delete cascade,
  client_uuid uuid not null,
  server_version integer not null default 1,
  farmer_id text not null default '',
  farm_id text not null default '',
  visit_type text not null,
  crop_stage text not null default '',
  expected_harvest_date date,
  estimated_quantity_kg numeric(14,3),
  expected_grade text not null default '',
  readiness text not null default '',
  recommendation text not null default '',
  notes text not null default '',
  photos text[] not null default '{}'::text[],
  check_in jsonb not null default '{}'::jsonb,
  check_out jsonb not null default '{}'::jsonb,
  sync_status text not null default 'synced',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(officer_user_id, client_uuid)
);

-- The receiver service shipped before this table reached every live project.
-- Keep the original actor-scoped columns so older app builds remain compatible.
create table if not exists public.fpc_procurement_records (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null,
  farmer_id text,
  farm_id text,
  analysis_id uuid references public.analysis_jobs(id) on delete set null,
  batch_id text,
  customer_name text not null default '',
  crop_type text not null default '',
  variety text not null default '',
  quantity_kg numeric,
  grade text,
  price_per_kg numeric,
  total_value numeric,
  delivery_status text not null default 'received'
    check (delivery_status in ('received', 'graded', 'stored', 'sold', 'returned')),
  fpc_rating integer check (fpc_rating between 1 and 5),
  rating_notes text not null default '',
  trace_payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists fpc_procurement_records_fpc_created_idx
  on public.fpc_procurement_records(fpc_id, created_at desc);
create index if not exists fpc_procurement_records_farmer_farm_idx
  on public.fpc_procurement_records(farmer_id, farm_id);

alter table public.fpc_procurement_records enable row level security;
grant select, insert, update on public.fpc_procurement_records to authenticated;

create table if not exists public.procurement_lots (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  receipt_id uuid,
  batch_id text not null,
  traceability_code text not null,
  farmer_id text not null default '',
  farm_id text not null default '',
  crop text not null,
  variety text not null default '',
  bags integer not null default 0 check (bags >= 0),
  gross_weight_kg numeric(14,3) not null default 0,
  net_weight_kg numeric(14,3) not null default 0,
  moisture_percent numeric(6,2),
  grade text not null default '',
  status text not null default 'received',
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(fpc_id, batch_id)
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'procurement_lots_receipt_fk'
      and conrelid = 'public.procurement_lots'::regclass
  ) then
    alter table public.procurement_lots
      add constraint procurement_lots_receipt_fk
      foreign key (receipt_id) references public.fpc_procurement_records(id) on delete set null;
  end if;
end $$;

create table if not exists public.quality_certificates (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  lot_id uuid not null references public.procurement_lots(id) on delete restrict,
  analysis_job_id uuid references public.analysis_jobs(id) on delete set null,
  certificate_number text not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'rejected')),
  grade text not null default '',
  results jsonb not null default '{}'::jsonb,
  immutable_snapshot jsonb not null default '{}'::jsonb,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique(fpc_id, certificate_number)
);

create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  name text not null,
  address text not null default '',
  capacity_kg numeric(14,3) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.warehouse_locations (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  warehouse_id uuid not null references public.warehouses(id) on delete cascade,
  code text not null,
  location_type text not null default 'bin',
  capacity_kg numeric(14,3) not null default 0,
  active boolean not null default true,
  unique(warehouse_id, code)
);

create table if not exists public.stock_ledger (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  warehouse_id uuid references public.warehouses(id) on delete restrict,
  location_id uuid references public.warehouse_locations(id) on delete restrict,
  lot_id uuid references public.procurement_lots(id) on delete restrict,
  packaging_batch_id uuid,
  movement_type text not null,
  item_type text not null,
  item_name text not null,
  quantity_kg numeric(14,3) not null,
  occurred_at timestamptz not null default now(),
  reference_type text not null default '',
  reference_id text not null default '',
  reason text not null default '',
  posted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.production_runs (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  run_number text not null,
  process_type text not null check (process_type in ('millet', 'rice')),
  input_lot_id uuid references public.procurement_lots(id) on delete restrict,
  input_kg numeric(14,3) not null default 0,
  output_kg numeric(14,3) not null default 0,
  waste_kg numeric(14,3) not null default 0,
  stages jsonb not null default '[]'::jsonb,
  machine text not null default '',
  operator_name text not null default '',
  status text not null default 'planned'
    check (status in ('planned', 'in_progress', 'completed', 'cancelled')),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(fpc_id, run_number)
);

create table if not exists public.packaging_batches (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  production_run_id uuid references public.production_runs(id) on delete restrict,
  batch_number text not null,
  product_name text not null,
  package_size_grams integer not null check (package_size_grams in (500, 1000, 5000, 10000, 25000, 50000)),
  package_count integer not null default 0 check (package_count >= 0),
  total_weight_kg numeric(14,3) not null default 0,
  qr_payload jsonb not null default '{}'::jsonb,
  barcode_value text not null default '',
  manufactured_on date not null default current_date,
  expires_on date,
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(fpc_id, batch_number)
);

alter table public.stock_ledger
  add constraint stock_ledger_packaging_batch_fk
  foreign key (packaging_batch_id) references public.packaging_batches(id) on delete restrict;

create table if not exists public.buyers (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  buyer_type text not null check (buyer_type in ('retail', 'distributor', 'government', 'export', 'institutional')),
  name text not null,
  phone text not null default '',
  email text not null default '',
  gstin text not null default '',
  address jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  buyer_id uuid not null references public.buyers(id) on delete restrict,
  order_number text not null,
  quotation_number text not null default '',
  invoice_number text not null default '',
  status text not null default 'quotation'
    check (status in ('quotation', 'confirmed', 'invoiced', 'dispatched', 'delivered', 'paid', 'cancelled')),
  subtotal numeric(14,2) not null default 0,
  cgst numeric(14,2) not null default 0,
  sgst numeric(14,2) not null default 0,
  igst numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  immutable_invoice_snapshot jsonb not null default '{}'::jsonb,
  payment_reference text not null default '',
  ordered_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(fpc_id, order_number)
);

create table if not exists public.sales_order_items (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  sales_order_id uuid not null references public.sales_orders(id) on delete cascade,
  packaging_batch_id uuid references public.packaging_batches(id) on delete restrict,
  description text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit text not null default 'kg',
  rate numeric(14,2) not null default 0,
  tax_rate numeric(5,2) not null default 0,
  line_total numeric(14,2) not null default 0
);

create table if not exists public.dispatches (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  sales_order_id uuid not null references public.sales_orders(id) on delete restrict,
  vehicle_number text not null default '',
  driver_name text not null default '',
  route_notes text not null default '',
  status text not null default 'planned'
    check (status in ('planned', 'dispatched', 'in_transit', 'delivered', 'cancelled')),
  proof_of_delivery jsonb not null default '{}'::jsonb,
  dispatched_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.farmer_payment_ledger (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  lot_id uuid not null references public.procurement_lots(id) on delete restrict,
  farmer_id text not null,
  net_weight_kg numeric(14,3) not null,
  rate_per_kg numeric(14,2) not null,
  bonus numeric(14,2) not null default 0,
  deductions numeric(14,2) not null default 0,
  final_amount numeric(14,2) generated always as
    (round((net_weight_kg * rate_per_kg + bonus - deductions)::numeric, 2)) stored,
  status text not null default 'draft'
    check (status in ('draft', 'verified', 'approved', 'paid', 'reversed')),
  payment_mode text not null default '' check (payment_mode in ('', 'upi', 'bank_transfer')),
  payment_reference text not null default '',
  payment_proof_path text not null default '',
  reversal_of uuid references public.farmer_payment_ledger(id) on delete restrict,
  verified_by uuid references auth.users(id) on delete set null,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists farmer_payment_active_lot_idx
  on public.farmer_payment_ledger(lot_id)
  where reversal_of is null and status <> 'reversed';

create unique index if not exists stock_ledger_reference_movement_idx
  on public.stock_ledger(fpc_id, reference_type, reference_id, movement_type)
  where reference_id <> '';

create table if not exists public.fpc_notifications (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  recipient_user_id uuid references auth.users(id) on delete cascade,
  event_key text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid references public.fpcs(id) on delete cascade,
  notification_id uuid references public.fpc_notifications(id) on delete cascade,
  channel text not null check (channel in ('in_app', 'sms', 'whatsapp')),
  recipient text not null default '',
  status text not null default 'pending'
    check (status in ('pending', 'disabled', 'sent', 'failed')),
  attempt_count integer not null default 0,
  last_error text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ai_insights (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  insight_type text not null,
  title text not null,
  summary text not null,
  source_period daterange,
  engine text not null default 'rules',
  model_version text not null default 'deterministic-v1',
  confidence numeric(5,4) check (confidence between 0 and 1),
  evidence jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default now()
);

create table if not exists public.fpc_operational_records (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  module text not null check (module in (
    'farmer_network', 'farm_monitoring', 'harvest_planning', 'procurement',
    'collection_center', 'quality', 'warehouse', 'production', 'packaging',
    'inventory', 'sales', 'logistics', 'farmer_payments', 'reports', 'ai_insights'
  )),
  record_type text not null,
  title text not null,
  status text not null default 'active',
  scheduled_at timestamptz,
  quantity numeric(14,3),
  amount numeric(14,2),
  assigned_to uuid references auth.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  client_uuid uuid,
  server_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(fpc_id, client_uuid)
);

alter table public.role_account_profiles
  add column if not exists fpc_id uuid references public.fpcs(id) on delete set null;

alter table public.role_account_profiles
  drop constraint if exists role_account_profiles_role_check;
alter table public.role_account_profiles
  add constraint role_account_profiles_role_check
  check (role in ('admin', 'fpc', 'fpc_admin', 'field_officer'));

alter table public.fpc_procurement_records
  add column if not exists fpc_organization_id uuid references public.fpcs(id) on delete set null,
  add column if not exists client_request_id uuid,
  add column if not exists gross_weight_kg numeric(14,3),
  add column if not exists net_weight_kg numeric(14,3),
  add column if not exists bags integer,
  add column if not exists moisture_percent numeric(6,2),
  add column if not exists receipt_number text;

create unique index if not exists fpc_procurement_org_batch_idx
  on public.fpc_procurement_records(fpc_organization_id, batch_id)
  where fpc_organization_id is not null and batch_id is not null;

alter table public.analysis_jobs
  add column if not exists fpc_organization_id uuid references public.fpcs(id) on delete set null,
  add column if not exists procurement_lot_id uuid references public.procurement_lots(id) on delete set null;

insert into public.fpcs(name, email, phone, status, legacy_owner_user_id)
select p.organization_name, p.email, coalesce(p.phone, ''), 'active', p.user_id
from public.role_account_profiles p
where p.role = 'fpc'
  and not exists (
    select 1 from public.fpcs f where f.legacy_owner_user_id = p.user_id
  );

insert into public.fpc_memberships(fpc_id, user_id, role, status, display_name, email, phone)
select f.id, p.user_id, 'fpc_admin',
  case when p.status = 'active' then 'active' else 'disabled' end,
  p.display_name, p.email, coalesce(p.phone, '')
from public.role_account_profiles p
join public.fpcs f on f.legacy_owner_user_id = p.user_id
where p.role = 'fpc'
on conflict (fpc_id, user_id) do nothing;

update public.role_account_profiles p
set fpc_id = f.id
from public.fpcs f
where f.legacy_owner_user_id = p.user_id
  and p.fpc_id is null;

update public.fpc_procurement_records r
set fpc_organization_id = m.fpc_id
from public.fpc_memberships m
where r.fpc_id = m.user_id
  and r.fpc_organization_id is null;

update public.analysis_jobs j
set fpc_organization_id = m.fpc_id
from public.fpc_memberships m
where j.fpc_id = m.user_id
  and j.fpc_organization_id is null;

create or replace function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_server_role(array['admin']);
$$;

create or replace function private.active_fpc_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.fpc_id
  from public.fpc_memberships m
  join public.fpcs f on f.id = m.fpc_id
  where m.user_id = auth.uid()
    and m.status = 'active'
    and f.status = 'active'
  limit 1;
$$;

create or replace function private.has_fpc_role(required_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.fpc_memberships m
    join public.fpcs f on f.id = m.fpc_id
    where m.user_id = auth.uid()
      and m.status = 'active'
      and f.status = 'active'
      and m.role = any(required_roles)
  );
$$;

create or replace function private.can_access_fpc(requested_fpc_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_platform_admin()
    or requested_fpc_id = private.active_fpc_id();
$$;

create or replace function private.can_manage_fpc(requested_fpc_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select requested_fpc_id = private.active_fpc_id()
    and private.has_fpc_role(array['fpc_admin']);
$$;

grant usage on schema private to authenticated;
grant execute on function private.is_platform_admin() to authenticated;
grant execute on function private.active_fpc_id() to authenticated;
grant execute on function private.has_fpc_role(text[]) to authenticated;
grant execute on function private.can_access_fpc(uuid) to authenticated;
grant execute on function private.can_manage_fpc(uuid) to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'fpcs', 'fpc_registration_applications', 'fpc_memberships',
    'fpc_subscriptions', 'fpc_subscription_invoices', 'platform_settings',
    'notification_templates', 'audit_events', 'fpc_farmer_links',
    'harvest_plans', 'collection_centers', 'procurement_schedules',
    'vehicle_assignments', 'field_assignments', 'field_visits',
    'procurement_lots', 'quality_certificates', 'warehouses',
    'warehouse_locations', 'stock_ledger', 'production_runs',
    'packaging_batches', 'buyers', 'sales_orders', 'sales_order_items',
    'dispatches', 'farmer_payment_ledger', 'fpc_notifications',
    'notification_outbox', 'ai_insights', 'fpc_operational_records'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
  end loop;
end $$;

create policy "platform admin and members read fpcs"
on public.fpcs for select to authenticated
using (private.can_access_fpc(id));
create policy "platform admins manage fpcs"
on public.fpcs for all to authenticated
using (private.is_platform_admin()) with check (private.is_platform_admin());

create policy "platform admins read applications"
on public.fpc_registration_applications for select to authenticated
using (private.is_platform_admin());
create policy "platform admins review applications"
on public.fpc_registration_applications for update to authenticated
using (private.is_platform_admin()) with check (private.is_platform_admin());

create policy "members read own organization memberships"
on public.fpc_memberships for select to authenticated
using (private.is_platform_admin() or user_id = auth.uid() or private.can_manage_fpc(fpc_id));
create policy "platform admins manage memberships"
on public.fpc_memberships for all to authenticated
using (private.is_platform_admin()) with check (private.is_platform_admin());

create policy "platform users read subscriptions"
on public.fpc_subscriptions for select to authenticated
using (private.can_access_fpc(fpc_id));
create policy "platform admins manage subscriptions"
on public.fpc_subscriptions for all to authenticated
using (private.is_platform_admin()) with check (private.is_platform_admin());
create policy "platform users read subscription invoices"
on public.fpc_subscription_invoices for select to authenticated
using (private.can_access_fpc(fpc_id));
create policy "platform admins manage subscription invoices"
on public.fpc_subscription_invoices for all to authenticated
using (private.is_platform_admin()) with check (private.is_platform_admin());

create policy "platform admins manage settings"
on public.platform_settings for all to authenticated
using (private.is_platform_admin()) with check (private.is_platform_admin());
create policy "platform admins manage templates"
on public.notification_templates for all to authenticated
using (private.is_platform_admin()) with check (private.is_platform_admin());

create policy "authorized users read audit"
on public.audit_events for select to authenticated
using (private.is_platform_admin() or (fpc_id is not null and private.can_access_fpc(fpc_id)));
create policy "users append own audit events"
on public.audit_events for insert to authenticated
with check (actor_user_id = auth.uid() and (fpc_id is null or private.can_access_fpc(fpc_id)));

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'fpc_farmer_links', 'harvest_plans', 'collection_centers',
    'procurement_schedules', 'vehicle_assignments', 'procurement_lots',
    'quality_certificates', 'warehouses', 'warehouse_locations',
    'production_runs', 'packaging_batches', 'buyers', 'sales_orders',
    'sales_order_items', 'dispatches', 'farmer_payment_ledger',
    'notification_outbox', 'ai_insights', 'fpc_operational_records'
  ] loop
    execute format(
      'create policy "tenant read" on public.%I for select to authenticated using (private.can_access_fpc(fpc_id))',
      table_name
    );
    execute format(
      'create policy "fpc admin insert" on public.%I for insert to authenticated with check (private.can_manage_fpc(fpc_id))',
      table_name
    );
    execute format(
      'create policy "fpc admin update" on public.%I for update to authenticated using (private.can_manage_fpc(fpc_id)) with check (private.can_manage_fpc(fpc_id))',
      table_name
    );
    execute format(
      'create policy "fpc admin delete" on public.%I for delete to authenticated using (private.can_manage_fpc(fpc_id))',
      table_name
    );
  end loop;
end $$;

drop policy if exists "fpc admin update" on public.stock_ledger;
drop policy if exists "fpc admin delete" on public.stock_ledger;

create policy "field users read assignments"
on public.field_assignments for select to authenticated
using (private.can_manage_fpc(fpc_id) or officer_user_id = auth.uid() or private.is_platform_admin());
create policy "fpc admins manage assignments"
on public.field_assignments for all to authenticated
using (private.can_manage_fpc(fpc_id)) with check (private.can_manage_fpc(fpc_id));
create policy "field users update assigned work"
on public.field_assignments for update to authenticated
using (officer_user_id = auth.uid())
with check (officer_user_id = auth.uid() and fpc_id = private.active_fpc_id());

create policy "field users read visits"
on public.field_visits for select to authenticated
using (private.can_manage_fpc(fpc_id) or officer_user_id = auth.uid() or private.is_platform_admin());
create policy "field users create visits"
on public.field_visits for insert to authenticated
with check (officer_user_id = auth.uid() and fpc_id = private.active_fpc_id());
create policy "field users update visits"
on public.field_visits for update to authenticated
using (officer_user_id = auth.uid())
with check (officer_user_id = auth.uid() and fpc_id = private.active_fpc_id());
create policy "fpc admins manage visits"
on public.field_visits for all to authenticated
using (private.can_manage_fpc(fpc_id)) with check (private.can_manage_fpc(fpc_id));

create policy "notification recipients read"
on public.fpc_notifications for select to authenticated
using (
  private.is_platform_admin()
  or recipient_user_id = auth.uid()
  or (recipient_user_id is null and private.can_access_fpc(fpc_id))
);
create policy "fpc admins create notifications"
on public.fpc_notifications for insert to authenticated
with check (private.can_manage_fpc(fpc_id));
create policy "notification recipients mark read"
on public.fpc_notifications for update to authenticated
using (recipient_user_id = auth.uid() or private.can_manage_fpc(fpc_id))
with check (recipient_user_id = auth.uid() or private.can_manage_fpc(fpc_id));

drop policy if exists "fpc users can read own procurement records" on public.fpc_procurement_records;
drop policy if exists "fpc users can create own procurement records" on public.fpc_procurement_records;
drop policy if exists "fpc users can update own procurement records" on public.fpc_procurement_records;
create policy "tenant users read procurement records"
on public.fpc_procurement_records for select to authenticated
using (
  private.is_platform_admin()
  or (fpc_organization_id is not null and private.can_access_fpc(fpc_organization_id))
  or (fpc_organization_id is null and fpc_id = auth.uid())
);
create policy "fpc admins create procurement records"
on public.fpc_procurement_records for insert to authenticated
with check (
  (fpc_organization_id is not null and private.can_manage_fpc(fpc_organization_id))
  or (fpc_organization_id is null and fpc_id = auth.uid())
);
create policy "fpc admins update procurement records"
on public.fpc_procurement_records for update to authenticated
using (
  (fpc_organization_id is not null and private.can_manage_fpc(fpc_organization_id))
  or (fpc_organization_id is null and fpc_id = auth.uid())
)
with check (
  (fpc_organization_id is not null and private.can_manage_fpc(fpc_organization_id))
  or (fpc_organization_id is null and fpc_id = auth.uid())
);

drop policy if exists "fpo admins can read grading review jobs" on public.analysis_jobs;
drop policy if exists "fpo admins can update grading review jobs" on public.analysis_jobs;
create policy "tenant users read grading review jobs"
on public.analysis_jobs for select to authenticated
using (
  private.is_platform_admin()
  or actor_role <> 'fpc'
  or (fpc_organization_id is not null and private.can_access_fpc(fpc_organization_id))
  or (fpc_organization_id is null and fpc_id = auth.uid())
);
create policy "fpc admins update grading review jobs"
on public.analysis_jobs for update to authenticated
using (
  private.is_platform_admin()
  or (fpc_organization_id is not null and private.can_manage_fpc(fpc_organization_id))
  or (fpc_organization_id is null and fpc_id = auth.uid())
)
with check (
  private.is_platform_admin()
  or (fpc_organization_id is not null and private.can_manage_fpc(fpc_organization_id))
  or (fpc_organization_id is null and fpc_id = auth.uid())
);

create or replace function public.link_farmer_to_current_fpc(payload jsonb)
returns public.fpc_farmer_links
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  target_fpc_id uuid := private.active_fpc_id();
  saved public.fpc_farmer_links;
begin
  if target_fpc_id is null then
    raise exception 'No active FPC membership';
  end if;
  insert into public.fpc_farmer_links(
    fpc_id, farmer_id, farmer_phone, farmer_name, farm_id, farm_name,
    village, crop, kyc_status, status, source_payload, linked_by
  ) values (
    target_fpc_id,
    nullif(trim(payload->>'farmerId'), ''),
    coalesce(payload->>'phone', ''),
    coalesce(payload->>'name', ''),
    coalesce(payload->>'farmId', ''),
    coalesce(payload->>'primaryFarm', ''),
    coalesce(payload->>'village', ''),
    coalesce(payload->>'crop', ''),
    'verified', 'active', payload, auth.uid()
  )
  on conflict (fpc_id, farmer_id) do update set
    farmer_phone = excluded.farmer_phone,
    farmer_name = excluded.farmer_name,
    farm_id = excluded.farm_id,
    farm_name = excluded.farm_name,
    village = excluded.village,
    crop = excluded.crop,
    source_payload = excluded.source_payload,
    status = 'active',
    updated_at = now()
  returning * into saved;
  return saved;
end;
$$;

grant execute on function public.link_farmer_to_current_fpc(jsonb) to authenticated;

create or replace function public.receive_fpc_harvest(
  trace_payload jsonb,
  price_per_kg numeric default null,
  fpc_rating integer default null,
  rating_notes text default ''
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  target_fpc_id uuid := private.active_fpc_id();
  actor_id uuid := auth.uid();
  batch text := trim(coalesce(trace_payload->>'batchId', ''));
  quantity numeric := nullif(regexp_replace(coalesce(trace_payload->>'totalKg', ''), '[^0-9.-]', '', 'g'), '')::numeric;
  moisture numeric := nullif(regexp_replace(coalesce(trace_payload->>'moisture', ''), '[^0-9.-]', '', 'g'), '')::numeric;
  bag_count integer := nullif(regexp_replace(coalesce(trace_payload->>'bagCount', ''), '[^0-9]', '', 'g'), '')::integer;
  analysis uuid := case
    when coalesce(trace_payload->>'analysisId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then (trace_payload->>'analysisId')::uuid else null end;
  receipt public.fpc_procurement_records;
  lot public.procurement_lots;
begin
  if target_fpc_id is null or not private.can_manage_fpc(target_fpc_id) then
    raise exception 'Active FPC Admin membership required';
  end if;
  if batch = '' then raise exception 'Harvest batch ID is required'; end if;

  select * into receipt
  from public.fpc_procurement_records r
  where r.fpc_organization_id = target_fpc_id and r.batch_id = batch
  limit 1;

  if receipt.id is null then
    insert into public.fpc_procurement_records(
      fpc_id, fpc_organization_id, farmer_id, farm_id, analysis_id, batch_id,
      customer_name, crop_type, variety, quantity_kg, gross_weight_kg,
      net_weight_kg, bags, moisture_percent, grade, price_per_kg, total_value,
      delivery_status, fpc_rating, rating_notes, trace_payload, receipt_number,
      received_at
    ) values (
      actor_id, target_fpc_id, trace_payload->>'farmerId', trace_payload->>'farmId',
      analysis, batch, coalesce(trace_payload->>'farmerName', trace_payload->>'fpcCustomerName', ''),
      coalesce(trace_payload->>'crop', ''), coalesce(trace_payload->>'variety', ''),
      quantity, quantity, quantity, bag_count, moisture, coalesce(trace_payload->>'grade', ''),
      price_per_kg, case when quantity is not null and price_per_kg is not null then quantity * price_per_kg end,
      'received', fpc_rating, coalesce(rating_notes, ''), trace_payload,
      'RCPT-' || to_char(now(), 'YYYYMMDD') || '-' || upper(right(replace(batch, '-', ''), 8)),
      now()
    ) returning * into receipt;
  else
    update public.fpc_procurement_records r set
      fpc_id = actor_id,
      analysis_id = analysis,
      customer_name = coalesce(trace_payload->>'farmerName', trace_payload->>'fpcCustomerName', ''),
      quantity_kg = quantity,
      gross_weight_kg = quantity,
      net_weight_kg = quantity,
      bags = bag_count,
      moisture_percent = moisture,
      grade = coalesce(trace_payload->>'grade', ''),
      price_per_kg = receive_fpc_harvest.price_per_kg,
      total_value = case when quantity is not null and receive_fpc_harvest.price_per_kg is not null then quantity * receive_fpc_harvest.price_per_kg end,
      fpc_rating = receive_fpc_harvest.fpc_rating,
      rating_notes = coalesce(receive_fpc_harvest.rating_notes, ''),
      trace_payload = receive_fpc_harvest.trace_payload,
      updated_at = now()
    where r.id = receipt.id returning * into receipt;
  end if;

  insert into public.procurement_lots(
    fpc_id, receipt_id, batch_id, traceability_code, farmer_id, farm_id, crop,
    variety, bags, gross_weight_kg, net_weight_kg, moisture_percent, grade, status
  ) values (
    target_fpc_id, receipt.id, batch, batch, coalesce(trace_payload->>'farmerId', ''),
    coalesce(trace_payload->>'farmId', ''), coalesce(trace_payload->>'crop', ''),
    coalesce(trace_payload->>'variety', ''), coalesce(bag_count, 0), coalesce(quantity, 0),
    coalesce(quantity, 0), moisture, coalesce(trace_payload->>'grade', ''), 'received'
  )
  on conflict (fpc_id, batch_id) do update set
    receipt_id = excluded.receipt_id,
    bags = excluded.bags,
    gross_weight_kg = excluded.gross_weight_kg,
    net_weight_kg = excluded.net_weight_kg,
    moisture_percent = excluded.moisture_percent,
    grade = excluded.grade,
    updated_at = now()
  returning * into lot;

  if not exists (
    select 1 from public.stock_ledger s
    where s.fpc_id = target_fpc_id and s.reference_type = 'procurement_lot'
      and s.reference_id = lot.id::text and s.movement_type = 'receipt'
  ) then
    insert into public.stock_ledger(
      fpc_id, lot_id, movement_type, item_type, item_name, quantity_kg,
      reference_type, reference_id, reason, posted_by
    ) values (
      target_fpc_id, lot.id, 'receipt', 'raw_material', coalesce(trace_payload->>'crop', 'Grain'),
      coalesce(quantity, 0), 'procurement_lot', lot.id::text, 'Harvest receiver intake', actor_id
    );
  end if;

  if price_per_kg is not null and quantity is not null then
    if exists (
      select 1 from public.farmer_payment_ledger p
      where p.lot_id = lot.id and p.reversal_of is null and p.status <> 'reversed'
    ) then
      update public.farmer_payment_ledger p set
        net_weight_kg = quantity,
        rate_per_kg = receive_fpc_harvest.price_per_kg,
        updated_at = now()
      where p.lot_id = lot.id and p.reversal_of is null and p.status = 'draft';
    else
      insert into public.farmer_payment_ledger(
        fpc_id, lot_id, farmer_id, net_weight_kg, rate_per_kg, status
      ) values (
        target_fpc_id, lot.id, coalesce(trace_payload->>'farmerId', ''), quantity,
        receive_fpc_harvest.price_per_kg, 'draft'
      );
    end if;
  end if;

  update public.analysis_jobs
  set fpc_organization_id = target_fpc_id, procurement_lot_id = lot.id
  where id = analysis;

  insert into public.audit_events(
    fpc_id, actor_user_id, actor_role, action, target_type, target_id, after_data
  ) values (
    target_fpc_id, actor_id, 'fpc_admin', 'harvest_received', 'procurement_lot',
    lot.id::text, jsonb_build_object('batchId', batch, 'quantityKg', quantity)
  );

  return to_jsonb(receipt) || jsonb_build_object('procurement_lot_id', lot.id);
end;
$$;

grant execute on function public.receive_fpc_harvest(jsonb, numeric, integer, text) to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'fpcs', 'fpc_registration_applications', 'fpc_memberships',
    'fpc_subscriptions', 'fpc_subscription_invoices', 'platform_settings',
    'notification_templates', 'audit_events', 'fpc_farmer_links',
    'harvest_plans', 'collection_centers', 'procurement_schedules',
    'vehicle_assignments', 'field_assignments', 'field_visits',
    'procurement_lots', 'quality_certificates', 'warehouses',
    'warehouse_locations', 'stock_ledger', 'production_runs',
    'packaging_batches', 'buyers', 'sales_orders', 'sales_order_items',
    'dispatches', 'farmer_payment_ledger', 'fpc_notifications',
    'notification_outbox', 'ai_insights', 'fpc_operational_records'
  ] loop
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
  end loop;
end $$;

revoke update, delete on public.stock_ledger from authenticated;
revoke delete on public.audit_events from authenticated;
revoke all on public.fpc_registration_applications from anon;
revoke all on public.fpcs from anon;
