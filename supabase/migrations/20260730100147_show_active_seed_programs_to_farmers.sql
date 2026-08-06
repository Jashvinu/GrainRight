-- Active seed programs must be discoverable from the Farmer Seeds page before
-- an FPC has scanned that Farmer's profile QR. The first seed request creates
-- an auditable, phone-verified FPC relationship; enrollment still requires an
-- explicit FPC review and Field Officer assignment.

create or replace function private.fpc_seed_crop_key(value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case lower(trim(coalesce(value, '')))
    when 'rice' then 'rice'
    when 'paddy' then 'rice'
    when 'finger millet' then 'finger_millet'
    when 'ragi' then 'finger_millet'
    when 'nachni' then 'finger_millet'
    when 'pearl millet' then 'pearl_millet'
    when 'bajra' then 'pearl_millet'
    else lower(trim(coalesce(value, '')))
  end;
$$;

revoke all on function private.fpc_seed_crop_key(text)
  from public, anon, authenticated;

create or replace function private.ensure_seed_request_farmer_link(
  target_fpc_id uuid,
  target_farm_id uuid,
  target_program_crop text,
  actor_user_id uuid
)
returns public.fpc_farmer_links
language plpgsql
security definer
set search_path = ''
as $$
declare
  farm_row public.farms;
  profile_row public.farmer_phone_profiles;
  link_row public.fpc_farmer_links;
  farmer_name_value text;
begin
  if actor_user_id is null then raise exception 'Login required'; end if;

  select * into farm_row
  from public.farms farm
  where farm.id = target_farm_id
    and private.farmer_can_access_farm(farm.id, actor_user_id);
  if farm_row.id is null then raise exception 'Farmer farm not found'; end if;

  if private.fpc_seed_crop_key(farm_row.crop) <>
      private.fpc_seed_crop_key(target_program_crop) then
    raise exception 'Program crop does not match the selected farm crop';
  end if;

  select * into profile_row
  from public.farmer_phone_profiles profile
  where profile.user_id = actor_user_id
    and profile.status = 'active'
  order by
    profile.phone_verified_at desc nulls last,
    profile.updated_at desc
  limit 1;
  if profile_row.id is null or profile_row.phone_verified_at is null then
    raise exception 'A verified Farmer phone profile is required';
  end if;
  if nullif(trim(profile_row.farmer_id), '') is null then
    raise exception 'A verified Farmer ID is required';
  end if;

  select * into link_row
  from public.fpc_farmer_links link
  where link.fpc_id = target_fpc_id
    and (
      link.farm_id = target_farm_id::text
      or link.farmer_id = profile_row.farmer_id
      or (
        length(regexp_replace(profile_row.phone, '\D', '', 'g')) >= 10
        and right(regexp_replace(link.farmer_phone, '\D', '', 'g'), 10) =
            right(regexp_replace(profile_row.phone, '\D', '', 'g'), 10)
      )
    )
  order by
    (link.farm_id = target_farm_id::text) desc,
    link.updated_at desc
  limit 1;

  if link_row.id is not null then
    if link_row.status <> 'active' then
      raise exception 'This Farmer relationship was deactivated by the FPC';
    end if;
    return link_row;
  end if;

  select coalesce(
    nullif(trim(profile_row.farmer_name), ''),
    (
      select nullif(trim(profile.display_name), '')
      from public.farmer_ai_profiles profile
      where profile.user_id = actor_user_id
      order by profile.updated_at desc
      limit 1
    ),
    'Farmer'
  )
  into farmer_name_value;

  insert into public.fpc_farmer_links(
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
  ) values (
    target_fpc_id,
    profile_row.farmer_id,
    profile_row.phone,
    farmer_name_value,
    farm_row.id::text,
    farm_row.name,
    coalesce(profile_row.default_location, ''),
    coalesce(farm_row.crop, ''),
    case
      when profile_row.identity_verified_at is not null then 'verified'
      else 'phone_verified'
    end,
    'active',
    jsonb_build_object(
      'source', 'farmer_seed_request',
      'farmId', farm_row.id,
      'farmerUserId', actor_user_id,
      'verification', case
        when profile_row.identity_verified_at is not null
          then 'identity_and_phone'
        else 'phone'
      end
    ),
    actor_user_id
  )
  on conflict (fpc_id, farmer_id) do update
  set farmer_phone = excluded.farmer_phone,
      farmer_name = excluded.farmer_name,
      farm_id = excluded.farm_id,
      farm_name = excluded.farm_name,
      village = excluded.village,
      crop = excluded.crop,
      source_payload = public.fpc_farmer_links.source_payload ||
        jsonb_build_object(
          'lastSeedRequestFarmId', target_farm_id,
          'lastSeedRequestAt', now()
        ),
      updated_at = now()
  where public.fpc_farmer_links.status = 'active'
  returning * into link_row;

  if link_row.id is null then
    raise exception 'This Farmer relationship was deactivated by the FPC';
  end if;
  return link_row;
end;
$$;

revoke all on function private.ensure_seed_request_farmer_link(
  uuid, uuid, text, uuid
) from public, anon, authenticated;

create or replace function public.farmer_crop_program_for_farm(p_farm_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_is_permanent boolean := false;
  actor_profile public.farmer_phone_profiles;
  farm_row public.farms;
  enrollment public.fpc_program_enrollments;
  seed_request public.fpc_seed_requests;
  context_fpc_id uuid;
begin
  if actor_id is null then raise exception 'Login required'; end if;

  select coalesce(user_account.is_anonymous, false) = false
  into actor_is_permanent
  from auth.users user_account
  where user_account.id = actor_id;

  select * into actor_profile
  from public.farmer_phone_profiles profile
  where profile.user_id = actor_id
    and profile.status = 'active'
  order by
    profile.phone_verified_at desc nulls last,
    profile.updated_at desc
  limit 1;

  select * into farm_row
  from public.farms farm
  where farm.id = p_farm_id
    and private.farmer_can_access_farm(farm.id, actor_id);
  if farm_row.id is null then raise exception 'Farmer farm not found'; end if;

  select * into enrollment
  from public.fpc_program_enrollments enrollment_row
  where enrollment_row.farm_id = p_farm_id
    and enrollment_row.farmer_user_id = actor_id
  order by enrollment_row.created_at desc
  limit 1;
  if enrollment.id is not null then
    enrollment := private.refresh_crop_program_release(enrollment.id);
  end if;

  select * into seed_request
  from public.fpc_seed_requests request_row
  where request_row.farm_id = p_farm_id
    and request_row.farmer_user_id = actor_id
  order by request_row.created_at desc
  limit 1;

  context_fpc_id := coalesce(enrollment.fpc_id, seed_request.fpc_id);

  return jsonb_build_object(
    'enrollment', case
      when enrollment.id is null then null
      else to_jsonb(enrollment)
    end,
    'program', case
      when enrollment.id is null then null
      else (
        select to_jsonb(program)
        from public.fpc_crop_programs program
        where program.id = enrollment.program_id
      )
    end,
    'fpc', case
      when context_fpc_id is null then null
      else (
        select jsonb_build_object('id', fpc.id, 'name', fpc.name)
        from public.fpcs fpc
        where fpc.id = context_fpc_id
      )
    end,
    'seed_request', case
      when seed_request.id is null then null
      else to_jsonb(seed_request) || jsonb_build_object(
        'program', (
          select to_jsonb(program)
          from public.fpc_crop_programs program
          where program.id = seed_request.program_id
        ),
        'fpc', (
          select jsonb_build_object('id', fpc.id, 'name', fpc.name)
          from public.fpcs fpc
          where fpc.id = seed_request.fpc_id
        ),
        'enrollment_status', (
          select enrollment_row.status
          from public.fpc_program_enrollments enrollment_row
          where enrollment_row.id = seed_request.enrollment_id
        )
      )
    end,
    'available_programs', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', program.id,
          'fpc_id', program.fpc_id,
          'name', program.name,
          'code', program.code,
          'crop', program.crop,
          'variety', program.variety,
          'season', program.season,
          'fpc_name', fpc.name,
          'available_seed_kg', seed_stock.available_seed_kg,
          'is_linked', coalesce(farmer_link.status = 'active', false),
          'link_status', coalesce(farmer_link.status, ''),
          'request_allowed',
            actor_is_permanent
            and actor_profile.id is not null
            and actor_profile.phone_verified_at is not null
            and coalesce(farmer_link.status, 'active') = 'active'
        )
        order by program.created_at desc
      )
      from public.fpc_crop_programs program
      join public.fpcs fpc
        on fpc.id = program.fpc_id
       and fpc.status = 'active'
      cross join lateral (
        select coalesce(sum(batch.available_quantity_kg), 0)
          as available_seed_kg
        from public.fpc_seed_batches batch
        where batch.program_id = program.id
          and batch.status = 'active'
          and batch.available_quantity_kg > 0
          and (batch.expires_on is null or batch.expires_on >= current_date)
      ) seed_stock
      left join lateral (
        select link.id, link.status
        from public.fpc_farmer_links link
        where link.fpc_id = program.fpc_id
          and (
            link.farm_id = p_farm_id::text
            or (
              nullif(trim(actor_profile.farmer_id), '') is not null
              and link.farmer_id = actor_profile.farmer_id
            )
            or (
              length(
                regexp_replace(coalesce(actor_profile.phone, ''), '\D', '', 'g')
              ) >= 10
              and right(
                regexp_replace(link.farmer_phone, '\D', '', 'g'),
                10
              ) = right(
                regexp_replace(actor_profile.phone, '\D', '', 'g'),
                10
              )
            )
          )
        order by
          (link.farm_id = p_farm_id::text) desc,
          link.updated_at desc
        limit 1
      ) farmer_link on true
      where program.status = 'active'
        and seed_stock.available_seed_kg > 0
        and private.fpc_seed_crop_key(program.crop) =
            private.fpc_seed_crop_key(farm_row.crop)
    ), '[]'::jsonb),
    'seed_issue', case
      when enrollment.id is null then null
      else (
        select to_jsonb(issue) || jsonb_build_object(
          'seed_batch', (
            select to_jsonb(batch)
            from public.fpc_seed_batches batch
            where batch.id = issue.seed_batch_id
          )
        )
        from public.fpc_seed_issues issue
        where issue.enrollment_id = enrollment.id
        order by issue.created_at desc
        limit 1
      )
    end,
    'checks', case
      when enrollment.id is null then '[]'::jsonb
      else coalesce((
        select jsonb_agg(to_jsonb(check_row) order by check_row.sequence)
        from public.fpc_program_checks check_row
        where check_row.enrollment_id = enrollment.id
      ), '[]'::jsonb)
    end,
    'evaluations', case
      when enrollment.id is null then '[]'::jsonb
      else coalesce((
        select jsonb_agg(to_jsonb(evaluation) order by evaluation.attempt_no desc)
        from public.fpc_compliance_evaluations evaluation
        where evaluation.enrollment_id = enrollment.id
      ), '[]'::jsonb)
    end
  );
