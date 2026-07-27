create index if not exists farm_harvest_zones_farm_idx
  on public.farm_harvest_zones(farm_id);
create index if not exists farm_harvest_zones_user_idx
  on public.farm_harvest_zones(user_id);
create index if not exists farmer_inventory_farm_idx
  on public.farmer_inventory_items(farm_id);
create index if not exists farmer_inventory_harvest_zone_id_idx
  on public.farmer_inventory_items(harvest_zone_id);
create index if not exists analysis_jobs_harvest_zone_id_idx
  on public.analysis_jobs(harvest_zone_id);

drop policy if exists "farmers read own harvest zone plans"
  on public.farm_harvest_zone_plans;
create policy "farmers read own harvest zone plans"
on public.farm_harvest_zone_plans for select to authenticated
using (
  user_id = (select auth.uid())
  and not coalesce(
    (((select auth.jwt()) ->> 'is_anonymous')::boolean),
    false
  )
);

drop policy if exists "farmers read own harvest zones"
  on public.farm_harvest_zones;
create policy "farmers read own harvest zones"
on public.farm_harvest_zones for select to authenticated
using (
  user_id = (select auth.uid())
  and not coalesce(
    (((select auth.jwt()) ->> 'is_anonymous')::boolean),
    false
  )
);

drop policy if exists "farmer inventory select own"
  on public.farmer_inventory_items;
create policy "farmer inventory select own"
on public.farmer_inventory_items for select to authenticated
using (
  user_id = (select auth.uid())
  and not coalesce(
    (((select auth.jwt()) ->> 'is_anonymous')::boolean),
    false
  )
);

drop policy if exists "farmer inventory insert own"
  on public.farmer_inventory_items;
create policy "farmer inventory insert own"
on public.farmer_inventory_items for insert to authenticated
with check (
  user_id = (select auth.uid())
  and not coalesce(
    (((select auth.jwt()) ->> 'is_anonymous')::boolean),
    false
  )
  and exists (
    select 1 from public.farms
    where farms.id = farmer_inventory_items.farm_id
      and farms.user_id = (select auth.uid())
  )
);

drop policy if exists "farmer inventory update own"
  on public.farmer_inventory_items;
create policy "farmer inventory update own"
on public.farmer_inventory_items for update to authenticated
using (
  user_id = (select auth.uid())
  and not coalesce(
    (((select auth.jwt()) ->> 'is_anonymous')::boolean),
    false
  )
)
with check (
  user_id = (select auth.uid())
  and not coalesce(
    (((select auth.jwt()) ->> 'is_anonymous')::boolean),
    false
  )
  and exists (
    select 1 from public.farms
    where farms.id = farmer_inventory_items.farm_id
      and farms.user_id = (select auth.uid())
  )
);

drop policy if exists "farmer inventory delete own"
  on public.farmer_inventory_items;
create policy "farmer inventory delete own"
on public.farmer_inventory_items for delete to authenticated
using (
  user_id = (select auth.uid())
  and not coalesce(
    (((select auth.jwt()) ->> 'is_anonymous')::boolean),
    false
  )
);
