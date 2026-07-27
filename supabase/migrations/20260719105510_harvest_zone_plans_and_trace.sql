create table if not exists public.farm_harvest_zone_plans (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_scan_date date,
  growth_stage text not null default '',
  readiness text not null default 'not_ready'
    check (readiness in ('ready', 'not_ready', 'unknown')),
  confidence numeric not null default 0
    check (confidence between 0 and 1),
  coverage_percent numeric not null default 0
    check (coverage_percent between 0 and 100),
  data_available boolean not null default false,
  scoring_version text not null default 'field-grade-v1',
  status text not null default 'active'
    check (status in ('active', 'stale')),
  summary jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (farm_id, source_scan_date, scoring_version)
);

create table if not exists public.farm_harvest_zones (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.farm_harvest_zone_plans(id)
    on delete cascade,
  farm_id uuid not null references public.farms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  zone_label text not null,
  field_grade text not null check (field_grade in ('A', 'B', 'C')),
  field_score numeric not null check (field_score between 0 and 100),
  area_acres numeric not null check (area_acres >= 0),
  area_percent numeric not null check (area_percent between 0 and 100),
  confidence numeric not null default 0 check (confidence between 0 and 1),
  source_cell_count integer not null default 0 check (source_cell_count >= 0),
  quality_drivers jsonb not null default '{}'::jsonb,
  geometry public.geometry(MultiPolygon, 4326) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (plan_id, zone_label)
);

create index if not exists farm_harvest_zone_plans_farm_generated_idx
  on public.farm_harvest_zone_plans(farm_id, generated_at desc);
create index if not exists farm_harvest_zone_plans_user_generated_idx
  on public.farm_harvest_zone_plans(user_id, generated_at desc);
create index if not exists farm_harvest_zones_plan_idx
  on public.farm_harvest_zones(plan_id);
create index if not exists farm_harvest_zones_geometry_idx
  on public.farm_harvest_zones using gist(geometry);

alter table public.farm_harvest_zone_plans enable row level security;
alter table public.farm_harvest_zones enable row level security;

drop policy if exists "farmers read own harvest zone plans"
  on public.farm_harvest_zone_plans;
create policy "farmers read own harvest zone plans"
on public.farm_harvest_zone_plans for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "farmers read own harvest zones"
  on public.farm_harvest_zones;
create policy "farmers read own harvest zones"
on public.farm_harvest_zones for select to authenticated
using (user_id = (select auth.uid()));

grant select on public.farm_harvest_zone_plans to authenticated;
grant select on public.farm_harvest_zones to authenticated;

create table if not exists public.farmer_inventory_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  farmer_phone text not null
    check (char_length(trim(farmer_phone)) between 10 and 15),
  farmer_id text,
  farm_id uuid not null references public.farms(id) on delete cascade,
  farm_name text not null default '',
  inventory_id text not null,
  harvest_batch_id text,
  product_category text not null default 'crop_lot'
    check (product_category in ('crop_lot', 'byproduct', 'processed_product')),
  product_name text not null default '',
  crop text not null default '',
  variety text not null default '',
  quantity numeric not null check (quantity > 0),
  unit text not null default 'kg',
  bag_count integer check (bag_count is null or bag_count >= 0),
  bag_size_kg numeric check (bag_size_kg is null or bag_size_kg >= 0),
  moisture_percent numeric check (
    moisture_percent is null or moisture_percent between 0 and 100
  ),
  grade text not null default '',
  grade_score integer,
  grade_basis text not null default '',
  estimated_yield_kg numeric check (
    estimated_yield_kg is null or estimated_yield_kg >= 0
  ),
  harvested_at timestamptz not null default now(),
  latitude numeric,
  longitude numeric,
  image_name text not null default '',
  source_flow text not null default 'inventory',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, inventory_id)
);

create index if not exists farmer_inventory_user_created_idx
  on public.farmer_inventory_items(user_id, created_at desc);
create index if not exists farmer_inventory_farmer_farm_idx
  on public.farmer_inventory_items(farmer_phone, farmer_id, farm_id);

