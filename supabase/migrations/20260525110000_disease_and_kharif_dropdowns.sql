alter table public.survey_kharif_crops
  add column if not exists production_qty_unit text default 'qt';
update public.survey_kharif_crops
set production_qty_unit = 'qt'
where production_qty is not null
  and production_qty_unit is null;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'survey_kharif_crops_production_qty_unit_check'
  ) then
    alter table public.survey_kharif_crops
      add constraint survey_kharif_crops_production_qty_unit_check
      check (production_qty_unit is null or production_qty_unit in ('qt', 'kg', 'ton'));
  end if;
end $$;
update public.form_fields
set
  label = 'Crop affected',
  label_hi = 'प्रभावित फसल',
  label_mr = 'बाधित पीक',
  input_type = 'dropdown',
  sort_order = 2,
  validation = '{}'::jsonb,
  dropdown_options_key = 'affected_crop_fallback',
  hint_text = 'Select affected crop',
  updated_at = now()
where field_key = 'affected_crop';
update public.form_fields
set
  label = 'Disease Name',
  input_type = 'dropdown',
  sort_order = 3,
  validation = '{}'::jsonb,
  dropdown_options_key = 'disease_name_common',
  hint_text = 'Select disease name',
  updated_at = now()
where field_key = 'disease_name';
update public.form_fields
set sort_order = 4, updated_at = now()
where field_key = 'disease_severity';
update public.form_fields
set sort_order = 5, updated_at = now()
where field_key = 'symptoms_observed';
update public.form_fields
set sort_order = 6, updated_at = now()
where field_key = 'treatment_taken';
insert into public.dropdown_options (option_key, value, label, label_hi, label_mr, sort_order, is_active)
values
  ('affected_crop_fallback', 'bajra', 'Bajra', 'बाजरा', 'बाजरी', 10, true),
  ('affected_crop_fallback', 'nachani', 'Nachani (Ragi)', 'रागी/नाचनी', 'नाचणी', 20, true),
  ('affected_crop_fallback', 'paddy', 'Paddy (Rice)', 'धान', 'भात', 30, true),
  ('affected_crop_fallback', 'Other', 'Other', 'अन्य', 'इतर', 999, true),

  ('disease_name_common', 'Blast', 'Blast', null, null, 10, true),
  ('disease_name_common', 'Leaf blast', 'Leaf blast', null, null, 20, true),
  ('disease_name_common', 'Neck blast', 'Neck blast', null, null, 30, true),
  ('disease_name_common', 'Finger blast', 'Finger blast', null, null, 40, true),
  ('disease_name_common', 'Brown spot', 'Brown spot', null, null, 50, true),
  ('disease_name_common', 'Sheath blight', 'Sheath blight', null, null, 60, true),
  ('disease_name_common', 'Bacterial leaf blight', 'Bacterial leaf blight', null, null, 70, true),
  ('disease_name_common', 'Bacterial leaf streak', 'Bacterial leaf streak', null, null, 80, true),
  ('disease_name_common', 'False smut', 'False smut', null, null, 90, true),
  ('disease_name_common', 'Tungro', 'Tungro', null, null, 100, true),
  ('disease_name_common', 'Downy mildew', 'Downy mildew', null, null, 110, true),
  ('disease_name_common', 'Green ear disease', 'Green ear disease', null, null, 120, true),
  ('disease_name_common', 'Ergot', 'Ergot', null, null, 130, true),
  ('disease_name_common', 'Smut', 'Smut', null, null, 140, true),
  ('disease_name_common', 'Rust', 'Rust', null, null, 150, true),
  ('disease_name_common', 'Grain mold', 'Grain mold', null, null, 160, true),
  ('disease_name_common', 'Foot rot', 'Foot rot', null, null, 170, true),
  ('disease_name_common', 'Seedling blight', 'Seedling blight', null, null, 180, true),
  ('disease_name_common', 'Other', 'Other', 'अन्य', 'इतर', 999, true),

  ('crop_variety_bajra', 'Dhanshakti', 'Dhanshakti', null, null, 10, true),
  ('crop_variety_bajra', 'ICTP 8203', 'ICTP 8203', null, null, 20, true),
  ('crop_variety_bajra', 'Phule Adishakti', 'Phule Adishakti', null, null, 30, true),
  ('crop_variety_bajra', 'Phule Mahashakti', 'Phule Mahashakti', null, null, 40, true),
  ('crop_variety_bajra', 'Pusa Composite 612', 'Pusa Composite 612', null, null, 50, true),
  ('crop_variety_bajra', 'ICMV 221', 'ICMV 221', null, null, 60, true),
  ('crop_variety_bajra', 'ICMV 155', 'ICMV 155', null, null, 70, true),
  ('crop_variety_bajra', 'AIMP 92901 Samrudhi', 'AIMP 92901 Samrudhi', null, null, 80, true),
  ('crop_variety_bajra', 'Other', 'Other', 'अन्य', 'इतर', 999, true),

  ('crop_variety_nachani', 'GPU 28', 'GPU 28', null, null, 10, true),
  ('crop_variety_nachani', 'GPU 67', 'GPU 67', null, null, 20, true),
  ('crop_variety_nachani', 'GPU 66', 'GPU 66', null, null, 30, true),
  ('crop_variety_nachani', 'VL Mandua', 'VL Mandua', null, null, 40, true),
  ('crop_variety_nachani', 'Dapoli 1', 'Dapoli 1', null, null, 50, true),
  ('crop_variety_nachani', 'Phule Nachani', 'Phule Nachani', null, null, 60, true),
  ('crop_variety_nachani', 'MR 6', 'MR 6', null, null, 70, true),
  ('crop_variety_nachani', 'Other', 'Other', 'अन्य', 'इतर', 999, true),

  ('crop_variety_paddy', 'Indrayani', 'Indrayani', null, null, 10, true),
  ('crop_variety_paddy', 'Ambemohar', 'Ambemohar', null, null, 20, true),
  ('crop_variety_paddy', 'Phule Maval', 'Phule Maval', null, null, 30, true),
  ('crop_variety_paddy', 'Phule Samruddhi', 'Phule Samruddhi', null, null, 40, true),
  ('crop_variety_paddy', 'Jaya', 'Jaya', null, null, 50, true),
  ('crop_variety_paddy', 'Kolam', 'Kolam', null, null, 60, true),
  ('crop_variety_paddy', 'HMT', 'HMT', null, null, 70, true),
  ('crop_variety_paddy', 'Sona Masuri', 'Sona Masuri', null, null, 80, true),
  ('crop_variety_paddy', 'Other', 'Other', 'अन्य', 'इतर', 999, true)
on conflict (option_key, value) do update
set
  label = excluded.label,
  label_hi = excluded.label_hi,
  label_mr = excluded.label_mr,
  sort_order = excluded.sort_order,
  is_active = true;
drop view if exists public.survey_kharif_crops_export;
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
  production_qty_unit,
  avg_estimated_cost,
  created_at,
  updated_at,
  extra_details
from public.survey_kharif_crops;
grant select on public.survey_kharif_crops_export to authenticated;
