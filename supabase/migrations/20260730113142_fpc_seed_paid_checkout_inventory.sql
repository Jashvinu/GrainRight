-- Paid, batch-specific FPC seed checkout. Reservations are temporary, stock
-- remains physical until issue, and Farmer seed inventory is created only
-- after delivery acknowledgement.

alter table public.fpc_seed_batches
  add column unit_price_paise bigint
    check (unit_price_paise is null or unit_price_paise > 0);

alter table public.fpc_seed_requests
  add column seed_batch_id uuid
    references public.fpc_seed_batches(id) on delete restrict,
  add column unit_price_paise bigint
    check (unit_price_paise is null or unit_price_paise > 0),
  add column amount_paise bigint
    check (amount_paise is null or amount_paise > 0),
  add column currency text not null default 'INR'
    check (currency = 'INR'),
  add column reservation_expires_at timestamptz,
  add column payment_status text not null default 'not_started'
    check (payment_status in (
      'not_started', 'awaiting_payment', 'order_created', 'captured',
      'signature_verified', 'authorized', 'failed', 'expired',
      'refund_pending', 'refunded'
    )),
  add column paid_at timestamptz,
  add column refunded_at timestamptz,
  add column razorpay_order_id text,
  add column razorpay_payment_id text;

create index fpc_seed_requests_batch_reservation_idx
  on public.fpc_seed_requests(
    seed_batch_id, payment_status, reservation_expires_at
  )
  where seed_batch_id is not null;

create unique index fpc_seed_requests_razorpay_order_idx
  on public.fpc_seed_requests(razorpay_order_id)
  where razorpay_order_id is not null;

create unique index fpc_seed_requests_razorpay_payment_idx
  on public.fpc_seed_requests(razorpay_payment_id)
  where razorpay_payment_id is not null;

create table public.fpc_seed_payment_attempts (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  seed_request_id uuid not null
    references public.fpc_seed_requests(id) on delete cascade,
  farmer_user_id uuid not null references auth.users(id) on delete restrict,
  provider text not null default 'razorpay' check (provider = 'razorpay'),
  environment text not null default 'test' check (environment = 'test'),
  provider_order_id text not null unique,
  provider_payment_id text unique,
  provider_refund_id text unique,
  amount_subunits bigint not null check (amount_subunits > 0),
  currency text not null default 'INR' check (currency = 'INR'),
  checkout_signature text not null default '',
  provider_status text not null default 'created',
  status text not null default 'created'
    check (status in (
      'created', 'signature_verified', 'authorized', 'captured', 'failed',
      'refund_pending', 'refunded'
    )),
  failure_code text not null default '',
  failure_description text not null default '',
  captured_at timestamptz,
  refunded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index fpc_seed_payment_attempts_request_idx
  on public.fpc_seed_payment_attempts(seed_request_id, created_at desc);

create table public.farmer_seed_inventory (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete restrict,
  farmer_user_id uuid not null references auth.users(id) on delete restrict,
  farmer_id text not null,
  farm_id uuid not null references public.farms(id) on delete restrict,
  program_id uuid not null
    references public.fpc_crop_programs(id) on delete restrict,
  seed_request_id uuid not null
    references public.fpc_seed_requests(id) on delete restrict,
  seed_issue_id uuid not null
    references public.fpc_seed_issues(id) on delete restrict,
  seed_batch_id uuid not null
    references public.fpc_seed_batches(id) on delete restrict,
  seed_name text not null,
  batch_code text not null,
  crop text not null,
  variety text not null default '',
  quantity_kg numeric(14,3) not null check (quantity_kg > 0),
  unit_price_paise bigint not null check (unit_price_paise > 0),
  amount_paise bigint not null check (amount_paise > 0),
  currency text not null default 'INR' check (currency = 'INR'),
  status text not null default 'available'
    check (status in ('available', 'used')),
  received_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (seed_issue_id)
);

create index farmer_seed_inventory_farmer_idx
  on public.farmer_seed_inventory(
    farmer_user_id, status, received_at desc
  );

create index farmer_seed_inventory_fpc_idx
  on public.farmer_seed_inventory(fpc_id, status, received_at desc);

create table public.fpc_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android' check (platform = 'android'),
  app_role text not null default 'fpc_admin',
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index fpc_push_tokens_user_active_idx
  on public.fpc_push_tokens(user_id, active, last_seen_at desc);

create table public.fpc_seed_webhook_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null unique,
  event_type text not null,
  environment text not null default 'test' check (environment = 'test'),
  payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz,
  processing_error text not null default '',
  created_at timestamptz not null default now()
);

drop trigger if exists set_fpc_seed_payment_attempts_updated_at
  on public.fpc_seed_payment_attempts;
create trigger set_fpc_seed_payment_attempts_updated_at
before update on public.fpc_seed_payment_attempts
for each row execute function public.set_updated_at();

