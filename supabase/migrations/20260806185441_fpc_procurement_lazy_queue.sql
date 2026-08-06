-- Keep the initial FPC procurement screen small. The existing full snapshot is
-- retained for operational management, while the queue returns only five
-- operator-facing farm previews at a time.

create or replace function public.fpc_procurement_dashboard_overview(
  p_cluster_id uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select public.fpc_workspace_dashboard_snapshot(p_cluster_id) - 'farms';
$$;

create or replace function public.fpc_procurement_farm_queue(
  p_cluster_id uuid default null,
  p_offset integer default 0,
  p_limit integer default 5
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_fpc_id uuid;
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_limit integer := least(greatest(coalesce(p_limit, 5), 1), 10);
begin
  v_fpc_id := private.active_fpc_id();

  if v_fpc_id is null or not private.can_manage_fpc(v_fpc_id) then
    raise exception 'An active FPC administrator membership is required.'
      using errcode = '42501';
  end if;

  if p_cluster_id is not null and not exists (
    select 1
    from public.fpc_operating_clusters cluster
    where cluster.id = p_cluster_id
      and cluster.fpc_id = v_fpc_id
      and cluster.active
  ) then
    raise exception 'The selected operating cluster is not available for this FPC.'
      using errcode = '22023';
  end if;

  return (
    with queue_cards as (
      select
        link.id as link_id,
        link.cluster_id,
        link.farmer_id,
        coalesce(nullif(link.farmer_name, ''), 'Farmer') as farmer_name,
        coalesce(link.farmer_phone, '') as farmer_phone,
        coalesce(link.farm_id, '') as farm_id,
        coalesce(nullif(link.farm_name, ''), farm.name, 'Farm') as farm_name,
        coalesce(link.village, '') as village,
        coalesce(nullif(link.crop, ''), farm.crop, plan.crop, '') as crop,
        coalesce(link.kyc_status, '') as kyc_status,
        farm.sowing_date,
        coalesce(farm.current_status, '') as current_status,
        coalesce(farm.current_status_stage, '') as current_status_stage,
        plan.id as harvest_plan_id,
        plan.expected_harvest_date,
        plan.expected_quantity_kg,
        coalesce(plan.expected_grade, '') as expected_grade,
        coalesce(
          nullif(plan.readiness, ''),
          case
            when lower(coalesce(farm.current_status, '')) like '%ready%'
              then 'ready'
            else 'not_planned'
          end
        ) as readiness,
        greatest(link.updated_at, plan.updated_at) as data_updated_at
      from public.fpc_farmer_links link
      left join public.farms farm
        on link.farm_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       and farm.id = link.farm_id::uuid
      left join lateral (
        select candidate.*
        from public.harvest_plans candidate
        where candidate.fpc_id = link.fpc_id
          and (
            candidate.farmer_link_id = link.id
            or (
              candidate.farmer_link_id is null
              and candidate.farm_id <> ''
              and candidate.farm_id = link.farm_id
            )
          )
          and lower(candidate.status) not in ('cancelled', 'completed', 'closed')
        order by
          candidate.expected_harvest_date asc nulls last,
          candidate.updated_at desc
        limit 1
      ) plan on true
      where link.fpc_id = v_fpc_id
        and link.status = 'active'
        and (p_cluster_id is null or link.cluster_id = p_cluster_id)
    ),
    ranked_cards as (
      select
        card.*,
        lower(card.readiness) in (
          'ready', 'harvest_ready', 'ready_to_harvest', 'ready for harvest'
        ) as is_ready,
        count(*) over ()::integer as total_count
      from queue_cards card
    ),
    page as (
      select *
      from ranked_cards
      order by
        is_ready desc,
        expected_harvest_date asc nulls last,
        farmer_name,
        farm_name,
        link_id
      offset v_offset
      limit v_limit
    )
    select jsonb_build_object(
      'farms', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'link_id', card.link_id,
            'cluster_id', card.cluster_id,
            'farmer_id', card.farmer_id,
            'farmer_name', card.farmer_name,
            'farmer_phone', card.farmer_phone,
            'farm_id', card.farm_id,
            'farm_name', card.farm_name,
            'village', card.village,
            'crop', card.crop,
            'kyc_status', card.kyc_status,
            'sowing_date', card.sowing_date,
            'current_status', card.current_status,
            'current_status_stage', card.current_status_stage,
            'harvest_plan_id', card.harvest_plan_id,
            'expected_harvest_date', card.expected_harvest_date,
            'expected_quantity_kg', card.expected_quantity_kg,
            'expected_grade', card.expected_grade,
            'readiness', card.readiness,
            'is_ready', card.is_ready,
            'data_updated_at', card.data_updated_at
          )
          order by
            card.is_ready desc,
            card.expected_harvest_date asc nulls last,
            card.farmer_name,
            card.farm_name,
            card.link_id
        )
        from page card
      ), '[]'::jsonb),
      'has_more', coalesce((select max(total_count) > v_offset + v_limit from page), false),
      'next_offset', v_offset + (select count(*) from page)
    )
  );
