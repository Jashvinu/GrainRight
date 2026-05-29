alter table public.farmer_surveys
  add column if not exists other_crop_details text,
  add column if not exists income_sources_other text,
  add column if not exists farming_type_other text;
alter table public.farmer_surveys add column if not exists disease_present boolean;
alter table public.farmer_surveys add column if not exists disease_name text;
alter table public.farmer_surveys add column if not exists affected_crop text;
alter table public.farmer_surveys add column if not exists disease_severity text;
alter table public.farmer_surveys add column if not exists symptoms_observed text;
alter table public.farmer_surveys add column if not exists treatment_taken text;
alter table public.survey_kharif_crops
  add column if not exists other_crop_name text,
  add column if not exists other_crop_details text,
  add column if not exists extra_details jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();
alter table public.survey_main_crop_yearly
  add column if not exists extra_details jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();
alter table public.survey_crop_practices
  add column if not exists grown_on_other text,
  add column if not exists seed_treatment_materials_other text,
  add column if not exists transplant_method_other text,
  add column if not exists jeevamrut_per_acre numeric,
  add column if not exists pesticide_per_acre numeric,
  add column if not exists monitoring_methods_other text,
  add column if not exists extra_details jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();
update public.farmer_surveys
set
  other_crop_details = coalesce(
    other_crop_details,
    nullif(extra_details->>'other_crop_details', '')
  ),
  income_sources_other = coalesce(
    income_sources_other,
    nullif(extra_details->>'income_sources_other', '')
  ),
  farming_type_other = coalesce(
    farming_type_other,
    nullif(extra_details->>'farming_type_other', '')
  ),
  disease_present = coalesce(
    disease_present,
    case lower(coalesce(
      extra_details #>> '{cropping_pattern,disease,disease_present}',
      extra_details->>'disease_present'
    ))
      when 'true' then true
      when 'false' then false
      else null
    end
  ),
  disease_name = coalesce(
    disease_name,
    nullif(coalesce(
      extra_details #>> '{cropping_pattern,disease,disease_name}',
      extra_details->>'disease_name'
    ), '')
  ),
  affected_crop = coalesce(
    affected_crop,
    nullif(coalesce(
      extra_details #>> '{cropping_pattern,disease,affected_crop}',
      extra_details->>'affected_crop'
    ), '')
  ),
  disease_severity = coalesce(
    disease_severity,
    nullif(coalesce(
      extra_details #>> '{cropping_pattern,disease,disease_severity}',
      extra_details->>'disease_severity'
    ), '')
  ),
  symptoms_observed = coalesce(
    symptoms_observed,
    nullif(coalesce(
      extra_details #>> '{cropping_pattern,disease,symptoms_observed}',
      extra_details->>'symptoms_observed'
    ), '')
  ),
  treatment_taken = coalesce(
    treatment_taken,
    nullif(coalesce(
      extra_details #>> '{cropping_pattern,disease,treatment_taken}',
      extra_details->>'treatment_taken'
    ), '')
  )
where extra_details ? 'other_crop_details'
  or extra_details ? 'income_sources_other'
  or extra_details ? 'farming_type_other'
  or extra_details ? 'disease_present'
  or extra_details ? 'disease_name'
  or extra_details ? 'affected_crop'
  or extra_details ? 'disease_severity'
  or extra_details ? 'symptoms_observed'
  or extra_details ? 'treatment_taken'
  or extra_details ? 'cropping_pattern';
update public.farmer_surveys
set extra_details =
  (
    coalesce(extra_details, '{}'::jsonb)
    - 'other_crop_details'
    - 'income_sources_other'
    - 'farming_type_other'
    - 'disease_present'
    - 'disease_name'
    - 'affected_crop'
    - 'disease_severity'
    - 'symptoms_observed'
    - 'treatment_taken'
  ) #- '{cropping_pattern,disease}'
