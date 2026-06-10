-- Tighten soil calibration sample ownership.
-- Calibration samples may later feed trained models, so row-level access must
-- require an owned farm. Null-farm/global calibration data should live in a
-- separate curated aggregate table, not in farmer-submitted rows.

drop policy if exists "soil_calibration_samples_select_own" on public.soil_calibration_samples;
drop policy if exists "soil_calibration_samples_insert_own" on public.soil_calibration_samples;
drop policy if exists "soil_calibration_samples_delete_own" on public.soil_calibration_samples;
create policy "soil_calibration_samples_select_own"
on public.soil_calibration_samples
for select
to authenticated
using (
  farm_id is not null
  and exists (
    select 1
    from public.farmer_ai_farms f
    join public.farmer_ai_profiles p on p.id = f.profile_id
    where f.id = soil_calibration_samples.farm_id
      and p.user_id = auth.uid()
  )
);
create policy "soil_calibration_samples_insert_own"
on public.soil_calibration_samples
for insert
to authenticated
with check (
  farm_id is not null
  and exists (
    select 1
    from public.farmer_ai_farms f
    join public.farmer_ai_profiles p on p.id = f.profile_id
    where f.id = soil_calibration_samples.farm_id
      and p.user_id = auth.uid()
  )
);
create policy "soil_calibration_samples_delete_own"
on public.soil_calibration_samples
for delete
to authenticated
using (
  farm_id is not null
  and exists (
    select 1
    from public.farmer_ai_farms f
    join public.farmer_ai_profiles p on p.id = f.profile_id
    where f.id = soil_calibration_samples.farm_id
      and p.user_id = auth.uid()
  )
);
