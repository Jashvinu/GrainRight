-- Farmer <-> FPC marketplace negotiation, whole-lot orders, quarantine intake,
-- and auditable FPC margin accounting.

alter table public.marketplace_purchase_requests
  add column if not exists fpc_id uuid references public.fpcs(id) on delete restrict,
  add column if not exists current_offer_id uuid,
  add column if not exists accepted_at timestamptz,
  add column if not exists closed_at timestamptz;

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
      and t.relname = 'marketplace_purchase_requests'
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%status%'
  loop
    execute format(
      'alter table public.marketplace_purchase_requests drop constraint %I',
      constraint_name
    );
  end loop;
end $$;

alter table public.marketplace_purchase_requests
  add constraint marketplace_purchase_requests_status_check
  check (status in (
    'submitted', 'countered', 'accepted', 'declined', 'cancelled',
    'superseded', 'closed'
  ));

create index if not exists marketplace_purchase_requests_fpc_status_idx
  on public.marketplace_purchase_requests(fpc_id, status, updated_at desc)
  where fpc_id is not null;

create table if not exists public.marketplace_offer_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.marketplace_purchase_requests(id) on delete cascade,
  listing_id uuid not null
    references public.marketplace_listings(id) on delete restrict,
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  offered_by_user_id uuid not null references auth.users(id) on delete restrict,
  offered_by_role text not null
    check (offered_by_role in ('farmer', 'fpc_admin')),
  quantity numeric(14,3) not null check (quantity > 0),
  unit text not null default 'kg',
  price_per_unit numeric(14,2) not null check (price_per_unit >= 0),
  message text not null default '',
  status text not null default 'open'
    check (status in ('open', 'accepted', 'rejected', 'superseded', 'withdrawn')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);

alter table public.marketplace_purchase_requests
  drop constraint if exists marketplace_purchase_requests_current_offer_fk;
alter table public.marketplace_purchase_requests
  add constraint marketplace_purchase_requests_current_offer_fk
  foreign key (current_offer_id)
  references public.marketplace_offer_events(id) on delete set null;

create index if not exists marketplace_offer_events_request_idx
  on public.marketplace_offer_events(request_id, created_at desc);
create index if not exists marketplace_offer_events_fpc_idx
  on public.marketplace_offer_events(fpc_id, created_at desc);

update public.marketplace_purchase_requests request
set fpc_id = membership.fpc_id,
    updated_at = now()
from public.fpc_memberships membership
where request.fpc_id is null
  and request.listing_id is not null
  and membership.user_id = request.buyer_user_id
  and membership.role = 'fpc_admin'
  and membership.status = 'active';

insert into public.marketplace_offer_events(
  request_id, listing_id, fpc_id, offered_by_user_id, offered_by_role,
  quantity, unit, price_per_unit, message, status, created_at
)
select
  request.id, request.listing_id, request.fpc_id, request.buyer_user_id,
  'fpc_admin', listing.quantity, listing.unit,
  coalesce(
    request.proposed_price,
    listing.asking_price_per_unit,
    listing.asking_price_per_kg
  ),
  request.message, 'open', request.created_at
from public.marketplace_purchase_requests request
join public.marketplace_listings listing on listing.id = request.listing_id
where request.fpc_id is not null
  and request.status in ('submitted', 'countered')
  and listing.quantity is not null
  and coalesce(
    request.proposed_price,
    listing.asking_price_per_unit,
    listing.asking_price_per_kg
  ) is not null
  and not exists (
    select 1 from public.marketplace_offer_events offer
    where offer.request_id = request.id
  );

update public.marketplace_purchase_requests request
set current_offer_id = offer.id,
    proposed_price = offer.price_per_unit,
    updated_at = now()
from public.marketplace_offer_events offer
where request.id = offer.request_id
  and request.current_offer_id is null
  and offer.status = 'open';

