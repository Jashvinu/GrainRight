create or replace function public.normalize_farm_bounds_keys()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if new.bounds is null then
    return new;
  end if;

  if new.bounds ? 'north' and new.bounds ? 'south'
    and new.bounds ? 'east' and new.bounds ? 'west' then
    new.bounds := new.bounds || jsonb_build_object(
      'minLat', new.bounds -> 'south',
      'maxLat', new.bounds -> 'north',
      'minLng', new.bounds -> 'west',
      'maxLng', new.bounds -> 'east'
    );
  elsif new.bounds ? 'minLat' and new.bounds ? 'maxLat'
    and new.bounds ? 'minLng' and new.bounds ? 'maxLng' then
    new.bounds := new.bounds || jsonb_build_object(
      'south', new.bounds -> 'minLat',
      'north', new.bounds -> 'maxLat',
      'west', new.bounds -> 'minLng',
      'east', new.bounds -> 'maxLng'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists normalize_farm_bounds_keys on public.farms;
create trigger normalize_farm_bounds_keys
before insert or update of bounds on public.farms
for each row
execute function public.normalize_farm_bounds_keys();

update public.farms
set bounds = bounds
where bounds is not null;
