-- One-time tenant link backfill: make current Farmer profiles visible to the
-- active Sagar FPC workspace without changing Farmer auth or farm ownership.

do $$
declare
  target_fpc_id uuid;
  active_match_count integer;
  source_profile_count integer;
  skipped_missing_farmer_id_count integer;
  skipped_duplicate_farmer_id_count integer;
  upserted_link_count integer;
begin
  select count(*)
  into active_match_count
  from public.fpcs fpc
  where lower(trim(fpc.email)) = 'atharva@gmail.com'
    and fpc.status = 'active';

  if active_match_count <> 1 then
    raise exception
      'Expected exactly one active Sagar FPC with email atharva@gmail.com, found %',
      active_match_count;
  end if;

  select fpc.id
  into target_fpc_id
  from public.fpcs fpc
  where lower(trim(fpc.email)) = 'atharva@gmail.com'
    and fpc.status = 'active'
  limit 1;

  select count(*)
  into source_profile_count
  from public.farmer_phone_profiles;

  select count(*)
  into skipped_missing_farmer_id_count
  from public.farmer_phone_profiles profile
  where nullif(trim(coalesce(profile.farmer_id, '')), '') is null;

  with raw_source_profiles as (
    select
      profile.id as profile_id,
      profile.user_id,
      trim(profile.farmer_id) as farmer_id,
      coalesce(profile.phone, '') as farmer_phone,
      coalesce(nullif(trim(profile.farmer_name), ''), 'Farmer') as farmer_name,
      coalesce(profile.default_location, '') as default_location,
      coalesce(profile.status, 'active') as profile_status,
      profile.created_at as profile_created_at,
      profile.updated_at as profile_updated_at,
      farm.id as farm_id,
      coalesce(farm.name, '') as farm_name,
      coalesce(farm.crop, '') as farm_crop,
      coalesce(farm.variety, '') as farm_variety,
      farm.area_acres,
      farm.created_at as farm_created_at,
      farm.updated_at as farm_updated_at
    from public.farmer_phone_profiles profile
    left join lateral (
      select farm.*
      from public.farms farm
      where farm.user_id = profile.user_id
      order by farm.updated_at desc nulls last, farm.created_at desc, farm.id
      limit 1
    ) farm on true
    where nullif(trim(coalesce(profile.farmer_id, '')), '') is not null
  ),
  ranked_source_profiles as (
    select
      raw_source_profiles.*,
      row_number() over (
        partition by raw_source_profiles.farmer_id
        order by
          (raw_source_profiles.farm_id is not null) desc,
          (raw_source_profiles.profile_status = 'active') desc,
          raw_source_profiles.profile_updated_at desc nulls last,
          raw_source_profiles.profile_created_at desc,
          raw_source_profiles.profile_id
      ) as source_rank
    from raw_source_profiles
  ),
  duplicate_source_profiles as (
    select 1
    from ranked_source_profiles
    where source_rank > 1
  ),
  duplicate_count as (
    select count(*) as value
    from duplicate_source_profiles
  ),
  source_profiles as (
    select *
    from ranked_source_profiles
    where source_rank = 1
  ),
  upserted as (
    insert into public.fpc_farmer_links (
      fpc_id,
      farmer_id,
      farmer_phone,
      farmer_name,
      farm_id,
      farm_name,
      village,
      crop,
      kyc_status,
      status,
      source_payload,
      linked_by
    )
    select
      target_fpc_id,
      source_profiles.farmer_id,
      source_profiles.farmer_phone,
      source_profiles.farmer_name,
      coalesce(source_profiles.farm_id::text, ''),
      source_profiles.farm_name,
      source_profiles.default_location,
      source_profiles.farm_crop,
      case
        when source_profiles.profile_status = 'active' then 'verified'
        else 'profile_backfilled'
      end,
      'active',
      jsonb_build_object(
        'source', 'sagar_fpc_all_farmer_backfill',
        'backfilledAt', now(),
        'farmerProfileId', source_profiles.profile_id,
        'farmerUserId', source_profiles.user_id,
        'profileStatus', source_profiles.profile_status,
        'directoryOnly', source_profiles.farm_id is null,
        'farmId', source_profiles.farm_id,
        'farmVariety', source_profiles.farm_variety,
        'farmAreaAcres', source_profiles.area_acres,
        'profileCreatedAt', source_profiles.profile_created_at,
        'profileUpdatedAt', source_profiles.profile_updated_at,
        'farmCreatedAt', source_profiles.farm_created_at,
        'farmUpdatedAt', source_profiles.farm_updated_at
      ),
      null
    from source_profiles
    on conflict (fpc_id, farmer_id) do update
    set farmer_phone = excluded.farmer_phone,
        farmer_name = excluded.farmer_name,
        farm_id = excluded.farm_id,
        farm_name = excluded.farm_name,
        village = excluded.village,
        crop = excluded.crop,
        kyc_status = excluded.kyc_status,
        status = 'active',
        source_payload = public.fpc_farmer_links.source_payload ||
          jsonb_build_object(
            'source', 'sagar_fpc_all_farmer_backfill',
            'lastBackfilledAt', now(),
            'farmerProfileId', excluded.source_payload->'farmerProfileId',
            'farmerUserId', excluded.source_payload->'farmerUserId',
            'profileStatus', excluded.source_payload->'profileStatus',
            'directoryOnly', excluded.source_payload->'directoryOnly',
            'farmId', excluded.source_payload->'farmId',
            'farmVariety', excluded.source_payload->'farmVariety',
            'farmAreaAcres', excluded.source_payload->'farmAreaAcres'
          ),
        linked_by = coalesce(public.fpc_farmer_links.linked_by, excluded.linked_by),
        updated_at = now()
    returning 1
  )
  select
    (select value from duplicate_count),
    (select count(*) from upserted)
  into skipped_duplicate_farmer_id_count, upserted_link_count
  ;

  raise notice
    'Sagar FPC farmer link backfill complete: source profiles %, linked %, skipped missing farmer_id %, skipped duplicate farmer_id %',
    source_profile_count,
    upserted_link_count,
    skipped_missing_farmer_id_count,
    skipped_duplicate_farmer_id_count;
end $$;
