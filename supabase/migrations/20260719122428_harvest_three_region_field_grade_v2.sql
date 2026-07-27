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

  select max(c.scan_date)
  into v_scan_date
  from public.disease_risk_cells c
  where c.farm_id = p_farm_id;

  select count(*)
  into v_cell_count
  from (
    select distinct c.cell_lat, c.cell_lng
    from public.disease_risk_cells c
    where c.farm_id = p_farm_id
      and c.scan_date = v_scan_date
      and c.cell_lat is not null
      and c.cell_lng is not null
  ) distinct_cells;

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
    when v_cell_count < 3 then 0
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
    v_confidence, case when v_cell_count >= 3 then 100 else 0 end,
    v_cell_count >= 3, 'field-grade-v2-three-region', 'active',
    jsonb_build_object(
      'cell_count', v_cell_count,
      'region_count', case when v_cell_count >= 3 then 3 else 0 end,
      'classification_method', 'relative_spatial_rank',
      'weights', jsonb_build_object(
        'disease_health', 0.40,
        'crop_vigor', 0.30,
        'abiotic_health', 0.20,
        'weather_health', 0.10
      )
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
  if v_cell_count < 3 then
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
  raw_cells as (
    select distinct on (c.cell_lat, c.cell_lng)
      c.id,
      public.ST_SetSRID(public.ST_MakePoint(c.cell_lng, c.cell_lat), 4326) as point,
      least(1, greatest(0, coalesce(c.composite_risk, 0.5))) as disease_risk,
      c.ndvi,
      least(1, greatest(0, greatest(
        coalesce(c.dws, 0),
        coalesce(c.thermal_stress, 0),
        case when c.likely_abiotic then 0.75 else 0 end
      ))) as abiotic_risk,
      coalesce((select weather_risk from latest_snapshot), 0.5) as weather_risk
    from public.disease_risk_cells c
    where c.farm_id = p_farm_id
      and c.scan_date = v_scan_date
      and c.cell_lat is not null
      and c.cell_lng is not null
    order by c.cell_lat, c.cell_lng, c.id
  ),
  cell_base as (
    select
      raw_cells.*,
      min(ndvi) over () as min_ndvi,
      max(ndvi) over () as max_ndvi
    from raw_cells
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
      end as vigor
    from cell_base
  ),
  quality_cells as (
    select
      scored.*,
      100 * (
        0.40 * (1 - disease_risk) +
        0.30 * vigor +
        0.20 * (1 - abiotic_risk) +
        0.10 * (1 - weather_risk)
      ) as score,
      public.ST_ClusterKMeans(point, 3) over () as cluster_id
    from scored
  ),
  cluster_centers as (
    select
      cluster_id,
      public.ST_Centroid(public.ST_Collect(point)) as centroid
    from quality_cells
    group by cluster_id
  ),
  seeds as (
    select
      center.cluster_id,
      nearest.point as seed
    from cluster_centers center
    cross join lateral (
      select quality.point
      from quality_cells quality
      where quality.cluster_id = center.cluster_id
      order by public.ST_Distance(
        quality.point::public.geography,
        center.centroid::public.geography
      ), quality.id
      limit 1
    ) nearest
  ),
  voronoi_parts as (
    select (public.ST_Dump(public.ST_VoronoiPolygons(
      public.ST_Collect(seed),
      0,
      public.ST_Envelope((select geom from farm_shape))
    ))).geom as geom
    from seeds
  ),
  regions as (
    select
      nearest.cluster_id,
      public.ST_Multi(public.ST_CollectionExtract(
        public.ST_Intersection(part.geom, farm.geom), 3
      )) as geom
    from voronoi_parts part
    cross join farm_shape farm
    cross join lateral (
      select seed.cluster_id
      from seeds seed
      order by public.ST_Distance(
        seed.seed::public.geography,
        public.ST_PointOnSurface(part.geom)::public.geography
      ), seed.cluster_id
      limit 1
    ) nearest
    where not public.ST_IsEmpty(public.ST_Intersection(part.geom, farm.geom))
  ),
  region_metrics as (
    select
      seed.cluster_id,
      count(*)::integer as source_count,
      avg(quality.score) as score,
      avg(quality.disease_risk) as disease_risk,
      avg(quality.vigor) as vigor,
      avg(quality.abiotic_risk) as abiotic_risk,
      avg(quality.weather_risk) as weather_risk
    from seeds seed
    join quality_cells quality on true
    where seed.cluster_id = (
      select candidate.cluster_id
      from seeds candidate
      order by public.ST_Distance(
        quality.point::public.geography,
        candidate.seed::public.geography
      ), candidate.cluster_id
      limit 1
    )
    group by seed.cluster_id
  ),
  ranked as (
    select
      region.geom,
      metrics.*,
      row_number() over (
        order by metrics.score desc, region.cluster_id
      ) as quality_rank
    from regions region
    join region_metrics metrics using (cluster_id)
  ),
  labeled as (
    select
      *,
      case quality_rank when 1 then 'A' when 2 then 'B' else 'C' end as grade
    from ranked
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
    grade,
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
    geom,
    now()
  from labeled;

  update public.farm_harvest_zone_plans plan
  set summary = plan.summary || jsonb_build_object(
        'grade_area_percent', (
          select jsonb_object_agg(zone.field_grade, round(zone.area_percent, 2))
          from public.farm_harvest_zones zone
          where zone.plan_id = v_plan_id
        )
      ),
      updated_at = now()
  where plan.id = v_plan_id;

  return v_plan_id;
end;
$$;

revoke all on function public.generate_harvest_zone_plan(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.generate_harvest_zone_plan(uuid, uuid)
  to service_role;
