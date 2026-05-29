alter table public.farmer_surveys add column if not exists disease_present boolean;
alter table public.farmer_surveys add column if not exists disease_name text;
alter table public.farmer_surveys add column if not exists affected_crop text;
alter table public.farmer_surveys add column if not exists disease_severity text;
alter table public.farmer_surveys add column if not exists symptoms_observed text;
alter table public.farmer_surveys add column if not exists treatment_taken text;
update public.form_fields
set label_mr = 'पाण्याखालील जमीन'
where field_key = 'irrigated_land_acre';
update public.form_fields
set label_mr = 'पडीक जमीन'
where field_key = 'fallow_land_acre';
update public.form_fields
set label_mr = 'भाड्याने घेतलेली जमीन'
where field_key = 'leased_land_acre';
update public.form_fields
set label_mr = 'शेतीव्यतिरिक्त उत्पादन'
where field_key = 'non_agri_income';
update public.dropdown_options
set label_mr = 'पाण्याखालील'
where option_key = 'farming_type_v2'
  and value = 'irrigated';
do $$
declare
  disease_section_id uuid;
begin
  select id into disease_section_id
  from public.form_sections
  where title = 'Disease'
  order by created_at
  limit 1;

  if disease_section_id is null then
    insert into public.form_sections (
      title,
      title_hi,
      title_mr,
      icon_name,
      sort_order,
      is_active
    )
    values ('Disease', 'रोग', 'रोग', 'eco_outlined', 100, true)
    returning id into disease_section_id;
  else
    update public.form_sections
    set title_hi = 'रोग',
        title_mr = 'रोग',
        icon_name = 'eco_outlined',
        sort_order = 100,
        is_active = true,
        updated_at = now()
    where id = disease_section_id;
  end if;

  delete from public.form_fields
  where field_key in (
    'disease_present',
    'disease_name',
    'affected_crop',
    'disease_severity',
    'symptoms_observed',
    'treatment_taken'
  );

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
  values
    (
      disease_section_id,
      'disease_present',
      'Any Disease Observed?',
      'क्या कोई रोग दिखाई दिया?',
      'कोणताही रोग दिसला का?',
      'boolean',
      1,
      false,
      '{}'::jsonb,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null
    ),
    (
      disease_section_id,
      'disease_name',
      'Disease Name',
      'रोग का नाम',
      'रोगाचे नाव',
      'text',
      2,
      false,
      '{"min_length":2}'::jsonb,
      '{"depends_on":"disease_present","operator":"equals","value":true}'::jsonb,
      null,
      null,
      'e.g. Blast, Rust, Smut',
      null,
      null,
      null,
      null,
      null
    ),
    (
      disease_section_id,
      'affected_crop',
      'Affected Crop',
      'प्रभावित फसल',
      'बाधित पीक',
      'text',
      3,
      false,
      '{}'::jsonb,
      '{"depends_on":"disease_present","operator":"equals","value":true}'::jsonb,
      null,
      null,
      'Enter crop name',
      null,
      null,
      null,
      null,
      null
    ),
    (
      disease_section_id,
      'disease_severity',
      'Disease Severity',
      'रोग की गंभीरता',
      'रोगाची तीव्रता',
      'dropdown',
      4,
      false,
      '{}'::jsonb,
      '{"depends_on":"disease_present","operator":"equals","value":true}'::jsonb,
      null,
      'disease_severity',
      null,
      null,
      null,
      null,
      null,
      null
    ),
    (
      disease_section_id,
      'symptoms_observed',
      'Symptoms Observed',
      'देखे गए लक्षण',
      'दिसलेली लक्षणे',
      'textarea',
      5,
      false,
      '{}'::jsonb,
      '{"depends_on":"disease_present","operator":"equals","value":true}'::jsonb,
      null,
      null,
      'Write key symptoms',
      null,
      null,
      null,
      null,
      null
    ),
    (
      disease_section_id,
      'treatment_taken',
      'Treatment Taken',
      'किया गया उपचार',
      'केलेली उपाययोजना',
      'textarea',
      6,
      false,
      '{}'::jsonb,
      '{"depends_on":"disease_present","operator":"equals","value":true}'::jsonb,
      null,
      null,
      'Fungicide, biocontrol, etc.',
      null,
      null,
      null,
      null,
      null
    );
end $$;
delete from public.dropdown_options
where option_key = 'disease_severity';
insert into public.dropdown_options (
  option_key,
  value,
  label,
  label_hi,
  label_mr,
  sort_order,
  is_active
)
values
  ('disease_severity', 'Mild', 'Mild', 'हल्का', 'सौम्य', 10, true),
  ('disease_severity', 'Moderate', 'Moderate', 'मध्यम', 'मध्यम', 20, true),
  ('disease_severity', 'Severe', 'Severe', 'गंभीर', 'गंभीर', 30, true);
