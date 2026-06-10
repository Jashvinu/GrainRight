create table if not exists public.farmer_ai_diagnostics (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid null references public.farmer_ai_farms(id) on delete cascade,
  plan_id uuid null references public.farmer_ai_plans(id) on delete cascade,
  requested_at timestamptz not null default now(),
  status text not null check (status in ('available', 'partial', 'unavailable')),
  geometry_snapshot jsonb not null check (public.is_valid_geojson_polygon(geometry_snapshot)),
  weather_json jsonb null check (weather_json is null or jsonb_typeof(weather_json) = 'object'),
  satellite_json jsonb null check (satellite_json is null or jsonb_typeof(satellite_json) = 'object'),
  risk_spots_json jsonb not null default '[]'::jsonb check (jsonb_typeof(risk_spots_json) = 'array'),
  ai_evaluation_json jsonb null check (ai_evaluation_json is null or jsonb_typeof(ai_evaluation_json) = 'object'),
  sources_json jsonb not null default '[]'::jsonb check (jsonb_typeof(sources_json) = 'array'),
  error_json jsonb null check (error_json is null or jsonb_typeof(error_json) = 'object'),
  created_at timestamptz not null default now()
);
create index if not exists farmer_ai_diagnostics_plan_id_idx
on public.farmer_ai_diagnostics(plan_id);
create index if not exists farmer_ai_diagnostics_farm_id_created_idx
on public.farmer_ai_diagnostics(farm_id, created_at desc);
create index if not exists farmer_ai_diagnostics_created_idx
on public.farmer_ai_diagnostics(created_at desc);
alter table public.farmer_ai_diagnostics enable row level security;
create policy "farmer_ai_diagnostics select own"
on public.farmer_ai_diagnostics for select to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_diagnostics.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
  or exists (
    select 1
    from public.farmer_ai_plans
    join public.farmer_ai_farms on farmer_ai_farms.id = farmer_ai_plans.farm_id
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_plans.id = farmer_ai_diagnostics.plan_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer_ai_diagnostics insert own"
on public.farmer_ai_diagnostics for insert to authenticated
with check (
  (
    farm_id is not null
    and exists (
      select 1
      from public.farmer_ai_farms
      join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
      where farmer_ai_farms.id = farmer_ai_diagnostics.farm_id
        and farmer_ai_profiles.user_id = auth.uid()
    )
  )
  or (
    plan_id is not null
    and exists (
      select 1
      from public.farmer_ai_plans
      join public.farmer_ai_farms on farmer_ai_farms.id = farmer_ai_plans.farm_id
      join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
      where farmer_ai_plans.id = farmer_ai_diagnostics.plan_id
        and farmer_ai_profiles.user_id = auth.uid()
    )
  )
);
create policy "farmer_ai_diagnostics delete own"
on public.farmer_ai_diagnostics for delete to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_diagnostics.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
