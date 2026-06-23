alter table public.farms
  add column if not exists current_status text,
  add column if not exists current_status_stage text,
  add column if not exists current_status_updated_at timestamptz;

create table if not exists public.farm_status_updates (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  farmer_id text,
  farmer_phone text,
  farmer_name text,
  farm_name text,
  crop text,
  variety text,
  growth_stage text not null,
  stage_question text,
  days_after_sowing integer,
  status_text text not null,
  prior_status text,
  source text not null default 'farmer_dashboard_status_chat',
  created_at timestamptz not null default now()
);

create index if not exists farm_status_updates_farm_created
  on public.farm_status_updates (farm_id, created_at desc);

create index if not exists farm_status_updates_farmer_created
  on public.farm_status_updates (farmer_id, farmer_phone, created_at desc);

alter table public.farm_status_updates enable row level security;

drop policy if exists "owner_only_farm_status_updates" on public.farm_status_updates;
create policy "owner_only_farm_status_updates"
  on public.farm_status_updates for all
  using (farm_id in (select id from public.farms where user_id = auth.uid()))
  with check (farm_id in (select id from public.farms where user_id = auth.uid()));
