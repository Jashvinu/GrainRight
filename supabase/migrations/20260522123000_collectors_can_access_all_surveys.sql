create or replace view public.farmer_survey_list as
select
  id,
  user_id,
  survey_date,
  farmer_name,
  village,
  gram_panchayat,
  taluka,
  district,
  mobile_number,
  main_crop,
  main_crop_land_acre,
  farm_polygon,
  created_at,
  updated_at
from public.farmer_surveys
where auth.uid() is not null;
grant select on public.farmer_survey_list to anon, authenticated;
