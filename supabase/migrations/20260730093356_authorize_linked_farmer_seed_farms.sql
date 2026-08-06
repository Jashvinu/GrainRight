-- Farmer farm loading already treats active phone/profile identities as one
-- verified farmer. Keep the seed RPC contract aligned without changing the
-- canonical farm owner or widening access beyond those verified links.
create or replace function private.farmer_can_access_farm(
  target_farm_id uuid,
  actor_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select actor_user_id is not null
    and exists (
      select 1
      from public.farms farm
      where farm.id = target_farm_id
        and (
          farm.user_id = actor_user_id
          or exists (
            select 1
            from public.farmer_phone_profiles current_profile
            join public.farmer_phone_profiles owner_profile
              on owner_profile.user_id = farm.user_id
            where current_profile.user_id = actor_user_id
              and coalesce(current_profile.status, 'active') = 'active'
              and coalesce(owner_profile.status, 'active') = 'active'
              and (
                (
                  length(
                    regexp_replace(
                      coalesce(current_profile.phone, ''),
                      '\D',
                      '',
                      'g'
                    )
                  ) >= 10
                  and right(
                    regexp_replace(
                      coalesce(current_profile.phone, ''),
                      '\D',
                      '',
                      'g'
                    ),
                    10
                  ) = right(
                    regexp_replace(
                      coalesce(owner_profile.phone, ''),
                      '\D',
                      '',
                      'g'
                    ),
                    10
                  )
                )
                or (
                  nullif(current_profile.farmer_id, '') is not null
                  and current_profile.farmer_id = owner_profile.farmer_id
                )
              )
          )
          or exists (
            select 1
            from public.farmer_phone_profiles current_profile
            join public.farmer_ai_profiles legacy_owner
              on legacy_owner.user_id = farm.user_id
            where current_profile.user_id = actor_user_id
              and coalesce(current_profile.status, 'active') = 'active'
              and length(
                regexp_replace(
                  coalesce(current_profile.phone, ''),
                  '\D',
                  '',
                  'g'
                )
              ) >= 10
              and right(
                regexp_replace(
                  coalesce(current_profile.phone, ''),
                  '\D',
                  '',
                  'g'
                ),
                10
              ) = right(
                regexp_replace(
                  coalesce(legacy_owner.phone, ''),
                  '\D',
                  '',
                  'g'
                ),
                10
              )
          )
        )
    );
$$;

revoke all on function private.farmer_can_access_farm(uuid, uuid)
  from public, anon, authenticated;

-- These functions were introduced in the immediately preceding seed-request
-- migration. Patch only their ownership predicates and fail loudly if the
-- expected contract has drifted.
do $migration$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'private.request_program_seed(uuid,uuid,numeric,text,timestamp with time zone,uuid)'::regprocedure
  )
  into function_definition;
  if position('and farm.user_id = actor_id' in function_definition) = 0 then
    raise exception 'request_program_seed farm ownership predicate changed';
  end if;
  function_definition := replace(
    function_definition,
    'and farm.user_id = actor_id',
    'and private.farmer_can_access_farm(farm.id, actor_id)'
  );
  execute function_definition;

  select pg_get_functiondef(
    'public.farmer_crop_program_for_farm(uuid)'::regprocedure
  )
  into function_definition;
  if position('and farm.user_id = actor_id' in function_definition) = 0 then
    raise exception 'farmer_crop_program_for_farm ownership predicate changed';
  end if;
  function_definition := replace(
    function_definition,
    'and farm.user_id = actor_id',
    'and private.farmer_can_access_farm(farm.id, actor_id)'
  );
  execute function_definition;

  select pg_get_functiondef(
    'private.execute_seed_request_operation(text,jsonb,uuid)'::regprocedure
  )
  into function_definition;
  if position(
    'and farm.user_id = request_row.farmer_user_id'
    in function_definition
  ) = 0 then
    raise exception 'seed request approval farm ownership predicate changed';
  end if;
  function_definition := replace(
    function_definition,
    'and farm.user_id = request_row.farmer_user_id',
    'and private.farmer_can_access_farm(farm.id, request_row.farmer_user_id)'
  );
  execute function_definition;
end;
$migration$;

comment on function private.farmer_can_access_farm(uuid, uuid) is
  'Checks direct or verified linked-profile access to a farm for seed workflows without reassigning farm ownership.';
