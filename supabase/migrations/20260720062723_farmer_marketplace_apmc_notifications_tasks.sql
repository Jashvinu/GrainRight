-- Reconcile the farmer marketplace with both the legacy production schema and
-- the newer inventory-backed schema. Every statement is additive so existing
-- harvest custody and order records remain intact.

create table if not exists public.marketplace_harvest_lots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  farm_id uuid references public.farms(id) on delete set null,
  inventory_item_id uuid references public.farmer_inventory_items(id) on delete set null,
  analysis_job_id uuid,
  lot_code text not null,
  crop text not null default '',
  variety text not null default '',
  grade text not null default '',
  bags integer check (bags is null or bags >= 0),
  quantity_kg numeric not null default 0 check (quantity_kg >= 0),
  moisture_percent numeric check (
    moisture_percent is null or moisture_percent between 0 and 100
  ),
  status text not null default 'draft',
  qr_payload jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.marketplace_harvest_lots
  add column if not exists inventory_item_id uuid references public.farmer_inventory_items(id) on delete set null,
  add column if not exists moisture_percent numeric;

create unique index if not exists marketplace_harvest_lots_inventory_uidx
  on public.marketplace_harvest_lots (inventory_item_id)
  where inventory_item_id is not null;
create unique index if not exists marketplace_harvest_lots_owner_code_uidx
  on public.marketplace_harvest_lots (owner_id, lot_code);
create index if not exists marketplace_harvest_lots_owner_created_idx
  on public.marketplace_harvest_lots (owner_id, created_at desc);

alter table public.marketplace_harvest_lots enable row level security;
grant select, insert, update on public.marketplace_harvest_lots to authenticated;

drop policy if exists "marketplace harvest lots select own" on public.marketplace_harvest_lots;
create policy "marketplace harvest lots select own"
on public.marketplace_harvest_lots for select to authenticated
using (owner_id = auth.uid());

drop policy if exists "marketplace harvest lots insert own" on public.marketplace_harvest_lots;
create policy "marketplace harvest lots insert own"
on public.marketplace_harvest_lots for insert to authenticated
with check (
  owner_id = auth.uid()
  and (
    inventory_item_id is null
    or exists (
      select 1 from public.farmer_inventory_items item
      where item.id = marketplace_harvest_lots.inventory_item_id
        and item.user_id = auth.uid()
    )
  )
);

drop policy if exists "marketplace harvest lots update own" on public.marketplace_harvest_lots;
create policy "marketplace harvest lots update own"
on public.marketplace_harvest_lots for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

-- Add the inventory-backed contract to the production listing table while
-- retaining the legacy lot/order columns used by FPC custody workflows.
alter table public.marketplace_listings
  add column if not exists owner_id uuid references auth.users(id) on delete cascade,
  add column if not exists lot_id uuid references public.marketplace_harvest_lots(id) on delete set null,
  add column if not exists inventory_item_id uuid references public.farmer_inventory_items(id) on delete set null,
  add column if not exists farmer_user_id uuid references auth.users(id) on delete cascade,
  add column if not exists farmer_phone text not null default '',
  add column if not exists farmer_id text not null default '',
  add column if not exists farm_id uuid references public.farms(id) on delete set null,
  add column if not exists farm_name text not null default '',
  add column if not exists batch_id text not null default '',
  add column if not exists product_category text not null default 'crop_lot',
  add column if not exists product_name text not null default '',
  add column if not exists crop text not null default '',
  add column if not exists variety text not null default '',
  add column if not exists quantity numeric,
  add column if not exists unit text not null default 'kg',
  add column if not exists grade text not null default '',
  add column if not exists grade_score integer,
  add column if not exists moisture_percent numeric,
  add column if not exists asking_price_per_unit numeric,
  add column if not exists asking_price_per_kg numeric,
  add column if not exists listing_note text not null default '',
  add column if not exists title text not null default '',
  add column if not exists buyer_city text not null default '',
  add column if not exists buyer_request text not null default '',
  add column if not exists description text not null default '',
  add column if not exists location_label text not null default '',
  add column if not exists price_unit text not null default 'kg',
  add column if not exists image_paths text[] not null default '{}',
  add column if not exists view_count integer not null default 0,
  add column if not exists expires_at timestamptz,
  add column if not exists paused_at timestamptz,
  add column if not exists closed_reason text not null default '',
  add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.marketplace_listings