end;
$$;

revoke all on function public.farmer_crop_program_for_farm(uuid)
  from public, anon;
grant execute on function public.farmer_crop_program_for_farm(uuid)
  to authenticated;

do $migration$
declare
  function_definition text;
  old_link_block text := $old$
  select link.* into link_row
  from public.fpc_farmer_links link
  where link.fpc_id = program_row.fpc_id
    and link.farm_id = target_farm_id::text
    and link.status = 'active'
    and lower(coalesce(nullif(farm_row.crop, ''), link.crop, '')) =
        lower(program_row.crop)
  order by link.updated_at desc
  limit 1;
  if link_row.id is null then
    raise exception 'This farm is not actively linked to the selected FPC crop program';
  end if;
$old$;
  new_link_block text := $new$
  link_row := private.ensure_seed_request_farmer_link(
    program_row.fpc_id,
    target_farm_id,
    program_row.crop,
    actor_id
  );
$new$;
  old_crop_check text := $old$
    if lower(coalesce(nullif(farm_row.crop, ''), link_row.crop, '')) <>
        lower(program_row.crop) then
      raise exception 'Program crop does not match the linked farm crop';
    end if;
$old$;
  new_crop_check text := $new$
    if private.fpc_seed_crop_key(farm_row.crop) <>
        private.fpc_seed_crop_key(program_row.crop) then
      raise exception 'Program crop does not match the linked farm crop';
    end if;
