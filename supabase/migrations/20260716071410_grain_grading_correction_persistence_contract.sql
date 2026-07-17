alter table public.operator_corrections
  add column if not exists predicted_moisture_risk text,
  add column if not exists corrected_moisture_risk text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'operator_corrections_predicted_moisture_risk_check'
      and conrelid = 'public.operator_corrections'::regclass
  ) then
    alter table public.operator_corrections
      add constraint operator_corrections_predicted_moisture_risk_check
      check (
        predicted_moisture_risk is null
        or predicted_moisture_risk in ('LOW', 'MODERATE', 'HIGH', 'CRITICAL')
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'operator_corrections_corrected_moisture_risk_check'
      and conrelid = 'public.operator_corrections'::regclass
  ) then
    alter table public.operator_corrections
      add constraint operator_corrections_corrected_moisture_risk_check
      check (
        corrected_moisture_risk is null
        or corrected_moisture_risk in ('LOW', 'MODERATE', 'HIGH', 'CRITICAL')
      );
  end if;
end $$;

update public.operator_corrections corrections
set predicted_moisture_risk = jobs.moisture_risk
from public.analysis_jobs jobs
where jobs.id = corrections.analysis_id
  and corrections.predicted_moisture_risk is null
  and jobs.moisture_risk in ('LOW', 'MODERATE', 'HIGH', 'CRITICAL');

update public.operator_corrections
set corrected_moisture_risk =
  (regexp_match(
    notes,
    '\[moisture:(LOW|MODERATE|HIGH|CRITICAL)\]'
  ))[1]
where corrected_moisture_risk is null
  and notes ~ '\[moisture:(LOW|MODERATE|HIGH|CRITICAL)\]';
