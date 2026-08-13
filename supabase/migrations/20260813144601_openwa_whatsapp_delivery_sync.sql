alter table public.whatsapp_identities
  add column if not exists notifications_enabled boolean not null default true,
  add column if not exists notifications_updated_at timestamptz;

alter table public.whatsapp_chat_sessions
  add column if not exists verified boolean not null default false,
  add column if not exists bot_state jsonb not null default '{}'::jsonb;

alter table public.whatsapp_notification_outbox
  drop constraint if exists whatsapp_notification_outbox_status_check;

alter table public.whatsapp_notification_outbox
  add constraint whatsapp_notification_outbox_status_check
  check (status in ('pending', 'accepted', 'sent', 'delivered', 'read', 'failed', 'disabled'));

alter table public.whatsapp_notification_outbox
  add column if not exists accepted_at timestamptz,
  add column if not exists read_at timestamptz;

alter table public.whatsapp_dispatch_control
  add column if not exists rollout_started_at timestamptz not null default now(),
  add column if not exists proactive_alerts_enabled boolean not null default true,
  add column if not exists last_dispatch_at timestamptz;

create table if not exists public.whatsapp_webhook_events (
  event_key text primary key,
  provider text not null,
  event_type text not null,
  message_id text,
  whatsapp_phone text not null,
  status text not null default 'processing'
    check (status in ('processing', 'reply_pending', 'completed', 'failed')),
  attempt_count integer not null default 1 check (attempt_count > 0),
  reply_text text,
  provider_message_id text,
  last_error text not null default '',
  claimed_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.whatsapp_webhook_events enable row level security;
revoke all on public.whatsapp_webhook_events from public, anon, authenticated;
grant select, insert, update, delete on public.whatsapp_webhook_events to service_role;

create or replace function public.claim_whatsapp_webhook_event(
  p_event_key text,
  p_provider text,
  p_event_type text,
  p_message_id text,
  p_whatsapp_phone text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  existing public.whatsapp_webhook_events%rowtype;
begin
  select * into existing
  from public.whatsapp_webhook_events
  where event_key = p_event_key
  for update;

  if found and existing.status = 'completed' then
    return jsonb_build_object(
      'duplicate', true,
      'status', existing.status,
      'reply', existing.reply_text,
      'providerMessageId', existing.provider_message_id
    );
  end if;

  if found and existing.status = 'reply_pending' then
    return jsonb_build_object(
      'duplicate', false,
      'resume', true,
      'status', existing.status,
      'reply', existing.reply_text
    );
  end if;

  if found and existing.status = 'processing'
     and existing.claimed_at > now() - interval '2 minutes' then
    return jsonb_build_object('duplicate', true, 'status', existing.status);
  end if;

  insert into public.whatsapp_webhook_events(
    event_key, provider, event_type, message_id, whatsapp_phone,
    status, attempt_count, claimed_at, updated_at
  ) values (
    p_event_key, p_provider, p_event_type, p_message_id, p_whatsapp_phone,
    'processing', 1, now(), now()
  )
  on conflict (event_key) do update set
    status = 'processing',
    attempt_count = public.whatsapp_webhook_events.attempt_count + 1,
    claimed_at = now(),
    last_error = '',
    updated_at = now();

  return jsonb_build_object('duplicate', false, 'status', 'processing');
end;
$$;

revoke all on function public.claim_whatsapp_webhook_event(text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.claim_whatsapp_webhook_event(text,text,text,text,text)
  to service_role;

create index if not exists whatsapp_webhook_events_status_idx
  on public.whatsapp_webhook_events(status, claimed_at);

create index if not exists whatsapp_notification_provider_message_idx
  on public.whatsapp_notification_outbox(provider_message_id)
  where provider_message_id is not null;
