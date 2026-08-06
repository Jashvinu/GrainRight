create or replace function public.fpc_procurement_map_points(
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

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'link_id', point.link_id,
        'farmer_name', point.farmer_name,
        'farm_name', point.farm_name,
        'crop', point.crop,
        'village', point.village,
        'centroid_lat', point.centroid_lat,
        'centroid_lng', point.centroid_lng,
        'readiness', point.readiness,
        'needs_review', point.needs_review
      ) order by point.is_ready desc, point.farmer_name, point.farm_name
    )
    from (
      select
        link.id as link_id,
        coalesce(nullif(link.farmer_name, ''), 'Farmer') as farmer_name,
        coalesce(nullif(link.farm_name, ''), farm.name, 'Farm') as farm_name,
        coalesce(nullif(link.crop, ''), farm.crop, plan.crop, '') as crop,
        coalesce(link.village, '') as village,
        public.st_y(public.st_pointonsurface(farm.geometry)) as centroid_lat,
        public.st_x(public.st_pointonsurface(farm.geometry)) as centroid_lng,
        coalesce(
          nullif(plan.readiness, ''),
          case
            when lower(coalesce(farm.current_status, '')) like '%ready%'
              then 'ready'
            else 'not_planned'
          end
        ) as readiness,
        exists (
          select 1
          from public.analysis_jobs job
          where (job.fpc_organization_id = link.fpc_id or job.fpc_id = link.fpc_id)
            and ((job.farm_id <> '' and job.farm_id = link.farm_id)
              or (job.farmer_id <> '' and job.farmer_id = link.farmer_id))
            and lower(job.review_status) in ('pending', 'needs_review', 'queued')
        ) as needs_review,
        lower(coalesce(
          nullif(plan.readiness, ''),
          case
            when lower(coalesce(farm.current_status, '')) like '%ready%'
              then 'ready'
            else 'not_planned'
          end
        )) in ('ready', 'harvest_ready', 'ready_to_harvest', 'ready for harvest')
          as is_ready
      from public.fpc_farmer_links link
      join public.farms farm
        on link.farm_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       and farm.id = link.farm_id::uuid
       and farm.geometry is not null
       and not public.st_isempty(farm.geometry)
      left join lateral (
        select candidate.crop, candidate.readiness
        from public.harvest_plans candidate
        where candidate.fpc_id = link.fpc_id
          and (
            candidate.farmer_link_id = link.id
            or (candidate.farmer_link_id is null
              and candidate.farm_id <> ''
              and candidate.farm_id = link.farm_id)
          )
          and lower(candidate.status) not in ('cancelled', 'completed', 'closed')
        order by candidate.expected_harvest_date asc nulls last, candidate.updated_at desc
        limit 1
      ) plan on true
      where link.fpc_id = v_fpc_id
        and link.status = 'active'
        and (p_cluster_id is null or link.cluster_id = p_cluster_id)
    ) point
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.fpc_procurement_map_points(uuid) from public, anon;
grant execute on function public.fpc_procurement_map_points(uuid) to authenticated;

comment on function public.fpc_procurement_map_points(uuid) is
  'Returns tenant-scoped, marker-only FPC farm map points without geometry or boundaries.';