drop trigger if exists set_farmer_inventory_items_updated_at
  on public.farmer_inventory_items;
create trigger set_farmer_inventory_items_updated_at
before update on public.farmer_inventory_items
for each row execute function public.set_updated_at();

alter table public.farmer_inventory_items enable row level security;

drop policy if exists "farmer inventory select own"
  on public.farmer_inventory_items;
create policy "farmer inventory select own"
on public.farmer_inventory_items for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "farmer inventory insert own"
  on public.farmer_inventory_items;
create policy "farmer inventory insert own"
on public.farmer_inventory_items for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.farms
    where farms.id = farmer_inventory_items.farm_id
      and farms.user_id = (select auth.uid())
  )
);

drop policy if exists "farmer inventory update own"
  on public.farmer_inventory_items;
create policy "farmer inventory update own"
on public.farmer_inventory_items for update to authenticated
using (user_id = (select auth.uid()))
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.farms
    where farms.id = farmer_inventory_items.farm_id
      and farms.user_id = (select auth.uid())
  )
);

drop policy if exists "farmer inventory delete own"
  on public.farmer_inventory_items;
create policy "farmer inventory delete own"
on public.farmer_inventory_items for delete to authenticated
using (user_id = (select auth.uid()));

grant select, insert, update, delete on public.farmer_inventory_items
  to authenticated;

alter table public.analysis_jobs
  add column if not exists harvest_zone_plan_id uuid
    references public.farm_harvest_zone_plans(id) on delete set null,
  add column if not exists harvest_zone_id uuid
    references public.farm_harvest_zones(id) on delete set null,
  add column if not exists field_grade text,
  add column if not exists field_score numeric;

