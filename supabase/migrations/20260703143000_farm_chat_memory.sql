create table if not exists public.farm_chat_messages (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  farmer_id text,
  farmer_phone text,
  role text not null check (role in ('farmer', 'assistant', 'system')),
  source text not null default 'ai_chat',
  message text not null check (char_length(trim(message)) between 1 and 8000),
  language text not null default 'en',
  growth_stage text,
  days_after_sowing integer,
  weather_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(weather_snapshot) = 'object'),
  farm_context jsonb not null default '{}'::jsonb check (jsonb_typeof(farm_context) = 'object'),
  created_at timestamptz not null default now()
);

create index if not exists farm_chat_messages_farm_created_idx
  on public.farm_chat_messages (farm_id, created_at desc);

create index if not exists farm_chat_messages_farmer_created_idx
  on public.farm_chat_messages (farmer_phone, farmer_id, created_at desc)
  where farmer_phone is not null;

create index if not exists farm_chat_messages_source_created_idx
  on public.farm_chat_messages (source, created_at desc);

alter table public.farm_chat_messages enable row level security;

drop policy if exists "farm chat messages select own farm"
  on public.farm_chat_messages;
create policy "farm chat messages select own farm"
on public.farm_chat_messages for select
to authenticated
using (
  farm_id in (
    select id from public.farms where user_id = auth.uid()
  )
);

drop policy if exists "farm chat messages insert own farm"
  on public.farm_chat_messages;
create policy "farm chat messages insert own farm"
on public.farm_chat_messages for insert
to authenticated
with check (
  farm_id in (
    select id from public.farms where user_id = auth.uid()
  )
);