set
  owner_id = coalesce(owner_id, farmer_user_id),
  farmer_user_id = coalesce(farmer_user_id, owner_id),
  asking_price_per_unit = coalesce(asking_price_per_unit, asking_price_per_kg),
  product_name = case when trim(product_name) = '' then title else product_name end,
  crop = case when trim(crop) = '' then title else crop end,
  description = case
    when trim(description) = '' then coalesce(nullif(listing_note, ''), metadata ->> 'description', '')
    else description
  end
where owner_id is null
   or farmer_user_id is null
   or asking_price_per_unit is null
   or trim(product_name) = ''
   or trim(crop) = ''
   or trim(description) = '';

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'marketplace_listings'
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%status%'
  loop
    execute format('alter table public.marketplace_listings drop constraint %I', constraint_name);
  end loop;
end $$;

alter table public.marketplace_listings
  add constraint marketplace_listings_status_check
  check (status in (
    'draft', 'active', 'listed', 'paused', 'rfq', 'order_accepted',
    'dispatch_due', 'dispatched', 'sold', 'closed', 'expired'
  ));

create unique index if not exists marketplace_listings_inventory_uidx
  on public.marketplace_listings (inventory_item_id)
  where inventory_item_id is not null;
create index if not exists marketplace_listings_browse_idx
  on public.marketplace_listings (status, created_at desc);
create index if not exists marketplace_listings_owner_idx
  on public.marketplace_listings ((coalesce(farmer_user_id, owner_id)), created_at desc);

alter table public.marketplace_listings enable row level security;
grant select, insert, update on public.marketplace_listings to authenticated;

drop policy if exists "marketplace listings select active or own" on public.marketplace_listings;
drop policy if exists "marketplace listings browse or own" on public.marketplace_listings;
create policy "marketplace listings browse or own"
on public.marketplace_listings for select to authenticated
using (
  status in ('active', 'listed')
  or coalesce(farmer_user_id, owner_id) = auth.uid()
);

drop policy if exists "marketplace listings insert own inventory" on public.marketplace_listings;
create policy "marketplace listings insert own inventory"
on public.marketplace_listings for insert to authenticated
with check (
  coalesce(farmer_user_id, owner_id) = auth.uid()
  and (
    inventory_item_id is null
    or exists (
      select 1 from public.farmer_inventory_items item
      where item.id = marketplace_listings.inventory_item_id
        and item.user_id = auth.uid()
    )
  )
);

drop policy if exists "marketplace listings update own" on public.marketplace_listings;
create policy "marketplace listings update own"
on public.marketplace_listings for update to authenticated
using (coalesce(farmer_user_id, owner_id) = auth.uid())
with check (coalesce(farmer_user_id, owner_id) = auth.uid());

