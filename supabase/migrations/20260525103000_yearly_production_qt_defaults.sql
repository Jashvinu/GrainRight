alter table public.survey_main_crop_yearly
  alter column total_production_unit set default 'qt',
  alter column home_consumption_unit set default 'qt',
  alter column quantity_sold_unit set default 'qt';
update public.survey_main_crop_yearly
set total_production_unit = 'qt'
where total_production is not null
  and total_production_unit is null;
update public.survey_main_crop_yearly
set home_consumption_unit = 'qt'
where home_consumption is not null
  and home_consumption_unit is null;
update public.survey_main_crop_yearly
set quantity_sold_unit = 'qt'
where quantity_sold is not null
  and quantity_sold_unit is null;
