create table if not exists public.stakeholder_plans (
  id uuid primary key default gen_random_uuid(),
  plan_code text not null unique,
  title text not null,
  summary text not null default '',
  currency text not null default 'INR',
  share_unit_value numeric not null check (share_unit_value > 0),
  min_amount numeric not null check (min_amount >= 0),
  max_amount numeric not null check (max_amount >= min_amount),
  status text not null default 'active'
    check (status in ('draft', 'active', 'closed', 'archived')),
  purpose jsonb not null default '[]'::jsonb,
  use_of_funds jsonb not null default '[]'::jsonb,
  stages jsonb not null default '[]'::jsonb,
  risk_notes jsonb not null default '[]'::jsonb,
  terms jsonb not null default '[]'::jsonb,
  opened_at timestamptz default now(),
  closes_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists stakeholder_plans_status_idx
  on public.stakeholder_plans(status, created_at desc);

insert into public.stakeholder_plans (
  plan_code,
  title,
  summary,
  currency,
  share_unit_value,
  min_amount,
  max_amount,
  status,
  purpose,
  use_of_funds,
  stages,
  risk_notes,
  terms
) values (
  'kalsubai-farmer-stakeholder-v1',
  'Kalsubai Farms Farmer Stakeholder Plan',
  'Register interest as a farmer stakeholder. Final allocation is reviewed by the Kalsubai Farms team.',
  'INR',
  100,
  100,
  25000,
  'active',
  '[
    "Let registered farmers express interest in Kalsubai Farms participation.",
    "Keep farmer identity, selected amount, and consent in one review-ready record.",
    "Prepare an auditable queue before final approval and allocation."
  ]'::jsonb,
  '[
    "Farm aggregation and procurement readiness",
    "Millet quality, grading, and packaging operations",
    "Traceability, farmer services, and working capital planning"
  ]'::jsonb,
  '[
    "Submit interest with selected amount",
    "Kalsubai Farms reviews farmer record and plan capacity",
    "Approved allocation and documents are updated later"
  ]'::jsonb,
  '[
    "This is not a payment receipt or confirmed share issue.",
    "Returns are not guaranteed and depend on final approval and business performance.",
    "Final terms must be reviewed before any payment or allocation."
  ]'::jsonb,
  '[
    "The selected amount is only an expression of interest.",
    "Estimated shares are calculated from the current plan share value.",
    "Kalsubai Farms may approve, revise, or reject the application after review."
  ]'::jsonb
) on conflict (plan_code) do update set
  title = excluded.title,
  summary = excluded.summary,
  currency = excluded.currency,
  share_unit_value = excluded.share_unit_value,
  min_amount = excluded.min_amount,
  max_amount = excluded.max_amount,
  status = excluded.status,
  purpose = excluded.purpose,
  use_of_funds = excluded.use_of_funds,
  stages = excluded.stages,
  risk_notes = excluded.risk_notes,
  terms = excluded.terms,
  updated_at = now();

create table if not exists public.stakeholder_applications (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.stakeholder_plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  farmer_phone text not null check (char_length(trim(farmer_phone)) between 10 and 15),
  farmer_id text not null default '',
  farmer_name text not null default '',
  agri_record_id text not null default '',
  aadhaar_last4 text not null default '',
  selected_amount numeric not null check (selected_amount > 0),
  estimated_shares integer not null check (estimated_shares >= 1),
  status text not null default 'submitted'
    check (status in ('submitted', 'under_review', 'approved', 'rejected')),
  consent_interest_only boolean not null default false,
  consent_no_guaranteed_return boolean not null default false,
  consent_data_use boolean not null default false,
  farmer_note text not null default '',
  admin_note text not null default '',
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, plan_id)
);

create index if not exists stakeholder_applications_farmer_idx
  on public.stakeholder_applications(farmer_phone, farmer_id, updated_at desc);

create index if not exists stakeholder_applications_status_idx
  on public.stakeholder_applications(status, updated_at desc);

create table if not exists public.stakeholder_application_events (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null
    references public.stakeholder_applications(id) on delete cascade,
  status text not null default 'submitted',
  title text not null default '',
  note text not null default '',
  actor_role text not null default 'farmer',
  created_at timestamptz not null default now()
);

create index if not exists stakeholder_application_events_app_idx
  on public.stakeholder_application_events(application_id, created_at desc);

drop trigger if exists set_stakeholder_plans_updated_at
  on public.stakeholder_plans;
create trigger set_stakeholder_plans_updated_at
before update on public.stakeholder_plans
for each row
execute function public.set_updated_at();

drop trigger if exists set_stakeholder_applications_updated_at
  on public.stakeholder_applications;
create trigger set_stakeholder_applications_updated_at
before update on public.stakeholder_applications
for each row
execute function public.set_updated_at();

alter table public.stakeholder_plans enable row level security;
alter table public.stakeholder_applications enable row level security;
alter table public.stakeholder_application_events enable row level security;

drop policy if exists "authenticated users can read active stakeholder plans"
  on public.stakeholder_plans;
create policy "authenticated users can read active stakeholder plans"
on public.stakeholder_plans for select to authenticated
using (status = 'active');

drop policy if exists "farmers can read own stakeholder applications"
  on public.stakeholder_applications;
create policy "farmers can read own stakeholder applications"
on public.stakeholder_applications for select to authenticated
using (user_id = auth.uid());

drop policy if exists "farmers can create own stakeholder applications"
  on public.stakeholder_applications;
create policy "farmers can create own stakeholder applications"
on public.stakeholder_applications for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "farmers can update submitted stakeholder applications"
  on public.stakeholder_applications;
create policy "farmers can update submitted stakeholder applications"
on public.stakeholder_applications for update to authenticated
using (user_id = auth.uid() and status = 'submitted')
with check (user_id = auth.uid() and status = 'submitted');

drop policy if exists "farmers can read own stakeholder events"
  on public.stakeholder_application_events;
create policy "farmers can read own stakeholder events"
on public.stakeholder_application_events for select to authenticated
using (
  exists (
    select 1
    from public.stakeholder_applications app
    where app.id = stakeholder_application_events.application_id
      and app.user_id = auth.uid()
  )
);
