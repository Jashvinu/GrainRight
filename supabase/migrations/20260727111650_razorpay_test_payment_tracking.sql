-- Razorpay Test Mode payment state; live provider credentials are rejected.
create table public.stakeholder_payment_attempts (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null
    references public.stakeholder_applications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null default 'test'
    check (environment = 'test'),
  provider text not null default 'razorpay'
    check (provider = 'razorpay'),
  provider_order_id text,
  provider_payment_id text,
  receipt text not null,
  amount_subunits bigint not null check (amount_subunits > 0),
  currency text not null default 'INR'
    check (currency = 'INR'),
  status text not null default 'creating'
    check (
      status in (
        'creating',
        'order_created',
        'signature_verified',
        'authorized',
        'captured',
        'failed',
        'refunded'
      )
    ),
  provider_status text not null default '',
  checkout_signature text not null default '',
  failure_code text not null default '',
  failure_description text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  captured_at timestamptz,
  refunded_at timestamptz,
  unique (provider_order_id),
  unique (provider_payment_id),
  unique (receipt)
);

create unique index stakeholder_payment_attempts_active_application_idx
  on public.stakeholder_payment_attempts(application_id)
  where status in (
    'creating',
    'order_created',
    'signature_verified',
    'authorized'
  );

create index stakeholder_payment_attempts_user_created_idx
  on public.stakeholder_payment_attempts(user_id, created_at desc);

create index stakeholder_payment_attempts_application_created_idx
  on public.stakeholder_payment_attempts(application_id, created_at desc);

drop trigger if exists set_stakeholder_payment_attempts_updated_at
  on public.stakeholder_payment_attempts;
create trigger set_stakeholder_payment_attempts_updated_at
before update on public.stakeholder_payment_attempts
for each row execute function public.set_updated_at();

alter table public.stakeholder_payment_attempts enable row level security;

revoke all on table public.stakeholder_payment_attempts
  from anon, authenticated;
grant select on table public.stakeholder_payment_attempts to authenticated;

create policy "farmers can read own stakeholder payment attempts"
on public.stakeholder_payment_attempts for select
to authenticated
using (user_id = auth.uid());

create policy "admins can read stakeholder payment attempts"
on public.stakeholder_payment_attempts for select
to authenticated
using (public.has_server_role(array['admin']));

create table public.razorpay_webhook_events (
  event_id text primary key,
  environment text not null default 'test'
    check (environment = 'test'),
  event_type text not null,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_error text not null default ''
);

create index razorpay_webhook_events_received_idx
  on public.razorpay_webhook_events(received_at desc);

alter table public.razorpay_webhook_events enable row level security;

revoke all on table public.razorpay_webhook_events
  from anon, authenticated;

drop policy if exists "admins can read stakeholder applications"
  on public.stakeholder_applications;
create policy "admins can read stakeholder applications"
on public.stakeholder_applications for select
to authenticated
using (public.has_server_role(array['admin']));

drop policy if exists "admins can review stakeholder applications"
  on public.stakeholder_applications;
create policy "admins can review stakeholder applications"
on public.stakeholder_applications for update
to authenticated
using (public.has_server_role(array['admin']))
with check (public.has_server_role(array['admin']));

drop policy if exists "admins can read stakeholder events"
  on public.stakeholder_application_events;
create policy "admins can read stakeholder events"
on public.stakeholder_application_events for select
to authenticated
using (public.has_server_role(array['admin']));

drop policy if exists "admins can create stakeholder events"
  on public.stakeholder_application_events;
create policy "admins can create stakeholder events"
on public.stakeholder_application_events for insert
to authenticated
with check (public.has_server_role(array['admin']));
