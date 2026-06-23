create table if not exists public.farm_timeline_events (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  farmer_id text,
  farmer_phone text,
  event_type text not null,
  title text not null,
  message text not null,
  stage text,
  severity text not null default 'info',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists farm_timeline_events_farm_created
  on public.farm_timeline_events (farm_id, created_at desc);

create index if not exists farm_timeline_events_farmer_created
  on public.farm_timeline_events (farmer_id, farmer_phone, created_at desc);

create index if not exists farm_timeline_events_type_created
  on public.farm_timeline_events (event_type, created_at desc);

alter table public.farm_timeline_events enable row level security;

drop policy if exists "owner_only_farm_timeline_events"
  on public.farm_timeline_events;
create policy "owner_only_farm_timeline_events"
  on public.farm_timeline_events for all
  using (farm_id in (select id from public.farms where user_id = auth.uid()))
  with check (farm_id in (select id from public.farms where user_id = auth.uid()));
