update public.form_fields
set validation = jsonb_set(
  jsonb_set(
    coalesce(validation, '{}'::jsonb),
    '{date_min}',
    '"1930-01-01"'::jsonb,
    true
  ),
  '{date_max}',
  '"today"'::jsonb,
  true
)
where field_key = 'date_of_birth';
