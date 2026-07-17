create table if not exists public.farmer_inventory_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  farmer_phone text not null check (char_length(trim(farmer_phone)) between 10 and 15),
  farmer_id text,
  farm_id uuid not null references public.farms(id) on delete cascade,
  farm_name text not null default '',
  inventory_id text not null,
  harvest_batch_id text,
  product_category text not null default 'crop_lot'
    check (product_category in ('crop_lot', 'byproduct', 'processed_product')),
  product_name text not null default '',
  crop text not null default '',
  variety text not null default '',
  quantity numeric not null check (quantity > 0),
  unit text not null default 'kg',
  bag_count integer check (bag_count is null or bag_count >= 0),
  bag_size_kg numeric check (bag_size_kg is null or bag_size_kg >= 0),
  moisture_percent numeric check (
    moisture_percent is null or
    (moisture_percent >= 0 and moisture_percent <= 100)
  ),
  grade text not null default '',
  grade_score integer,
  grade_basis text not null default '',
  estimated_yield_kg numeric check (
    estimated_yield_kg is null or estimated_yield_kg >= 0
  ),
  harvested_at timestamptz not null default now(),
  latitude numeric,
  longitude numeric,
  image_name text not null default '',
  source_flow text not null default 'inventory',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, inventory_id)
);

create index if not exists farmer_inventory_user_created_idx
  on public.farmer_inventory_items(user_id, created_at desc);

create index if not exists farmer_inventory_farmer_farm_idx
  on public.farmer_inventory_items(farmer_phone, farmer_id, farm_id);

drop trigger if exists set_farmer_inventory_items_updated_at
  on public.farmer_inventory_items;
create trigger set_farmer_inventory_items_updated_at
before update on public.farmer_inventory_items
for each row
execute function public.set_updated_at();

alter table public.farmer_inventory_items enable row level security;

drop policy if exists "farmer inventory select own"
  on public.farmer_inventory_items;
create policy "farmer inventory select own"
on public.farmer_inventory_items for select to authenticated
using (user_id = auth.uid());

drop policy if exists "farmer inventory insert own"
  on public.farmer_inventory_items;
create policy "farmer inventory insert own"
on public.farmer_inventory_items for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.farms
    where farms.id = farmer_inventory_items.farm_id
      and farms.user_id = auth.uid()
  )
);

drop policy if exists "farmer inventory update own"
  on public.farmer_inventory_items;
create policy "farmer inventory update own"
on public.farmer_inventory_items for update to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.farms
    where farms.id = farmer_inventory_items.farm_id
      and farms.user_id = auth.uid()
  )
);

drop policy if exists "farmer inventory delete own"
  on public.farmer_inventory_items;
create policy "farmer inventory delete own"
on public.farmer_inventory_items for delete to authenticated
using (user_id = auth.uid());