drop trigger if exists set_farmer_seed_inventory_updated_at
  on public.farmer_seed_inventory;
create trigger set_farmer_seed_inventory_updated_at
before update on public.farmer_seed_inventory
for each row execute function public.set_updated_at();

drop trigger if exists set_fpc_push_tokens_updated_at
  on public.fpc_push_tokens;
create trigger set_fpc_push_tokens_updated_at
before update on public.fpc_push_tokens
for each row execute function public.set_updated_at();

alter table public.fpc_seed_payment_attempts enable row level security;
alter table public.farmer_seed_inventory enable row level security;
alter table public.fpc_push_tokens enable row level security;
alter table public.fpc_seed_webhook_events enable row level security;

create policy "seed payment related read"
on public.fpc_seed_payment_attempts for select to authenticated
using (
  farmer_user_id = (select auth.uid())
  or private.can_manage_fpc(fpc_id)
);

create policy "Farmer reads purchased seed inventory"
on public.farmer_seed_inventory for select to authenticated
using (
  farmer_user_id = (select auth.uid())
  or private.can_manage_fpc(fpc_id)
);

create policy "users manage their FPC push tokens"
on public.fpc_push_tokens for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

grant select on public.fpc_seed_payment_attempts to authenticated;
grant select on public.farmer_seed_inventory to authenticated;
grant select, insert, update, delete on public.fpc_push_tokens to authenticated;
grant select, insert, update, delete on
  public.fpc_seed_payment_attempts,
  public.farmer_seed_inventory,
  public.fpc_push_tokens,
  public.fpc_seed_webhook_events
to service_role;

revoke insert, update, delete on
  public.fpc_seed_payment_attempts,
  public.farmer_seed_inventory
from anon, authenticated;
revoke all on public.fpc_seed_webhook_events from anon, authenticated;

create or replace function private.farm_has_sown_seed(target_farm_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select
      (farm.sowing_date is not null and farm.sowing_date <= current_date)
      or lower(trim(coalesce(farm.current_status_stage, ''))) in (
        'sowing', 'germination', 'vegetative', 'flowering',
        'grain filling', 'grain_filling', 'maturity'
      )
      or lower(trim(coalesce(farm.current_status, ''))) in (
        'seed sown', 'sown', 'growing'
      )
    from public.farms farm
    where farm.id = target_farm_id
  ), false);
$$;

create or replace function private.seed_batch_reserved_quantity(
  target_batch_id uuid,
  excluded_request_id uuid default null
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(request.requested_quantity_kg), 0)
  from public.fpc_seed_requests request
  where request.seed_batch_id = target_batch_id
    and (excluded_request_id is null or request.id <> excluded_request_id)
    and request.status in ('approved', 'seed_issued', 'delivered')
    and (
      request.payment_status = 'captured'
      or (
        request.payment_status in (
          'awaiting_payment', 'order_created', 'failed', 'refund_pending'
        )
        and request.reservation_expires_at > now()
      )
    )
    and not exists (
      select 1
      from public.fpc_seed_issues issue
      where issue.enrollment_id = request.enrollment_id
        and issue.status <> 'cancelled'
    );
$$;

revoke all on function private.farm_has_sown_seed(uuid)
  from public, anon, authenticated;
revoke all on function private.seed_batch_reserved_quantity(uuid,uuid)
  from public, anon, authenticated;

create or replace function private.validate_new_seed_purchase_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.seed_batch_id is null
    or new.unit_price_paise is null
    or new.amount_paise is null then
    raise exception 'A priced certified seed batch is required';
  end if;
  if private.farm_has_sown_seed(new.farm_id) then
    raise exception 'This farm already has seed sown';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_new_seed_purchase_request
  on public.fpc_seed_requests;
create trigger validate_new_seed_purchase_request
before insert on public.fpc_seed_requests
for each row execute function private.validate_new_seed_purchase_request();

