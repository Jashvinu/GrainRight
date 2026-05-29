do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'farmer_surveys'
      and policyname = 'collectors select all surveys'
  ) then
    create policy "collectors select all surveys"
      on public.farmer_surveys
      for select
      using (auth.uid() is not null);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'survey_kharif_crops'
      and policyname = 'collectors select all kharif crops'
  ) then
    create policy "collectors select all kharif crops"
      on public.survey_kharif_crops
      for select
      using (auth.uid() is not null);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'survey_main_crop_yearly'
      and policyname = 'collectors select all yearly production'
  ) then
    create policy "collectors select all yearly production"
      on public.survey_main_crop_yearly
      for select
      using (auth.uid() is not null);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'survey_crop_practices'
      and policyname = 'collectors select all crop practices'
  ) then
    create policy "collectors select all crop practices"
      on public.survey_crop_practices
      for select
      using (auth.uid() is not null);
  end if;
end $$;
