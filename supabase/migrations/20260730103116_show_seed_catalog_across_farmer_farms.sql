-- Farmer Seeds is a catalogue first: active, in-stock FPC programmes remain
-- visible even when the currently selected farm grows another crop. The
-- selected farm still has to match before a seed request is enabled.
do $migration$
declare
  function_definition text;
  old_program_fields text := $old$
          'available_seed_kg', seed_stock.available_seed_kg,
          'is_linked', coalesce(farmer_link.status = 'active', false),
$old$;
  new_program_fields text := $new$
          'available_seed_kg', seed_stock.available_seed_kg,
          'farm_matches_crop',
            private.fpc_seed_crop_key(program.crop) =
            private.fpc_seed_crop_key(farm_row.crop),
          'is_linked', coalesce(farmer_link.status = 'active', false),
$new$;
  old_request_gate text := $old$
          'request_allowed',
            actor_is_permanent
            and actor_profile.id is not null
            and actor_profile.phone_verified_at is not null
            and coalesce(farmer_link.status, 'active') = 'active'
$old$;
  new_request_gate text := $new$
          'request_allowed',
            private.fpc_seed_crop_key(program.crop) =
              private.fpc_seed_crop_key(farm_row.crop)
            and actor_is_permanent
            and actor_profile.id is not null
            and actor_profile.phone_verified_at is not null
            and coalesce(farmer_link.status, 'active') = 'active'
$new$;
  old_crop_filter text := $old$
      where program.status = 'active'
        and seed_stock.available_seed_kg > 0
        and private.fpc_seed_crop_key(program.crop) =
            private.fpc_seed_crop_key(farm_row.crop)
$old$;
  new_crop_filter text := $new$
      where program.status = 'active'
        and seed_stock.available_seed_kg > 0
$new$;
begin
  select pg_get_functiondef(
    'public.farmer_crop_program_for_farm(uuid)'::regprocedure
  )
  into function_definition;

  if position(old_program_fields in function_definition) = 0 then
    raise exception 'Farmer seed programme fields changed';
  end if;
  function_definition := replace(
    function_definition,
    old_program_fields,
    new_program_fields
  );

  if position(old_request_gate in function_definition) = 0 then
    raise exception 'Farmer seed request gate changed';
  end if;
  function_definition := replace(
    function_definition,
    old_request_gate,
    new_request_gate
  );

  if position(old_crop_filter in function_definition) = 0 then
    raise exception 'Farmer seed crop filter changed';
  end if;
  function_definition := replace(
    function_definition,
    old_crop_filter,
    new_crop_filter
  );

  execute function_definition;
end;
$migration$;

comment on function public.farmer_crop_program_for_farm(uuid) is
  'Returns the active in-stock FPC seed catalogue for an authorized Farmer farm and marks whether the selected farm can request each programme.';