create or replace function private.request_seed_purchase(
  target_farm_id uuid,
  target_seed_batch_id uuid,
  requested_quantity_kg numeric,
  farmer_note text,
  preferred_delivery_at timestamptz,
  request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  farm_row public.farms;
  batch_row public.fpc_seed_batches;
  program_row public.fpc_crop_programs;
  link_row public.fpc_farmer_links;
  saved public.fpc_seed_requests;
  existing public.fpc_seed_requests;
  amount_value bigint;
  new_seed_request_id uuid := gen_random_uuid();
begin
  if actor_id is null then raise exception 'Login required'; end if;
  if exists (
    select 1 from auth.users user_account
    where user_account.id = actor_id and user_account.is_anonymous
  ) then
    raise exception 'A permanent Farmer account is required';
  end if;
  if target_farm_id is null or target_seed_batch_id is null then
    raise exception 'Farm and certified seed batch are required';
  end if;
  if requested_quantity_kg is null or requested_quantity_kg <= 0 then
    raise exception 'Requested seed quantity must be greater than zero';
  end if;
  if request_id is null then raise exception 'Request ID is required'; end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'farmer-seed-purchase:' || actor_id::text || ':' ||
      target_farm_id::text || ':' || target_seed_batch_id::text,
      0
    )
  );

  select * into existing
  from public.fpc_seed_requests request
  where request.farmer_user_id = actor_id
    and request.client_request_id = request_id;
  if existing.id is not null then return to_jsonb(existing); end if;

  select * into farm_row
  from public.farms farm
  where farm.id = target_farm_id
    and private.farmer_can_access_farm(farm.id, actor_id);
  if farm_row.id is null then raise exception 'Farmer farm not found'; end if;
  if private.farm_has_sown_seed(farm_row.id) then
    raise exception 'This farm already has seed sown';
  end if;

  select batch.* into batch_row
  from public.fpc_seed_batches batch
  join public.fpcs fpc
    on fpc.id = batch.fpc_id and fpc.status = 'active'
  where batch.id = target_seed_batch_id
    and batch.status = 'active'
    and batch.available_quantity_kg > 0
    and batch.unit_price_paise is not null
    and (batch.expires_on is null or batch.expires_on >= current_date);
  if batch_row.id is null then
    raise exception 'Priced active certified seed batch not found';
  end if;

  select * into program_row
  from public.fpc_crop_programs program
  where program.id = batch_row.program_id
    and program.fpc_id = batch_row.fpc_id
    and program.status = 'active';
  if program_row.id is null then raise exception 'Active crop program not found'; end if;
  if private.fpc_seed_crop_key(farm_row.crop) <>
      private.fpc_seed_crop_key(program_row.crop) then
    raise exception 'Seed crop does not match the selected farm crop';
  end if;
  if requested_quantity_kg > batch_row.available_quantity_kg then
    raise exception 'Requested quantity exceeds physical seed stock';
  end if;

  link_row := private.ensure_seed_request_farmer_link(
    batch_row.fpc_id,
    farm_row.id,
    program_row.crop,
    actor_id
  );

  if exists (
    select 1
    from public.fpc_seed_requests request
    where request.farm_id = farm_row.id
      and request.status in (
        'submitted', 'approved', 'seed_issued', 'delivered'
      )
  ) then
    raise exception 'An active seed request already exists for this farm';
  end if;

  amount_value := round(
    requested_quantity_kg * batch_row.unit_price_paise
  )::bigint;
  if amount_value <= 0 then raise exception 'Seed order amount is invalid'; end if;

  insert into public.fpc_seed_requests(
    id, fpc_id, program_id, seed_batch_id, farmer_link_id, farmer_user_id,
    farmer_id, farm_id, requested_quantity_kg, preferred_delivery_at,
    farmer_note, unit_price_paise, amount_paise, currency, client_request_id
  ) values (
    new_seed_request_id, batch_row.fpc_id, program_row.id, batch_row.id,
    link_row.id, actor_id,
    link_row.farmer_id, farm_row.id, requested_quantity_kg,
    preferred_delivery_at, coalesce(farmer_note, ''),
    batch_row.unit_price_paise, amount_value, 'INR', request_id
  );

  select * into saved
  from public.fpc_seed_requests request
  where request.id = new_seed_request_id;

  insert into public.fpc_notifications(
    fpc_id, recipient_user_id, event_key, title, body, data
  )
  select
    saved.fpc_id,
    membership.user_id,
    'farmer_seed_purchase_request',
    'New Farmer seed purchase request',
    coalesce(nullif(link_row.farmer_name, ''), link_row.farmer_id) ||
      ' requested ' ||
      trim(to_char(saved.requested_quantity_kg, 'FM999999990.000')) ||
      ' kg from batch ' || batch_row.batch_code || '.',
    jsonb_build_object(
      'seed_request_id', saved.id,
      'seed_batch_id', saved.seed_batch_id,
      'program_id', saved.program_id,
      'farm_id', saved.farm_id,
      'farmer_id', saved.farmer_id,
      'amount_paise', saved.amount_paise
    )
  from public.fpc_memberships membership
  where membership.fpc_id = saved.fpc_id
    and membership.role = 'fpc_admin'
    and membership.status = 'active';

  return to_jsonb(saved) || jsonb_build_object(
    'program', to_jsonb(program_row),
    'seed_batch', to_jsonb(batch_row),
    'fpc', (
      select jsonb_build_object('id', fpc.id, 'name', fpc.name)
      from public.fpcs fpc where fpc.id = saved.fpc_id
    )
  );
end;
$$;

