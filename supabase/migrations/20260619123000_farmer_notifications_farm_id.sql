alter table public.farmer_notifications
  add column if not exists farm_id uuid references public.farms(id) on delete cascade;

create index if not exists farmer_notifications_farm_created_idx
  on public.farmer_notifications (farmer_id, farm_id, created_at desc)
  where farm_id is not null;