where extra_details ? 'other_crop_details'
  or extra_details ? 'income_sources_other'
  or extra_details ? 'farming_type_other'
  or extra_details ? 'disease_present'
  or extra_details ? 'disease_name'
  or extra_details ? 'affected_crop'
  or extra_details ? 'disease_severity'
  or extra_details ? 'symptoms_observed'
  or extra_details ? 'treatment_taken'
  or extra_details ? 'cropping_pattern';
update public.farmer_surveys
set extra_details = extra_details - 'cropping_pattern'
where extra_details->'cropping_pattern' = '{}'::jsonb;
update public.survey_kharif_crops
set
  other_crop_name = coalesce(
    other_crop_name,
    nullif(extra_details->>'other_crop_name', '')
  ),
  other_crop_details = coalesce(
    other_crop_details,
    nullif(extra_details->>'other_crop_details', '')
  )
where extra_details ? 'other_crop_name'
  or extra_details ? 'other_crop_details';
update public.survey_kharif_crops
set extra_details = coalesce(extra_details, '{}'::jsonb)
  - 'other_crop_name'
  - 'other_crop_details'
where extra_details ? 'other_crop_name'
  or extra_details ? 'other_crop_details';
update public.survey_crop_practices
set
  grown_on_other = coalesce(
    grown_on_other,
    nullif(extra_details->>'grown_on_other', '')
  ),
  seed_treatment_materials_other = coalesce(
    seed_treatment_materials_other,
    nullif(extra_details->>'seed_treatment_materials_other', '')
  ),
  transplant_method_other = coalesce(
    transplant_method_other,
    nullif(extra_details->>'transplant_method_other', '')
  ),
  jeevamrut_per_acre = coalesce(
    jeevamrut_per_acre,
    case
      when extra_details->>'jeevamrut_per_acre' ~ '^-?[0-9]+(\.[0-9]+)?$'
        then (extra_details->>'jeevamrut_per_acre')::numeric
      else null
    end
  ),
  pesticide_per_acre = coalesce(
    pesticide_per_acre,
    case
      when extra_details->>'pesticide_per_acre' ~ '^-?[0-9]+(\.[0-9]+)?$'
        then (extra_details->>'pesticide_per_acre')::numeric
      else null
    end
  ),
  monitoring_methods_other = coalesce(
    monitoring_methods_other,
    nullif(extra_details->>'monitoring_methods_other', '')
  )
where extra_details ? 'grown_on_other'
  or extra_details ? 'seed_treatment_materials_other'
  or extra_details ? 'transplant_method_other'
  or extra_details ? 'jeevamrut_per_acre'
  or extra_details ? 'pesticide_per_acre'
  or extra_details ? 'monitoring_methods_other';
update public.survey_crop_practices
set extra_details = coalesce(extra_details, '{}'::jsonb)
  - 'grown_on_other'
  - 'seed_treatment_materials_other'
  - 'transplant_method_other'
  - 'jeevamrut_per_acre'
  - 'pesticide_per_acre'
  - 'monitoring_methods_other'
where extra_details ? 'grown_on_other'
  or extra_details ? 'seed_treatment_materials_other'
  or extra_details ? 'transplant_method_other'
  or extra_details ? 'jeevamrut_per_acre'
  or extra_details ? 'pesticide_per_acre'
  or extra_details ? 'monitoring_methods_other';