create or replace function public.farmer_request_seed_purchase(
  p_farm_id uuid,
  p_seed_batch_id uuid,
  p_quantity_kg numeric,
  p_farmer_note text default '',
  p_preferred_delivery_at timestamptz default null,
  p_client_request_id uuid default gen_random_uuid()
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.request_seed_purchase(
    p_farm_id,
    p_seed_batch_id,
    p_quantity_kg,
    p_farmer_note,
    p_preferred_delivery_at,
    p_client_request_id
  );
$$;

create or replace function public.farmer_seed_store_for_farm(p_farm_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  farm_row public.farms;
  base_snapshot jsonb;
  buying_eligible boolean;
begin
  if actor_id is null then raise exception 'Login required'; end if;
  select * into farm_row
  from public.farms farm
  where farm.id = p_farm_id
    and private.farmer_can_access_farm(farm.id, actor_id);
  if farm_row.id is null then raise exception 'Farmer farm not found'; end if;

  base_snapshot := public.farmer_crop_program_for_farm(p_farm_id);
  buying_eligible := not private.farm_has_sown_seed(farm_row.id);

  return base_snapshot || jsonb_build_object(
    'seed_buying_eligible', buying_eligible,
    'available_batches', case
      when not buying_eligible then '[]'::jsonb
      else coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', batch.id,
            'fpc_id', batch.fpc_id,
            'program_id', batch.program_id,
            'batch_code', batch.batch_code,
            'seed_name', batch.seed_name,
            'crop', batch.crop,
            'variety', batch.variety,
            'supplier_name', batch.supplier_name,
            'certification_number', batch.certification_number,
            'expires_on', batch.expires_on,
            'unit_price_paise', batch.unit_price_paise,
            'sellable_quantity_kg',
              greatest(
                batch.available_quantity_kg -
                  private.seed_batch_reserved_quantity(batch.id),
                0
              ),
            'program_name', program.name,
            'fpc_name', fpc.name,
            'request_allowed',
              private.fpc_seed_crop_key(batch.crop) =
                private.fpc_seed_crop_key(farm_row.crop)
          )
          order by batch.expires_on nulls last, batch.created_at desc
        )
        from public.fpc_seed_batches batch
        join public.fpc_crop_programs program
          on program.id = batch.program_id
         and program.status = 'active'
        join public.fpcs fpc
          on fpc.id = batch.fpc_id
         and fpc.status = 'active'
        where batch.status = 'active'
          and batch.unit_price_paise is not null
          and batch.available_quantity_kg >
            private.seed_batch_reserved_quantity(batch.id)
          and (batch.expires_on is null or batch.expires_on >= current_date)
      ), '[]'::jsonb)
    end
  );
end;
$$;

