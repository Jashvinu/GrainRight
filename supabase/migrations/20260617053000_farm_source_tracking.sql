alter table public.farms
  add column if not exists source_table text;
alter table public.farms
  add column if not exists source_id uuid;

create index if not exists farms_source_table_source_id_idx
  on public.farms (source_table, source_id);

create unique index if not exists farms_source_table_source_id_uniq_idx
  on public.farms (source_table, source_id)
  where source_table is not null and source_id is not null;