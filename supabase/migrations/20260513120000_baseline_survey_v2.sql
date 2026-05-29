create extension if not exists pgcrypto;
create table if not exists public.form_sections (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  icon_name text not null default 'article',
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create table if not exists public.form_fields (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references public.form_sections(id) on delete cascade,
  field_key text not null,
  label text not null,
  input_type text not null,
  sort_order int not null default 0,
  is_required boolean not null default false,
  validation jsonb not null default '{}'::jsonb,
  visibility_rule jsonb,
  auto_calc_formula jsonb,
  dropdown_options_key text,
  hint_text text,
  suffix_text text,
  is_active boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (field_key)
);
create table if not exists public.dropdown_options (
  id uuid primary key default gen_random_uuid(),
  option_key text not null,
  value text not null,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default now(),
  unique (option_key, value)
);
do $$
begin
  if to_regclass('public.farmer_surveys') is not null
     and to_regclass('public.farmer_surveys_legacy_v1') is null then
    alter table public.farmer_surveys rename to farmer_surveys_legacy_v1;
  end if;
end $$;
create table if not exists public.farmer_surveys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  survey_date date not null default current_date,
  language text not null default 'en' check (language in ('en','hi','mr')),
  location_lat double precision,
  location_lng double precision,
  location_accuracy_m double precision,
  started_at timestamptz,
  submitted_at timestamptz,
  farmer_name text not null,
  village text,
  gram_panchayat text,
  taluka text,
  district text,
  mobile_number text,
  aadhaar_number text,
  date_of_birth date,
  education text,
  gender text,
  category text,
  income_sources text[] default '{}'::text[],
  farming_type text[] default '{}'::text[],
  owns_farmland boolean,
  total_land_area_acre numeric,
  irrigated_land_acre numeric,
  dry_land_acre numeric,
  fallow_land_acre numeric,
  leased_land_acre numeric,
  rain_based_area_acre numeric,
  has_forest_patta boolean,
  forest_patta_acre numeric,
  applied_for_forest_patta boolean,
  main_crop text,
  main_crop_other text,
  main_crop_land_acre numeric,
  farm_polygon jsonb,
  annual_agri_income numeric,
  non_agri_income numeric,
  total_annual_income numeric,
  makes_food_products boolean,
  food_products_list text,
  food_product_training_received boolean,
  food_product_training_source text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists farmer_surveys_user_idx on public.farmer_surveys(user_id);
create index if not exists farmer_surveys_main_crop_idx on public.farmer_surveys(main_crop);
create table if not exists public.survey_kharif_crops (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.farmer_surveys(id) on delete cascade,
  position smallint not null check (position between 1 and 8),
  crop_name text,
  cultivated_area_acre numeric,
  crop_variety text,
  production_qty numeric,
  avg_estimated_cost numeric,
  unique (survey_id, position)
);
create table if not exists public.survey_main_crop_yearly (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.farmer_surveys(id) on delete cascade,
  year smallint not null,
  area_acre numeric,
  total_production numeric,
  home_consumption numeric,
  quantity_sold numeric,
  sold_where text,
  selling_price numeric,
  unique (survey_id, year)
);
create table if not exists public.survey_crop_practices (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.farmer_surveys(id) on delete cascade,
  crop_role text not null check (crop_role in ('main','other')),
  grown_on text,
  same_land_every_year boolean,
  land_topology text,
  land_topology_other text,
  seed_sources text[] default '{}'::text[],
  seed_source_other text,
  pop_training_received boolean,
  pop_training_source text,
  farming_method text,
  treats_seeds boolean,
  seed_treatment_materials text[] default '{}'::text[],
  seedling_method text,
  seedling_method_other text,
  seedling_ready_days int,
  seedling_method_difference text,
  land_prep_tractor_days numeric,
  land_prep_tractor_cost numeric,
  land_prep_bullock_days numeric,
  land_prep_bullock_cost numeric,
  land_prep_by_hand boolean,
  transplant_method text,
  dip_in_jeevamrut boolean,
  plant_spacing_cm numeric,
  transplant_days int,
  needs_transplant_labour boolean,
  transplant_labourers int,
  transplant_daily_wage numeric,
  does_weeding boolean,
  weeding_after_days int,
  sprays_for_pest boolean,
  spray_methods text[] default '{}'::text[],
  matka_per_acre numeric,
  neem_per_acre numeric,
  spray_methods_other text,
  organic_fert_helps_disease boolean,
  planting_to_flowering_days int,
  uses_fertilizer boolean,
  fertilizer_names text,
  fertilizer_qty_per_acre numeric,
  flowering_pest_problem boolean,
  flowering_pest_type text,
  flowering_sprays_used text,
  maturity_days int,
  monitors_crop boolean,
  monitoring_methods text[] default '{}'::text[],
  harvest_method text,
  harvest_labour_type text,
  harvest_daily_wage numeric,
  harvest_labourers int,
  harvest_days int,
  ready_to_eat_or_sell_days int,
  sells_main_crop boolean,
  selling_time text,
  unique (survey_id, crop_role)
);
alter table public.form_fields add column if not exists crop_role text;
alter table public.form_fields add column if not exists repeat_group text;
alter table public.form_fields add column if not exists hint_text_hi text;
alter table public.form_fields add column if not exists hint_text_mr text;
alter table public.form_fields add column if not exists label_hi text;
alter table public.form_fields add column if not exists label_mr text;
alter table public.dropdown_options add column if not exists label_hi text;
alter table public.dropdown_options add column if not exists label_mr text;
alter table public.form_sections enable row level security;
alter table public.form_fields enable row level security;
alter table public.dropdown_options enable row level security;
alter table public.farmer_surveys enable row level security;
alter table public.survey_kharif_crops enable row level security;
alter table public.survey_main_crop_yearly enable row level security;
alter table public.survey_crop_practices enable row level security;
create policy "public can read form sections" on public.form_sections
  for select using (is_active = true);
create policy "public can read form fields" on public.form_fields
  for select using (is_active = true);
create policy "public can read dropdown options" on public.dropdown_options
  for select using (is_active = true);
create policy "farmers select own surveys" on public.farmer_surveys
  for select using (auth.uid() = user_id);
create policy "farmers insert own surveys" on public.farmer_surveys
  for insert with check (auth.uid() = user_id or user_id is null);
create policy "farmers update own surveys" on public.farmer_surveys
  for update using (auth.uid() = user_id);
create policy "farmers select own kharif crops" on public.survey_kharif_crops
  for select using (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ));
create policy "farmers insert own kharif crops" on public.survey_kharif_crops
  for insert with check (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and (s.user_id = auth.uid() or s.user_id is null)
  ));
create policy "farmers select own yearly production" on public.survey_main_crop_yearly
  for select using (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ));
create policy "farmers insert own yearly production" on public.survey_main_crop_yearly
  for insert with check (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and (s.user_id = auth.uid() or s.user_id is null)
  ));
create policy "farmers select own crop practices" on public.survey_crop_practices
  for select using (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ));
create policy "farmers insert own crop practices" on public.survey_crop_practices
  for insert with check (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and (s.user_id = auth.uid() or s.user_id is null)
  ));
grant usage on schema public to anon, authenticated;
grant select on public.form_sections to anon, authenticated;
grant select on public.form_fields to anon, authenticated;
grant select on public.dropdown_options to anon, authenticated;
grant select, insert, update on public.farmer_surveys to anon, authenticated;
grant select, insert on public.survey_kharif_crops to anon, authenticated;
grant select, insert on public.survey_main_crop_yearly to anon, authenticated;
grant select, insert on public.survey_crop_practices to anon, authenticated;
