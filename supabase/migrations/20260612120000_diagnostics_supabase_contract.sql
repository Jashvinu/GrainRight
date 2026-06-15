create extension if not exists pgcrypto;

create table if not exists public.farms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 160),
  geometry jsonb not null check (public.is_valid_geojson_polygon(geometry)),
  bounds jsonb null check (bounds is null or jsonb_typeof(bounds) = 'object'),
  area_hectares numeric not null check (area_hectares > 0),
  area_acres numeric null check (area_acres is null or area_acres > 0),
  user_id uuid null references auth.users(id) on delete cascade,
  crop text null,
  variety text null,
  previous_crop text null,
  season text null,
  irrigation text null,
  soil_type text null,
  ownership_type text null,
  seed_source text null,
  harvest_intent text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.farms add column if not exists bounds jsonb;
alter table public.farms add column if not exists area_acres numeric;
alter table public.farms add column if not exists crop text;
alter table public.farms add column if not exists variety text;
alter table public.farms add column if not exists previous_crop text;
alter table public.farms add column if not exists season text;
alter table public.farms add column if not exists irrigation text;
alter table public.farms add column if not exists soil_type text;
alter table public.farms add column if not exists ownership_type text;
alter table public.farms add column if not exists seed_source text;
alter table public.farms add column if not exists harvest_intent text;
alter table public.farms add column if not exists updated_at timestamptz not null default now();

create index if not exists farms_user_created_idx on public.farms(user_id, created_at desc);

drop trigger if exists set_farms_updated_at on public.farms;
create trigger set_farms_updated_at
before update on public.farms
for each row
execute function public.set_updated_at();

alter table public.farms enable row level security;

drop policy if exists "farms select own" on public.farms;
create policy "farms select own"
on public.farms for select to authenticated
using (user_id = auth.uid());

drop policy if exists "farms insert own" on public.farms;
create policy "farms insert own"
on public.farms for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "farms update own" on public.farms;
create policy "farms update own"
on public.farms for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "farms delete own" on public.farms;
create policy "farms delete own"
on public.farms for delete to authenticated
using (user_id = auth.uid());

drop function if exists public.list_farms_geojson();
create or replace function public.list_farms_geojson()
returns table (
  id uuid,
  name text,
  geometry jsonb,
  bounds jsonb,
  area_hectares numeric,
  area_acres numeric,
  user_id uuid,
  crop text,
  variety text,
  previous_crop text,
  season text,
  irrigation text,
  soil_type text,
  ownership_type text,
  seed_source text,
  harvest_intent text,
  created_at timestamptz
)
language plpgsql
stable
security invoker
as $$
declare
  geometry_type text;
begin
  select format_type(a.atttypid, a.atttypmod)
  into geometry_type
  from pg_attribute a
  where a.attrelid = 'public.farms'::regclass
    and a.attname = 'geometry'
    and not a.attisdropped;

  if geometry_type = 'jsonb' then
    return query execute $q$
      select
        f.id,
        f.name,
        f.geometry,
        f.bounds,
        f.area_hectares,
        f.area_acres,
        f.user_id,
        f.crop,
        f.variety,
        f.previous_crop,
        f.season,
        f.irrigation,
        f.soil_type,
        f.ownership_type,
        f.seed_source,
        f.harvest_intent,
        f.created_at
      from public.farms f
      where f.user_id = auth.uid()
      order by f.created_at desc
    $q$;
    return;
  end if;

  return query execute $q$
    select
      f.id,
      f.name,
      st_asgeojson(f.geometry)::jsonb,
      f.bounds,
      f.area_hectares,
      f.area_acres,
      f.user_id,
      f.crop,
      f.variety,
      f.previous_crop,
      f.season,
      f.irrigation,
      f.soil_type,
      f.ownership_type,
      f.seed_source,
      f.harvest_intent,
      f.created_at
    from public.farms f
    where f.user_id = auth.uid()
    order by f.created_at desc
  $q$;
end;
$$;

grant execute on function public.list_farms_geojson() to authenticated;

create table if not exists public.diagnostics_cache (
  farm_id uuid primary key references public.farms(id) on delete cascade,
  generated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  date_range jsonb not null default '{}'::jsonb check (jsonb_typeof(date_range) = 'object'),
  season text not null,
  indices text[] not null default '{}',
  raster_urls jsonb not null default '{}'::jsonb check (jsonb_typeof(raster_urls) = 'object'),
  bounds jsonb not null default '[[0,0],[0,0]]'::jsonb check (jsonb_typeof(bounds) = 'array'),
  cell_stats jsonb not null default '[]'::jsonb check (jsonb_typeof(cell_stats) = 'array'),
  analysis_summary jsonb not null default '{}'::jsonb check (jsonb_typeof(analysis_summary) = 'object')
);

create index if not exists diagnostics_cache_expires_at_idx
on public.diagnostics_cache(expires_at);

alter table public.diagnostics_cache enable row level security;

drop policy if exists "diagnostics cache select own" on public.diagnostics_cache;
create policy "diagnostics cache select own"
on public.diagnostics_cache for select to authenticated
using (
  exists (
    select 1 from public.farms
    where farms.id = diagnostics_cache.farm_id
      and farms.user_id = auth.uid()
  )
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('diagnostics', 'diagnostics', true, 10485760, array['image/png']),
  ('disease-photos', 'disease-photos', false, 8388608, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "diagnostics public read" on storage.objects;
create policy "diagnostics public read"
on storage.objects for select
using (bucket_id = 'diagnostics');

drop policy if exists "disease photo owner read" on storage.objects;
create policy "disease photo owner read"
on storage.objects for select to authenticated
using (
  bucket_id = 'disease-photos'
  and owner = auth.uid()
);

drop policy if exists "disease photo owner insert" on storage.objects;
create policy "disease photo owner insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'disease-photos'
  and owner = auth.uid()
);
