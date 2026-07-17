create table if not exists public.stakeholder_document_uploads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  farmer_phone text not null default '',
  document_kind text not null,
  document_path text not null,
  content_type text not null default '',
  created_at timestamptz not null default now(),
  unique (user_id, document_path)
);

create index if not exists stakeholder_document_uploads_user_kind_idx
  on public.stakeholder_document_uploads(user_id, document_kind, created_at desc);

alter table public.stakeholder_document_uploads enable row level security;

drop policy if exists "farmers can read own stakeholder document uploads"
  on public.stakeholder_document_uploads;
create policy "farmers can read own stakeholder document uploads"
on public.stakeholder_document_uploads for select to authenticated
using (user_id = auth.uid());

drop policy if exists "farmers can insert own stakeholder document uploads"
  on public.stakeholder_document_uploads;
create policy "farmers can insert own stakeholder document uploads"
on public.stakeholder_document_uploads for insert to authenticated
with check (user_id = auth.uid());
