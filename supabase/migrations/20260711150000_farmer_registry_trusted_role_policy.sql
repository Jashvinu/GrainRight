drop policy if exists "admins can read farmer phone registry"
  on public.farmer_phone_registry;

create policy "admins can read farmer phone registry"
on public.farmer_phone_registry for select
to authenticated
using (
  public.has_server_role(array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'])
);