create or replace view public.farmer_surveys_export
with (security_invoker = true) as
select
  id,
  user_id,
  survey_date,
  language,
  farmer_name,
  gender,
  date_of_birth,
  category,
  education as education_level,
  village as village_gp,
  gram_panchayat,
  taluka as block,
  district,
  aadhaar_number as aadhar_no,
  mobile_number as mobile_no,
  income_sources as sources_of_income,
  income_sources_other,
  farming_type,
  farming_type_other,
  owns_farmland,
  total_land_area_acre as land_owned,
  leased_land_acre as land_leased,
  rain_based_area_acre as total_rainfed_land,
  irrigated_land_acre as total_irrigated_land,
  dry_land_acre,
  fallow_land_acre,
  has_forest_patta,
  forest_patta_acre,
  applied_for_forest_patta,
  main_crop,
  main_crop_other,
  main_crop_land_acre as land_under_millet,
  other_crop_land_acre as land_under_other_crops,
  other_crop_details,
  farm_polygon,
  annual_agri_income,
  non_agri_income as annual_non_agri_income,
  total_annual_income,
  makes_food_products,
  food_products_list,
  food_product_training_received,
  food_product_training_source,
  disease_present,
  disease_name,
  affected_crop,
  disease_severity,
  symptoms_observed,
  treatment_taken,
  location_lat as form_latitude,
  location_lng as form_longitude,
  location_accuracy_m as form_location_accuracy,
  started_at as form_started_at,
  submitted_at,
  created_at,
  updated_at,
  extra_details
from public.farmer_surveys;
grant select on public.farmer_surveys_export to authenticated;
create or replace view public.survey_kharif_crops_export
with (security_invoker = true) as
select
  id,
  survey_id,
  position,
  crop_name,
  other_crop_name,
  other_crop_details,
  cultivated_area_acre,
  crop_variety,
  production_qty,
  avg_estimated_cost,
  created_at,
  updated_at,
  extra_details
from public.survey_kharif_crops;
grant select on public.survey_kharif_crops_export to authenticated;
create or replace view public.survey_main_crop_yearly_export
with (security_invoker = true) as
select
  id,
  survey_id,
  year,
  area_acre,
  total_production,
  home_consumption,
  quantity_sold,
  sold_where,
  selling_price,
  created_at,
  updated_at,
  extra_details
from public.survey_main_crop_yearly;
grant select on public.survey_main_crop_yearly_export to authenticated;
create or replace view public.survey_crop_practices_export
with (security_invoker = true) as
select
  id,
  survey_id,
  crop_role,
  grown_on,
  grown_on_other,
  same_land_every_year,
  land_topology,
  land_topology_other,
  seed_sources,
  seed_source_other,
  pop_training_received,
  pop_training_source,
  farming_method,
  treats_seeds,
  seed_treatment_materials,
  seed_treatment_materials_other,
  seedling_method,
  seedling_method_other,
  seedling_ready_days,
  seedling_method_difference,
  land_prep_tractor_days,
  land_prep_tractor_cost,
  land_prep_bullock_days,
  land_prep_bullock_cost,
  land_prep_by_hand,
  transplant_method,
  transplant_method_other,
  dip_in_jeevamrut,
  plant_spacing_cm,
  transplant_days,
  needs_transplant_labour,
  transplant_labourers,
  transplant_daily_wage,
  does_weeding,
  weeding_after_days,
  sprays_for_pest,
  spray_methods,
  matka_per_acre,
  neem_per_acre,
  jeevamrut_per_acre,
  pesticide_per_acre,
  spray_methods_other,
  organic_fert_helps_disease,
  planting_to_flowering_days,
  uses_fertilizer,
  fertilizer_names,
  fertilizer_qty_per_acre,
  flowering_pest_problem,
  flowering_pest_type,
  flowering_sprays_used,
  maturity_days,
  monitors_crop,
  monitoring_methods,
  monitoring_methods_other,
  harvest_method,
  harvest_labour_type,
  harvest_daily_wage,
  harvest_labourers,
  harvest_days,
  ready_to_eat_or_sell_days,
  sells_main_crop,
  selling_time,
  created_at,
  updated_at,
  extra_details
from public.survey_crop_practices;
grant select on public.survey_crop_practices_export to authenticated;
do $$
begin
  if to_regclass('public.diagnostics_cache') is not null then
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'diagnostics_cache'
        and column_name = 'expires_at'
    ) then
      execute 'delete from public.diagnostics_cache where expires_at < now()';
      execute 'create index if not exists diagnostics_cache_expires_at_idx on public.diagnostics_cache(expires_at)';
    end if;
  end if;
end $$;
notify pgrst, 'reload schema';
