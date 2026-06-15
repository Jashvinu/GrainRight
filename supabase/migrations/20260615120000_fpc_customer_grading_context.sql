alter table public.analysis_jobs
  add column if not exists actor_role text not null default 'farmer';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'analysis_jobs_actor_role_check'
      and conrelid = 'public.analysis_jobs'::regclass
  ) then
    alter table public.analysis_jobs
      add constraint analysis_jobs_actor_role_check
      check (actor_role in ('farmer', 'fpc'));
  end if;
end $$;

alter table public.analysis_jobs
  add column if not exists fpc_id uuid;

alter table public.analysis_jobs
  add column if not exists fpc_customer_id text;

alter table public.analysis_jobs
  add column if not exists fpc_customer_name text;

alter table public.analysis_jobs
  add column if not exists source text not null default 'app';

create index if not exists analysis_jobs_fpc_created_idx
on public.analysis_jobs(fpc_id, created_at desc);

create index if not exists analysis_jobs_fpc_customer_created_idx
on public.analysis_jobs(fpc_customer_id, created_at desc);

create index if not exists analysis_jobs_farmer_farm_created_idx
on public.analysis_jobs(farmer_id, farm_id, created_at desc);

create table if not exists public.fpc_procurement_records (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null,
  farmer_id text,
  farm_id text,
  analysis_id uuid references public.analysis_jobs(id) on delete set null,
  batch_id text,
  customer_name text not null default '',
  crop_type text not null default '',
  variety text not null default '',
  quantity_kg numeric,
  grade text,
  price_per_kg numeric,
  total_value numeric,
  delivery_status text not null default 'received'
    check (delivery_status in ('received', 'graded', 'stored', 'sold', 'returned')),
  fpc_rating integer check (fpc_rating between 1 and 5),
  rating_notes text not null default '',
  trace_payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists fpc_procurement_records_fpc_created_idx
on public.fpc_procurement_records(fpc_id, created_at desc);

create index if not exists fpc_procurement_records_farmer_farm_idx
on public.fpc_procurement_records(farmer_id, farm_id);

drop trigger if exists set_fpc_procurement_records_updated_at
on public.fpc_procurement_records;

create trigger set_fpc_procurement_records_updated_at
before update on public.fpc_procurement_records
for each row
execute function public.set_updated_at();

alter table public.fpc_procurement_records enable row level security;

drop policy if exists "fpc users can read own procurement records"
on public.fpc_procurement_records;

create policy "fpc users can read own procurement records"
on public.fpc_procurement_records for select
to authenticated
using (
  fpc_id = auth.uid()
  or coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') in
    ('admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc')
);

drop policy if exists "fpc users can create own procurement records"
on public.fpc_procurement_records;

create policy "fpc users can create own procurement records"
on public.fpc_procurement_records for insert
to authenticated
with check (
  fpc_id = auth.uid()
  or coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') in
    ('admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc')
);

drop policy if exists "fpc users can update own procurement records"
on public.fpc_procurement_records;

create policy "fpc users can update own procurement records"
on public.fpc_procurement_records for update
to authenticated
using (
  fpc_id = auth.uid()
  or coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') in
    ('admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc')
)
with check (
  fpc_id = auth.uid()
  or coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') in
    ('admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc')
);
