create extension if not exists http with schema public;
create extension if not exists pg_cron with schema pg_catalog;

create table if not exists public.farm_daily_tracking_runs (
  run_date date primary key,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'running'
    check (status in ('running', 'completed', 'partial', 'failed')),
  farms_total integer not null default 0,
  farms_saved integer not null default 0,
  farms_failed integer not null default 0,
  failures jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.farm_daily_tracking_runs enable row level security;

create or replace function public.run_daily_farm_tracking(
  target_date date default ((now() at time zone 'Asia/Kolkata')::date)
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  farm_row record;
  existing_row public.farm_data_snapshots%rowtype;
  weather_response public.http_response;
  weather_payload jsonb;
  current_weather jsonb;
  water_stress jsonb;
  crop_weather jsonb;
  disease_payload jsonb;
  snapshot_payload jsonb;
  collected_at timestamptz;
  latitude numeric;
  longitude numeric;
  days_after_sowing integer;
  rain_total numeric;
  latest_scan_date date;
  disease_max numeric;
  risk_cells integer;
  scout_zones integer;
  total_count integer := 0;
  saved_count integer := 0;
  failed_count integer := 0;
  failure_rows jsonb := '[]'::jsonb;
begin
  if target_date is null then
    target_date := (now() at time zone 'Asia/Kolkata')::date;
  end if;

  insert into public.farm_daily_tracking_runs (
    run_date, started_at, completed_at, status,
    farms_total, farms_saved, farms_failed, failures, updated_at
  ) values (
    target_date, now(), null, 'running', 0, 0, 0, '[]'::jsonb, now()
  )
  on conflict (run_date) do update set
    started_at = excluded.started_at,
    completed_at = null,
    status = 'running',
    farms_total = 0,
    farms_saved = 0,
    farms_failed = 0,
    failures = '[]'::jsonb,
    updated_at = now();

  for farm_row in
    select distinct on (f.id)
      f.id,
      f.name,
      f.bounds,
      f.crop,
      f.variety,
      f.current_status,
      f.current_status_stage,
      f.sowing_date,
      p.farmer_id,
      regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') as farmer_phone
    from public.farms f
    join public.farmer_phone_profiles p
      on p.user_id = f.user_id
     and p.status = 'active'
    where f.user_id is not null
    order by f.id, p.updated_at desc nulls last, p.created_at desc nulls last
  loop
    total_count := total_count + 1;
    begin
      if length(farm_row.farmer_phone) > 10 then
        farm_row.farmer_phone := right(farm_row.farmer_phone, 10);
      end if;
      if length(farm_row.farmer_phone) <> 10 then
        raise exception 'Farm has no valid linked farmer phone';
      end if;

      latitude := (
        ((farm_row.bounds ->> 'minLat')::numeric +
         (farm_row.bounds ->> 'maxLat')::numeric) / 2
      );
      longitude := (
        ((farm_row.bounds ->> 'minLng')::numeric +
         (farm_row.bounds ->> 'maxLng')::numeric) / 2
      );
      if latitude is null or longitude is null then
        raise exception 'Farm bounds are missing';
      end if;

      days_after_sowing := case
        when farm_row.sowing_date is null then null
        else greatest(0, target_date - farm_row.sowing_date)
      end;
      collected_at := now();

      select * into weather_response
      from public.http_get((
        'https://udbnskydigoqpxmmduvr.supabase.co/functions/v1/weather' ||
        '?latitude=' || latitude::text ||
        '&longitude=' || longitude::text ||
        '&crop=' || public.urlencode(coalesce(nullif(farm_row.crop, ''), 'millet')::varchar) ||
        '&growth_stage=' || public.urlencode(coalesce(farm_row.current_status_stage, '')::varchar) ||
        case when days_after_sowing is null then ''
          else '&days_after_sowing=' || days_after_sowing::text end ||
        '&language=en'
      )::varchar);

      if weather_response.status < 200 or weather_response.status >= 300 then
        raise exception 'Weather service returned HTTP %', weather_response.status;
      end if;

      weather_payload := coalesce(weather_response.content::jsonb, '{}'::jsonb);
      if coalesce((weather_payload ->> 'success')::boolean, false) is not true then
        raise exception 'Weather service did not return a successful result';
      end if;
      current_weather := coalesce(weather_payload -> 'current', '{}'::jsonb);
      water_stress := coalesce(weather_payload -> 'water_stress', '{}'::jsonb);
      crop_weather := coalesce(
        weather_payload -> 'crop_health_weather',
        '{}'::jsonb
      );

      select coalesce(sum((day ->> 'rain_mm')::numeric), 0)
      into rain_total
      from jsonb_array_elements(
        coalesce(weather_payload -> 'daily_7d', '[]'::jsonb)
      ) as day;

      select max(scan_date) into latest_scan_date
      from public.disease_risk_cells
      where farm_id = farm_row.id;

      if latest_scan_date is null then
        disease_max := null;
        risk_cells := 0;
        scout_zones := 0;
      else
        select max(composite_risk), count(*)::integer
        into disease_max, risk_cells
        from public.disease_risk_cells
        where farm_id = farm_row.id
          and scan_date = latest_scan_date;

        select count(*)::integer into scout_zones
        from public.disease_scout_zones
        where farm_id = farm_row.id
          and scan_date = latest_scan_date;
      end if;

      disease_payload := jsonb_build_object(
        'scan_date', latest_scan_date,
        'max_risk', disease_max,
        'risk_cells_count', risk_cells,
        'scout_zones_count', scout_zones
      );

      select * into existing_row
      from public.farm_data_snapshots
      where farm_id = farm_row.id
        and snapshot_date = target_date
      for update;

      snapshot_payload := coalesce(existing_row.snapshot, '{}'::jsonb) ||
        jsonb_build_object(
          'source', 'server_daily',
          'sources', jsonb_build_array('server_daily'),
          'collected_at', collected_at,
          'first_collected_at', coalesce(
            existing_row.snapshot ->> 'first_collected_at',
            collected_at::text
          ),
          'last_collected_at', collected_at,
          'refresh_count', coalesce(existing_row.refresh_count, 0) + 1,
          'farm', jsonb_build_object('id', farm_row.id, 'name', farm_row.name),
          'crop', jsonb_build_object(
            'name', farm_row.crop,
            'variety', farm_row.variety,
            'growth_stage', farm_row.current_status_stage,
            'days_after_sowing', days_after_sowing
          ),
          'status', jsonb_build_object(
            'current', farm_row.current_status,
            'stage', farm_row.current_status_stage
          ),
          'weather', jsonb_build_object(
            'temperature_c', current_weather -> 'temperature_c',
            'humidity_percent', current_weather -> 'humidity_percent',
            'rain_mm', current_weather -> 'rain_mm',
            'total_rain_mm', rain_total,
            'wind_kmh', current_weather -> 'wind_kmh',
            'weather_risk', case
              when crop_weather ? 'score'
                then greatest(0, 1 - (crop_weather ->> 'score')::numeric)
              else null
            end,
            'water_stress_label', water_stress -> 'label',
            'water_stress_score', water_stress -> 'score',
            'crop_weather_label', crop_weather -> 'label',
            'crop_weather_score', crop_weather -> 'score',
            'daily_7d', weather_payload -> 'daily_7d'
          ),
          'disease', disease_payload,
          'lifecycle', jsonb_build_object(
            'next_action', weather_payload #> '{agro_weather,next_action}'
          ),
          'timeline', jsonb_build_object('tracked_on', target_date)
        );

      insert into public.farm_data_snapshots (
        farm_id,
        farmer_id,
        farmer_phone,
        snapshot_date,
        collected_at,
        source,
        farm_name,
        crop,
        variety,
        growth_stage,
        current_status,
        days_after_sowing,
        temperature_c,
        humidity_percent,
        rain_mm,
        total_rain_mm,
        wind_kmh,
        weather_risk,
        water_stress_label,
        water_stress_score,
        crop_weather_label,
        crop_weather_score,
        disease_risk,
        risk_cells_count,
        scout_zones_count,
        refresh_count,
        snapshot,
        compact_after,
        compacted,
        compacted_at,
        updated_at
      ) values (
        farm_row.id,
        farm_row.farmer_id,
        farm_row.farmer_phone,
        target_date,
        collected_at,
        'server_daily',
        farm_row.name,
        farm_row.crop,
        farm_row.variety,
        farm_row.current_status_stage,
        farm_row.current_status,
        days_after_sowing,
        (current_weather ->> 'temperature_c')::numeric,
        (current_weather ->> 'humidity_percent')::numeric,
        (current_weather ->> 'rain_mm')::numeric,
        rain_total,
        (current_weather ->> 'wind_kmh')::numeric,
        case when crop_weather ? 'score'
          then greatest(0, 1 - (crop_weather ->> 'score')::numeric)
          else null end,
        water_stress ->> 'label',
        (water_stress ->> 'score')::numeric,
        crop_weather ->> 'label',
        (crop_weather ->> 'score')::numeric,
        disease_max,
        risk_cells,
        scout_zones,
        coalesce(existing_row.refresh_count, 0) + 1,
        snapshot_payload,
        (target_date + 4)::timestamptz,
        false,
        null,
        now()
      )
      on conflict (farm_id, snapshot_date) do update set
        farmer_id = excluded.farmer_id,
        farmer_phone = excluded.farmer_phone,
        collected_at = excluded.collected_at,
        source = excluded.source,
        farm_name = excluded.farm_name,
        crop = excluded.crop,
        variety = excluded.variety,
        growth_stage = excluded.growth_stage,
        current_status = excluded.current_status,
        days_after_sowing = excluded.days_after_sowing,
        temperature_c = excluded.temperature_c,
        humidity_percent = excluded.humidity_percent,
        rain_mm = excluded.rain_mm,
        total_rain_mm = excluded.total_rain_mm,
        wind_kmh = excluded.wind_kmh,
        weather_risk = excluded.weather_risk,
        water_stress_label = excluded.water_stress_label,
        water_stress_score = excluded.water_stress_score,
        crop_weather_label = excluded.crop_weather_label,
        crop_weather_score = excluded.crop_weather_score,
        disease_risk = excluded.disease_risk,
        risk_cells_count = excluded.risk_cells_count,
        scout_zones_count = excluded.scout_zones_count,
        refresh_count = excluded.refresh_count,
        snapshot = excluded.snapshot,
        compacted = false,
        compacted_at = null,
        updated_at = now();

      saved_count := saved_count + 1;
    exception when others then
      failed_count := failed_count + 1;
      failure_rows := failure_rows || jsonb_build_array(jsonb_build_object(
        'farm_id', farm_row.id,
        'error', left(sqlerrm, 300)
      ));
    end;
  end loop;

  update public.farm_daily_tracking_runs set
    completed_at = now(),
    status = case
      when total_count > 0 and failed_count = total_count then 'failed'
      when failed_count > 0 then 'partial'
      else 'completed'
    end,
    farms_total = total_count,
    farms_saved = saved_count,
    farms_failed = failed_count,
    failures = failure_rows,
    updated_at = now()
  where run_date = target_date;

  return jsonb_build_object(
    'run_date', target_date,
    'farms_total', total_count,
    'farms_saved', saved_count,
    'farms_failed', failed_count,
    'failures', failure_rows
  );
exception when others then
  update public.farm_daily_tracking_runs set
    completed_at = now(),
    status = 'failed',
    failures = jsonb_build_array(jsonb_build_object(
      'error', left(sqlerrm, 300)
    )),
    updated_at = now()
  where run_date = target_date;
  raise;
end;
$$;

revoke all on function public.run_daily_farm_tracking(date)
  from public, anon, authenticated;
grant execute on function public.run_daily_farm_tracking(date)
  to service_role;

do $$
declare
  existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'grainright-daily-farm-tracking';

  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;

  perform cron.schedule(
    'grainright-daily-farm-tracking',
    '30 20 * * *',
    'select public.run_daily_farm_tracking();'
  );
end;
$$;
