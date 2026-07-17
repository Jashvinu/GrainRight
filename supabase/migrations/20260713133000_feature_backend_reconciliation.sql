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
