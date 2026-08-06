-- Keep paid seed records unavailable to anonymous-auth sessions and cover the
-- foreign keys used by Farmer inventory and FPC payment lookups.

drop policy if exists "seed payment related read"
  on public.fpc_seed_payment_attempts;
create policy "seed payment related read"
on public.fpc_seed_payment_attempts for select to authenticated
using (
  coalesce(
    ((select auth.jwt()) ->> 'is_anonymous')::boolean,
    false
  ) = false
  and (
    farmer_user_id = (select auth.uid())
    or private.can_manage_fpc(fpc_id)
  )
);

drop policy if exists "Farmer reads purchased seed inventory"
  on public.farmer_seed_inventory;
create policy "Farmer reads purchased seed inventory"
on public.farmer_seed_inventory for select to authenticated
using (
  coalesce(
    ((select auth.jwt()) ->> 'is_anonymous')::boolean,
    false
  ) = false
  and (
    farmer_user_id = (select auth.uid())
    or private.can_manage_fpc(fpc_id)
  )
);

drop policy if exists "users manage their FPC push tokens"
  on public.fpc_push_tokens;
create policy "FPC admins manage their push tokens"
on public.fpc_push_tokens for all to authenticated
using (
  coalesce(
    ((select auth.jwt()) ->> 'is_anonymous')::boolean,
    false
  ) = false
  and user_id = (select auth.uid())
  and exists (
    select 1
    from public.fpc_memberships membership
    where membership.user_id = (select auth.uid())
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  )
)
with check (
  coalesce(
    ((select auth.jwt()) ->> 'is_anonymous')::boolean,
    false
  ) = false
  and user_id = (select auth.uid())
  and app_role = 'fpc_admin'
  and exists (
    select 1
    from public.fpc_memberships membership
    where membership.user_id = (select auth.uid())
      and membership.role = 'fpc_admin'
      and membership.status = 'active'
  )
);

create index farmer_seed_inventory_farm_idx
  on public.farmer_seed_inventory(farm_id);
create index farmer_seed_inventory_program_idx
  on public.farmer_seed_inventory(program_id);
create index farmer_seed_inventory_request_idx
  on public.farmer_seed_inventory(seed_request_id);
create index farmer_seed_inventory_batch_idx
  on public.farmer_seed_inventory(seed_batch_id);
create index fpc_seed_payment_attempts_fpc_idx
  on public.fpc_seed_payment_attempts(fpc_id);
create index fpc_seed_payment_attempts_farmer_idx
  on public.fpc_seed_payment_attempts(farmer_user_id);

create unique index fpc_seed_payment_attempts_active_request_idx
  on public.fpc_seed_payment_attempts(seed_request_id)
  where status in ('created', 'signature_verified', 'authorized');

comment on table public.fpc_seed_webhook_events is
  'Service-role-only signed Razorpay webhook receipt ledger; RLS intentionally has no client policy.';