create table if not exists public.marketplace_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  request_id uuid not null unique
    references public.marketplace_purchase_requests(id) on delete restrict,
  accepted_offer_id uuid not null unique
    references public.marketplace_offer_events(id) on delete restrict,
  listing_id uuid not null unique
    references public.marketplace_listings(id) on delete restrict,
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  farmer_user_id uuid not null references auth.users(id) on delete restrict,
  farmer_id text not null default '',
  farm_id uuid references public.farms(id) on delete set null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit text not null default 'kg',
  provisional_rate numeric(14,2) not null check (provisional_rate >= 0),
  provisional_amount numeric(14,2) not null check (provisional_amount >= 0),
  arrival_quantity_kg numeric(14,3)
    check (arrival_quantity_kg is null or arrival_quantity_kg > 0),
  arrival_grade text not null default '',
  arrival_moisture_percent numeric(6,2)
    check (
      arrival_moisture_percent is null
      or arrival_moisture_percent between 0 and 100
    ),
  arrival_analysis_id uuid references public.analysis_jobs(id) on delete set null,
  final_rate numeric(14,2) check (final_rate is null or final_rate >= 0),
  final_amount numeric(14,2) check (final_amount is null or final_amount >= 0),
  final_rate_proposed_by uuid references auth.users(id) on delete set null,
  final_rate_proposed_at timestamptz,
  final_rate_confirmed_by uuid references auth.users(id) on delete set null,
  final_rate_confirmed_at timestamptz,
  procurement_accepted_by uuid references auth.users(id) on delete set null,
  procurement_accepted_at timestamptz,
  procurement_record_id uuid references public.fpc_procurement_records(id) on delete set null,
  procurement_lot_id uuid references public.procurement_lots(id) on delete set null,
  status text not null default 'awaiting_arrival'
    check (status in (
      'awaiting_arrival', 'dispatched', 'arrived_quarantine', 'grading',
      'final_rate_pending', 'final_rate_confirmed', 'procurement_accepted',
      'payment_pending', 'completed', 'returned', 'cancelled', 'disputed'
    )),
  qr_payload jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  accepted_at timestamptz not null default now(),
  arrived_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_orders_farmer_status_idx
  on public.marketplace_orders(farmer_user_id, status, updated_at desc);
create index if not exists marketplace_orders_fpc_status_idx
  on public.marketplace_orders(fpc_id, status, updated_at desc);

alter table public.fpc_procurement_records
  add column if not exists marketplace_order_id uuid
    references public.marketplace_orders(id) on delete set null,
  add column if not exists quarantine_status text not null default 'not_applicable'
    check (quarantine_status in (
      'not_applicable', 'awaiting_grade', 'awaiting_farmer_confirmation',
      'awaiting_fpc_acceptance', 'released', 'returned'
    ));

create unique index if not exists fpc_procurement_marketplace_order_uidx
  on public.fpc_procurement_records(marketplace_order_id)
  where marketplace_order_id is not null;

alter table public.procurement_lots
  add column if not exists marketplace_order_id uuid
    references public.marketplace_orders(id) on delete set null;

create unique index if not exists procurement_lots_marketplace_order_uidx
  on public.procurement_lots(marketplace_order_id)
  where marketplace_order_id is not null;

alter table public.sales_order_items
  add column if not exists procurement_lot_id uuid
    references public.procurement_lots(id) on delete restrict;

alter table public.stock_reservations
  alter column packaging_batch_id drop not null,
  add column if not exists procurement_lot_id uuid
    references public.procurement_lots(id) on delete restrict;

alter table public.stock_reservations
  drop constraint if exists stock_reservations_inventory_source_check;
alter table public.stock_reservations
  add constraint stock_reservations_inventory_source_check
  check (num_nonnulls(packaging_batch_id, procurement_lot_id) = 1);

create index if not exists sales_order_items_procurement_lot_idx
  on public.sales_order_items(procurement_lot_id)
  where procurement_lot_id is not null;
create index if not exists stock_reservations_procurement_lot_idx
  on public.stock_reservations(procurement_lot_id, status)
  where procurement_lot_id is not null;

