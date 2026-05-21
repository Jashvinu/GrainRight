alter table public.form_sections
  add column if not exists title_hi text,
  add column if not exists title_mr text;

alter table public.farmer_surveys
  add column if not exists income_sources_other text,
  add column if not exists farming_type_other text;

update public.form_sections
set
  title_hi = case title
    when 'Family Information' then 'पारिवारिक जानकारी'
    when 'Land / Farming' then 'भूमि / खेती'
    when 'Forest Patta' then 'वन अधिकार पट्टा'
    when 'Farm Boundary' then 'खेत की सीमा'
    when 'Main Crop' then 'मुख्य फसल'
    when 'Kharif Crops' then 'खरीफ फसलें'
    when 'Other Crops' then 'अन्य फसलें'
    when 'Main Crop Agronomy' then 'मुख्य फसल की कृषि पद्धतियां'
    when 'Other Crop Agronomy' then 'अन्य फसल की कृषि पद्धतियां'
    when 'Main Crop 3-Year Production' then 'मुख्य फसल का 3-वर्षीय उत्पादन'
    when 'Income & Food Products' then 'आय और खाद्य उत्पाद'
    else title_hi
  end,
  title_mr = case title
    when 'Family Information' then 'कौटुंबिक माहिती'
    when 'Land / Farming' then 'जमीन / शेती'
    when 'Forest Patta' then 'वन हक्क पट्टा'
    when 'Farm Boundary' then 'शेताची सीमा'
    when 'Main Crop' then 'मुख्य पीक'
    when 'Kharif Crops' then 'खरीप पिके'
    when 'Other Crops' then 'इतर पिके'
    when 'Main Crop Agronomy' then 'मुख्य पीक कृषी पद्धती'
    when 'Other Crop Agronomy' then 'इतर पीक कृषी पद्धती'
    when 'Main Crop 3-Year Production' then 'मुख्य पीक 3 वर्षांचे उत्पादन'
    when 'Income & Food Products' then 'उत्पन्न आणि अन्न उत्पादने'
    else title_mr
  end,
  updated_at = now()
where title in (
  'Family Information',
  'Land / Farming',
  'Forest Patta',
  'Farm Boundary',
  'Main Crop',
  'Kharif Crops',
  'Other Crops',
  'Main Crop Agronomy',
  'Other Crop Agronomy',
  'Main Crop 3-Year Production',
  'Income & Food Products'
);

update public.form_sections
set is_active = false,
    updated_at = now()
where title = 'Other Crops';

with land_section as (
  select id from public.form_sections where title = 'Land / Farming' limit 1
)
insert into public.form_fields (
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
  auto_calc_formula,
  dropdown_options_key,
  hint_text,
  hint_text_hi,
  hint_text_mr,
  suffix_text,
  crop_role,
  repeat_group
)
select
  id,
  'income_sources_other',
  'Other income source',
  'अन्य आय स्रोत',
  'इतर उत्पन्नाचा स्रोत',
  'text',
  15,
  false,
  '{}'::jsonb,
  '{"depends_on":"income_sources","operator":"contains_any","value":["other"]}'::jsonb,
  null,
  null,
  'Describe the other income source',
  'अन्य आय स्रोत लिखें',
  'इतर उत्पन्नाचा स्रोत लिहा',
  null,
  null,
  null
from land_section
on conflict (field_key) do update set
  label = excluded.label,
  label_hi = excluded.label_hi,
  label_mr = excluded.label_mr,
  input_type = excluded.input_type,
  sort_order = excluded.sort_order,
  is_required = excluded.is_required,
  validation = excluded.validation,
  visibility_rule = excluded.visibility_rule,
  dropdown_options_key = excluded.dropdown_options_key,
  hint_text = excluded.hint_text,
  hint_text_hi = excluded.hint_text_hi,
  hint_text_mr = excluded.hint_text_mr,
  is_active = true,
  updated_at = now();

with land_section as (
  select id from public.form_sections where title = 'Land / Farming' limit 1
)
insert into public.form_fields (
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
  auto_calc_formula,
  dropdown_options_key,
  hint_text,
  hint_text_hi,
  hint_text_mr,
  suffix_text,
  crop_role,
  repeat_group
)
select
  id,
  'farming_type_other',
  'Other farming type',
  'अन्य खेती का प्रकार',
  'इतर शेतीचा प्रकार',
  'text',
  25,
  false,
  '{}'::jsonb,
  '{"depends_on":"farming_type","operator":"contains_any","value":["other"]}'::jsonb,
  null,
  null,
  'Describe the other farming type',
  'अन्य खेती का प्रकार लिखें',
  'इतर शेतीचा प्रकार लिहा',
  null,
  null,
  null
from land_section
on conflict (field_key) do update set
  label = excluded.label,
  label_hi = excluded.label_hi,
  label_mr = excluded.label_mr,
  input_type = excluded.input_type,
  sort_order = excluded.sort_order,
  is_required = excluded.is_required,
  validation = excluded.validation,
  visibility_rule = excluded.visibility_rule,
  dropdown_options_key = excluded.dropdown_options_key,
  hint_text = excluded.hint_text,
  hint_text_hi = excluded.hint_text_hi,
  hint_text_mr = excluded.hint_text_mr,
  is_active = true,
  updated_at = now();

update public.form_fields
set label_hi = 'क्या वन अधिकार पट्टा है?',
    label_mr = 'वन हक्क पट्टा आहे का?',
    updated_at = now()
where field_key = 'has_forest_patta';

update public.form_fields
set label_hi = 'वन अधिकार पट्टा क्षेत्र',
    label_mr = 'वन हक्क पट्टा क्षेत्र',
    updated_at = now()
where field_key = 'forest_patta_acre';

update public.form_fields
set label_hi = 'क्या वन अधिकार पट्टा के लिए आवेदन किया?',
    label_mr = 'वन हक्क पट्ट्यासाठी अर्ज केला आहे का?',
    updated_at = now()
where field_key = 'applied_for_forest_patta';
