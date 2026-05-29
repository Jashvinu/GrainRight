alter table public.farmer_surveys
  add column if not exists client_uuid uuid;

create unique index if not exists farmer_surveys_client_uuid_uidx
  on public.farmer_surveys(client_uuid)
  where client_uuid is not null;

grant select, insert, update, delete on public.survey_kharif_crops to authenticated;
grant select, insert, update, delete on public.survey_main_crop_yearly to authenticated;
grant select, insert, update, delete on public.survey_crop_practices to authenticated;

drop policy if exists "farmers update own kharif crops" on public.survey_kharif_crops;
create policy "farmers update own kharif crops" on public.survey_kharif_crops
  for update using (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ));

drop policy if exists "farmers delete own kharif crops" on public.survey_kharif_crops;
create policy "farmers delete own kharif crops" on public.survey_kharif_crops
  for delete using (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ));

drop policy if exists "farmers update own yearly production" on public.survey_main_crop_yearly;
create policy "farmers update own yearly production" on public.survey_main_crop_yearly
  for update using (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ));

drop policy if exists "farmers delete own yearly production" on public.survey_main_crop_yearly;
create policy "farmers delete own yearly production" on public.survey_main_crop_yearly
  for delete using (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ));

drop policy if exists "farmers update own crop practices" on public.survey_crop_practices;
create policy "farmers update own crop practices" on public.survey_crop_practices
  for update using (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ));

drop policy if exists "farmers delete own crop practices" on public.survey_crop_practices;
create policy "farmers delete own crop practices" on public.survey_crop_practices
  for delete using (exists (
    select 1 from public.farmer_surveys s
    where s.id = survey_id and s.user_id = auth.uid()
  ));