create table if not exists public.marketplace_input_products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null,
  brand text not null default '',
  description text not null default '',
  package_size text not null default '',
  price numeric check (price is null or price >= 0),
  price_unit text not null default 'unit',
  image_path text not null default '',
  supplier_name text not null default '',
  supplier_contact text not null default '',
  is_verified boolean not null default false,
  status text not null default 'draft' check (status in ('draft', 'published', 'paused')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_input_products_browse_idx
  on public.marketplace_input_products (status, category, name);
alter table public.marketplace_input_products enable row level security;
grant select on public.marketplace_input_products to authenticated;
drop policy if exists "marketplace input products read verified" on public.marketplace_input_products;
create policy "marketplace input products read verified"
on public.marketplace_input_products for select to authenticated
using (status = 'published' and is_verified = true);

create table if not exists public.marketplace_purchase_requests (
  id uuid primary key default gen_random_uuid(),
  buyer_user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid references public.marketplace_input_products(id) on delete set null,
  listing_id uuid references public.marketplace_listings(id) on delete set null,
  product_name text not null default '',
  quantity numeric check (quantity is null or quantity > 0),
  unit text not null default 'unit',
  proposed_price numeric check (proposed_price is null or proposed_price >= 0),
  message text not null default '',
  status text not null default 'submitted'
    check (status in ('submitted', 'contacted', 'accepted', 'declined', 'cancelled', 'closed')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (product_id is not null or listing_id is not null or trim(product_name) <> '')
);

create index if not exists marketplace_purchase_requests_buyer_idx
  on public.marketplace_purchase_requests (buyer_user_id, created_at desc);
create index if not exists marketplace_purchase_requests_listing_idx
  on public.marketplace_purchase_requests (listing_id, created_at desc)
  where listing_id is not null;
alter table public.marketplace_purchase_requests enable row level security;
grant select, insert, update on public.marketplace_purchase_requests to authenticated;
drop policy if exists "marketplace purchase requests select related" on public.marketplace_purchase_requests;
create policy "marketplace purchase requests select related"
on public.marketplace_purchase_requests for select to authenticated
using (
  buyer_user_id = auth.uid()
  or exists (
    select 1 from public.marketplace_listings listing
    where listing.id = marketplace_purchase_requests.listing_id
      and coalesce(listing.farmer_user_id, listing.owner_id) = auth.uid()
  )
);
drop policy if exists "marketplace purchase requests insert own" on public.marketplace_purchase_requests;
create policy "marketplace purchase requests insert own"
on public.marketplace_purchase_requests for insert to authenticated
with check (buyer_user_id = auth.uid());
drop policy if exists "marketplace purchase requests update own" on public.marketplace_purchase_requests;
create policy "marketplace purchase requests update own"
on public.marketplace_purchase_requests for update to authenticated
using (buyer_user_id = auth.uid())
with check (buyer_user_id = auth.uid());

create table if not exists public.apmc_market_rate_history (
  id bigint generated by default as identity primary key,
  source text not null default 'data.gov.in',
  state text not null,
  district text not null,
  market text not null,
  commodity text not null,
  variety text not null default '',
  grade text not null default '',
  arrival_date date not null,
  min_price numeric not null check (min_price >= 0),
  max_price numeric not null check (max_price >= 0),
  modal_price numeric not null check (modal_price >= 0),
  source_record jsonb not null default '{}'::jsonb,
  synced_at timestamptz not null default now()
);

create unique index if not exists apmc_market_rate_history_uidx
  on public.apmc_market_rate_history (
    source, state, district, market, commodity, variety, grade, arrival_date
  );
create index if not exists apmc_market_rate_history_search_idx
  on public.apmc_market_rate_history (state, commodity, arrival_date desc);
alter table public.apmc_market_rate_history enable row level security;
grant select on public.apmc_market_rate_history to anon, authenticated;
drop policy if exists "apmc history public read" on public.apmc_market_rate_history;
create policy "apmc history public read"
on public.apmc_market_rate_history for select to anon, authenticated
using (true);

create table if not exists public.farmer_daily_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  farm_id uuid references public.farms(id) on delete cascade,
  task_date date not null default current_date,
  task_key text not null,
  task_type text not null,
  title_key text not null,
  description_key text not null default '',
  priority text not null default 'normal' check (priority in ('urgent', 'high', 'normal', 'low')),
  due_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'done', 'snoozed', 'dismissed')),
  source_type text not null,
  source_id text not null default '',
  action_route text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  completed_at timestamptz,
  snoozed_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, farm_id, task_date, task_key)
);

