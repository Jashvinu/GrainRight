create or replace function public.has_server_role(required_roles text[])
returns boolean
language sql
stable
set search_path = ''
as $$
  select
    lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = any(required_roles)
    or exists (
      select 1
      from jsonb_array_elements_text(
        case
          when jsonb_typeof(auth.jwt() -> 'app_metadata' -> 'roles') = 'array'
          then auth.jwt() -> 'app_metadata' -> 'roles'
          else '[]'::jsonb
        end
      ) as role(value)
      where lower(role.value) = any(required_roles)
    );
$$;

grant execute on function public.has_server_role(text[]) to authenticated;

drop policy if exists "admins can read farmer phone registry"
  on public.farmer_phone_registry;
create policy "admins can read farmer phone registry"
on public.farmer_phone_registry for select
to authenticated
using (
  public.has_server_role(array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'])
);

drop policy if exists "fpo admins can read grading review jobs"
  on public.analysis_jobs;
create policy "fpo admins can read grading review jobs"
on public.analysis_jobs for select
to authenticated
using (
  public.has_server_role(array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'])
);

drop policy if exists "fpo admins can update grading review jobs"
  on public.analysis_jobs;
create policy "fpo admins can update grading review jobs"
on public.analysis_jobs for update
to authenticated
using (
  public.has_server_role(array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'])
)
with check (
  public.has_server_role(array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'])
);

drop policy if exists "admins can read stakeholder applications"
  on public.stakeholder_applications;
create policy "admins can read stakeholder applications"
on public.stakeholder_applications for select
to authenticated
using (public.has_server_role(array['admin']));

drop policy if exists "admins can review stakeholder applications"
  on public.stakeholder_applications;
create policy "admins can review stakeholder applications"
on public.stakeholder_applications for update
to authenticated
using (public.has_server_role(array['admin']))
with check (public.has_server_role(array['admin']));

drop policy if exists "admins can read stakeholder events"
  on public.stakeholder_application_events;
create policy "admins can read stakeholder events"
on public.stakeholder_application_events for select
to authenticated
using (public.has_server_role(array['admin']));

drop policy if exists "admins can create stakeholder events"
  on public.stakeholder_application_events;
create policy "admins can create stakeholder events"
on public.stakeholder_application_events for insert
to authenticated
with check (public.has_server_role(array['admin']));

drop policy if exists "admins can read stakeholder documents"
  on storage.objects;
create policy "admins can read stakeholder documents"
on storage.objects for select
to authenticated
using (
  bucket_id = 'stakeholder-documents'
  and public.has_server_role(array['admin'])
);

drop policy if exists "farmers can read own notifications"
  on public.farmer_notifications;
create policy "farmers can read own notifications"
on public.farmer_notifications for select
to authenticated
using (
  public.has_server_role(array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'])
  or exists (
    select 1
    from public.farmer_phone_profiles p
    where p.user_id = auth.uid()
      and coalesce(p.status, 'active') = 'active'
      and (
        p.farmer_id = farmer_notifications.farmer_id
        or regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')
          = regexp_replace(coalesce(farmer_notifications.farmer_phone, ''), '\D', '', 'g')
      )
  )
);

drop policy if exists "farmers can mark own notifications read"
  on public.farmer_notifications;
create policy "farmers can mark own notifications read"
on public.farmer_notifications for update
to authenticated
using (
  public.has_server_role(array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'])
  or exists (
    select 1
    from public.farmer_phone_profiles p
    where p.user_id = auth.uid()
      and coalesce(p.status, 'active') = 'active'
      and (
        p.farmer_id = farmer_notifications.farmer_id
        or regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')
          = regexp_replace(coalesce(farmer_notifications.farmer_phone, ''), '\D', '', 'g')
      )
  )
)
with check (
  public.has_server_role(array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'])
  or exists (
    select 1
    from public.farmer_phone_profiles p
    where p.user_id = auth.uid()
      and coalesce(p.status, 'active') = 'active'
      and (
        p.farmer_id = farmer_notifications.farmer_id
        or regexp_replace(coalesce(p.phone, ''), '\D', '', 'g')
          = regexp_replace(coalesce(farmer_notifications.farmer_phone, ''), '\D', '', 'g')
      )
  )
);

create index if not exists stakeholder_application_events_application_created_idx
  on public.stakeholder_application_events(application_id, created_at desc);

create index if not exists farmer_phone_profiles_user_status_farmer_idx
  on public.farmer_phone_profiles(user_id, status, farmer_id);