create or replace function private.execute_paid_seed_request_operation(
  operation_name text,
  payload jsonb,
  request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target_fpc_id uuid;
  existing_response jsonb;
  request_row public.fpc_seed_requests;
  batch_row public.fpc_seed_batches;
  program_row public.fpc_crop_programs;
  saved public.fpc_seed_requests;
  enrollment_row public.fpc_program_enrollments;
  reserved_quantity numeric;
  result jsonb;
  new_seed_batch_id uuid := gen_random_uuid();
begin
  if actor_id is null then raise exception 'Login required'; end if;
  select membership.fpc_id into target_fpc_id
  from public.fpc_memberships membership
  join public.fpcs fpc
    on fpc.id = membership.fpc_id and fpc.status = 'active'
  where membership.user_id = actor_id
    and membership.role = 'fpc_admin'
    and membership.status = 'active'
  limit 1;
  if target_fpc_id is null then
    raise exception 'Active FPC Admin membership required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'paid-seed-operation:' || target_fpc_id::text || ':' ||
      request_id::text,
      0
    )
  );

  select operation_request.response into existing_response
  from private.fpc_operation_requests operation_request
  where operation_request.fpc_id = target_fpc_id
    and operation_request.client_request_id = request_id;
  if existing_response is not null then return existing_response; end if;

  if operation_name = 'register_seed_batch' then
    if coalesce((payload->>'unit_price_paise')::bigint, 0) <= 0 then
      raise exception 'Seed batch price must be greater than zero';
    end if;
    if coalesce((payload->>'received_quantity_kg')::numeric, 0) <= 0 then
      raise exception 'Received seed quantity must be greater than zero';
    end if;
    if nullif(trim(payload->>'batch_code'), '') is null then
      raise exception 'Seed batch code is required';
    end if;
    select * into program_row
    from public.fpc_crop_programs program
    where program.id = (payload->>'program_id')::uuid
      and program.fpc_id = target_fpc_id
      and program.status = 'active';
    if program_row.id is null then raise exception 'Active crop program not found'; end if;

    perform set_config('app.fpc_operation', '1', true);
    insert into public.fpc_seed_batches(
      id, fpc_id, program_id, batch_code, seed_name, crop, variety,
      supplier_name, certification_number, received_quantity_kg,
      available_quantity_kg, unit_price_paise, manufactured_on, expires_on,
      evidence, created_by
    ) values (
      new_seed_batch_id, target_fpc_id, program_row.id,
      trim(payload->>'batch_code'),
      coalesce(nullif(trim(payload->>'seed_name'), ''), program_row.crop || ' seed'),
      program_row.crop, program_row.variety,
      coalesce(payload->>'supplier_name', ''),
      coalesce(payload->>'certification_number', ''),
      (payload->>'received_quantity_kg')::numeric,
      (payload->>'received_quantity_kg')::numeric,
      (payload->>'unit_price_paise')::bigint,
      nullif(payload->>'manufactured_on', '')::date,
      nullif(payload->>'expires_on', '')::date,
      coalesce(payload->'evidence', '{}'::jsonb),
      actor_id
    );
    select * into batch_row
    from public.fpc_seed_batches batch
    where batch.id = new_seed_batch_id;
    result := to_jsonb(batch_row);
    perform private.record_fpc_audit(
      target_fpc_id, operation_name, 'seed_batch', batch_row.id::text,
      '{}'::jsonb, result, request_id
    );
    insert into private.fpc_operation_requests(
      fpc_id, client_request_id, operation, response
    ) values (target_fpc_id, request_id, operation_name, result);
    return result;
  end if;

  if operation_name = 'price_seed_batch' then
    if coalesce((payload->>'unit_price_paise')::bigint, 0) <= 0 then
      raise exception 'Seed batch price must be greater than zero';
    end if;
    select * into batch_row
    from public.fpc_seed_batches batch
    where batch.id = (payload->>'seed_batch_id')::uuid
      and batch.fpc_id = target_fpc_id
    for update;
    if batch_row.id is null then raise exception 'Seed batch not found'; end if;

    perform set_config('app.fpc_operation', '1', true);
    update public.fpc_seed_batches
    set unit_price_paise = (payload->>'unit_price_paise')::bigint,
        updated_at = now()
    where id = batch_row.id
    returning * into batch_row;
    result := to_jsonb(batch_row);

    perform private.record_fpc_audit(
      target_fpc_id, operation_name, 'seed_batch', batch_row.id::text,
      '{}'::jsonb, result, request_id
    );
    insert into private.fpc_operation_requests(
      fpc_id, client_request_id, operation, response
    ) values (target_fpc_id, request_id, operation_name, result);
    return result;
  end if;

  select * into request_row
  from public.fpc_seed_requests request
  where request.id = (payload->>'seed_request_id')::uuid
    and request.fpc_id = target_fpc_id
  for update;
  if request_row.id is null then raise exception 'Seed request not found'; end if;
  if request_row.seed_batch_id is null then
    raise exception 'Seed request is not linked to a priced batch';
  end if;
  if request_row.status <> 'submitted' then
    raise exception 'Only a submitted seed request can be reviewed';
  end if;
  if request_row.payment_status = 'captured' then
    raise exception 'Paid seed requests must be refunded, not declined';
  end if;

  if operation_name = 'decline_seed_request' then
    update public.fpc_seed_requests
    set reservation_expires_at = null,
        payment_status = case
          when payment_status = 'not_started' then payment_status
          else 'expired'
        end,
        updated_at = now()
    where id = request_row.id;
    result := private.execute_seed_request_operation(
      operation_name, payload, request_id
    );
    if request_row.enrollment_id is not null then
      update public.fpc_program_enrollments
      set status = 'cancelled', updated_at = now()
      where id = request_row.enrollment_id
        and status = 'pending_farmer_acceptance';
    end if;
    return result;
  end if;
  if operation_name <> 'approve_seed_request' then
    raise exception 'Unsupported paid seed operation: %', operation_name;
  end if;
  if private.farm_has_sown_seed(request_row.farm_id) then
    raise exception 'This farm already has seed sown';
  end if;

  select * into batch_row
  from public.fpc_seed_batches batch
  where batch.id = request_row.seed_batch_id
    and batch.fpc_id = target_fpc_id
    and batch.program_id = request_row.program_id
    and batch.status = 'active'
    and batch.unit_price_paise is not null
  for update;
  if batch_row.id is null then
    raise exception 'Active priced certified seed batch not found';
  end if;
  if batch_row.expires_on is not null and batch_row.expires_on < current_date then
    raise exception 'Seed batch is expired';
  end if;

  reserved_quantity := private.seed_batch_reserved_quantity(
    batch_row.id,
    request_row.id
  );
  if batch_row.available_quantity_kg - reserved_quantity <
      request_row.requested_quantity_kg then
    raise exception 'Insufficient unreserved seed quantity';
  end if;

  update public.fpc_seed_requests
  set unit_price_paise = batch_row.unit_price_paise,
      amount_paise = round(
        requested_quantity_kg * batch_row.unit_price_paise
      )::bigint,
      payment_status = 'awaiting_payment',
      reservation_expires_at = now() + interval '24 hours',
      razorpay_order_id = null,
      razorpay_payment_id = null,
      updated_at = now()
  where id = request_row.id;

  if request_row.enrollment_id is null then
    return private.execute_seed_request_operation(
      operation_name, payload, request_id
    );
  end if;

  select * into enrollment_row
  from public.fpc_program_enrollments enrollment
  where enrollment.id = request_row.enrollment_id
    and enrollment.fpc_id = target_fpc_id
  for update;
  if enrollment_row.id is null then
    raise exception 'Seed request enrollment not found';
  end if;

  update public.fpc_seed_requests
  set status = 'approved',
      response_note = coalesce(payload->>'response_note', ''),
      reviewed_by = actor_id,
      reviewed_at = now(),
      updated_at = now()
  where id = request_row.id;

  select * into saved
  from public.fpc_seed_requests request
  where request.id = request_row.id;

  result := to_jsonb(saved) ||
    jsonb_build_object('enrollment', to_jsonb(enrollment_row));
  perform private.record_fpc_audit(
    target_fpc_id, operation_name, 'seed_request', saved.id::text,
    to_jsonb(request_row), result, request_id
  );
  insert into private.fpc_operation_requests(
    fpc_id, client_request_id, operation, response
  ) values (target_fpc_id, request_id, operation_name, result);
  return result;
