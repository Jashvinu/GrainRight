alter table public.analysis_jobs
  add column if not exists actor_role text not null default 'farmer',
  add column if not exists fpc_id uuid,
  add column if not exists fpc_customer_id text,
  add column if not exists fpc_customer_name text,
  add column if not exists source text not null default 'app';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'analysis_jobs_actor_role_check'
      and conrelid = 'public.analysis_jobs'::regclass
  ) then
    alter table public.analysis_jobs
      add constraint analysis_jobs_actor_role_check
      check (actor_role in ('farmer', 'fpc'));
  end if;
end $$;

create index if not exists analysis_jobs_fpc_created_idx
  on public.analysis_jobs(fpc_id, created_at desc);

create index if not exists analysis_jobs_fpc_customer_created_idx
  on public.analysis_jobs(fpc_customer_id, created_at desc);

create index if not exists analysis_jobs_farmer_farm_created_idx
  on public.analysis_jobs(farmer_id, farm_id, created_at desc);

with unique_profiles as (
  select user_id, min(farmer_id) as farmer_id
  from public.farmer_phone_profiles
  where user_id is not null
    and nullif(farmer_id, '') is not null
  group by user_id
  having count(distinct farmer_id) = 1
)
update public.analysis_jobs jobs
set farmer_id = profiles.farmer_id,
    updated_at = now()
from unique_profiles profiles
where jobs.operator_id = profiles.user_id
  and nullif(jobs.farmer_id, '') is null;

with single_farms as (
  select user_id, min(id::text) as farm_id
  from public.farms
  where user_id is not null
  group by user_id
  having count(*) = 1
)
update public.analysis_jobs jobs
set farm_id = farms.farm_id,
    updated_at = now()
from single_farms farms
where jobs.operator_id = farms.user_id
  and nullif(jobs.farm_id, '') is null;

update public.analysis_jobs
set result_payload = jsonb_build_object(
      'analysis_id', id,
      'grain_image_name',
        regexp_replace(coalesce(grain_image_path, ''), '^.*/', ''),
      'grain_image_path', grain_image_path,
      'moisture_image_name', case
        when moisture_image_path is null then null
        else regexp_replace(moisture_image_path, '^.*/', '')
      end,
      'moisture_image_path', moisture_image_path,
      'quality', coalesce(quality_metrics, '{}'::jsonb) || jsonb_build_object(
        'grade', final_grade,
        'grain_grade', grain_grade,
        'score', final_score,
        'grain_score', grain_score,
        'reject_recommended', reject_recommended,
        'reject_reasons', reject_reasons
      ),
      'moisture', jsonb_build_object(
        'risk_level', moisture_risk,
        'percent_estimate', moisture_percent,
        'machine_percent', manual_moisture_percent,
        'source', moisture_source,
        'ocr_confidence', moisture_confidence
      ),
      'selection', jsonb_build_object(
        'selected_crop', crop_type,
        'selected_variety', variety
      ),
      'applied_rules', applied_rules,
      'manual_review_required', review_status = 'pending',
      'review_status', review_status,
      'signal_highlights', '[]'::jsonb
    ),
    updated_at = now()
where result_payload is null
  or result_payload = '{}'::jsonb;
