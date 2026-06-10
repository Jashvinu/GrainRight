with kharif_summary as (
  select
    survey_id,
    string_agg(
      concat_ws(
        '',
        nullif(crop_name, '') || ': ',
        production_qty::text,
        case when production_qty_unit is null or production_qty_unit = '' then '' else ' ' || production_qty_unit end
      ),
      '; ' order by position
    ) filter (where production_qty is not null) as kharif_crop_production_units
  from public.survey_kharif_crops_export
  group by survey_id
),
yearly_summary as (
  select
    survey_id,
    string_agg(
      concat_ws(
        '',
        year::text || ': ',
        total_production::text,
        case when total_production_unit is null or total_production_unit = '' then '' else ' ' || total_production_unit end
      ),
      '; ' order by year
    ) filter (where total_production is not null) as main_crop_yearly_total_production_units,
    string_agg(
      concat_ws(
        '',
        year::text || ': ',
        yield_avg_per_acre::text,
        case when yield_avg_per_acre_unit is null or yield_avg_per_acre_unit = '' then '' else ' ' || yield_avg_per_acre_unit end
      ),
      '; ' order by year
    ) filter (where yield_avg_per_acre is not null) as main_crop_yearly_yield_avg_per_acre_units,
    string_agg(
      concat_ws(
        '',
        year::text || ': ',
        home_consumption::text,
        case when home_consumption_unit is null or home_consumption_unit = '' then '' else ' ' || home_consumption_unit end
      ),
      '; ' order by year
    ) filter (where home_consumption is not null) as main_crop_yearly_home_consumption_units,
    string_agg(
      concat_ws(
        '',
        year::text || ': ',
        quantity_sold::text,
        case when quantity_sold_unit is null or quantity_sold_unit = '' then '' else ' ' || quantity_sold_unit end
      ),
      '; ' order by year
    ) filter (where quantity_sold is not null) as main_crop_yearly_quantity_sold_units,
    string_agg(year::text || ': ' || sold_where, '; ' order by year)
      filter (where sold_where is not null and btrim(sold_where) <> '') as main_crop_yearly_sold_where,
    string_agg(year::text || ': ' || sold_where_other, '; ' order by year)
      filter (where sold_where_other is not null and btrim(sold_where_other) <> '') as main_crop_yearly_sold_where_other
  from public.survey_main_crop_yearly_export
  group by survey_id
),
practice_parts as (
  select
    survey_id,
    crop_role,
    concat_ws(
      ', ',
      case
        when matka_per_acre is null then null
        else 'Matka ' || matka_per_acre::text ||
          case when matka_per_acre_unit is null or matka_per_acre_unit = '' then '' else ' ' || matka_per_acre_unit end
      end,
      case
        when neem_per_acre is null then null
        else 'Neem ' || neem_per_acre::text ||
          case when neem_per_acre_unit is null or neem_per_acre_unit = '' then '' else ' ' || neem_per_acre_unit end
      end,
      case
        when jeevamrut_per_acre is null then null
        else 'Jeevamrut ' || jeevamrut_per_acre::text ||
          case when jeevamrut_per_acre_unit is null or jeevamrut_per_acre_unit = '' then '' else ' ' || jeevamrut_per_acre_unit end
      end,
      case
        when pesticide_per_acre is null then null
        else 'Pesticide ' || pesticide_per_acre::text ||
          case when pesticide_per_acre_unit is null or pesticide_per_acre_unit = '' then '' else ' ' || pesticide_per_acre_unit end
      end
    ) as spray_summary
  from public.survey_crop_practices_export
),
practice_summary as (
  select
    survey_id,
    string_agg(crop_role || ': ' || spray_summary, '; ' order by crop_role)
      filter (where spray_summary is not null and spray_summary <> '') as crop_practice_spray_units
  from practice_parts
  group by survey_id
),
survey_rows as (
  select
    f.*,
    row_number() over (order by coalesce(f.submitted_at, f.created_at) asc, f.id asc) as sl_no,
    k.kharif_crop_production_units,
    y.main_crop_yearly_total_production_units,
    y.main_crop_yearly_yield_avg_per_acre_units,
    y.main_crop_yearly_home_consumption_units,
    y.main_crop_yearly_quantity_sold_units,
    y.main_crop_yearly_sold_where,
    y.main_crop_yearly_sold_where_other,
    p.crop_practice_spray_units
  from public.farmer_surveys_export f
  left join kharif_summary k on k.survey_id = f.id
  left join yearly_summary y on y.survey_id = f.id
  left join practice_summary p on p.survey_id = f.id
)
select
  id,
  sl_no,
  survey_date,
  null::text as season,
  farmer_name,
  gender,
  date_of_birth,
  category,
  education_level,
  village_gp,
  block,
  district,
  null::text as fpc_name,
  aadhar_no,
  mobile_no,
  land_owned,
  land_leased,
  total_rainfed_land,
  total_irrigated_land,
  land_under_millet,
  land_under_other_crops,
  null::numeric as cropping_intensity,
  null::text as major_crops_grown,
  null::text as millet_seed_type,
  null::text as millet_seed_variety,
  null::numeric as seed_used_kg_per_acre,
  null::numeric as fertilizer_used_kg_per_acre,
  null::numeric as pesticide_used_litres_per_acre,
  null::boolean as use_bio_fertilizer,
  null::boolean as access_to_credit,
  null::boolean as access_to_extension_services,
  null::text as mechanization_access,
  null::numeric as millet_productivity,
  null::numeric as other_crops_productivity,
  null::numeric as total_millet_production,
  null::numeric as quantity_millet_sold,
  null::numeric as quantity_home_consumption,
  null::numeric as quantity_used_as_seed,
  null::numeric as avg_millet_selling_price,
  null::text as post_harvest_practices,
  null::text as where_produce_sold,
  kharif_crop_production_units,
  main_crop_yearly_total_production_units,
  main_crop_yearly_yield_avg_per_acre_units,
  main_crop_yearly_home_consumption_units,
  main_crop_yearly_quantity_sold_units,
  main_crop_yearly_sold_where,
  main_crop_yearly_sold_where_other,
  crop_practice_spray_units,
  null::boolean as training_received,
  null::text as training_source,
  null::numeric as avg_cost_cultivation_millets,
  null::numeric as net_income_millets,
  null::numeric as avg_cost_cultivation_other,
  null::numeric as net_income_other_crops,
  total_cultivation_cost,
  array_to_string(sources_of_income, ', ') as sources_of_income,
  annual_agri_income,
  annual_non_agri_income,
  total_annual_income,
  created_at,
  updated_at,
  null::text as millet_land_areas,
  form_latitude,
  form_longitude,
  form_location_accuracy,
  form_started_at,
  language,
  gram_panchayat,
  income_sources_other,
  array_to_string(farming_type, ', ') as farming_type,
  farming_type_other,
  owns_farmland,
  dry_land_acre,
  fallow_land_acre,
  has_forest_patta,
  forest_patta_acre,
  applied_for_forest_patta,
  main_crop,
  main_crop_other,
  land_under_other_crops as other_crop_land_acre,
  other_crop_details,
  farm_polygon::text as farm_polygon,
  makes_food_products,
  food_products_list,
  food_product_training_received,
  food_product_training_source,
  disease_present,
  disease_name,
  affected_crop,
  disease_severity,
  symptoms_observed,
  treatment_taken,
  submitted_at
from survey_rows
order by coalesce(submitted_at, created_at) desc, id;
