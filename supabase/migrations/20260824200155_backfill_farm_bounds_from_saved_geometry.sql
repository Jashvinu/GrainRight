create schema if not exists private;

create or replace function private.ensure_farm_bounds_from_geometry()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  if new.geometry is null then
    return new;
  end if;
  if new.bounds is not null
     and new.bounds ? 'minLat'
     and new.bounds ? 'maxLat'
     and new.bounds ? 'minLng'
     and new.bounds ? 'maxLng' then
    return new;
  end if;

  new.bounds := jsonb_build_object(
    'minLat', st_ymin(st_envelope(new.geometry)),
    'maxLat', st_ymax(st_envelope(new.geometry)),
    'minLng', st_xmin(st_envelope(new.geometry)),
    'maxLng', st_xmax(st_envelope(new.geometry))
  );
  return new;
end;
$$;

revoke all on function private.ensure_farm_bounds_from_geometry() from public;

drop trigger if exists ensure_farm_bounds_from_geometry on public.farms;
create trigger ensure_farm_bounds_from_geometry
before insert or update of geometry on public.farms
for each row execute function private.ensure_farm_bounds_from_geometry();

update public.farms
set bounds = jsonb_build_object(
  'minLat', st_ymin(st_envelope(geometry)),
  'maxLat', st_ymax(st_envelope(geometry)),
  'minLng', st_xmin(st_envelope(geometry)),
  'maxLng', st_xmax(st_envelope(geometry))
)
where geometry is not null
  and (
    bounds is null
    or not (bounds ? 'minLat' and bounds ? 'maxLat' and bounds ? 'minLng' and bounds ? 'maxLng')
  );
