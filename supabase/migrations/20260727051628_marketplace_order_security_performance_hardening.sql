-- Keep marketplace order data unavailable to anonymous-auth sessions and add
-- covering indexes for every new foreign-key access path.

drop policy if exists "marketplace purchase requests select related"
  on public.marketplace_purchase_requests;
create policy "marketplace purchase requests select related"
on public.marketplace_purchase_requests for select to authenticated
using (
  coalesce((select auth.jwt() ->> 'is_anonymous'), 'false') = 'false'
  and (
    buyer_user_id = (select auth.uid())
    or (
      fpc_id is not null
      and exists (
        select 1
        from public.fpc_memberships membership
        where membership.fpc_id = marketplace_purchase_requests.fpc_id
          and membership.user_id = (select auth.uid())
          and membership.role = 'fpc_admin'
          and membership.status = 'active'
      )
    )
    or exists (
      select 1
      from public.marketplace_listings listing
      where listing.id = marketplace_purchase_requests.listing_id
        and coalesce(listing.farmer_user_id, listing.owner_id) =
          (select auth.uid())
    )
  )
);

drop policy if exists "marketplace offer events select related"
  on public.marketplace_offer_events;
create policy "marketplace offer events select related"
on public.marketplace_offer_events for select to authenticated
using (
  coalesce((select auth.jwt() ->> 'is_anonymous'), 'false') = 'false'
  and (
    exists (
      select 1
      from public.marketplace_listings listing
      where listing.id = marketplace_offer_events.listing_id
        and coalesce(listing.farmer_user_id, listing.owner_id) =
          (select auth.uid())
    )
    or exists (
      select 1
      from public.fpc_memberships membership
      where membership.fpc_id = marketplace_offer_events.fpc_id
        and membership.user_id = (select auth.uid())
        and membership.role = 'fpc_admin'
        and membership.status = 'active'
    )
  )
);

drop policy if exists "marketplace orders select related"
  on public.marketplace_orders;
create policy "marketplace orders select related"
on public.marketplace_orders for select to authenticated
using (
  coalesce((select auth.jwt() ->> 'is_anonymous'), 'false') = 'false'
  and (
    farmer_user_id = (select auth.uid())
    or exists (
      select 1
      from public.fpc_memberships membership
      where membership.fpc_id = marketplace_orders.fpc_id
        and membership.user_id = (select auth.uid())
        and membership.role = 'fpc_admin'
        and membership.status = 'active'
    )
  )
);

drop policy if exists "fpc cost ledger select admins"
  on public.fpc_cost_ledger;
create policy "fpc cost ledger select admins"
on public.fpc_cost_ledger for select to authenticated
using (
  coalesce((select auth.jwt() ->> 'is_anonymous'), 'false') = 'false'
  and exists (
    select 1
    from public.fpc_memberships membership
    where membership.fpc_id = fpc_cost_ledger.fpc_id
      and membership.user_id = (select auth.uid())
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  )
);

create index if not exists marketplace_offer_events_listing_idx
  on public.marketplace_offer_events(listing_id);
create index if not exists marketplace_offer_events_actor_idx
  on public.marketplace_offer_events(offered_by_user_id);

create index if not exists marketplace_orders_farm_idx
  on public.marketplace_orders(farm_id)
  where farm_id is not null;
create index if not exists marketplace_orders_analysis_idx
  on public.marketplace_orders(arrival_analysis_id)
  where arrival_analysis_id is not null;
create index if not exists marketplace_orders_rate_proposer_idx
  on public.marketplace_orders(final_rate_proposed_by)
  where final_rate_proposed_by is not null;
create index if not exists marketplace_orders_rate_confirmer_idx
  on public.marketplace_orders(final_rate_confirmed_by)
  where final_rate_confirmed_by is not null;
create index if not exists marketplace_orders_procurement_actor_idx
  on public.marketplace_orders(procurement_accepted_by)
  where procurement_accepted_by is not null;
create index if not exists marketplace_orders_procurement_record_idx
  on public.marketplace_orders(procurement_record_id)
  where procurement_record_id is not null;
create index if not exists marketplace_orders_procurement_lot_idx
  on public.marketplace_orders(procurement_lot_id)
  where procurement_lot_id is not null;

create index if not exists fpc_cost_ledger_procurement_lot_idx
  on public.fpc_cost_ledger(procurement_lot_id)
  where procurement_lot_id is not null;
create index if not exists fpc_cost_ledger_production_run_idx
  on public.fpc_cost_ledger(production_run_id)
  where production_run_id is not null;
create index if not exists fpc_cost_ledger_packaging_batch_idx
  on public.fpc_cost_ledger(packaging_batch_id)
  where packaging_batch_id is not null;
create index if not exists fpc_cost_ledger_sales_order_idx
  on public.fpc_cost_ledger(sales_order_id)
  where sales_order_id is not null;
create index if not exists fpc_cost_ledger_reversal_idx
  on public.fpc_cost_ledger(reversal_of)
  where reversal_of is not null;
create index if not exists fpc_cost_ledger_recorded_by_idx
  on public.fpc_cost_ledger(recorded_by);

notify pgrst, 'reload schema';
