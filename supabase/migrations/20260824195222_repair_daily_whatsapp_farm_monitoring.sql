-- Daily WhatsApp messages must be derived from the same saved snapshots that
-- power the farmer app. A stale scan never becomes a false "healthy" result.
create or replace function public.run_daily_farmer_health_digest(
  target_date date default ((now() at time zone 'Asia/Kolkata')::date)
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  farm_row record;
  condition_key text;
  title text;
  message text;
  inserted_rows integer;
  total_count integer := 0;
  created_count integer := 0;
begin
  if target_date is null then
    target_date := (now() at time zone 'Asia/Kolkata')::date;
  end if;

  for farm_row in
    select distinct on (farm.id)
      farm.id as farm_id,
      farm.user_id,
      farm.name as farm_name,
      profile.farmer_id,
      nullif(right(regexp_replace(coalesce(profile.phone, ''), '\D', '', 'g'), 10), '') as farmer_phone,
      snapshot.snapshot_date,
      snapshot.collected_at,
      snapshot.disease_risk,
      snapshot.weather_risk,
      snapshot.water_stress_score
    from public.farms farm
    join public.farmer_phone_profiles profile
      on profile.user_id = farm.user_id
     and profile.status = 'active'
    join public.whatsapp_identities identity_row
      on identity_row.user_id = farm.user_id
     and identity_row.role = 'farmer'
     and identity_row.notifications_enabled is distinct from false
    left join lateral (
      select snapshot_row.*
      from public.farm_data_snapshots snapshot_row
      where snapshot_row.farm_id = farm.id
        and snapshot_row.snapshot_date <= target_date
      order by snapshot_row.snapshot_date desc, snapshot_row.updated_at desc
      limit 1
    ) snapshot on true
    where farm.user_id is not null
      and nullif(btrim(profile.farmer_id), '') is not null
    order by farm.id, snapshot.snapshot_date desc nulls last, snapshot.updated_at desc nulls last
  loop
    total_count := total_count + 1;
    if farm_row.snapshot_date is null or farm_row.snapshot_date < target_date - 1 then
      condition_key := 'daily_monitoring_pending';
      title := 'Daily farm update';
      message := 'A current verified monitoring update is not available yet.';
    elsif coalesce(farm_row.disease_risk, 0) >= 0.72
       or coalesce(farm_row.weather_risk, 0) >= 0.66
       or coalesce(farm_row.water_stress_score, 0) >= 0.70 then
      condition_key := 'daily_active_risk';
      title := 'Daily farm update';
      message := 'A verified high-risk field condition is active in the latest monitoring update.';
    else
      condition_key := 'daily_healthy';
      title := 'Daily farm update';
      message := 'No high-risk condition was found in the latest verified monitoring update.';
    end if;

    insert into public.farmer_notifications (
      recipient_user_id,
      farmer_id,
      farm_id,
      farmer_phone,
      type,
      title,
      message,
      farm_name,
      dedupe_key,
      action_route,
      payload,
      severity,
      critical,
      alert_key,
      expires_at
    ) values (
      farm_row.user_id,
      farm_row.farmer_id,
      farm_row.farm_id,
      farm_row.farmer_phone,
      'farm_daily_health',
      title,
      message,
      farm_row.farm_name,
      farm_row.farm_id::text || ':daily_health:' || target_date::text,
      '/farmer',
      jsonb_build_object(
        'condition_key', condition_key,
        'snapshot_date', farm_row.snapshot_date,
        'collected_at', farm_row.collected_at,
        'disease_risk', farm_row.disease_risk,
        'weather_risk', farm_row.weather_risk,
        'water_stress_score', farm_row.water_stress_score
      ),
      'normal',
      false,
      condition_key,
      now() + interval '30 hours'
    )
    on conflict (recipient_user_id, dedupe_key)
      where recipient_user_id is not null and dedupe_key is not null
      do nothing;
    get diagnostics inserted_rows = row_count;
    created_count := created_count + coalesce(inserted_rows, 0);
  end loop;

  return jsonb_build_object(
    'run_date', target_date,
    'farms_considered', total_count,
    'notifications_created', created_count
  );
end;
$$;

revoke all on function public.run_daily_farmer_health_digest(date)
  from public, anon, authenticated;
grant execute on function public.run_daily_farmer_health_digest(date)
  to service_role;

do $cron$
declare
  existing_job bigint;
begin
  for existing_job in
    select jobid from cron.job
    where jobname = 'grainright-daily-farmer-health-digest'
  loop
    perform cron.unschedule(existing_job);
  end loop;

  -- pg_cron runs in UTC: 01:00 UTC is 06:30 Asia/Kolkata.
  perform cron.schedule(
    'grainright-daily-farmer-health-digest',
    '0 1 * * *',
    'select public.run_daily_farmer_health_digest();'
  );
end;
$cron$;