alter table public.farmer_inventory_items
  add column if not exists harvest_zone_plan_id uuid
    references public.farm_harvest_zone_plans(id) on delete set null,
  add column if not exists harvest_zone_id uuid
    references public.farm_harvest_zones(id) on delete set null,
  add column if not exists harvest_zone_label text not null default '',
  add column if not exists field_grade text not null default '',
  add column if not exists field_score numeric;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'analysis_jobs_field_grade_check'
      and conrelid = 'public.analysis_jobs'::regclass
  ) then
    alter table public.analysis_jobs
      add constraint analysis_jobs_field_grade_check
      check (field_grade is null or field_grade in ('A', 'B', 'C'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'analysis_jobs_field_score_check'
      and conrelid = 'public.analysis_jobs'::regclass
  ) then
    alter table public.analysis_jobs
      add constraint analysis_jobs_field_score_check
      check (field_score is null or field_score between 0 and 100);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'farmer_inventory_items_field_grade_check'
      and conrelid = 'public.farmer_inventory_items'::regclass
  ) then
    alter table public.farmer_inventory_items
      add constraint farmer_inventory_items_field_grade_check
      check (field_grade = '' or field_grade in ('A', 'B', 'C'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'farmer_inventory_items_field_score_check'
      and conrelid = 'public.farmer_inventory_items'::regclass
  ) then
    alter table public.farmer_inventory_items
      add constraint farmer_inventory_items_field_score_check
      check (field_score is null or field_score between 0 and 100);
  end if;
end
$$;

create index if not exists analysis_jobs_harvest_zone_idx
  on public.analysis_jobs(harvest_zone_plan_id, harvest_zone_id);
create index if not exists farmer_inventory_harvest_zone_idx
  on public.farmer_inventory_items(harvest_zone_plan_id, harvest_zone_id);

create or replace function public.generate_harvest_zone_plan(
  p_farm_id uuid,
  p_user_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_plan_id uuid;
  v_scan_date date;
  v_stage text := '';
  v_readiness text := 'unknown';
  v_cell_count integer := 0;
  v_confidence numeric := 0;
  v_farm_area_m2 numeric := 0;
begin
  if not exists (
    select 1
    from public.farms f
    where f.id = p_farm_id
      and f.user_id = p_user_id
      and f.geometry is not null
  ) then
    raise exception 'farm_not_found_or_not_owned' using errcode = '42501';
  end if;

  select max(c.scan_date), count(*) filter (
      where c.scan_date = (select max(c2.scan_date)
                           from public.disease_risk_cells c2
                           where c2.farm_id = p_farm_id)
    )
  into v_scan_date, v_cell_count
  from public.disease_risk_cells c
  where c.farm_id = p_farm_id;

  select coalesce(nullif(s.growth_stage, ''), nullif(f.current_status_stage, ''), ''),
         public.ST_Area(f.geometry::public.geography)
  into v_stage, v_farm_area_m2
  from public.farms f
  left join lateral (
    select growth_stage
    from public.farm_data_snapshots
    where farm_id = f.id
    order by collected_at desc
    limit 1
  ) s on true
  where f.id = p_farm_id;

  v_readiness := case
    when lower(v_stage) ~ '(matur|harvest|ripen|grain.?fill)' then 'ready'
    when v_stage = '' then 'unknown'
    else 'not_ready'
  end;
  v_confidence := case
    when v_cell_count <= 0 then 0
    else least(1, 0.35 + (v_cell_count::numeric / 20))
  end;

  update public.farm_harvest_zone_plans
  set status = 'stale', updated_at = now()
  where farm_id = p_farm_id and status = 'active';

  insert into public.farm_harvest_zone_plans (
    farm_id, user_id, source_scan_date, growth_stage, readiness,
    confidence, coverage_percent, data_available, scoring_version,
    status, summary, generated_at, updated_at
  ) values (
    p_farm_id, p_user_id, v_scan_date, v_stage, v_readiness,
    v_confidence, case when v_cell_count > 0 then 100 else 0 end,
    v_cell_count > 0, 'field-grade-v1', 'active',
    jsonb_build_object(
      'cell_count', v_cell_count,
      'weights', jsonb_build_object(
        'disease_health', 0.40,
        'crop_vigor', 0.30,
        'abiotic_health', 0.20,
        'weather_health', 0.10
      ),
      'thresholds', jsonb_build_object('A', 85, 'B', 70, 'C', 0)
    ),
    now(), now()
  )
  on conflict (farm_id, source_scan_date, scoring_version)
  do update set
    user_id = excluded.user_id,
    growth_stage = excluded.growth_stage,
    readiness = excluded.readiness,
    confidence = excluded.confidence,
    coverage_percent = excluded.coverage_percent,
    data_available = excluded.data_available,
    status = 'active',
    summary = excluded.summary,
    generated_at = now(),
    updated_at = now()
  returning id into v_plan_id;

  delete from public.farm_harvest_zones where plan_id = v_plan_id;
  if v_cell_count = 0 then
    return v_plan_id;
  end if;

  with farm_shape as (
    select public.ST_MakeValid(geometry) as geom
    from public.farms
    where id = p_farm_id
  ),
  latest_snapshot as (
    select least(1, greatest(0, coalesce(weather_risk, 0.5))) as weather_risk
    from public.farm_data_snapshots
    where farm_id = p_farm_id
    order by collected_at desc
    limit 1
  ),
  cell_base as (
    select
      c.id,
      public.ST_SetSRID(public.ST_MakePoint(c.cell_lng, c.cell_lat), 4326) as point,
      least(1, greatest(0, coalesce(c.composite_risk, 0.5))) as disease_risk,
      c.ndvi,
      least(1, greatest(0, greatest(
        coalesce(c.dws, 0),
        coalesce(c.thermal_stress, 0),
        case when c.likely_abiotic then 0.75 else 0 end
      ))) as abiotic_risk,
      coalesce((select weather_risk from latest_snapshot), 0.5) as weather_risk,
      min(c.ndvi) over () as min_ndvi,
      max(c.ndvi) over () as max_ndvi
    from public.disease_risk_cells c
    where c.farm_id = p_farm_id and c.scan_date = v_scan_date
  ),
  scored as (
    select
      id,
      point,
      disease_risk,
      abiotic_risk,
      weather_risk,
      case
        when ndvi is null then 1 - disease_risk
        when max_ndvi is null or min_ndvi is null or max_ndvi = min_ndvi
          then 1 - disease_risk
        else least(1, greatest(0, (ndvi - min_ndvi) / nullif(max_ndvi - min_ndvi, 0)))
      end as vigor,
      100 * (
        0.40 * (1 - disease_risk) +
        0.30 * case
          when ndvi is null then 1 - disease_risk
          when max_ndvi is null or min_ndvi is null or max_ndvi = min_ndvi
            then 1 - disease_risk
          else least(1, greatest(0, (ndvi - min_ndvi) / nullif(max_ndvi - min_ndvi, 0)))
        end +
        0.20 * (1 - abiotic_risk) +
        0.10 * (1 - weather_risk)
      ) as score
    from cell_base
  ),
  voronoi_parts as (
    select (public.ST_Dump(
      case when v_cell_count = 1
        then (select geom from farm_shape)
        else public.ST_VoronoiPolygons(
          public.ST_Collect(scored.point),
          0,
          public.ST_Envelope((select geom from farm_shape))
        )
      end
    )).geom as geom
    from scored
  ),
  clipped as (
    select
      public.ST_Multi(public.ST_CollectionExtract(
        public.ST_Intersection(v.geom, f.geom), 3
      )) as geom,
      nearest.score,
      nearest.disease_risk,
      nearest.vigor,
      nearest.abiotic_risk,
      nearest.weather_risk
    from voronoi_parts v
    cross join farm_shape f
    cross join lateral (
      select s.*
      from scored s
      order by public.ST_Distance(
        s.point::public.geography,
        public.ST_PointOnSurface(v.geom)::public.geography
      )
      limit 1
    ) nearest
    where not public.ST_IsEmpty(public.ST_Intersection(v.geom, f.geom))
  ),
  classified as (
    select *, case when score >= 85 then 'A'
                   when score >= 70 then 'B'
                   else 'C' end as grade
    from clipped
    where not public.ST_IsEmpty(geom)
  ),
  merged as (
    select
      grade,
      public.ST_UnaryUnion(public.ST_Collect(geom)) as geom,
      avg(score) as score,
      avg(disease_risk) as disease_risk,
      avg(vigor) as vigor,
      avg(abiotic_risk) as abiotic_risk,
      avg(weather_risk) as weather_risk,
      count(*)::integer as source_count
    from classified
    group by grade
  ),
  components as (
    select
      grade,
      (public.ST_Dump(geom)).geom as geom,
      score, disease_risk, vigor, abiotic_risk, weather_risk, source_count
    from merged
  ),
  labeled as (
    select
      *,
      grade || row_number() over (
        partition by grade
        order by public.ST_Area(geom::public.geography) desc
      )::text as zone_label
    from components
  )
  insert into public.farm_harvest_zones (
    plan_id, farm_id, user_id, zone_label, field_grade, field_score,
    area_acres, area_percent, confidence, source_cell_count,
    quality_drivers, geometry, updated_at
  )
  select
    v_plan_id,
    p_farm_id,
    p_user_id,
    zone_label,
    grade,
    round(score, 1),
    public.ST_Area(geom::public.geography) / 4046.8564224,
    case when v_farm_area_m2 > 0
      then 100 * public.ST_Area(geom::public.geography) / v_farm_area_m2
      else 0 end,
    v_confidence,
    source_count,
    jsonb_build_object(
      'disease_health', round((1 - disease_risk) * 100, 1),
      'crop_vigor', round(vigor * 100, 1),
      'abiotic_health', round((1 - abiotic_risk) * 100, 1),
      'weather_health', round((1 - weather_risk) * 100, 1)
    ),
    public.ST_Multi(geom),
    now()
  from labeled;

  return v_plan_id;
end;
$$;

revoke all on function public.generate_harvest_zone_plan(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.generate_harvest_zone_plan(uuid, uuid)
  to service_role;
