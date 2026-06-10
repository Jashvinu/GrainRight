-- Soil estimates (Layer C output) + ground-truth calibration store (for v2 ML).
--
-- We now produce honest, satellite-derived soil-property estimates (N/P/K/pH/
-- salinity/moisture) instead of a hardcoded "soil test required" placeholder.
-- These are persisted alongside the regional priors that backed them. The
-- soil_calibration_samples table accumulates farmer-submitted lab results from
-- day one so a calibrated model can be trained later (no training infra yet).

alter table public.farmer_ai_diagnostics
  add column if not exists soil_estimates_json jsonb not null default '[]'::jsonb
    check (jsonb_typeof(soil_estimates_json) = 'array');
alter table public.farmer_ai_diagnostics
  add column if not exists soil_priors_json jsonb null
    check (soil_priors_json is null or jsonb_typeof(soil_priors_json) = 'object');
-- Ground-truth soil-test results, keyed to a location + date, for future
-- model calibration. One row per submitted lab/soil-health-card result.
create table if not exists public.soil_calibration_samples (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid null references public.farmer_ai_farms(id) on delete set null,
  lat double precision not null check (lat >= -90 and lat <= 90),
  lng double precision not null check (lng >= -180 and lng <= 180),
  sampled_at date not null,
  source text not null default 'farmer-soil-test',
  -- Lab values (nullable; farmers may submit only some).
  nitrogen_g_kg double precision null,
  phosphorus_kg_ha double precision null,
  potassium_kg_ha double precision null,
  ph double precision null,
  ec_ds_m double precision null,
  organic_carbon_pct double precision null,
  notes text null,
  created_at timestamptz not null default now()
);
create index if not exists soil_calibration_samples_farm_idx
on public.soil_calibration_samples(farm_id);
create index if not exists soil_calibration_samples_loc_idx
on public.soil_calibration_samples(lat, lng);
alter table public.soil_calibration_samples enable row level security;
create policy "soil_calibration_samples select own"
on public.soil_calibration_samples for select to authenticated
using (
  farm_id is null
  or exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = soil_calibration_samples.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "soil_calibration_samples insert own"
on public.soil_calibration_samples for insert to authenticated
with check (
  farm_id is null
  or exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = soil_calibration_samples.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "soil_calibration_samples delete own"
on public.soil_calibration_samples for delete to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = soil_calibration_samples.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