end;
$$;

create or replace function public.fpc_execute_operation(
  operation_name text,
  payload jsonb default '{}'::jsonb,
  client_request_id uuid default gen_random_uuid()
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select case
    when operation_name in (
      'approve_seed_request', 'decline_seed_request', 'register_seed_batch',
      'price_seed_batch'
    ) then private.execute_paid_seed_request_operation(
      operation_name,
      payload,
      client_request_id
    )
    when operation_name in (
      'create_crop_program', 'activate_crop_program',
      'enroll_farmer_program', 'issue_program_seed',
      'review_program_compliance', 'release_program_enrollment'
    ) then private.execute_crop_program_operation(
      operation_name,
      payload,
      client_request_id
    )
    else private.execute_fpc_operation(
      operation_name,
      payload,
      client_request_id
    )
  end;
$$;

create or replace function private.enforce_paid_seed_issue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_row public.fpc_seed_requests;
begin
  select request.* into request_row
  from public.fpc_seed_requests request
  where request.enrollment_id = new.enrollment_id
  for update;
  if request_row.id is null then
    raise exception 'Seed issue requires an approved Farmer seed purchase';
  end if;
  if request_row.payment_status <> 'captured' then
    raise exception 'Seed payment must be captured before issue';
  end if;
  if request_row.seed_batch_id <> new.seed_batch_id then
    raise exception 'Issued batch does not match the paid seed order';
  end if;
  if request_row.requested_quantity_kg <> new.quantity_kg then
    raise exception 'Issued quantity must match the paid seed order';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_paid_seed_issue on public.fpc_seed_issues;
create trigger enforce_paid_seed_issue
before insert on public.fpc_seed_issues
for each row execute function private.enforce_paid_seed_issue();

create or replace function private.create_farmer_seed_inventory()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  enrollment_row public.fpc_program_enrollments;
  request_row public.fpc_seed_requests;
  batch_row public.fpc_seed_batches;
begin
  if new.status <> 'acknowledged'
    or (tg_op = 'UPDATE' and old.status = 'acknowledged') then
    return new;
  end if;

  select * into enrollment_row
  from public.fpc_program_enrollments enrollment
  where enrollment.id = new.enrollment_id;
  select * into request_row
  from public.fpc_seed_requests request
  where request.enrollment_id = new.enrollment_id;
  select * into batch_row
  from public.fpc_seed_batches batch
  where batch.id = new.seed_batch_id;

  if request_row.id is null or request_row.payment_status <> 'captured' then
    raise exception 'Paid seed order not found for inventory';
  end if;

  insert into public.farmer_seed_inventory(
    fpc_id, farmer_user_id, farmer_id, farm_id, program_id,
    seed_request_id, seed_issue_id, seed_batch_id, seed_name, batch_code,
    crop, variety, quantity_kg, unit_price_paise, amount_paise,
    currency, received_at
  ) values (
    new.fpc_id, enrollment_row.farmer_user_id, enrollment_row.farmer_id,
    enrollment_row.farm_id, enrollment_row.program_id, request_row.id,
    new.id, new.seed_batch_id, batch_row.seed_name, batch_row.batch_code,
    batch_row.crop, batch_row.variety, new.quantity_kg,
    request_row.unit_price_paise, request_row.amount_paise,
    request_row.currency, coalesce(new.acknowledged_at, now())
  )
  on conflict (seed_issue_id) do nothing;
  return new;
end;
$$;

drop trigger if exists create_farmer_seed_inventory
  on public.fpc_seed_issues;
create trigger create_farmer_seed_inventory
after insert or update of status on public.fpc_seed_issues
for each row execute function private.create_farmer_seed_inventory();

create or replace function private.mark_farmer_seed_inventory_used()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.farm_has_sown_seed(new.id) then
    update public.farmer_seed_inventory inventory
    set status = 'used',
        used_at = coalesce(inventory.used_at, now()),
        updated_at = now()
    where inventory.farm_id = new.id
      and inventory.status = 'available';
  end if;
  return new;
end;
$$;

drop trigger if exists mark_farmer_seed_inventory_used on public.farms;
create trigger mark_farmer_seed_inventory_used
after insert or update of sowing_date, current_status_stage, current_status
on public.farms
for each row execute function private.mark_farmer_seed_inventory_used();

create or replace function public.expire_fpc_seed_reservations()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_count integer;
begin
  with expired as (
    update public.fpc_seed_requests request
    set status = 'submitted',
        payment_status = 'expired',
        reservation_expires_at = null,
        razorpay_order_id = null,
        updated_at = now()
    where request.status = 'approved'
      and request.payment_status in (
        'awaiting_payment', 'order_created', 'failed'
      )
      and request.reservation_expires_at <= now()
    returning request.*
  ),
  notifications as (
    insert into public.farmer_notifications(
      recipient_user_id, farmer_id, farm_id, type, title, message,
      dedupe_key, action_route, payload
    )
    select
      expired.farmer_user_id,
      expired.farmer_id,
      expired.farm_id,
      'fpc_seed_reservation_expired',
      'Seed reservation expired',
      'Your 24-hour seed reservation expired. The FPC must approve it again.',
      'fpc-seed-reservation-expired:' || expired.id::text || ':' ||
        extract(epoch from now())::bigint::text,
      '/farmer',
      jsonb_build_object('seed_request_id', expired.id)
    from expired
    returning 1
  )
  select count(*) into expired_count from expired;
  return expired_count;
end;
$$;

do $cron$
begin
  if exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) and not exists (
    select 1 from cron.job
    where jobname = 'expire-fpc-seed-reservations'
  ) then
    perform cron.schedule(
      'expire-fpc-seed-reservations',
      '*/15 * * * *',
      'select public.expire_fpc_seed_reservations()'
    );
  end if;