create unique index if not exists farmer_daily_tasks_dedupe_uidx
  on public.farmer_daily_tasks (
    user_id,
    coalesce(farm_id, '00000000-0000-0000-0000-000000000000'::uuid),
    task_date,
    task_key
  );

create index if not exists farmer_daily_tasks_open_idx
  on public.farmer_daily_tasks (user_id, farm_id, task_date, status, due_at);
alter table public.farmer_daily_tasks enable row level security;
grant select, insert, update, delete on public.farmer_daily_tasks to authenticated;
drop policy if exists "farmer daily tasks own" on public.farmer_daily_tasks;
create policy "farmer daily tasks own"
on public.farmer_daily_tasks for all to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and (
    farm_id is null
    or exists (
      select 1 from public.farms farm
      where farm.id = farmer_daily_tasks.farm_id
        and farm.user_id = auth.uid()
    )
  )
);

alter table public.farmer_notifications
  add column if not exists recipient_user_id uuid references auth.users(id) on delete cascade,
  add column if not exists dedupe_key text,
  add column if not exists action_route text not null default '';

create unique index if not exists farmer_notifications_recipient_dedupe_uidx
  on public.farmer_notifications (recipient_user_id, dedupe_key)
  where recipient_user_id is not null and dedupe_key is not null;
create index if not exists farmer_notifications_recipient_unread_idx
  on public.farmer_notifications (recipient_user_id, created_at desc)
  where read_at is null;
alter table public.farmer_notifications enable row level security;
grant select, update on public.farmer_notifications to authenticated;
drop policy if exists "farmer notifications select own recipient" on public.farmer_notifications;
create policy "farmer notifications select own recipient"
on public.farmer_notifications for select to authenticated
using (
  recipient_user_id = auth.uid()
  or exists (
    select 1 from public.farmer_phone_profiles profile
    where profile.user_id = auth.uid()
      and profile.farmer_id = farmer_notifications.farmer_id
  )
);
drop policy if exists "farmer notifications update own recipient" on public.farmer_notifications;
create policy "farmer notifications update own recipient"
on public.farmer_notifications for update to authenticated
using (
  recipient_user_id = auth.uid()
  or exists (
    select 1 from public.farmer_phone_profiles profile
    where profile.user_id = auth.uid()
      and profile.farmer_id = farmer_notifications.farmer_id
  )
)
with check (
  recipient_user_id = auth.uid()
  or exists (
    select 1 from public.farmer_phone_profiles profile
    where profile.user_id = auth.uid()
      and profile.farmer_id = farmer_notifications.farmer_id
  )
);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'farmer_notifications'
    ) then
    alter publication supabase_realtime add table public.farmer_notifications;
  end if;
end $$;

do $$
begin
  if to_regprocedure('public.set_updated_at()') is not null then
    drop trigger if exists set_marketplace_harvest_lots_updated_at on public.marketplace_harvest_lots;
    create trigger set_marketplace_harvest_lots_updated_at
      before update on public.marketplace_harvest_lots
      for each row execute function public.set_updated_at();

    drop trigger if exists set_marketplace_input_products_updated_at on public.marketplace_input_products;
    create trigger set_marketplace_input_products_updated_at
      before update on public.marketplace_input_products
      for each row execute function public.set_updated_at();

    drop trigger if exists set_marketplace_purchase_requests_updated_at on public.marketplace_purchase_requests;
    create trigger set_marketplace_purchase_requests_updated_at
      before update on public.marketplace_purchase_requests
      for each row execute function public.set_updated_at();

    drop trigger if exists set_farmer_daily_tasks_updated_at on public.farmer_daily_tasks;
    create trigger set_farmer_daily_tasks_updated_at
      before update on public.farmer_daily_tasks
      for each row execute function public.set_updated_at();
  end if;
end $$;
