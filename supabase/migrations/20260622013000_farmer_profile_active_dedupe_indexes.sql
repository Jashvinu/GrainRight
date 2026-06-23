create index if not exists farmer_phone_profiles_user_status_phone_idx
  on public.farmer_phone_profiles (user_id, status, phone);

create index if not exists farmer_phone_profiles_phone_status_idx
  on public.farmer_phone_profiles (phone, status);

create index if not exists farmer_phone_profiles_farmer_id_status_idx
  on public.farmer_phone_profiles (farmer_id, status);

create index if not exists farmer_phone_profiles_active_phone_farmer_updated_idx
  on public.farmer_phone_profiles (phone, farmer_id, updated_at desc)
  where status = 'active';

with profile_farms as (
  select
    p.id,
    p.user_id,
    regexp_replace(p.phone, '\D', '', 'g') as phone_digits,
    coalesce(p.farmer_id, '') as farmer_id,
    p.created_at,
    exists (
      select 1
      from public.farms f
      where f.user_id = p.user_id
    ) as has_farm
  from public.farmer_phone_profiles p
  where coalesce(p.status, 'active') = 'active'
    and regexp_replace(p.phone, '\D', '', 'g') <> ''
),
ranked as (
  select
    *,
    row_number() over (
      partition by phone_digits, farmer_id
      order by has_farm desc, created_at desc, id
    ) as keep_rank
  from profile_farms
),
duplicate_no_farm_profiles as (
  select id
  from ranked
  where has_farm = false
    and keep_rank > 1
)
update public.farmer_phone_profiles p
set status = 'inactive',
    updated_at = now()
from duplicate_no_farm_profiles d
where p.id = d.id
  and coalesce(p.status, 'active') = 'active';
