create table if not exists public.farm_data_snapshots (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  farmer_id text,
  farmer_phone text,
  snapshot_date date not null default current_date,
  collected_at timestamptz not null default now(),
  source text not null default 'farm_refresh',
  farm_name text,
  crop text,
  variety text,
  growth_stage text,
  current_status text,
  days_after_sowing integer,
  temperature_c numeric,
  humidity_percent numeric,
  rain_mm numeric,
  total_rain_mm numeric,
  wind_kmh numeric,
  weather_risk numeric,
  water_stress_label text,
  water_stress_score numeric,
  crop_weather_label text,
  crop_weather_score numeric,
  disease_risk numeric,
  risk_cells_count integer not null default 0,
  scout_zones_count integer not null default 0,
  refresh_count integer not null default 1,
  snapshot jsonb not null default '{}'::jsonb,
  compact_after timestamptz not null default (now() + interval '4 days'),
  compacted boolean not null default false,
  compacted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists farm_data_snapshots_farm_date_unique
  on public.farm_data_snapshots (farm_id, snapshot_date);

create index if not exists farm_data_snapshots_farm_date
  on public.farm_data_snapshots (farm_id, snapshot_date desc);

create index if not exists farm_data_snapshots_due_compaction
  on public.farm_data_snapshots (farm_id, compacted, compact_after);

create table if not exists public.farm_data_compactions (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  farmer_id text,
  farmer_phone text,
  compacted_from date not null,
  compacted_to date not null,
  snapshot_count integer not null default 0,
  refresh_count integer not null default 0,
  farm_name text,
  crop text,
  variety text,
  latest_status text,
  latest_growth_stage text,
  avg_temperature_c numeric,
  total_rain_mm numeric,
  avg_water_stress_score numeric,
  max_disease_risk numeric,
  compact_summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists farm_data_compactions_farm_range_unique
  on public.farm_data_compactions (farm_id, compacted_from, compacted_to);

create index if not exists farm_data_compactions_farm_range
  on public.farm_data_compactions (farm_id, compacted_to desc);

alter table public.farm_data_snapshots enable row level security;
alter table public.farm_data_compactions enable row level security;

drop policy if exists "owner_only_farm_data_snapshots"
  on public.farm_data_snapshots;
create policy "owner_only_farm_data_snapshots"
  on public.farm_data_snapshots for all
  using (farm_id in (select id from public.farms where user_id = auth.uid()))
  with check (farm_id in (select id from public.farms where user_id = auth.uid()));

drop policy if exists "owner_only_farm_data_compactions"
  on public.farm_data_compactions;
create policy "owner_only_farm_data_compactions"
  on public.farm_data_compactions for all
  using (farm_id in (select id from public.farms where user_id = auth.uid()))
  with check (farm_id in (select id from public.farms where user_id = auth.uid()));