end;
$cron$;

create or replace function public.finalize_fpc_seed_refund(
  p_seed_request_id uuid,
  p_provider_payment_id text,
  p_provider_refund_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_row public.fpc_seed_requests;
  issue_row public.fpc_seed_issues;
  batch_row public.fpc_seed_batches;
  attempt_row public.fpc_seed_payment_attempts;
begin
  if (select auth.role()) <> 'service_role' then
    raise exception 'Service role required';
  end if;
  select * into request_row
  from public.fpc_seed_requests request
  where request.id = p_seed_request_id
  for update;
  if request_row.id is null then raise exception 'Seed request not found'; end if;
  if request_row.payment_status = 'refunded' then return to_jsonb(request_row); end if;
  if request_row.payment_status not in ('captured', 'refund_pending') then
    raise exception 'Captured seed payment not found';
  end if;

  select issue.* into issue_row
  from public.fpc_seed_issues issue
  where issue.enrollment_id = request_row.enrollment_id
    and issue.status <> 'cancelled'
  order by issue.created_at desc
  limit 1
  for update;
  if issue_row.status in ('delivered', 'acknowledged') then
    raise exception 'Delivered seed cannot be refunded';
  end if;

  if issue_row.id is not null then
    select * into batch_row
    from public.fpc_seed_batches batch
    where batch.id = issue_row.seed_batch_id
    for update;
    update public.fpc_seed_issues
    set status = 'cancelled', updated_at = now()
    where id = issue_row.id;
    update public.fpc_seed_batches
    set available_quantity_kg = available_quantity_kg + issue_row.quantity_kg,
        status = case when status = 'depleted' then 'active' else status end,
        updated_at = now()
    where id = issue_row.seed_batch_id;
    insert into public.stock_ledger(
      fpc_id, movement_type, item_type, item_name, quantity_kg,
      reference_type, reference_id, reason, client_request_id
    ) values (
      request_row.fpc_id, 'return', 'seed',
      batch_row.seed_name || ' / ' || batch_row.batch_code,
      issue_row.quantity_kg, 'seed_issue', issue_row.id::text,
      'Seed returned after full pre-delivery refund', gen_random_uuid()
    );
    update public.fpc_program_enrollments
    set status = 'accepted', updated_at = now()
    where id = request_row.enrollment_id
      and status = 'seed_issued';
  end if;

  select * into attempt_row
  from public.fpc_seed_payment_attempts attempt
  where attempt.seed_request_id = request_row.id
    and (
      attempt.provider_payment_id = p_provider_payment_id
      or p_provider_payment_id is null
    )
  order by attempt.created_at desc
  limit 1
  for update;
  if attempt_row.id is null then raise exception 'Seed payment attempt not found'; end if;

  update public.fpc_seed_payment_attempts
  set status = 'refunded',
      provider_status = 'refunded',
      provider_refund_id = nullif(p_provider_refund_id, ''),
      refunded_at = coalesce(refunded_at, now()),
      updated_at = now()
  where id = attempt_row.id;
  update public.fpc_seed_requests
  set status = 'cancelled',
      payment_status = 'refunded',
      refunded_at = coalesce(refunded_at, now()),
      reservation_expires_at = null,
      updated_at = now()
  where id = request_row.id;

  select * into request_row
  from public.fpc_seed_requests request
  where request.id = request_row.id;

  insert into public.farmer_notifications(
    recipient_user_id, farmer_id, farm_id, type, title, message,
    dedupe_key, action_route, payload
  ) values (
    request_row.farmer_user_id, request_row.farmer_id, request_row.farm_id,
    'fpc_seed_payment_refunded', 'Seed payment refunded',
    'Your full seed payment refund was confirmed.',
    'fpc-seed-refunded:' || request_row.id::text,
    '/farmer', jsonb_build_object('seed_request_id', request_row.id)
  )
  on conflict (recipient_user_id, dedupe_key)
    where recipient_user_id is not null and dedupe_key is not null
  do nothing;

  return to_jsonb(request_row);
end;
$$;

alter table public.notification_outbox
  drop constraint if exists notification_outbox_channel_check;
alter table public.notification_outbox
  add constraint notification_outbox_channel_check
  check (channel in ('in_app', 'sms', 'whatsapp', 'push'));

create unique index if not exists notification_outbox_notification_channel_idx
  on public.notification_outbox(notification_id, channel)
  where notification_id is not null;

create or replace function private.enqueue_fpc_push_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.recipient_user_id is not null then
    insert into public.notification_outbox(
      fpc_id, notification_id, channel, recipient, status
    ) values (
      new.fpc_id, new.id, 'push', new.recipient_user_id::text, 'pending'
    )
    on conflict (notification_id, channel)
      where notification_id is not null
    do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists enqueue_fpc_push_notification
  on public.fpc_notifications;
create trigger enqueue_fpc_push_notification
after insert on public.fpc_notifications
for each row execute function private.enqueue_fpc_push_notification();

do $realtime$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fpc_notifications'
  ) then
    alter publication supabase_realtime add table public.fpc_notifications;
  end if;
