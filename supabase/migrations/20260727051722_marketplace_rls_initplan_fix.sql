-- Ensure both auth.uid() and auth.jwt() are initialization plans in every
-- marketplace-order RLS predicate.

drop policy if exists "marketplace purchase requests select related"
  on public.marketplace_purchase_requests;
create policy "marketplace purchase requests select related"
on public.marketplace_purchase_requests for select to authenticated
using (
  coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
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
  coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
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
  coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
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
  coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false'
  and exists (
    select 1
    from public.fpc_memberships membership
    where membership.fpc_id = fpc_cost_ledger.fpc_id
      and membership.user_id = (select auth.uid())
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  )
);

notify pgrst, 'reload schema';
