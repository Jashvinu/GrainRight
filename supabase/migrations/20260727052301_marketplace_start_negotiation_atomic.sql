-- Create the request and first whole-lot offer in one transaction. A legacy
-- open request without an offer is repaired in place.

create unique index if not exists marketplace_request_open_fpc_listing_uidx
  on public.marketplace_purchase_requests(fpc_id, listing_id)
  where fpc_id is not null
    and listing_id is not null
    and status in ('submitted', 'countered');

create or replace function public.marketplace_start_negotiation(
  p_listing_id uuid,
  p_fpc_id uuid,
  p_actor_user_id uuid,
  p_price_per_unit numeric,
  p_message text default ''
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  listing_row public.marketplace_listings;
  request_row public.marketplace_purchase_requests;
  offer_row public.marketplace_offer_events;
begin
  if p_price_per_unit is null or p_price_per_unit < 0 then
    raise exception 'Offer rate must be zero or greater';
  end if;
  if not exists (
    select 1
    from public.fpc_memberships membership
    where membership.fpc_id = p_fpc_id
      and membership.user_id = p_actor_user_id
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  ) then
    raise exception 'Active FPC Admin membership required';
  end if;

  select * into listing_row
  from public.marketplace_listings
  where id = p_listing_id
  for update;
  if listing_row.id is null
     or listing_row.status not in ('active', 'listed')
     or listing_row.quantity is null
     or listing_row.quantity <= 0 then
    raise exception 'Listing is no longer available';
  end if;
  if coalesce(listing_row.farmer_user_id, listing_row.owner_id) =
     p_actor_user_id then
    raise exception 'You cannot request your own listing';
  end if;

  select * into request_row
  from public.marketplace_purchase_requests request
  where request.fpc_id = p_fpc_id
    and request.listing_id = p_listing_id
    and request.status in ('submitted', 'countered')
  limit 1
  for update;

  if request_row.id is null then
    insert into public.marketplace_purchase_requests(
      buyer_user_id, fpc_id, listing_id, product_name, quantity, unit,
      proposed_price, message, status
    ) values (
      p_actor_user_id, p_fpc_id, p_listing_id,
      coalesce(nullif(listing_row.product_name, ''), listing_row.title),
      listing_row.quantity, listing_row.unit, p_price_per_unit,
      coalesce(p_message, ''), 'submitted'
    )
    returning * into request_row;
  elsif request_row.current_offer_id is not null
     or exists (
       select 1 from public.marketplace_offer_events offer
       where offer.request_id = request_row.id and offer.status = 'open'
     ) then
    raise exception 'An open negotiation already exists for this FPC and listing';
  end if;

  insert into public.marketplace_offer_events(
    request_id, listing_id, fpc_id, offered_by_user_id, offered_by_role,
    quantity, unit, price_per_unit, message
  ) values (
    request_row.id, listing_row.id, p_fpc_id, p_actor_user_id, 'fpc_admin',
    listing_row.quantity, listing_row.unit, p_price_per_unit,
    coalesce(p_message, '')
  )
  returning * into offer_row;

  update public.marketplace_purchase_requests
  set buyer_user_id = p_actor_user_id,
      current_offer_id = offer_row.id,
      proposed_price = offer_row.price_per_unit,
      message = offer_row.message,
      status = 'submitted',
      updated_at = now()
  where id = request_row.id
  returning * into request_row;

  insert into public.audit_events(
    fpc_id, actor_user_id, actor_role, action, target_type, target_id,
    after_data
  ) values (
    p_fpc_id, p_actor_user_id, 'fpc_admin',
    'marketplace_negotiation_started', 'marketplace_purchase_request',
    request_row.id::text,
    jsonb_build_object('request', to_jsonb(request_row), 'offer', to_jsonb(offer_row))
  );

  return jsonb_build_object(
    'request', to_jsonb(request_row),
    'offer', to_jsonb(offer_row)
  );
end;
$$;

revoke all on function public.marketplace_start_negotiation(
  uuid, uuid, uuid, numeric, text
) from public, anon, authenticated;
grant execute on function public.marketplace_start_negotiation(
  uuid, uuid, uuid, numeric, text
) to service_role;

notify pgrst, 'reload schema';
