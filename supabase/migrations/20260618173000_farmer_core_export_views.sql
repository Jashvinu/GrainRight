create or replace view public.v_farmer_farm_export
with (security_invoker = true)
as
with latest_profile as (
  select distinct on (user_id)
    user_id,
    regexp_replace(coalesce(phone, ''), '\D', '', 'g') as farmer_phone,
    farmer_id,
    farmer_name,
    default_location,
    preferred_language,
    status as profile_status,
    updated_at as profile_updated_at
  from public.farmer_phone_profiles
  order by user_id, updated_at desc nulls last, created_at desc nulls last
),
latest_status as (
  select distinct on (farm_id)
    farm_id,
    farmer_id,
    growth_stage,
    status_text,
    days_after_sowing,
    created_at
  from public.farm_status_updates
  order by farm_id, created_at desc
)
select
  coalesce(lp.farmer_id, ls.farmer_id) as farmer_id,
  lp.farmer_phone as farmer_phone,
  lp.farmer_name as farmer_name,
  lp.default_location as farmer_location,
  lp.preferred_language as farmer_language,
  lp.profile_status as farmer_profile_status,
  f.user_id::text as user_id,
  f.id::text as farm_id,
  f.name as farm_name,
  f.crop,
  f.variety,
  f.previous_crop,
  f.season,
  f.irrigation,
  f.soil_type,
  f.ownership_type,
  f.seed_source,
  f.harvest_intent,
  f.area_hectares,
  f.area_acres,
  f.current_status,
  f.current_status_stage,
  f.current_status_updated_at,
  ls.status_text as latest_status_text,
  ls.growth_stage as latest_growth_stage,
  ls.days_after_sowing as latest_days_after_sowing,
  ls.created_at as latest_status_at,
  f.source_table,
  f.source_id::text as source_id,
  f.created_at as farm_created_at,
  f.updated_at as farm_updated_at
from public.farms f
left join latest_profile lp on lp.user_id = f.user_id
left join latest_status ls on ls.farm_id = f.id;

create or replace view public.v_farmer_core_activity_export
with (security_invoker = true)
as
select
  s.farmer_id,
  regexp_replace(coalesce(s.farmer_phone, ''), '\D', '', 'g') as farmer_phone,
  s.farm_id::text as farm_id,
  s.farm_name,
  'farm_status_update'::text as activity_type,
  s.growth_stage as activity_status,
  s.status_text as activity_summary,
  concat_ws(
    ' | ',
    nullif(s.crop, ''),
    nullif(s.variety, ''),
    nullif(s.stage_question, ''),
    case
      when s.days_after_sowing is null then null
      else 'DAS ' || s.days_after_sowing::text
    end
  ) as activity_detail,
  s.created_at
from public.farm_status_updates s
union all
select
  a.farmer_id,
  regexp_replace(coalesce(a.farmer_phone, ''), '\D', '', 'g') as farmer_phone,
  a.farm_id::text as farm_id,
  f.name as farm_name,
  'farm_issue_action'::text as activity_type,
  a.status as activity_status,
  a.action as activity_summary,
  concat_ws(
    ' | ',
    nullif(a.crop, ''),
    nullif(a.growth_stage, ''),
    case
      when a.risk_score is null then null
      else 'risk ' || round(a.risk_score::numeric, 2)::text
    end
  ) as activity_detail,
  a.created_at
from public.farm_issue_actions a
left join public.farms f on f.id = a.farm_id
union all
select
  n.farmer_id,
  regexp_replace(coalesce(n.farmer_phone, ''), '\D', '', 'g') as farmer_phone,
  nullif(n.payload ->> 'farmId', '') as farm_id,
  n.farm_name,
  'farmer_notification'::text as activity_type,
  n.type as activity_status,
  n.title as activity_summary,
  n.message as activity_detail,
  n.created_at
from public.farmer_notifications n;

create or replace view public.v_farmer_ai_context
with (security_invoker = true)
as
with latest_activity as (
  select distinct on (farm_id)
    farm_id,
    activity_type,
    activity_status,
    activity_summary,
    activity_detail,
    created_at
  from public.v_farmer_core_activity_export
  where farm_id is not null and farm_id <> ''
  order by farm_id, created_at desc
)
select
  f.farmer_id,
  f.farmer_phone,
  f.farmer_name,
  f.farm_id,
  f.farm_name,
  f.crop,
  f.variety,
  f.area_acres,
  f.irrigation,
  f.soil_type,
  f.current_status,
  f.current_status_stage,
  f.latest_status_text,
  f.latest_growth_stage,
  f.latest_days_after_sowing,
  la.activity_type as latest_activity_type,
  la.activity_status as latest_activity_status,
  la.activity_summary as latest_activity_summary,
  la.activity_detail as latest_activity_detail,
  la.created_at as latest_activity_at,
  concat_ws(
    ' | ',
    'farmer_id=' || coalesce(f.farmer_id, ''),
    'phone=' || coalesce(f.farmer_phone, ''),
    'farmer=' || coalesce(f.farmer_name, ''),
    'farm=' || coalesce(f.farm_name, ''),
    'crop=' || coalesce(f.crop, ''),
    'variety=' || coalesce(f.variety, ''),
    'stage=' || coalesce(f.current_status_stage, f.latest_growth_stage, ''),
    'status=' || coalesce(f.current_status, f.latest_status_text, ''),
    'irrigation=' || coalesce(f.irrigation, ''),
    'soil=' || coalesce(f.soil_type, ''),
    'last_activity=' || coalesce(la.activity_summary, '')
  ) as ai_context_text
from public.v_farmer_farm_export f
left join latest_activity la on la.farm_id = f.farm_id;

grant select on public.v_farmer_farm_export to authenticated;
grant select on public.v_farmer_core_activity_export to authenticated;
grant select on public.v_farmer_ai_context to authenticated;
