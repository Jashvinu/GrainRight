alter table public.farmer_surveys
  add column if not exists total_cultivation_cost numeric;

update public.farmer_surveys
set total_cultivation_cost = 0
where total_cultivation_cost is null;

alter table public.farmer_surveys
  alter column total_cultivation_cost set default 0;

insert into public.form_fields (
  id,
  section_id,
  field_key,
  label,
  label_hi,
  label_mr,
  input_type,
  sort_order,
  is_required,
  validation,
  visibility_rule,
  dropdown_options_key,
  auto_calc_formula,
  suffix_text,
  hint_text,
  crop_role,
  repeat_group
)
select
  gen_random_uuid(),
  s.id,
  'total_cultivation_cost',
  'Total cost of cultivation',
  'खेती की कुल लागत',
  'लागवडीचा एकूण खर्च',
  'currency',
  25,
  false,
  '{}'::jsonb,
  null,
  null,
  null,
  null,
  null,
  null,
  null
from public.form_sections s
where s.title = 'Income & Food Products'
  and not exists (
    select 1
    from public.form_fields f
    where f.field_key = 'total_cultivation_cost'
  );

update public.form_fields
set
  label = 'Total cost of cultivation',
  label_hi = 'खेती की कुल लागत',
  label_mr = 'लागवडीचा एकूण खर्च',
  input_type = 'currency',
  sort_order = 25,
  auto_calc_formula = null
where field_key = 'total_cultivation_cost';

update public.form_fields
set
  sort_order = 30,
  auto_calc_formula = '{"operation":"sum_then_subtract_last","operands":["annual_agri_income","non_agri_income","total_cultivation_cost"]}'::jsonb
where field_key = 'total_annual_income';

update public.survey_crop_practices
set farming_method = 'Traditional'
where farming_method = 'Natural';

drop view if exists public.farmer_surveys_export;

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
  total_cultivation_cost,
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
