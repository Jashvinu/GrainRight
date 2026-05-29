alter table public.survey_main_crop_yearly
  add column if not exists total_production_unit text,
  add column if not exists home_consumption_unit text,
  add column if not exists quantity_sold_unit text,
  add column if not exists sold_where_options text[] not null default '{}'::text[],
  add column if not exists sold_where_other text;
alter table public.survey_crop_practices
  add column if not exists matka_per_acre_unit text,
  add column if not exists neem_per_acre_unit text,
  add column if not exists jeevamrut_per_acre_unit text,
  add column if not exists pesticide_per_acre_unit text;
update public.survey_main_crop_yearly
set
  total_production_unit = coalesce(total_production_unit, 'kg'),
  home_consumption_unit = coalesce(home_consumption_unit, 'kg'),
  quantity_sold_unit = coalesce(quantity_sold_unit, 'kg')
where total_production is not null
  or home_consumption is not null
  or quantity_sold is not null;
update public.survey_main_crop_yearly
set sold_where_options = array[sold_where]
where sold_where is not null
  and btrim(sold_where) <> ''
  and coalesce(array_length(sold_where_options, 1), 0) = 0;
update public.survey_crop_practices
set
  matka_per_acre_unit = case
    when matka_per_acre is null then matka_per_acre_unit
    else coalesce(matka_per_acre_unit, 'ml')
  end,
  neem_per_acre_unit = case
    when neem_per_acre is null then neem_per_acre_unit
    else coalesce(neem_per_acre_unit, 'ml')
  end,
  jeevamrut_per_acre_unit = case
    when jeevamrut_per_acre is null then jeevamrut_per_acre_unit
    else coalesce(jeevamrut_per_acre_unit, 'ml')
  end,
  pesticide_per_acre_unit = case
    when pesticide_per_acre is null then pesticide_per_acre_unit
    else coalesce(pesticide_per_acre_unit, 'ml')
  end;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'survey_main_crop_yearly_total_production_unit_check'
  ) then
    alter table public.survey_main_crop_yearly
      add constraint survey_main_crop_yearly_total_production_unit_check
      check (total_production_unit is null or total_production_unit in ('kg', 'qt', 'ton'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'survey_main_crop_yearly_home_consumption_unit_check'
  ) then
    alter table public.survey_main_crop_yearly
      add constraint survey_main_crop_yearly_home_consumption_unit_check
      check (home_consumption_unit is null or home_consumption_unit in ('kg', 'qt', 'ton'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'survey_main_crop_yearly_quantity_sold_unit_check'
  ) then
    alter table public.survey_main_crop_yearly
      add constraint survey_main_crop_yearly_quantity_sold_unit_check
      check (quantity_sold_unit is null or quantity_sold_unit in ('kg', 'qt', 'ton'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'survey_crop_practices_matka_per_acre_unit_check'
  ) then
    alter table public.survey_crop_practices
      add constraint survey_crop_practices_matka_per_acre_unit_check
      check (matka_per_acre_unit is null or matka_per_acre_unit in ('ml', 'kg'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'survey_crop_practices_neem_per_acre_unit_check'
  ) then
    alter table public.survey_crop_practices
      add constraint survey_crop_practices_neem_per_acre_unit_check
      check (neem_per_acre_unit is null or neem_per_acre_unit in ('ml', 'kg'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'survey_crop_practices_jeevamrut_per_acre_unit_check'
  ) then
    alter table public.survey_crop_practices
      add constraint survey_crop_practices_jeevamrut_per_acre_unit_check
      check (jeevamrut_per_acre_unit is null or jeevamrut_per_acre_unit in ('ml', 'kg'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'survey_crop_practices_pesticide_per_acre_unit_check'
  ) then
    alter table public.survey_crop_practices
      add constraint survey_crop_practices_pesticide_per_acre_unit_check
      check (pesticide_per_acre_unit is null or pesticide_per_acre_unit in ('ml', 'kg'));
  end if;
end $$;
drop view if exists public.survey_main_crop_yearly_export;
create or replace view public.survey_main_crop_yearly_export
with (security_invoker = true) as
select
  id,
  survey_id,
  year,
  area_acre,
  total_production,
  total_production_unit,
  home_consumption,
  home_consumption_unit,
  quantity_sold,
  quantity_sold_unit,
  sold_where,
  sold_where_options,
  sold_where_other,
  selling_price,
  created_at,
  updated_at,
  extra_details
from public.survey_main_crop_yearly;
grant select on public.survey_main_crop_yearly_export to authenticated;
drop view if exists public.survey_crop_practices_export;
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
  matka_per_acre_unit,
  neem_per_acre,
  neem_per_acre_unit,
  jeevamrut_per_acre,
  jeevamrut_per_acre_unit,
  pesticide_per_acre,
  pesticide_per_acre_unit,
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
