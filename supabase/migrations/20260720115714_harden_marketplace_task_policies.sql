create index if not exists farmer_daily_tasks_farm_id_idx
  on public.farmer_daily_tasks (farm_id);
create index if not exists marketplace_listings_farm_id_idx
  on public.marketplace_listings (farm_id);
create index if not exists marketplace_listings_farmer_user_id_idx
  on public.marketplace_listings (farmer_user_id);

drop policy if exists "marketplace harvest lots select own" on public.marketplace_harvest_lots;
drop policy if exists "marketplace harvest lots select own or listed" on public.marketplace_harvest_lots;
create policy "marketplace harvest lots select own or listed"
on public.marketplace_harvest_lots for select to authenticated
using (
  owner_id = (select auth.uid())
  or status in ('listed', 'fpo_verified', 'ordered', 'dispatched', 'closed')
);

drop policy if exists "marketplace harvest lots insert own" on public.marketplace_harvest_lots;
create policy "marketplace harvest lots insert own"
on public.marketplace_harvest_lots for insert to authenticated
with check (
  owner_id = (select auth.uid())
  and (
    inventory_item_id is null
    or exists (
      select 1 from public.farmer_inventory_items item
      where item.id = marketplace_harvest_lots.inventory_item_id
        and item.user_id = (select auth.uid())
    )
  )
);

drop policy if exists "marketplace harvest lots update own" on public.marketplace_harvest_lots;
create policy "marketplace harvest lots update own"
on public.marketplace_harvest_lots for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

drop policy if exists "marketplace harvest lots delete own" on public.marketplace_harvest_lots;
create policy "marketplace harvest lots delete own"
on public.marketplace_harvest_lots for delete to authenticated
using (owner_id = (select auth.uid()));

drop policy if exists "marketplace listings browse or own" on public.marketplace_listings;
drop policy if exists "marketplace listings select own or public" on public.marketplace_listings;
create policy "marketplace listings browse or own"
on public.marketplace_listings for select to authenticated
using (
  coalesce(farmer_user_id, owner_id) = (select auth.uid())
  or status in (
    'active', 'listed', 'rfq', 'order_accepted', 'dispatch_due',
    'dispatched', 'closed'
  )
);

drop policy if exists "marketplace listings insert own" on public.marketplace_listings;
drop policy if exists "marketplace listings insert own inventory" on public.marketplace_listings;
create policy "marketplace listings insert own inventory"
on public.marketplace_listings for insert to authenticated
with check (
  coalesce(farmer_user_id, owner_id) = (select auth.uid())
  and (
    inventory_item_id is null
    or exists (
      select 1 from public.farmer_inventory_items item
      where item.id = marketplace_listings.inventory_item_id
        and item.user_id = (select auth.uid())
    )
  )
  and (
    lot_id is null
    or exists (
      select 1 from public.marketplace_harvest_lots lot
      where lot.id = marketplace_listings.lot_id
        and lot.owner_id = (select auth.uid())
    )
  )
);

drop policy if exists "marketplace listings update own" on public.marketplace_listings;
create policy "marketplace listings update own"
on public.marketplace_listings for update to authenticated
using (coalesce(farmer_user_id, owner_id) = (select auth.uid()))
with check (coalesce(farmer_user_id, owner_id) = (select auth.uid()));

drop policy if exists "farmer daily tasks own" on public.farmer_daily_tasks;
create policy "farmer daily tasks own"
on public.farmer_daily_tasks for all to authenticated
using (user_id = (select auth.uid()))
with check (
  user_id = (select auth.uid())
  and (
    farm_id is null
    or exists (
      select 1 from public.farms farm
      where farm.id = farmer_daily_tasks.farm_id
        and farm.user_id = (select auth.uid())
    )
  )
);
