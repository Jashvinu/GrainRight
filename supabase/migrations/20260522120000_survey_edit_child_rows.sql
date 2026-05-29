alter table public.survey_kharif_crops
  add column if not exists extra_details jsonb not null default '{}'::jsonb;
alter table public.survey_main_crop_yearly
  add column if not exists extra_details jsonb not null default '{}'::jsonb;
grant select, insert, update, delete on public.survey_kharif_crops
  to anon, authenticated;
grant select, insert, update, delete on public.survey_main_crop_yearly
  to anon, authenticated;
grant select, insert, update, delete on public.survey_crop_practices
  to anon, authenticated;
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'survey_kharif_crops'
      and policyname = 'farmers update own kharif crops'
  ) then
    create policy "farmers update own kharif crops"
      on public.survey_kharif_crops
      for update
      using (
        exists (
          select 1 from public.farmer_surveys s
          where s.id = survey_id and s.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1 from public.farmer_surveys s
          where s.id = survey_id and s.user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'survey_kharif_crops'
      and policyname = 'farmers delete own kharif crops'
  ) then
    create policy "farmers delete own kharif crops"
      on public.survey_kharif_crops
      for delete
      using (
        exists (
          select 1 from public.farmer_surveys s
          where s.id = survey_id and s.user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'survey_main_crop_yearly'
      and policyname = 'farmers update own yearly production'
  ) then
    create policy "farmers update own yearly production"
      on public.survey_main_crop_yearly
      for update
      using (
        exists (
          select 1 from public.farmer_surveys s
          where s.id = survey_id and s.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1 from public.farmer_surveys s
          where s.id = survey_id and s.user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'survey_main_crop_yearly'
      and policyname = 'farmers delete own yearly production'
  ) then
    create policy "farmers delete own yearly production"
      on public.survey_main_crop_yearly
      for delete
      using (
        exists (
          select 1 from public.farmer_surveys s
          where s.id = survey_id and s.user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'survey_crop_practices'
      and policyname = 'farmers update own crop practices'
  ) then
    create policy "farmers update own crop practices"
      on public.survey_crop_practices
      for update
      using (
        exists (
          select 1 from public.farmer_surveys s
          where s.id = survey_id and s.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1 from public.farmer_surveys s
          where s.id = survey_id and s.user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'survey_crop_practices'
      and policyname = 'farmers delete own crop practices'
  ) then
    create policy "farmers delete own crop practices"
      on public.survey_crop_practices
      for delete
      using (
        exists (
          select 1 from public.farmer_surveys s
          where s.id = survey_id and s.user_id = auth.uid()
        )
      );
  end if;
end $$;
