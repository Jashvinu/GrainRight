create table if not exists public.farmer_notifications (
  id uuid primary key default gen_random_uuid(),
  farmer_id text not null,
  farmer_phone text,
  type text not null default 'farm_status_update',
  title text not null,
  message text not null,
  farm_name text,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists farmer_notifications_farmer_created_idx
  on public.farmer_notifications (farmer_id, created_at desc);

create index if not exists farmer_notifications_phone_created_idx
  on public.farmer_notifications (farmer_phone, created_at desc)
  where farmer_phone is not null;

alter table public.farmer_notifications enable row level security;