create table if not exists public.fpc_cost_ledger (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  category text not null check (category in (
    'procurement_logistics', 'processing', 'packaging',
    'sales_logistics', 'adjustment'
  )),
  amount numeric(14,2) not null check (amount <> 0),
  description text not null,
  marketplace_order_id uuid references public.marketplace_orders(id) on delete restrict,
  procurement_lot_id uuid references public.procurement_lots(id) on delete restrict,
  production_run_id uuid references public.production_runs(id) on delete restrict,
  packaging_batch_id uuid references public.packaging_batches(id) on delete restrict,
  sales_order_id uuid references public.sales_orders(id) on delete restrict,
  reversal_of uuid references public.fpc_cost_ledger(id) on delete restrict,
  evidence jsonb not null default '{}'::jsonb,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (
    reversal_of is not null
    or num_nonnulls(
      marketplace_order_id, procurement_lot_id, production_run_id,
      packaging_batch_id, sales_order_id
    ) > 0
  )
);

create index if not exists fpc_cost_ledger_fpc_occurred_idx
  on public.fpc_cost_ledger(fpc_id, occurred_at desc);
create index if not exists fpc_cost_ledger_marketplace_order_idx
  on public.fpc_cost_ledger(marketplace_order_id)
  where marketplace_order_id is not null;

alter table public.marketplace_offer_events enable row level security;
alter table public.marketplace_orders enable row level security;
alter table public.fpc_cost_ledger enable row level security;

grant select on public.marketplace_offer_events to authenticated;
grant select on public.marketplace_orders to authenticated;
grant select on public.fpc_cost_ledger to authenticated;

drop policy if exists "marketplace purchase requests select related"
  on public.marketplace_purchase_requests;
create policy "marketplace purchase requests select related"
on public.marketplace_purchase_requests for select to authenticated
using (
  buyer_user_id = auth.uid()
  or (
    fpc_id is not null
    and exists (
      select 1
      from public.fpc_memberships membership
      where membership.fpc_id = marketplace_purchase_requests.fpc_id
        and membership.user_id = auth.uid()
        and membership.role = 'fpc_admin'
        and membership.status = 'active'
    )
  )
  or exists (
    select 1
    from public.marketplace_listings listing
    where listing.id = marketplace_purchase_requests.listing_id
      and coalesce(listing.farmer_user_id, listing.owner_id) = auth.uid()
  )
);

drop policy if exists "marketplace purchase requests insert own"
  on public.marketplace_purchase_requests;
drop policy if exists "marketplace purchase requests update own"
  on public.marketplace_purchase_requests;
revoke insert, update, delete on public.marketplace_purchase_requests
  from authenticated;

drop policy if exists "marketplace offer events select related"
  on public.marketplace_offer_events;
create policy "marketplace offer events select related"
on public.marketplace_offer_events for select to authenticated
using (
  exists (
    select 1
    from public.marketplace_listings listing
    where listing.id = marketplace_offer_events.listing_id
      and coalesce(listing.farmer_user_id, listing.owner_id) = auth.uid()
  )
  or exists (
    select 1
    from public.fpc_memberships membership
    where membership.fpc_id = marketplace_offer_events.fpc_id
      and membership.user_id = auth.uid()
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  )
);

drop policy if exists "marketplace orders select related"
  on public.marketplace_orders;
create policy "marketplace orders select related"
on public.marketplace_orders for select to authenticated
using (
  farmer_user_id = auth.uid()
  or exists (
    select 1
    from public.fpc_memberships membership
    where membership.fpc_id = marketplace_orders.fpc_id
      and membership.user_id = auth.uid()
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  )
);

drop policy if exists "fpc cost ledger select admins"
  on public.fpc_cost_ledger;
create policy "fpc cost ledger select admins"
on public.fpc_cost_ledger for select to authenticated
using (
  exists (
    select 1
    from public.fpc_memberships membership
    where membership.fpc_id = fpc_cost_ledger.fpc_id
      and membership.user_id = auth.uid()
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  )
);

revoke insert, update, delete on public.marketplace_offer_events
  from authenticated;
