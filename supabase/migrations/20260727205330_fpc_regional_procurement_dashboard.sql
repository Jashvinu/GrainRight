-- Regional procurement dashboard for FPC administrators.
-- Clusters are intentionally additive: existing farmer links remain unassigned
-- and continue to appear in the all-clusters snapshot.

create table public.fpc_operating_clusters (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 2 and 80),
  district text not null default '',
  state text not null default 'Maharashtra',
  preferred_apmc_market text not null default '',
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (fpc_id, id)
);

create unique index fpc_operating_clusters_fpc_name_key
on public.fpc_operating_clusters (fpc_id, lower(btrim(name)));

create index fpc_operating_clusters_fpc_active_idx
on public.fpc_operating_clusters (fpc_id, active, name);

alter table public.fpc_farmer_links
add column cluster_id uuid;

alter table public.fpc_farmer_links
add constraint fpc_farmer_links_cluster_same_fpc_fkey
foreign key (fpc_id, cluster_id)
references public.fpc_operating_clusters (fpc_id, id)
on delete restrict;

create index fpc_farmer_links_fpc_cluster_idx
on public.fpc_farmer_links (fpc_id, cluster_id)
where status = 'active';

comment on table public.fpc_operating_clusters is
'Admin-managed procurement regions owned by one FPC.';

comment on column public.fpc_farmer_links.cluster_id is
'Optional operating cluster. The composite foreign key prevents cross-FPC assignment.';

drop trigger if exists set_fpc_operating_clusters_updated_at
on public.fpc_operating_clusters;

create trigger set_fpc_operating_clusters_updated_at
before update on public.fpc_operating_clusters
for each row execute function public.set_updated_at();

alter table public.fpc_operating_clusters enable row level security;

create policy "fpc admins read operating clusters"
on public.fpc_operating_clusters
for select
to authenticated
using (private.can_manage_fpc(fpc_id));

create policy "fpc admins create operating clusters"
on public.fpc_operating_clusters
for insert
to authenticated
with check (
  private.can_manage_fpc(fpc_id)
  and created_by = (select auth.uid())
);

create policy "fpc admins update operating clusters"
on public.fpc_operating_clusters
for update
to authenticated
using (private.can_manage_fpc(fpc_id))
with check (private.can_manage_fpc(fpc_id));

create policy "fpc admins delete operating clusters"
on public.fpc_operating_clusters
for delete
to authenticated
using (private.can_manage_fpc(fpc_id));

revoke all on table public.fpc_operating_clusters from anon;
grant select, insert, update, delete
on table public.fpc_operating_clusters
to authenticated;

