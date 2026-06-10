create extension if not exists pgcrypto;
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
create or replace function public.is_valid_geojson_polygon(value jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  ring jsonb;
  point jsonb;
  first_point jsonb;
  last_point jsonb;
  point_count integer;
  idx integer;
  lng numeric;
  lat numeric;
begin
  if value is null or jsonb_typeof(value) is distinct from 'object' or value ->> 'type' <> 'Polygon' then
    return false;
  end if;

  if jsonb_typeof(value -> 'coordinates') is distinct from 'array' or jsonb_array_length(value -> 'coordinates') < 1 then
    return false;
  end if;

  ring := value -> 'coordinates' -> 0;
  if jsonb_typeof(ring) is distinct from 'array' then
    return false;
  end if;

  point_count := jsonb_array_length(ring);
  if point_count < 4 then
    return false;
  end if;

  first_point := ring -> 0;
  last_point := ring -> (point_count - 1);
  if first_point <> last_point then
    return false;
  end if;

  for idx in 0..point_count - 1 loop
    point := ring -> idx;
    if jsonb_typeof(point) is distinct from 'array' or jsonb_array_length(point) <> 2 then
      return false;
    end if;

    if jsonb_typeof(point -> 0) is distinct from 'number' or jsonb_typeof(point -> 1) is distinct from 'number' then
      return false;
    end if;

    lng := (point ->> 0)::numeric;
    lat := (point ->> 1)::numeric;

    if lng < -180 or lng > 180 or lat < -90 or lat > 90 then
      return false;
    end if;
  end loop;

  return true;
exception
  when others then
    return false;
end;
$$;
create or replace function public.is_valid_current_location(value jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  lat numeric;
  lng numeric;
begin
  if value is null then
    return true;
  end if;

  if jsonb_typeof(value) is distinct from 'object' then
    return false;
  end if;

  if jsonb_typeof(value -> 'lat') is distinct from 'number' or jsonb_typeof(value -> 'lng') is distinct from 'number' then
    return false;
  end if;

  lat := (value ->> 'lat')::numeric;
  lng := (value ->> 'lng')::numeric;

  if lat < -90 or lat > 90 or lng < -180 or lng > 180 then
    return false;
  end if;

  if value ? 'accuracyMeters' and jsonb_typeof(value -> 'accuracyMeters') is distinct from 'number' then
    return false;
  end if;

  return true;
exception
  when others then
    return false;
end;
$$;
create table public.farmer_ai_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 120),
  phone text null check (phone is null or char_length(phone) <= 40),
  preferred_language text not null default 'en' check (char_length(preferred_language) between 2 and 16),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.farmer_ai_farms (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.farmer_ai_profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 160),
  location_label text not null check (char_length(trim(location_label)) between 1 and 240),
  current_location jsonb null check (public.is_valid_current_location(current_location)),
  geometry jsonb not null check (public.is_valid_geojson_polygon(geometry)),
  area_hectares numeric not null check (area_hectares between 0.01 and 10000),
  area_acres numeric null check (area_acres is null or area_acres > 0),
  perimeter_meters numeric null check (perimeter_meters is null or perimeter_meters > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.farmer_ai_intakes (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farmer_ai_farms(id) on delete cascade,
  farmer_name text not null check (char_length(trim(farmer_name)) between 1 and 120),
  crop_id text not null check (char_length(trim(crop_id)) between 1 and 80),
  secondary_crop_ids text[] not null default '{}',
  season text not null check (season in ('kharif', 'rabi', 'summer', 'perennial')),
  irrigation text not null check (irrigation in ('rainfed', 'limited', 'drip', 'canal', 'borewell')),
  weekly_hours integer not null check (weekly_hours between 1 and 80),
  budget text not null check (budget in ('lean', 'balanced', 'premium')),
  soil_test text not null check (soil_test in ('available', 'not_available', 'planned')),
  experience text not null check (experience in ('new', 'some', 'experienced')),
  intent text not null check (intent in ('home-food', 'market-income', 'soil-building', 'low-water', 'learning', 'mixed')),
  crop_intent text not null check (crop_intent in ('cash-crop', 'horticulture', 'flowers', 'timber', 'orchard', 'food', 'low-water', 'mixed-agroforestry', 'not-sure')),
  intercropping boolean not null default false,
  plot_zones jsonb not null default '[]'::jsonb check (jsonb_typeof(plot_zones) = 'array'),
  constraints text[] not null default '{}',
  resource_notes text not null default '' check (char_length(resource_notes) <= 2000),
  farmer_goal text not null default '' check (char_length(farmer_goal) <= 1000),
  created_at timestamptz not null default now()
);
create table public.farmer_ai_plans (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farmer_ai_farms(id) on delete cascade,
  intake_id uuid not null references public.farmer_ai_intakes(id) on delete cascade,
  plan jsonb not null check (jsonb_typeof(plan) = 'object'),
  provider text not null default 'fallback' check (provider in ('gemini', 'qwen', 'deepseek', 'fallback')),
  model text not null default 'deterministic' check (char_length(model) between 1 and 120),
  used_fallback boolean not null default true,
  used_ai boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.farmer_ai_chat_sessions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.farmer_ai_profiles(id) on delete cascade,
  farm_id uuid null references public.farmer_ai_farms(id) on delete set null,
  plan_id uuid null references public.farmer_ai_plans(id) on delete set null,
  title text not null default 'Farm plan chat' check (char_length(trim(title)) between 1 and 160),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.farmer_ai_chat_messages (
  id uuid primary key default gen_random_uuid(),
  chat_session_id uuid not null references public.farmer_ai_chat_sessions(id) on delete cascade,
  role text not null check (role in ('farmer', 'agent')),
  text text not null check (char_length(trim(text)) between 1 and 8000),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now()
);
create table public.farmer_ai_photo_uploads (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.farmer_ai_profiles(id) on delete cascade,
  farm_id uuid null references public.farmer_ai_farms(id) on delete set null,
  plan_id uuid null references public.farmer_ai_plans(id) on delete set null,
  follow_up_task_id text null check (follow_up_task_id is null or char_length(follow_up_task_id) <= 120),
  storage_bucket text not null default 'field-photos' check (storage_bucket = 'field-photos'),
  storage_path text not null check (char_length(storage_path) between 1 and 600),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  size_bytes integer not null check (size_bytes > 0 and size_bytes <= 8388608),
  caption text null check (caption is null or char_length(caption) <= 1000),
  zone_id text null check (zone_id is null or char_length(zone_id) <= 120),
  created_at timestamptz not null default now()
);
create trigger set_farmer_ai_profiles_updated_at
before update on public.farmer_ai_profiles
for each row
execute function public.set_updated_at();
create trigger set_farmer_ai_farms_updated_at
before update on public.farmer_ai_farms
for each row
execute function public.set_updated_at();
create trigger set_farmer_ai_chat_sessions_updated_at
before update on public.farmer_ai_chat_sessions
for each row
execute function public.set_updated_at();
create index farmer_ai_farms_profile_id_idx on public.farmer_ai_farms(profile_id);
create index farmer_ai_intakes_farm_id_idx on public.farmer_ai_intakes(farm_id);
create index farmer_ai_plans_farm_id_created_at_idx on public.farmer_ai_plans(farm_id, created_at desc);
create index farmer_ai_plans_intake_id_idx on public.farmer_ai_plans(intake_id);
create index farmer_ai_chat_sessions_profile_updated_idx on public.farmer_ai_chat_sessions(profile_id, updated_at desc);
create index farmer_ai_chat_sessions_plan_id_idx on public.farmer_ai_chat_sessions(plan_id);
create index farmer_ai_chat_messages_session_created_idx on public.farmer_ai_chat_messages(chat_session_id, created_at);
create index farmer_ai_photo_uploads_profile_created_idx on public.farmer_ai_photo_uploads(profile_id, created_at desc);
create index farmer_ai_photo_uploads_plan_id_idx on public.farmer_ai_photo_uploads(plan_id);
alter table public.farmer_ai_profiles enable row level security;
alter table public.farmer_ai_farms enable row level security;
alter table public.farmer_ai_intakes enable row level security;
alter table public.farmer_ai_plans enable row level security;
alter table public.farmer_ai_chat_sessions enable row level security;
alter table public.farmer_ai_chat_messages enable row level security;
alter table public.farmer_ai_photo_uploads enable row level security;
create policy "farmer_ai_profiles select own"
on public.farmer_ai_profiles for select to authenticated
using (user_id = auth.uid());
create policy "farmer_ai_profiles insert own"
on public.farmer_ai_profiles for insert to authenticated
with check (user_id = auth.uid());
create policy "farmer_ai_profiles update own"
on public.farmer_ai_profiles for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());
create policy "farmer_ai_profiles delete own"
on public.farmer_ai_profiles for delete to authenticated
using (user_id = auth.uid());
create policy "farmer_ai_farms select own"
on public.farmer_ai_farms for select to authenticated
using (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_farms.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer_ai_farms insert own"
on public.farmer_ai_farms for insert to authenticated
with check (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_farms.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer_ai_farms update own"
on public.farmer_ai_farms for update to authenticated
using (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_farms.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_farms.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer_ai_farms delete own"
on public.farmer_ai_farms for delete to authenticated
using (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_farms.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer intakes select own"
on public.farmer_ai_intakes for select to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_intakes.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer intakes insert own"
on public.farmer_ai_intakes for insert to authenticated
with check (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_intakes.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer intakes update own"
on public.farmer_ai_intakes for update to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_intakes.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_intakes.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer intakes delete own"
on public.farmer_ai_intakes for delete to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_intakes.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer_ai_plans select own"
on public.farmer_ai_plans for select to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_plans.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer_ai_plans insert own"
on public.farmer_ai_plans for insert to authenticated
with check (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_plans.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer_ai_plans update own"
on public.farmer_ai_plans for update to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_plans.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_plans.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "farmer_ai_plans delete own"
on public.farmer_ai_plans for delete to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_farms
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id
    where farmer_ai_farms.id = farmer_ai_plans.farm_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "chat sessions select own"
on public.farmer_ai_chat_sessions for select to authenticated
using (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "chat sessions insert own"
on public.farmer_ai_chat_sessions for insert to authenticated
with check (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "chat sessions update own"
on public.farmer_ai_chat_sessions for update to authenticated
using (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "chat sessions delete own"
on public.farmer_ai_chat_sessions for delete to authenticated
using (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "chat messages select own"
on public.farmer_ai_chat_messages for select to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_chat_sessions
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
    where farmer_ai_chat_sessions.id = farmer_ai_chat_messages.chat_session_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "chat messages insert own"
on public.farmer_ai_chat_messages for insert to authenticated
with check (
  exists (
    select 1
    from public.farmer_ai_chat_sessions
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
    where farmer_ai_chat_sessions.id = farmer_ai_chat_messages.chat_session_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "chat messages update own"
on public.farmer_ai_chat_messages for update to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_chat_sessions
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
    where farmer_ai_chat_sessions.id = farmer_ai_chat_messages.chat_session_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.farmer_ai_chat_sessions
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
    where farmer_ai_chat_sessions.id = farmer_ai_chat_messages.chat_session_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "chat messages delete own"
on public.farmer_ai_chat_messages for delete to authenticated
using (
  exists (
    select 1
    from public.farmer_ai_chat_sessions
    join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_chat_sessions.profile_id
    where farmer_ai_chat_sessions.id = farmer_ai_chat_messages.chat_session_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "photo uploads select own"
on public.farmer_ai_photo_uploads for select to authenticated
using (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_photo_uploads.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "photo uploads insert own"
on public.farmer_ai_photo_uploads for insert to authenticated
with check (
  storage_bucket = 'field-photos'
  and storage_path like (auth.uid()::text || '/%')
  and exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_photo_uploads.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "photo uploads update own"
on public.farmer_ai_photo_uploads for update to authenticated
using (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_photo_uploads.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
)
with check (
  storage_bucket = 'field-photos'
  and storage_path like (auth.uid()::text || '/%')
  and exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_photo_uploads.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create policy "photo uploads delete own"
on public.farmer_ai_photo_uploads for delete to authenticated
using (
  exists (
    select 1 from public.farmer_ai_profiles
    where farmer_ai_profiles.id = farmer_ai_photo_uploads.profile_id
      and farmer_ai_profiles.user_id = auth.uid()
  )
);
create or replace view public.farmer_ai_advice_history
with (security_invoker = true)
as
select
  farmer_ai_profiles.id as profile_id,
  farmer_ai_plans.id as plan_id,
  farmer_ai_farms.id as farm_id,
  farmer_ai_farms.name as farm_name,
  farmer_ai_farms.location_label,
  coalesce(farmer_ai_plans.plan #>> '{cropProfile,id}', '') as crop_id,
  coalesce(farmer_ai_plans.plan #>> '{cropProfile,name}', '') as crop_name,
  farmer_ai_plans.created_at as generated_at,
  farmer_ai_plans.provider,
  farmer_ai_plans.used_fallback,
  (
    select farmer_ai_chat_messages.text
    from public.farmer_ai_chat_sessions
    join public.farmer_ai_chat_messages on farmer_ai_chat_messages.chat_session_id = farmer_ai_chat_sessions.id
    where farmer_ai_chat_sessions.plan_id = farmer_ai_plans.id
    order by farmer_ai_chat_messages.created_at desc
    limit 1
  ) as latest_chat_snippet,
  (
    select farmer_ai_chat_messages.created_at
    from public.farmer_ai_chat_sessions
    join public.farmer_ai_chat_messages on farmer_ai_chat_messages.chat_session_id = farmer_ai_chat_sessions.id
    where farmer_ai_chat_sessions.plan_id = farmer_ai_plans.id
    order by farmer_ai_chat_messages.created_at desc
    limit 1
  ) as latest_chat_at,
  (
    select count(*)::integer
    from jsonb_array_elements(coalesce(farmer_ai_plans.plan -> 'followUps', '[]'::jsonb)) as follow_up(item)
    where coalesce(follow_up.item ->> 'status', 'todo') <> 'done'
  ) as due_follow_ups,
  jsonb_array_length(coalesce(farmer_ai_plans.plan -> 'needsVerification', '[]'::jsonb)) as verification_count,
  (
    select count(*)::integer
    from public.farmer_ai_photo_uploads
    where farmer_ai_photo_uploads.plan_id = farmer_ai_plans.id
  ) as photo_count
from public.farmer_ai_plans
join public.farmer_ai_farms on farmer_ai_farms.id = farmer_ai_plans.farm_id
join public.farmer_ai_profiles on farmer_ai_profiles.id = farmer_ai_farms.profile_id;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'field-photos',
  'field-photos',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
create policy "field photos select own"
on storage.objects for select to authenticated
using (
  bucket_id = 'field-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);
create policy "field photos insert own"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'field-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);
create policy "field photos update own"
on storage.objects for update to authenticated
using (
  bucket_id = 'field-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'field-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);
create policy "field photos delete own"
on storage.objects for delete to authenticated
using (
  bucket_id = 'field-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);
grant usage on schema public to authenticated;
grant select, insert, update, delete on
  public.farmer_ai_profiles,
  public.farmer_ai_farms,
  public.farmer_ai_intakes,
  public.farmer_ai_plans,
  public.farmer_ai_chat_sessions,
  public.farmer_ai_chat_messages,
  public.farmer_ai_photo_uploads
to authenticated;
grant select on public.farmer_ai_advice_history to authenticated;
