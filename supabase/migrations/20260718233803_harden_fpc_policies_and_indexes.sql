-- Consolidate hot-path policies and prevent Field Officers from editing an
-- assignment's scope while still allowing version-checked status progress.
drop policy if exists "members read own organization memberships" on public.fpc_memberships;
create policy "members read own organization memberships"
on public.fpc_memberships for select to authenticated
using (
  private.is_platform_admin()
  or user_id = (select auth.uid())
  or private.can_manage_fpc(fpc_id)
);

drop policy if exists "field users read assignments" on public.field_assignments;
drop policy if exists "field users update assigned work" on public.field_assignments;
drop policy if exists "fpc admins manage assignments" on public.field_assignments;
create policy "authorized users read assignments"
on public.field_assignments for select to authenticated
using (
  private.is_platform_admin()
  or private.can_manage_fpc(fpc_id)
  or officer_user_id = (select auth.uid())
);
create policy "fpc admins create assignments"
on public.field_assignments for insert to authenticated
with check (private.can_manage_fpc(fpc_id));
create policy "authorized users update assignments"
on public.field_assignments for update to authenticated
using (private.can_manage_fpc(fpc_id) or officer_user_id = (select auth.uid()))
with check (
  private.can_manage_fpc(fpc_id)
  or (
    officer_user_id = (select auth.uid())
    and fpc_id = private.active_fpc_id()
  )
);
create policy "fpc admins delete assignments"
on public.field_assignments for delete to authenticated
using (private.can_manage_fpc(fpc_id));

create or replace function private.guard_field_assignment_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.can_manage_fpc(old.fpc_id) then
    return new;
  end if;
  if old.officer_user_id <> (select auth.uid()) then
    raise exception 'Assigned Field Officer access required';
  end if;
  if (to_jsonb(new) - 'status' - 'server_version' - 'updated_at')
      is distinct from
     (to_jsonb(old) - 'status' - 'server_version' - 'updated_at') then
    raise exception 'Field Officers can update only assignment status';
  end if;
  if not (
    (old.status = 'assigned' and new.status = 'in_progress')
    or (old.status = 'in_progress' and new.status = 'completed')
  ) then
    raise exception 'Invalid Field Officer assignment transition';
  end if;
  if new.server_version <> old.server_version + 1 then
    raise exception 'Assignment version conflict';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists guard_field_assignment_update on public.field_assignments;
create trigger guard_field_assignment_update
before update on public.field_assignments
for each row execute function private.guard_field_assignment_update();
revoke all on function private.guard_field_assignment_update() from public, anon, authenticated;

drop policy if exists "admins or recipients read notifications" on public.fpc_notifications;
drop policy if exists "notification recipients read" on public.fpc_notifications;
drop policy if exists "recipients update notifications" on public.fpc_notifications;
drop policy if exists "notification recipients mark read" on public.fpc_notifications;
create policy "authorized users read notifications"
on public.fpc_notifications for select to authenticated
using (
  private.is_platform_admin()
  or recipient_user_id = (select auth.uid())
  or (recipient_user_id is null and private.can_access_fpc(fpc_id))
);
create policy "authorized users mark notifications read"
on public.fpc_notifications for update to authenticated
using (
  recipient_user_id = (select auth.uid())
  or private.can_manage_fpc(fpc_id)
)
with check (
  recipient_user_id = (select auth.uid())
  or private.can_manage_fpc(fpc_id)
);

-- Cover the operational foreign keys used by tenant filters, reversals and
-- chronological workflows. These indexes also keep RLS helper joins bounded.
create index if not exists farmer_payment_reversal_idx on public.farmer_payment_ledger(reversal_of) where reversal_of is not null;
create index if not exists farmer_payment_supersedes_idx on public.farmer_payment_ledger(supersedes) where supersedes is not null;
create index if not exists farmer_payment_verified_by_idx on public.farmer_payment_ledger(verified_by) where verified_by is not null;
create index if not exists field_assignments_created_by_idx on public.field_assignments(created_by) where created_by is not null;
create index if not exists fpc_farmer_links_linked_by_idx on public.fpc_farmer_links(linked_by) where linked_by is not null;
create index if not exists fpc_memberships_created_by_idx on public.fpc_memberships(created_by) where created_by is not null;
create index if not exists fpc_notifications_fpc_idx on public.fpc_notifications(fpc_id, created_at desc);
create index if not exists fpc_notifications_recipient_idx on public.fpc_notifications(recipient_user_id, created_at desc) where recipient_user_id is not null;
create index if not exists fpc_report_exports_generated_by_idx on public.fpc_report_exports(generated_by) where generated_by is not null;
create index if not exists procurement_lots_receipt_idx on public.procurement_lots(receipt_id) where receipt_id is not null;
create index if not exists procurement_schedules_center_idx on public.procurement_schedules(collection_center_id);
create index if not exists procurement_schedules_plan_idx on public.procurement_schedules(harvest_plan_id);
create index if not exists quality_certificates_approved_by_idx on public.quality_certificates(approved_by) where approved_by is not null;
create index if not exists sales_credit_notes_issued_by_idx on public.sales_credit_notes(issued_by) where issued_by is not null;
create index if not exists sales_order_items_fpc_idx on public.sales_order_items(fpc_id);
create index if not exists sales_payment_order_idx on public.sales_payment_ledger(sales_order_id, recorded_at desc);
create index if not exists sales_payment_reversal_idx on public.sales_payment_ledger(reversal_of) where reversal_of is not null;
create index if not exists sales_payment_recorded_by_idx on public.sales_payment_ledger(recorded_by) where recorded_by is not null;
create index if not exists stock_ledger_location_idx on public.stock_ledger(location_id) where location_id is not null;
create index if not exists stock_ledger_lot_idx on public.stock_ledger(lot_id) where lot_id is not null;
create index if not exists stock_ledger_packaging_idx on public.stock_ledger(packaging_batch_id) where packaging_batch_id is not null;
create index if not exists stock_ledger_posted_by_idx on public.stock_ledger(posted_by) where posted_by is not null;
create index if not exists stock_ledger_reversal_idx on public.stock_ledger(reversal_of) where reversal_of is not null;
create index if not exists stock_ledger_warehouse_idx on public.stock_ledger(warehouse_id) where warehouse_id is not null;
create index if not exists stock_reservations_order_idx on public.stock_reservations(sales_order_id, status);
create index if not exists stock_reservations_created_by_idx on public.stock_reservations(created_by) where created_by is not null;