create or replace function public.fpc_procurement_dashboard_snapshot(
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

  return (
    with all_cards_base as (
      select
        link.id as link_id,
        link.cluster_id,
        link.farmer_id,
        link.farmer_name,
        link.farmer_phone,
        link.farm_id,
        coalesce(nullif(link.farm_name, ''), farm.name, 'Farm') as farm_name,
        link.village,
        coalesce(nullif(link.crop, ''), farm.crop, plan.crop, '') as crop,
        link.kyc_status,
        farm.area_acres,
        farm.sowing_date,
        farm.current_status,
        farm.current_status_stage,
        case
          when farm.geometry is null or public.st_isempty(farm.geometry) then null
          else public.st_asgeojson(farm.geometry)::jsonb
        end as geometry,
        case
          when farm.geometry is null or public.st_isempty(farm.geometry) then null
          else public.st_y(public.st_pointonsurface(farm.geometry))
        end as centroid_lat,
        case
          when farm.geometry is null or public.st_isempty(farm.geometry) then null
          else public.st_x(public.st_pointonsurface(farm.geometry))
        end as centroid_lng,
        plan.id as harvest_plan_id,
        plan.expected_harvest_date,
        plan.expected_quantity_kg,
        plan.expected_grade,
        coalesce(
          nullif(plan.readiness, ''),
          case
            when lower(coalesce(farm.current_status, '')) like '%ready%'
              then 'ready'
            else 'not_planned'
          end
        ) as readiness,
        latest_grade.final_grade,
        latest_grade.completed_at as grade_completed_at,
        pending_review.needs_review,
        open_lots.open_lot_count,
        snapshot.snapshot_date,
        snapshot.collected_at as snapshot_collected_at,
        snapshot.water_stress_score,
        snapshot.weather_risk,
        snapshot.disease_risk,
        case
          when snapshot.id is null
            or (
              snapshot.water_stress_score is null
              and snapshot.weather_risk is null
              and snapshot.disease_risk is null
            )
            then null
          else round(
            greatest(
              30::numeric,
              least(
                98::numeric,
                82::numeric
                  - coalesce(snapshot.water_stress_score, 0) * 10
                  - coalesce(snapshot.weather_risk, 0) * 7
                  - coalesce(snapshot.disease_risk, 0) * 28
              )
            )
          )::integer
        end as health_score,
        coalesce(
          nullif(link.source_payload ->> 'photo_url', ''),
          nullif(link.source_payload ->> 'photoUrl', '')
        ) as photo_url,
        greatest(
          link.updated_at,
          plan.updated_at,
          latest_grade.completed_at,
          snapshot.collected_at
        ) as data_updated_at
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
      left join lateral (
        select
          candidate.final_grade,
          coalesce(candidate.completed_at, candidate.updated_at) as completed_at
        from public.analysis_jobs candidate
        where (
            candidate.fpc_organization_id = link.fpc_id
            or candidate.fpc_id = link.fpc_id
          )
          and (
            (candidate.farm_id <> '' and candidate.farm_id = link.farm_id)
            or (candidate.farmer_id <> '' and candidate.farmer_id = link.farmer_id)
          )
          and lower(candidate.status) in ('complete', 'completed', 'success')
          and nullif(btrim(candidate.final_grade), '') is not null
        order by
          candidate.completed_at desc nulls last,
          candidate.updated_at desc
        limit 1
      ) latest_grade on true
      left join lateral (
        select exists (
          select 1
          from public.analysis_jobs candidate
          where (
              candidate.fpc_organization_id = link.fpc_id
              or candidate.fpc_id = link.fpc_id
            )
            and (
              (candidate.farm_id <> '' and candidate.farm_id = link.farm_id)
              or (candidate.farmer_id <> '' and candidate.farmer_id = link.farmer_id)
            )
            and lower(candidate.review_status) in ('pending', 'needs_review', 'queued')
        ) as needs_review
      ) pending_review on true
      left join lateral (
        select count(*)::integer as open_lot_count
        from public.procurement_lots lot
        where lot.fpc_id = link.fpc_id
          and (
            (lot.farm_id <> '' and lot.farm_id = link.farm_id)
            or (lot.farmer_id <> '' and lot.farmer_id = link.farmer_id)
          )
          and lower(lot.status) not in (
            'cancelled',
            'closed',
            'completed',
            'rejected',
            'returned'
          )
      ) open_lots on true
      left join lateral (
        select candidate.*
        from public.farm_data_snapshots candidate
        where farm.id is not null
          and candidate.farm_id = farm.id
        order by candidate.snapshot_date desc, candidate.collected_at desc
        limit 1
      ) snapshot on true
      where link.fpc_id = v_fpc_id
        and link.status = 'active'
    ),
    all_cards as (
      select
        card.*,
        case
          when nullif(btrim(card.final_grade), '') is null then 'Not graded'
          when lower(regexp_replace(card.final_grade, '[^a-z0-9]+', '', 'g'))
            in ('a', 'gradea', 'premium', 'premiumgrade') then 'Grade A'
          when lower(regexp_replace(card.final_grade, '[^a-z0-9]+', '', 'g'))
            in ('b', 'gradeb', 'standard', 'standardgrade') then 'Grade B'
          when lower(regexp_replace(card.final_grade, '[^a-z0-9]+', '', 'g'))
            in ('c', 'gradec', 'commercial', 'commercialgrade') then 'Grade C'
          else btrim(card.final_grade)
        end as normalized_grade,
        lower(card.readiness) in (
          'ready',
          'harvest_ready',
          'ready_to_harvest',
          'ready for harvest'
        ) as is_ready
      from all_cards_base card
    ),
    scoped_cards as (
      select *
      from all_cards
      where p_cluster_id is null or cluster_id = p_cluster_id
    ),
    scoped_cards_limited as (
      select *
      from scoped_cards
      order by
        is_ready desc,
        needs_review desc,
        expected_harvest_date asc nulls last,
        farmer_name,
        farm_name
      limit 200
    ),
    cluster_stats as (
      select
        cluster.id,
        count(card.link_id)::integer as farm_count,
        count(card.link_id) filter (where card.is_ready)::integer as ready_count,
        coalesce(sum(card.expected_quantity_kg), 0)::numeric as expected_quantity_kg
      from public.fpc_operating_clusters cluster
      left join all_cards card on card.cluster_id = cluster.id
      where cluster.fpc_id = v_fpc_id
        and cluster.active
      group by cluster.id
    )
    select jsonb_build_object(
      'generated_at', now(),
      'fpc_id', v_fpc_id,
      'selected_cluster_id', p_cluster_id,
      'unassigned_farm_count', (
        select count(*) from all_cards where cluster_id is null
      ),
      'clusters', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', cluster.id,
            'name', cluster.name,
            'district', cluster.district,
            'state', cluster.state,
            'preferred_apmc_market', cluster.preferred_apmc_market,
            'active', cluster.active,
            'farm_count', stats.farm_count,
            'ready_count', stats.ready_count,
            'expected_quantity_kg', stats.expected_quantity_kg
          )
          order by cluster.name
        )
        from public.fpc_operating_clusters cluster
        join cluster_stats stats on stats.id = cluster.id
        where cluster.fpc_id = v_fpc_id
          and cluster.active
      ), '[]'::jsonb),
      'summary', jsonb_build_object(
        'network_farms', (select count(*) from scoped_cards),
        'ready_farms', (
          select count(*) from scoped_cards where is_ready
        ),
        'expected_procurement_kg', coalesce((
          select sum(expected_quantity_kg) from scoped_cards
        ), 0),
        'open_lots', coalesce((
          select sum(open_lot_count) from scoped_cards
        ), 0),
        'needs_review', (
          select count(*) from scoped_cards where needs_review
        ),
        'health_average', (
          select round(avg(health_score))::integer
          from scoped_cards
          where health_score is not null
        ),
        'health_coverage', (
          select count(*) from scoped_cards where health_score is not null
        ),
        'grade_mix', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'grade', mix.normalized_grade,
              'count', mix.grade_count
            )
            order by
              case mix.normalized_grade
                when 'Grade A' then 1
                when 'Grade B' then 2
                when 'Grade C' then 3
                when 'Not graded' then 99
                else 50
              end,
              mix.normalized_grade
          )
          from (
            select normalized_grade, count(*)::integer as grade_count
            from scoped_cards
            group by normalized_grade
          ) mix
        ), '[]'::jsonb)
      ),
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
            'area_acres', card.area_acres,
            'sowing_date', card.sowing_date,
            'current_status', card.current_status,
            'current_status_stage', card.current_status_stage,
            'geometry', card.geometry,
            'centroid_lat', card.centroid_lat,
            'centroid_lng', card.centroid_lng,
            'harvest_plan_id', card.harvest_plan_id,
            'expected_harvest_date', card.expected_harvest_date,
            'expected_quantity_kg', card.expected_quantity_kg,
            'expected_grade', card.expected_grade,
            'readiness', card.readiness,
            'is_ready', card.is_ready,
            'latest_grade', card.normalized_grade,
            'latest_grade_at', card.grade_completed_at,
            'needs_review', card.needs_review,
            'open_lots', card.open_lot_count,
            'health_score', card.health_score,
            'snapshot_date', card.snapshot_date,
            'water_stress_score', card.water_stress_score,
            'weather_risk', card.weather_risk,
            'disease_risk', card.disease_risk,
            'photo_url', card.photo_url,
            'data_updated_at', card.data_updated_at
          )
          order by
            card.is_ready desc,
            card.needs_review desc,
            card.expected_harvest_date asc nulls last,
            card.farmer_name,
            card.farm_name
        )
        from scoped_cards_limited card
      ), '[]'::jsonb)
    )
  );
end;
$$;

comment on function public.fpc_procurement_dashboard_snapshot(uuid) is
'Returns the tenant-scoped live procurement dashboard for all clusters or one selected cluster.';

revoke all on function public.fpc_procurement_dashboard_snapshot(uuid)
from public;
revoke all on function public.fpc_procurement_dashboard_snapshot(uuid)
from anon;
grant execute on function public.fpc_procurement_dashboard_snapshot(uuid)
to authenticated;
