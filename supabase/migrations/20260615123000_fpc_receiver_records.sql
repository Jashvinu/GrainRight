alter table public.fpc_procurement_records
  add column if not exists batch_id text;

alter table public.fpc_procurement_records
  add column if not exists trace_payload jsonb not null default '{}'::jsonb;

alter table public.fpc_procurement_records
  add column if not exists received_at timestamptz not null default now();

create index if not exists fpc_procurement_records_received_idx
on public.fpc_procurement_records(fpc_id, received_at desc);

create index if not exists fpc_procurement_records_batch_idx
on public.fpc_procurement_records(fpc_id, batch_id);
