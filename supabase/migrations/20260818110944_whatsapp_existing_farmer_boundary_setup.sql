-- Support a durable WhatsApp farm-creation draft for farmers who already have
-- a GrainRight identity. New-farmer onboarding continues to use the default
-- flow_type value.
alter table public.whatsapp_farmer_onboardings
  add column if not exists flow_type text not null default 'new_farmer';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.whatsapp_farmer_onboardings'::regclass
      and conname = 'whatsapp_farmer_onboardings_flow_type_check'
  ) then
    alter table public.whatsapp_farmer_onboardings
      add constraint whatsapp_farmer_onboardings_flow_type_check
      check (flow_type in ('new_farmer', 'existing_farmer_farm'));
  end if;
end
$$;

create index if not exists whatsapp_farmer_onboardings_flow_idx
  on public.whatsapp_farmer_onboardings
  (whatsapp_phone, flow_type, status, updated_at desc);

comment on column public.whatsapp_farmer_onboardings.flow_type is
  'Durable WhatsApp flow kind: new farmer account or farm creation for an existing farmer.';

create or replace function public.whatsapp_complete_existing_farm_setup(
  p_setup_id uuid,
  p_user_id uuid,
  p_farm jsonb
)
returns public.farms
language plpgsql
security definer
set search_path = public
as $$
declare
  setup_row public.whatsapp_farmer_onboardings;
  saved_farm public.farms;
begin
  if p_setup_id is null or p_user_id is null then
    raise exception 'A farm setup and farmer user are required.' using errcode = '22023';
  end if;

  select * into setup_row
  from public.whatsapp_farmer_onboardings
  where id = p_setup_id
    and flow_type = 'existing_farmer_farm'
  for update;

  if not found then
    raise exception 'Farm setup was not found.' using errcode = '22023';
  end if;

  if setup_row.status = 'completed' and setup_row.farm_id is not null then
    select * into saved_farm from public.farms where id = setup_row.farm_id;
    if saved_farm.id is not null then
      return saved_farm;
    end if;
    raise exception 'Completed farm setup is missing its farm.' using errcode = '23503';
  end if;

  if setup_row.status <> 'active' then
    raise exception 'Farm setup is no longer active.' using errcode = '22023';
  end if;

  if setup_row.user_id is distinct from p_user_id then
    raise exception 'Farm setup does not belong to this farmer.' using errcode = '42501';
  end if;

  saved_farm := public.whatsapp_create_farmer_farm(p_user_id, p_farm);

  update public.whatsapp_farmer_onboardings
  set status = 'completed',
      step = 'completed',
      farm_id = saved_farm.id,
      completed_at = now(),
      updated_at = now()
  where id = p_setup_id;

  return saved_farm;
end;
$$;

revoke all on function public.whatsapp_complete_existing_farm_setup(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.whatsapp_complete_existing_farm_setup(uuid, uuid, jsonb)
  to service_role;
