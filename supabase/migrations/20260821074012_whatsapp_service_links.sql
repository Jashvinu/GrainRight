create table if not exists public.whatsapp_service_links (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  whatsapp_phone text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  farmer_id text not null,
  farm_id uuid not null references public.farms(id) on delete cascade,
  service text not null check (service in ('ai', 'grading')),
  language text not null default 'en' check (language in ('en', 'hi', 'mr')),
  status text not null default 'active' check (status in ('active', 'completed', 'cancelled', 'expired')),
  result jsonb not null default '{}'::jsonb,
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  completed_at timestamptz,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists whatsapp_service_links_phone_idx
  on public.whatsapp_service_links (whatsapp_phone, status, updated_at desc);

create index if not exists whatsapp_service_links_token_idx
  on public.whatsapp_service_links (token_hash);

alter table public.whatsapp_service_links enable row level security;
revoke all on public.whatsapp_service_links from public, anon, authenticated;

comment on table public.whatsapp_service_links is
  'Service-role-only, short-lived links from WhatsApp to a specific GrainRight farmer service.';