revoke insert, update, delete on public.marketplace_orders
  from authenticated;
revoke insert, update, delete on public.fpc_cost_ledger
  from authenticated;

create or replace function public.marketplace_append_offer(
  p_request_id uuid,
  p_actor_user_id uuid,
  p_actor_role text,
  p_price_per_unit numeric,
  p_message text default ''
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  request_row public.marketplace_purchase_requests;
  listing_row public.marketplace_listings;
  latest_offer public.marketplace_offer_events;
  saved_offer public.marketplace_offer_events;
  owner_user_id uuid;
begin
  if p_actor_role not in ('farmer', 'fpc_admin') then
    raise exception 'Only a Farmer or FPC Admin can make an offer';
  end if;
  if p_price_per_unit is null or p_price_per_unit < 0 then
    raise exception 'Offer rate must be zero or greater';
  end if;

  select * into request_row
  from public.marketplace_purchase_requests
  where id = p_request_id
  for update;
  if request_row.id is null or request_row.status not in ('submitted', 'countered') then
    raise exception 'Negotiation is no longer open';
  end if;

  select * into listing_row
  from public.marketplace_listings
  where id = request_row.listing_id
  for update;
  owner_user_id := coalesce(listing_row.farmer_user_id, listing_row.owner_id);
  if listing_row.id is null or listing_row.status not in ('active', 'listed') then
    raise exception 'Listing is no longer available';
  end if;
  if p_actor_role = 'farmer' and p_actor_user_id <> owner_user_id then
    raise exception 'Farmer does not own this listing';
  end if;
  if p_actor_role = 'fpc_admin'
     and not exists (
       select 1 from public.fpc_memberships membership
       where membership.fpc_id = request_row.fpc_id
         and membership.user_id = p_actor_user_id
         and membership.role = 'fpc_admin'
         and membership.status = 'active'
     ) then
    raise exception 'Active FPC Admin membership required';
  end if;

  select * into latest_offer
  from public.marketplace_offer_events
  where request_id = request_row.id and status = 'open'
  order by created_at desc
  limit 1
  for update;
  if latest_offer.id is not null and latest_offer.offered_by_role = p_actor_role then
    raise exception 'Wait for the other party before making another offer';
  end if;

  update public.marketplace_offer_events
  set status = 'superseded'
  where request_id = request_row.id and status = 'open';

  insert into public.marketplace_offer_events(
    request_id, listing_id, fpc_id, offered_by_user_id, offered_by_role,
    quantity, unit, price_per_unit, message
  ) values (
    request_row.id, listing_row.id, request_row.fpc_id, p_actor_user_id,
    p_actor_role, listing_row.quantity, listing_row.unit, p_price_per_unit,
    coalesce(p_message, '')
  )
  returning * into saved_offer;

  update public.marketplace_purchase_requests
  set status = 'countered',
      current_offer_id = saved_offer.id,
      proposed_price = saved_offer.price_per_unit,
      message = saved_offer.message,
      updated_at = now()
  where id = request_row.id;

  insert into public.audit_events(
    fpc_id, actor_user_id, actor_role, action, target_type, target_id,
    after_data
  ) values (
    request_row.fpc_id, p_actor_user_id, p_actor_role,
    'marketplace_offer_created', 'marketplace_offer',
    saved_offer.id::text, to_jsonb(saved_offer)
  );

  return to_jsonb(saved_offer);
end;
$$;

create or replace function public.marketplace_accept_offer(
  p_request_id uuid,
  p_offer_id uuid,
  p_actor_user_id uuid,
  p_actor_role text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  request_row public.marketplace_purchase_requests;
  offer_row public.marketplace_offer_events;
  listing_row public.marketplace_listings;
  saved_order public.marketplace_orders;
  owner_user_id uuid;
  order_number_value text;
begin
  if p_actor_role not in ('farmer', 'fpc_admin') then
    raise exception 'Only a Farmer or FPC Admin can accept an offer';
  end if;

  select * into request_row
  from public.marketplace_purchase_requests
  where id = p_request_id
  for update;
  if request_row.id is null or request_row.status not in ('submitted', 'countered') then
    raise exception 'Negotiation is no longer open';
  end if;

  select * into offer_row
  from public.marketplace_offer_events
  where id = p_offer_id and request_id = p_request_id
  for update;
  if offer_row.id is null or offer_row.status <> 'open' then
    raise exception 'Offer is no longer open';
  end if;

  select * into listing_row
  from public.marketplace_listings
  where id = request_row.listing_id
  for update;
  owner_user_id := coalesce(listing_row.farmer_user_id, listing_row.owner_id);
  if listing_row.id is null or listing_row.status not in ('active', 'listed') then
    raise exception 'Listing is no longer available';
  end if;
  if offer_row.quantity <> listing_row.quantity
     or lower(offer_row.unit) <> lower(listing_row.unit) then
    raise exception 'Marketplace orders must cover the whole listed lot';
  end if;
  if p_actor_role = 'farmer' and p_actor_user_id <> owner_user_id then
    raise exception 'Farmer does not own this listing';
  end if;
  if p_actor_role = 'fpc_admin'
     and not exists (
       select 1 from public.fpc_memberships membership
       where membership.fpc_id = offer_row.fpc_id
         and membership.user_id = p_actor_user_id
         and membership.role = 'fpc_admin'
         and membership.status = 'active'
     ) then
    raise exception 'Active FPC Admin membership required';
  end if;

  update public.marketplace_offer_events
  set status = case when id = p_offer_id then 'accepted' else 'superseded' end,
      accepted_at = case when id = p_offer_id then now() else accepted_at end
  where request_id = p_request_id and status = 'open';

  update public.marketplace_purchase_requests
  set status = 'accepted', current_offer_id = p_offer_id,
      accepted_at = now(), updated_at = now()
  where id = p_request_id;

  update public.marketplace_purchase_requests
  set status = 'superseded', closed_at = now(), updated_at = now()
  where listing_id = listing_row.id
    and id <> p_request_id
    and status in ('submitted', 'countered');

  update public.marketplace_offer_events offers
  set status = 'superseded'
  from public.marketplace_purchase_requests requests
  where requests.id = offers.request_id
    and requests.listing_id = listing_row.id
    and requests.id <> p_request_id
    and offers.status = 'open';

  order_number_value :=
    'MKT-' || to_char(now(), 'YYYYMMDD') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.marketplace_orders(
    order_number, request_id, accepted_offer_id, listing_id, fpc_id,
    farmer_user_id, farmer_id, farm_id, quantity, unit, provisional_rate,
    provisional_amount, qr_payload
  ) values (
    order_number_value, request_row.id, offer_row.id, listing_row.id,
    offer_row.fpc_id, owner_user_id, coalesce(listing_row.farmer_id, ''),
    listing_row.farm_id, offer_row.quantity, offer_row.unit,
    offer_row.price_per_unit,
    round(offer_row.quantity * offer_row.price_per_unit, 2),
    jsonb_build_object(
      'type', 'grainright_marketplace_order',
      'orderId', null,
      'orderNumber', order_number_value,
      'listingId', listing_row.id,
      'batchId', listing_row.batch_id
    )
  )
  returning * into saved_order;

  update public.marketplace_orders
  set qr_payload = jsonb_set(
    qr_payload,
    '{orderId}',
    to_jsonb(saved_order.id::text),
    true
  )
  where id = saved_order.id
  returning * into saved_order;

  update public.marketplace_listings
  set status = 'order_accepted', updated_at = now()
  where id = listing_row.id;

  insert into public.audit_events(
    fpc_id, actor_user_id, actor_role, action, target_type, target_id,
    after_data
  ) values (
    offer_row.fpc_id, p_actor_user_id, p_actor_role, 'marketplace_offer_accepted',
    'marketplace_order', saved_order.id::text, to_jsonb(saved_order)
  );

  return to_jsonb(saved_order);
end;
$$;

create or replace function public.marketplace_record_arrival(
  p_order_id uuid,
  p_actor_user_id uuid,
  p_quantity_kg numeric,
  p_grade text,
  p_moisture_percent numeric default null,
  p_analysis_id uuid default null,
  p_trace_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  order_row public.marketplace_orders;
  listing_row public.marketplace_listings;
  receipt_row public.fpc_procurement_records;
  lot_row public.procurement_lots;
  batch_value text;
begin
  select * into order_row
  from public.marketplace_orders
  where id = p_order_id
  for update;
  if order_row.id is null or order_row.status not in (
    'awaiting_arrival', 'dispatched', 'arrived_quarantine', 'grading'
  ) then
    raise exception 'Order cannot be received in its current state';
  end if;
  if not exists (
    select 1 from public.fpc_memberships membership
    where membership.fpc_id = order_row.fpc_id
      and membership.user_id = p_actor_user_id
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  ) then
    raise exception 'Active FPC Admin membership required';
  end if;
  if p_quantity_kg is null or p_quantity_kg <= 0 then
    raise exception 'Arrival weight must be greater than zero';
  end if;
  if trim(coalesce(p_grade, '')) = '' then
    raise exception 'Arrival grade is required';
  end if;

  select * into listing_row
  from public.marketplace_listings
  where id = order_row.listing_id;
  batch_value := coalesce(
    nullif(trim(listing_row.batch_id), ''),
    order_row.order_number
  );

  insert into public.fpc_procurement_records(
    fpc_id, fpc_organization_id, farmer_id, farm_id, analysis_id, batch_id,
    customer_name, crop_type, variety, quantity_kg, gross_weight_kg,
    net_weight_kg, moisture_percent, grade, price_per_kg, total_value,
    delivery_status, trace_payload, receipt_number, received_at,
    marketplace_order_id, quarantine_status
  ) values (
    p_actor_user_id, order_row.fpc_id, order_row.farmer_id,
    order_row.farm_id::text, p_analysis_id, batch_value,
    coalesce(listing_row.farm_name, ''), coalesce(listing_row.crop, ''),
    coalesce(listing_row.variety, ''), p_quantity_kg, p_quantity_kg,
    p_quantity_kg, p_moisture_percent, trim(p_grade), null, null,
    'received',
    coalesce(p_trace_payload, '{}'::jsonb) ||
      jsonb_build_object('marketplaceOrderId', order_row.id),
    'MKT-RCPT-' || upper(right(replace(order_row.id::text, '-', ''), 8)),
    now(), order_row.id, 'awaiting_farmer_confirmation'
  )
  on conflict (marketplace_order_id) where marketplace_order_id is not null
  do update set
    analysis_id = excluded.analysis_id,
    quantity_kg = excluded.quantity_kg,
    gross_weight_kg = excluded.gross_weight_kg,
    net_weight_kg = excluded.net_weight_kg,
    moisture_percent = excluded.moisture_percent,
    grade = excluded.grade,
    trace_payload = excluded.trace_payload,
    quarantine_status = 'awaiting_farmer_confirmation',
    updated_at = now()
  returning * into receipt_row;

  insert into public.procurement_lots(
    fpc_id, receipt_id, batch_id, traceability_code, farmer_id, farm_id,
    crop, variety, bags, gross_weight_kg, net_weight_kg, moisture_percent,
    grade, status, marketplace_order_id
  ) values (
    order_row.fpc_id, receipt_row.id, batch_value, order_row.order_number,
    order_row.farmer_id, coalesce(order_row.farm_id::text, ''),
    coalesce(listing_row.crop, ''), coalesce(listing_row.variety, ''), 0,
    p_quantity_kg, p_quantity_kg, p_moisture_percent, trim(p_grade),
    'quarantine', order_row.id
  )
  on conflict (marketplace_order_id) where marketplace_order_id is not null
  do update set
    receipt_id = excluded.receipt_id,
    gross_weight_kg = excluded.gross_weight_kg,
    net_weight_kg = excluded.net_weight_kg,
    moisture_percent = excluded.moisture_percent,
    grade = excluded.grade,
    status = 'quarantine',
    updated_at = now()
  returning * into lot_row;

  update public.marketplace_orders
  set arrival_quantity_kg = p_quantity_kg,
      arrival_grade = trim(p_grade),
      arrival_moisture_percent = p_moisture_percent,
      arrival_analysis_id = p_analysis_id,
      procurement_record_id = receipt_row.id,
      procurement_lot_id = lot_row.id,
      final_rate = null,
      final_amount = null,
      final_rate_proposed_by = null,
      final_rate_proposed_at = null,
      final_rate_confirmed_by = null,
      final_rate_confirmed_at = null,
      status = 'arrived_quarantine',
      arrived_at = coalesce(arrived_at, now()),
      updated_at = now()
  where id = order_row.id
  returning * into order_row;

  update public.analysis_jobs
  set fpc_organization_id = order_row.fpc_id,
      procurement_lot_id = lot_row.id
  where id = p_analysis_id;

  insert into public.audit_events(
    fpc_id, actor_user_id, actor_role, action, target_type, target_id,
    after_data
  ) values (
    order_row.fpc_id, p_actor_user_id, 'fpc_admin',
    'marketplace_arrival_quarantined', 'marketplace_order',
    order_row.id::text, to_jsonb(order_row)
  );

  return to_jsonb(order_row);
end;
$$;

create or replace function public.marketplace_finalize_procurement(
  p_order_id uuid,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  order_row public.marketplace_orders;
  listing_row public.marketplace_listings;
  lot_row public.procurement_lots;
  payment_row public.farmer_payment_ledger;
begin
  select * into order_row
  from public.marketplace_orders
  where id = p_order_id
  for update;
  if order_row.id is null or order_row.status <> 'final_rate_confirmed' then
    raise exception 'Farmer must confirm the final rate before procurement';
  end if;
  if order_row.final_rate is null
     or order_row.arrival_quantity_kg is null
     or order_row.procurement_lot_id is null then
    raise exception 'Arrival grading and final rate are incomplete';
  end if;
  if not exists (
    select 1 from public.fpc_memberships membership
    where membership.fpc_id = order_row.fpc_id
      and membership.user_id = p_actor_user_id
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  ) then
    raise exception 'Active FPC Admin membership required';
  end if;

  select * into lot_row
  from public.procurement_lots
  where id = order_row.procurement_lot_id
    and fpc_id = order_row.fpc_id
  for update;
  if lot_row.id is null or lot_row.status <> 'quarantine' then
    raise exception 'Quarantined procurement lot was not found';
  end if;

  select * into listing_row
  from public.marketplace_listings
  where id = order_row.listing_id;

  update public.procurement_lots
  set status = 'received', updated_at = now()
  where id = lot_row.id
  returning * into lot_row;

  update public.fpc_procurement_records
  set price_per_kg = order_row.final_rate,
      total_value = order_row.final_amount,
      delivery_status = 'graded',
      quarantine_status = 'released',
      updated_at = now()
  where id = order_row.procurement_record_id;

  if not exists (
    select 1 from public.stock_ledger stock
    where stock.fpc_id = order_row.fpc_id
      and stock.reference_type = 'marketplace_order'
      and stock.reference_id = order_row.id::text
      and stock.movement_type = 'receipt'
  ) then
    insert into public.stock_ledger(
      fpc_id, lot_id, movement_type, item_type, item_name, quantity_kg,
      reference_type, reference_id, reason, posted_by
    ) values (
      order_row.fpc_id, lot_row.id, 'receipt', 'raw_material',
      coalesce(nullif(listing_row.crop, ''), listing_row.product_name),
      order_row.arrival_quantity_kg, 'marketplace_order', order_row.id::text,
      'Released after Farmer final-rate confirmation and FPC acceptance',
      p_actor_user_id
    );
  end if;

  insert into public.farmer_payment_ledger(
    fpc_id, lot_id, farmer_id, net_weight_kg, rate_per_kg, status
  ) values (
    order_row.fpc_id, lot_row.id, order_row.farmer_id,
    order_row.arrival_quantity_kg, order_row.final_rate, 'draft'
  )
  on conflict (lot_id) where reversal_of is null and status <> 'reversed'
  do update set
    net_weight_kg = excluded.net_weight_kg,
    rate_per_kg = excluded.rate_per_kg,
    updated_at = now()
  returning * into payment_row;

  update public.marketplace_orders
  set status = 'procurement_accepted',
      procurement_accepted_by = p_actor_user_id,
      procurement_accepted_at = now(),
      updated_at = now()
  where id = order_row.id
  returning * into order_row;

  update public.marketplace_listings
  set status = 'sold', closed_reason = 'marketplace_procurement_accepted',
      updated_at = now()
  where id = order_row.listing_id;

  insert into public.audit_events(
    fpc_id, actor_user_id, actor_role, action, target_type, target_id,
    after_data
  ) values (
    order_row.fpc_id, p_actor_user_id, 'fpc_admin',
    'marketplace_procurement_accepted', 'marketplace_order',
    order_row.id::text,
    jsonb_build_object(
      'order', to_jsonb(order_row),
      'procurement_lot_id', lot_row.id,
      'farmer_payment_id', payment_row.id
    )
  );

  return to_jsonb(order_row) ||
    jsonb_build_object(
      'farmer_payment_id', payment_row.id,
      'procurement_lot_id', lot_row.id
    );
end;
$$;

revoke all on function public.marketplace_accept_offer(uuid, uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.marketplace_append_offer(
  uuid, uuid, text, numeric, text
) from public, anon, authenticated;
revoke all on function public.marketplace_record_arrival(
  uuid, uuid, numeric, text, numeric, uuid, jsonb
) from public, anon, authenticated;
revoke all on function public.marketplace_finalize_procurement(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.marketplace_accept_offer(uuid, uuid, uuid, text)
  to service_role;
grant execute on function public.marketplace_append_offer(
  uuid, uuid, text, numeric, text
) to service_role;
grant execute on function public.marketplace_record_arrival(
  uuid, uuid, numeric, text, numeric, uuid, jsonb
) to service_role;
grant execute on function public.marketplace_finalize_procurement(uuid, uuid)
  to service_role;

create or replace view public.fpc_profit_summary
with (security_invoker = true)
as
with acquisition as (
  select payment.fpc_id, sum(payment.final_amount) as amount
  from public.farmer_payment_ledger payment
  where payment.reversal_of is null
    and payment.status in ('verified', 'approved', 'paid')
  group by payment.fpc_id
),
operating_cost as (
  select cost.fpc_id, sum(cost.amount) as amount
  from public.fpc_cost_ledger cost
  group by cost.fpc_id
),
revenue as (
  select sales.fpc_id, sum(sales.total) as amount
  from public.sales_orders sales
  where sales.status in ('invoiced', 'dispatched', 'delivered', 'paid')
  group by sales.fpc_id
)
select
  fpc.id as fpc_id,
  coalesce(acquisition.amount, 0)::numeric(14,2) as acquisition_cost,
  coalesce(operating_cost.amount, 0)::numeric(14,2) as operating_cost,
  coalesce(revenue.amount, 0)::numeric(14,2) as revenue,
  (
    coalesce(revenue.amount, 0)
    - coalesce(acquisition.amount, 0)
    - coalesce(operating_cost.amount, 0)
  )::numeric(14,2) as net_margin
from public.fpcs fpc
left join acquisition on acquisition.fpc_id = fpc.id
left join operating_cost on operating_cost.fpc_id = fpc.id
left join revenue on revenue.fpc_id = fpc.id;

grant select on public.fpc_profit_summary to authenticated;

drop trigger if exists set_marketplace_orders_updated_at
  on public.marketplace_orders;
create trigger set_marketplace_orders_updated_at
before update on public.marketplace_orders
for each row execute function public.set_updated_at();

notify pgrst, 'reload schema';
