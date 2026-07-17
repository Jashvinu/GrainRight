alter table public.stakeholder_applications
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz;

create index if not exists stakeholder_applications_review_idx
  on public.stakeholder_applications(status, payment_status, updated_at desc);

create index if not exists stakeholder_applications_reviewed_at_idx
  on public.stakeholder_applications(reviewed_at desc)
  where reviewed_at is not null;

drop policy if exists "admins can read stakeholder applications"
  on public.stakeholder_applications;
create policy "admins can read stakeholder applications"
on public.stakeholder_applications for select to authenticated
using (
  coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') = 'admin'
);

drop policy if exists "admins can review stakeholder applications"
  on public.stakeholder_applications;
create policy "admins can review stakeholder applications"
on public.stakeholder_applications for update to authenticated
using (
  coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') = 'admin'
)
with check (
  coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') = 'admin'
);

drop policy if exists "admins can read stakeholder events"
  on public.stakeholder_application_events;
create policy "admins can read stakeholder events"
on public.stakeholder_application_events for select to authenticated
using (
  coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') = 'admin'
);

drop policy if exists "admins can create stakeholder events"
  on public.stakeholder_application_events;
create policy "admins can create stakeholder events"
on public.stakeholder_application_events for insert to authenticated
with check (
  coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') = 'admin'
);

drop policy if exists "admins can read stakeholder documents"
  on storage.objects;
create policy "admins can read stakeholder documents"
on storage.objects for select to authenticated
using (
  bucket_id = 'stakeholder-documents'
  and coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') = 'admin'
);