$new$;
begin
  select pg_get_functiondef(
    'private.request_program_seed(uuid,uuid,numeric,text,timestamp with time zone,uuid)'::regprocedure
  )
  into function_definition;
  if position(old_link_block in function_definition) = 0 then
    raise exception 'request_program_seed link predicate changed';
  end if;
  function_definition := replace(
    function_definition,
    old_link_block,
    new_link_block
  );
  execute function_definition;

  select pg_get_functiondef(
    'private.execute_seed_request_operation(text,jsonb,uuid)'::regprocedure
  )
  into function_definition;
  if position(
    'target_fpc_id, program_row.id, link_row.id, farm_row.user_id,'
    in function_definition
  ) = 0 then
    raise exception 'seed request enrollment identity assignment changed';
  end if;
  function_definition := replace(
    function_definition,
    'target_fpc_id, program_row.id, link_row.id, farm_row.user_id,',
    'target_fpc_id, program_row.id, link_row.id, request_row.farmer_user_id,'
  );
  if position(old_crop_check in function_definition) = 0 then
    raise exception 'seed request approval crop predicate changed';
  end if;
  function_definition := replace(
    function_definition,
    old_crop_check,
    new_crop_check
  );
  execute function_definition;
end;
$migration$;

comment on function private.ensure_seed_request_farmer_link(
  uuid, uuid, text, uuid
) is
  'Creates an audited phone-verified Farmer-FPC relationship on the first seed request while preserving FPC deactivation.';

comment on function public.farmer_crop_program_for_farm(uuid) is
  'Returns active in-stock seed programs matching an authorized Farmer farm, including request eligibility before the first FPC link.';
