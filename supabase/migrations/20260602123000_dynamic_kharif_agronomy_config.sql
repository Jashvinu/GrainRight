update public.form_fields
set visibility_rule = null
where field_key in (
  'repeat_kharif_crops',
  'repeat_main_crop_practices',
  'repeat_other_crop_practices'
);

update public.form_fields
set
  label = 'Main Crop Agronomy practices',
  hint_text = 'Fill the agronomy practices for the first crop group selected in Kharif Crop 1.'
where field_key = 'repeat_main_crop_practices';

update public.form_fields
set
  label = 'Other Crop Agronomy practices',
  hint_text = 'Fill the agronomy practices for the opposite crop group from Kharif Crop 1.'
where field_key = 'repeat_other_crop_practices';
