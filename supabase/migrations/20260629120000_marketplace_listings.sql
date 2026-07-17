create table if not exists public.marketplace_listings (
  id uuid primary key default gen_random_uuid(),
  inventory_item_id uuid not null references public.farmer_inventory_items(id) on delete cascade,
  farmer_user_id uuid not null references auth.users(id) on delete cascade,
  farmer_phone text not null default '',
  farmer_id text not null default '',
  farm_id uuid references public.farms(id) on delete set null,
  farm_name text not null default '',
  batch_id text not null default '',
  product_category text not null default 'crop_lot'
    check (product_category in ('crop_lot', 'byproduct', 'processed_product')),
  product_name text not null default '',
  crop text not null default '',
  variety text not null default '',
  quantity numeric not null check (quantity > 0),
  unit text not null default 'kg',
  grade text not null default '',
  grade_score integer,
  moisture_percent numeric check (
    moisture_percent is null or
    (moisture_percent >= 0 and moisture_percent <= 100)
  ),
  asking_price_per_unit numeric check (
    asking_price_per_unit is null or asking_price_per_unit >= 0
  ),
  listing_note text not null default '',
  status text not null default 'active'
    check (status in ('active', 'paused', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (inventory_item_id)
);

create index if not exists marketplace_listings_active_created_idx
  on public.marketplace_listings(status, created_at desc);

create index if not exists marketplace_listings_farmer_created_idx
  on public.marketplace_listings(farmer_user_id, created_at desc);

create index if not exists marketplace_listings_product_idx
  on public.marketplace_listings(product_category, crop);

drop trigger if exists set_marketplace_listings_updated_at
  on public.marketplace_listings;
create trigger set_marketplace_listings_updated_at
before update on public.marketplace_listings
for each row
execute function public.set_updated_at();

alter table public.marketplace_listings enable row level security;

drop policy if exists "marketplace listings select active or own"
  on public.marketplace_listings;
create policy "marketplace listings select active or own"
on public.marketplace_listings for select to authenticated
using (status = 'active' or farmer_user_id = auth.uid());

drop policy if exists "marketplace listings insert own inventory"
  on public.marketplace_listings;
create policy "marketplace listings insert own inventory"
on public.marketplace_listings for insert to authenticated
with check (
  farmer_user_id = auth.uid()
  and exists (
    select 1
    from public.farmer_inventory_items
    where farmer_inventory_items.id = marketplace_listings.inventory_item_id
      and farmer_inventory_items.user_id = auth.uid()
  )
);

drop policy if exists "marketplace listings update own"
  on public.marketplace_listings;
create policy "marketplace listings update own"
on public.marketplace_listings for update to authenticated
using (farmer_user_id = auth.uid())
with check (farmer_user_id = auth.uid());

drop policy if exists "marketplace listings delete own"
  on public.marketplace_listings;
create policy "marketplace listings delete own"
on public.marketplace_listings for delete to authenticated
using (farmer_user_id = auth.uid());

create table if not exists public.marketplace_listing_interests (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.marketplace_listings(id) on delete cascade,
  fpc_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'interested'
    check (status in ('interested', 'contacted', 'closed')),
  message text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (listing_id, fpc_user_id)
);

create index if not exists marketplace_listing_interests_listing_idx
  on public.marketplace_listing_interests(listing_id, created_at desc);

create index if not exists marketplace_listing_interests_fpc_idx
  on public.marketplace_listing_interests(fpc_user_id, created_at desc);

drop trigger if exists set_marketplace_listing_interests_updated_at
  on public.marketplace_listing_interests;
create trigger set_marketplace_listing_interests_updated_at
before update on public.marketplace_listing_interests
for each row
execute function public.set_updated_at();

alter table public.marketplace_listing_interests enable row level security;

drop policy if exists "marketplace interests select related"
  on public.marketplace_listing_interests;
create policy "marketplace interests select related"
on public.marketplace_listing_interests for select to authenticated
using (
  fpc_user_id = auth.uid()
  or exists (
    select 1
    from public.marketplace_listings
    where marketplace_listings.id = marketplace_listing_interests.listing_id
      and marketplace_listings.farmer_user_id = auth.uid()
  )
);

drop policy if exists "marketplace interests insert own"
  on public.marketplace_listing_interests;
create policy "marketplace interests insert own"
on public.marketplace_listing_interests for insert to authenticated
with check (
  fpc_user_id = auth.uid()
  and exists (
    select 1
    from public.marketplace_listings
    where marketplace_listings.id = marketplace_listing_interests.listing_id
      and marketplace_listings.status = 'active'
  )
);

drop policy if exists "marketplace interests update own"
  on public.marketplace_listing_interests;
create policy "marketplace interests update own"
on public.marketplace_listing_interests for update to authenticated
using (fpc_user_id = auth.uid())
with check (fpc_user_id = auth.uid());

drop policy if exists "marketplace interests delete own"
  on public.marketplace_listing_interests;
create policy "marketplace interests delete own"
on public.marketplace_listing_interests for delete to authenticated
using (fpc_user_id = auth.uid());
