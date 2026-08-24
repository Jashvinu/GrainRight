-- The scheduled tracker calls the protected weather function with the same
-- server-side control token used by the notification scheduler. The extension
-- owned http_get helper is intentionally left unchanged.
do $repair$
declare
  definition text;
  original_definition text;
begin
  select pg_get_functiondef('public.run_daily_farm_tracking(date)'::regprocedure)
    into definition;
  original_definition := definition;
  definition := replace(
    definition,
    'from public.http_get((',
    'from public.http((''GET'', ('
  );
  definition := replace(
    definition,
    '''&language=en''
      )::varchar);',
    '''&language=en''
      )::varchar,
      array[public.http_header(
        ''x-farm-monitoring-token'',
        (select cron_token from public.farmer_push_dispatch_control where id = true)
      )],
      null,
      null
    )::public.http_request);'
  );
  if definition = original_definition then
    raise exception 'Could not patch the scheduled farm weather request';
  end if;
  execute definition;
end;
$repair$;
