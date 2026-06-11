create table if not exists public.farmer_phone_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  phone text not null,
  farmer_id text,
  farmer_name text,
  default_location text,
  preferred_language text not null default 'en',
  auth_method text not null default 'anonymous_link'
    check (auth_method in ('anonymous_link', 'phone_otp')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists farmer_phone_profiles_phone_idx
on public.farmer_phone_profiles(phone);

alter table public.farmer_phone_profiles enable row level security;

create policy "farmer_phone_profiles select own"
on public.farmer_phone_profiles for select to authenticated
using (user_id = auth.uid());

create policy "farmer_phone_profiles insert own"
on public.farmer_phone_profiles for insert to authenticated
with check (user_id = auth.uid());

create policy "farmer_phone_profiles update own"
on public.farmer_phone_profiles for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

do $$
begin
  if to_regclass('public.farms') is not null then
    alter table public.farms add column if not exists crop text;
    alter table public.farms add column if not exists variety text;
    alter table public.farms add column if not exists area_acres numeric;
    alter table public.farms add column if not exists previous_crop text;
    alter table public.farms add column if not exists season text;
    alter table public.farms add column if not exists irrigation text;
    alter table public.farms add column if not exists soil_type text;
    alter table public.farms add column if not exists ownership_type text;
    alter table public.farms add column if not exists seed_source text;
    alter table public.farms add column if not exists harvest_intent text;
  end if;
end $$;
