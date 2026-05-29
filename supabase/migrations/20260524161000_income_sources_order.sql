with desired(value, label, sort_order) as (
  values
    ('farming', 'Farming', 10),
    ('private_job', 'Private Job', 20),
    ('govt_job', 'Government Job', 30),
    ('business', 'Business', 40),
    ('other', 'Other', 50)
)
update public.dropdown_options as option
set
  label = desired.label,
  sort_order = desired.sort_order
from desired
where option.option_key = 'income_sources_v2'
  and option.value = desired.value;
