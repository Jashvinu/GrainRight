alter table public.survey_main_crop_yearly
  add column if not exists yield_avg_per_acre numeric,
  add column if not exists yield_avg_per_acre_unit text default 'qt';

update public.survey_main_crop_yearly
set yield_avg_per_acre_unit = 'qt'
where yield_avg_per_acre is not null
  and yield_avg_per_acre_unit is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'survey_main_crop_yearly_yield_avg_per_acre_unit_check'
  ) then
    alter table public.survey_main_crop_yearly
      add constraint survey_main_crop_yearly_yield_avg_per_acre_unit_check
      check (
        yield_avg_per_acre_unit is null
        or yield_avg_per_acre_unit in ('kg', 'qt', 'ton')
      );
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
  yield_avg_per_acre,
  yield_avg_per_acre_unit,
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
