create extension if not exists pg_net with schema extensions;

create table if not exists public.apmc_sync_control (
  id boolean primary key default true check (id),
  cron_token text not null unique default encode(gen_random_bytes(32), 'hex'),
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  last_record_count integer not null default 0 check (last_record_count >= 0),
  last_error text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.apmc_sync_control enable row level security;
revoke all on public.apmc_sync_control from public, anon, authenticated;
grant select, update on public.apmc_sync_control to service_role;

insert into public.apmc_sync_control (id)
values (true)
on conflict (id) do nothing;

do $$
begin
  if exists (
    select 1
    from pg_proc
    join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
    where pg_namespace.nspname = 'cron'
      and pg_proc.proname = 'schedule'
  ) then
    perform cron.schedule(
      'grainright-daily-official-apmc-rates',
      '35 18 * * *',
      $job$
        select net.http_post(
          url := 'https://udbnskydigoqpxmmduvr.supabase.co/functions/v1/apmc-market-rates',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-apmc-cron-token', (
              select cron_token
              from public.apmc_sync_control
              where id = true
            )
          ),
          body := jsonb_build_object(
            'action', 'daily_refresh',
            'refresh', true,
            'limit', 500
          ),
          timeout_milliseconds := 30000
        ) as request_id;
      $job$
    );
  end if;
end $$;