end;
$realtime$;

revoke all on function private.validate_new_seed_purchase_request()
  from public, anon, authenticated;
revoke all on function private.request_seed_purchase(
  uuid,uuid,numeric,text,timestamptz,uuid
) from public, anon;
revoke all on function private.execute_paid_seed_request_operation(
  text,jsonb,uuid
) from public, anon, authenticated;
revoke all on function private.enforce_paid_seed_issue()
  from public, anon, authenticated;
revoke all on function private.create_farmer_seed_inventory()
  from public, anon, authenticated;
revoke all on function private.mark_farmer_seed_inventory_used()
  from public, anon, authenticated;
revoke all on function private.enqueue_fpc_push_notification()
  from public, anon, authenticated;
revoke all on function public.farmer_request_seed_purchase(
  uuid,uuid,numeric,text,timestamptz,uuid
) from public, anon;
revoke all on function public.farmer_seed_store_for_farm(uuid)
  from public, anon;
revoke all on function public.expire_fpc_seed_reservations()
  from public, anon, authenticated;
revoke all on function public.finalize_fpc_seed_refund(uuid,text,text)
  from public, anon, authenticated;

grant execute on function private.request_seed_purchase(
  uuid,uuid,numeric,text,timestamptz,uuid
) to authenticated;
grant execute on function public.farmer_request_seed_purchase(
  uuid,uuid,numeric,text,timestamptz,uuid
) to authenticated;
grant execute on function public.farmer_seed_store_for_farm(uuid)
  to authenticated;
grant execute on function public.fpc_execute_operation(text,jsonb,uuid)
  to authenticated;
grant execute on function public.finalize_fpc_seed_refund(uuid,text,text)
  to service_role;

comment on column public.fpc_seed_batches.unit_price_paise is
  'All-inclusive certified seed selling price in integer paise per kilogram.';
comment on table public.fpc_seed_payment_attempts is
  'Server-created Razorpay Test Mode orders and verified payment outcomes for FPC seed purchases.';
comment on table public.farmer_seed_inventory is
  'Farmer-owned seed history created exactly once after paid delivery acknowledgement; never marketplace sellable.';
comment on function public.farmer_seed_store_for_farm(uuid) is
  'Returns the Farmer seed lifecycle plus priced batch cards and the authoritative sown-farm buying gate.';