end;
$$;

create or replace function public.fpc_procurement_farm_detail(
  p_farmer_link_id uuid,
  p_cluster_id uuid default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_fpc_id uuid;
  detail jsonb;
begin
  v_fpc_id := private.active_fpc_id();

  if v_fpc_id is null or not private.can_manage_fpc(v_fpc_id) then
    raise exception 'An active FPC administrator membership is required.'
      using errcode = '42501';
  end if;

  if p_cluster_id is not null and not exists (
    select 1
    from public.fpc_operating_clusters cluster
    where cluster.id = p_cluster_id
      and cluster.fpc_id = v_fpc_id
      and cluster.active
  ) then
    raise exception 'The selected operating cluster is not available for this FPC.'
      using errcode = '22023';
  end if;

  select jsonb_build_object(
    'link_id', link.id,
    'cluster_id', link.cluster_id,
    'farmer_id', link.farmer_id,
    'farmer_name', coalesce(nullif(link.farmer_name, ''), 'Farmer'),
    'farmer_phone', coalesce(link.farmer_phone, ''),
    'farm_id', coalesce(link.farm_id, ''),
    'farm_name', coalesce(nullif(link.farm_name, ''), farm.name, 'Farm'),
    'village', coalesce(link.village, ''),
    'crop', coalesce(nullif(link.crop, ''), farm.crop, plan.crop, ''),
    'kyc_status', coalesce(link.kyc_status, ''),
    'area_acres', farm.area_acres,
    'sowing_date', farm.sowing_date,
    'current_status', coalesce(farm.current_status, ''),
    'current_status_stage', coalesce(farm.current_status_stage, ''),
    'geometry', case
      when farm.geometry is null or public.st_isempty(farm.geometry) then null
      else public.st_asgeojson(farm.geometry)::jsonb
    end,
    'centroid_lat', case
      when farm.geometry is null or public.st_isempty(farm.geometry) then null
      else public.st_y(public.st_pointonsurface(farm.geometry))
    end,
    'centroid_lng', case
      when farm.geometry is null or public.st_isempty(farm.geometry) then null
      else public.st_x(public.st_pointonsurface(farm.geometry))
    end,
    'harvest_plan_id', plan.id,
    'expected_harvest_date', plan.expected_harvest_date,
    'expected_quantity_kg', plan.expected_quantity_kg,
    'expected_grade', coalesce(plan.expected_grade, ''),
    'readiness', coalesce(
      nullif(plan.readiness, ''),
      case when lower(coalesce(farm.current_status, '')) like '%ready%'
        then 'ready' else 'not_planned' end
    ),
    'is_ready', lower(coalesce(
      nullif(plan.readiness, ''),
      case when lower(coalesce(farm.current_status, '')) like '%ready%'
        then 'ready' else 'not_planned' end
    )) in ('ready', 'harvest_ready', 'ready_to_harvest', 'ready for harvest'),
    'latest_grade', case
      when nullif(btrim(latest_grade.final_grade), '') is null then 'Not graded'
      when lower(regexp_replace(latest_grade.final_grade, '[^a-z0-9]+', '', 'g'))
        in ('a', 'gradea', 'premium', 'premiumgrade') then 'Grade A'
      when lower(regexp_replace(latest_grade.final_grade, '[^a-z0-9]+', '', 'g'))
        in ('b', 'gradeb', 'standard', 'standardgrade') then 'Grade B'
      when lower(regexp_replace(latest_grade.final_grade, '[^a-z0-9]+', '', 'g'))
        in ('c', 'gradec', 'commercial', 'commercialgrade') then 'Grade C'
      else btrim(latest_grade.final_grade)
    end,
    'latest_grade_at', latest_grade.completed_at,
    'needs_review', pending_review.needs_review,
    'open_lots', coalesce(open_lots.open_lot_count, 0),
    'health_score', case
      when snapshot.id is null or (
        snapshot.water_stress_score is null
        and snapshot.weather_risk is null
        and snapshot.disease_risk is null
      ) then null
      else round(greatest(30::numeric, least(98::numeric,
        82::numeric
          - coalesce(snapshot.water_stress_score, 0) * 10
          - coalesce(snapshot.weather_risk, 0) * 7
          - coalesce(snapshot.disease_risk, 0) * 28
      )))::integer
    end,
    'snapshot_date', snapshot.snapshot_date,
    'water_stress_score', snapshot.water_stress_score,
    'weather_risk', snapshot.weather_risk,
    'disease_risk', snapshot.disease_risk,
    'photo_url', coalesce(
      nullif(link.source_payload ->> 'photo_url', ''),
      nullif(link.source_payload ->> 'photoUrl', '')
    ),
    'data_updated_at', greatest(
      link.updated_at,
      plan.updated_at,
      latest_grade.completed_at,
      snapshot.collected_at
    )
  ) into detail
  from public.fpc_farmer_links link
  left join public.farms farm
    on link.farm_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
   and farm.id = link.farm_id::uuid
  left join lateral (
    select candidate.*
    from public.harvest_plans candidate
    where candidate.fpc_id = link.fpc_id
      and (candidate.farmer_link_id = link.id or (
        candidate.farmer_link_id is null
        and candidate.farm_id <> ''
        and candidate.farm_id = link.farm_id
      ))
      and lower(candidate.status) not in ('cancelled', 'completed', 'closed')
    order by candidate.expected_harvest_date asc nulls last, candidate.updated_at desc
    limit 1
  ) plan on true
  left join lateral (
    select candidate.final_grade,
      coalesce(candidate.completed_at, candidate.updated_at) as completed_at
    from public.analysis_jobs candidate
    where (candidate.fpc_organization_id = link.fpc_id or candidate.fpc_id = link.fpc_id)
      and ((candidate.farm_id <> '' and candidate.farm_id = link.farm_id)
        or (candidate.farmer_id <> '' and candidate.farmer_id = link.farmer_id))
      and lower(candidate.status) in ('complete', 'completed', 'success')
      and nullif(btrim(candidate.final_grade), '') is not null
    order by candidate.completed_at desc nulls last, candidate.updated_at desc
    limit 1
  ) latest_grade on true
  left join lateral (
    select exists (
      select 1 from public.analysis_jobs candidate
      where (candidate.fpc_organization_id = link.fpc_id or candidate.fpc_id = link.fpc_id)
        and ((candidate.farm_id <> '' and candidate.farm_id = link.farm_id)
          or (candidate.farmer_id <> '' and candidate.farmer_id = link.farmer_id))
        and lower(candidate.review_status) in ('pending', 'needs_review', 'queued')
    ) as needs_review
  ) pending_review on true
  left join lateral (
    select count(*)::integer as open_lot_count
    from public.procurement_lots lot
    where lot.fpc_id = link.fpc_id
      and ((lot.farm_id <> '' and lot.farm_id = link.farm_id)
        or (lot.farmer_id <> '' and lot.farmer_id = link.farmer_id))
      and lower(lot.status) not in ('cancelled', 'closed', 'completed', 'rejected', 'returned')
  ) open_lots on true
  left join lateral (
    select candidate.*
    from public.farm_data_snapshots candidate
    where farm.id is not null and candidate.farm_id = farm.id
    order by candidate.snapshot_date desc, candidate.collected_at desc
    limit 1
  ) snapshot on true
  where link.id = p_farmer_link_id
    and link.fpc_id = v_fpc_id
    and link.status = 'active'
    and (p_cluster_id is null or link.cluster_id = p_cluster_id);

  if detail is null then
    raise exception 'The selected farm is not available for this FPC.'
      using errcode = '22023';
  end if;

  return detail;
end;
$$;

revoke all on function public.fpc_procurement_dashboard_overview(uuid)
  from public, anon;
revoke all on function public.fpc_procurement_farm_queue(uuid, integer, integer)
  from public, anon;
revoke all on function public.fpc_procurement_farm_detail(uuid, uuid)
  from public, anon;

grant execute on function public.fpc_procurement_dashboard_overview(uuid)
  to authenticated;
grant execute on function public.fpc_procurement_farm_queue(uuid, integer, integer)
  to authenticated;
grant execute on function public.fpc_procurement_farm_detail(uuid, uuid)
  to authenticated;

comment on function public.fpc_procurement_dashboard_overview(uuid) is
  'Returns the tenant-scoped FPC procurement overview without farm card payloads.';
comment on function public.fpc_procurement_farm_queue(uuid, integer, integer) is
  'Returns a tenant-scoped, compact operator queue page with at most ten farm previews.';
comment on function public.fpc_procurement_farm_detail(uuid, uuid) is
  'Returns the full tenant-scoped farm detail only when an operator opens that farm.';
