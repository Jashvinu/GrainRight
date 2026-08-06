-- Farmer-visible delivery and payment timeline.
--
-- This keeps Field Officer/FPC writes on the existing operational tables and
-- exposes a read-only, RLS-filtered timeline for Farmer and FPC logins.

drop view if exists public.farmer_delivery_timeline;

drop policy if exists "farmers read own procurement lots"
  on public.procurement_lots;
create policy "farmers read own procurement lots"
on public.procurement_lots for select to authenticated
using (
  exists (
    select 1
    from public.farmer_phone_profiles profile
    where profile.user_id = auth.uid()
      and nullif(trim(profile.farmer_id), '') = procurement_lots.farmer_id
  )
);

drop policy if exists "farmers read own procurement records"
  on public.fpc_procurement_records;
create policy "farmers read own procurement records"
on public.fpc_procurement_records for select to authenticated
using (
  exists (
    select 1
    from public.farmer_phone_profiles profile
    where profile.user_id = auth.uid()
      and nullif(trim(profile.farmer_id), '') = fpc_procurement_records.farmer_id
  )
);

drop policy if exists "farmers read own payment ledger"
  on public.farmer_payment_ledger;
create policy "farmers read own payment ledger"
on public.farmer_payment_ledger for select to authenticated
using (
  exists (
    select 1
    from public.farmer_phone_profiles profile
    where profile.user_id = auth.uid()
      and nullif(trim(profile.farmer_id), '') = farmer_payment_ledger.farmer_id
  )
);

drop policy if exists "farmers read sales items for own lots"
  on public.sales_order_items;
create policy "farmers read sales items for own lots"
on public.sales_order_items for select to authenticated
using (
  exists (
    select 1
    from public.procurement_lots lot
    join public.farmer_phone_profiles profile
      on nullif(trim(profile.farmer_id), '') = lot.farmer_id
    where profile.user_id = auth.uid()
      and lot.id = sales_order_items.procurement_lot_id
  )
);

drop policy if exists "farmers read sales orders for own lots"
  on public.sales_orders;
create policy "farmers read sales orders for own lots"
on public.sales_orders for select to authenticated
using (
  exists (
    select 1
    from public.sales_order_items item
    join public.procurement_lots lot
      on lot.id = item.procurement_lot_id
    join public.farmer_phone_profiles profile
      on nullif(trim(profile.farmer_id), '') = lot.farmer_id
    where profile.user_id = auth.uid()
      and item.sales_order_id = sales_orders.id
  )
);

drop policy if exists "farmers read dispatches for own lots"
  on public.dispatches;
create policy "farmers read dispatches for own lots"
on public.dispatches for select to authenticated
using (
  exists (
    select 1
    from public.sales_order_items item
    join public.procurement_lots lot
      on lot.id = item.procurement_lot_id
    join public.farmer_phone_profiles profile
      on nullif(trim(profile.farmer_id), '') = lot.farmer_id
    where profile.user_id = auth.uid()
      and item.sales_order_id = dispatches.sales_order_id
  )
);

drop policy if exists "farmers read delivery fpcs"
  on public.fpcs;
create policy "farmers read delivery fpcs"
on public.fpcs for select to authenticated
using (
  exists (
    select 1
    from public.fpc_seed_requests request
    where request.fpc_id = fpcs.id
      and request.farmer_user_id = auth.uid()
  )
  or exists (
    select 1
    from public.procurement_lots lot
    join public.farmer_phone_profiles profile
      on nullif(trim(profile.farmer_id), '') = lot.farmer_id
    where profile.user_id = auth.uid()
      and lot.fpc_id = fpcs.id
  )
  or exists (
    select 1
    from public.farmer_payment_ledger payment
    join public.farmer_phone_profiles profile
      on nullif(trim(profile.farmer_id), '') = payment.farmer_id
    where profile.user_id = auth.uid()
      and payment.fpc_id = fpcs.id
  )
);

create view public.farmer_delivery_timeline
with (security_invoker = true)
as
select
  ('seed_request:' || request.id::text) as timeline_id,
  'seed_request'::text as record_type,
  request.fpc_id,
  coalesce(fpc.name, 'FPC')::text as fpc_name,
  request.farmer_id,
  request.farm_id::text as farm_id,
  'Seed request'::text as title,
  request.status,
  coalesce(request.payment_status, 'not_started')::text as payment_status,
  request.requested_quantity_kg as quantity_kg,
  case
    when request.amount_paise is null then null::numeric
    else (request.amount_paise::numeric / 100)
  end as amount,
  coalesce(request.currency, 'INR')::text as currency,
  coalesce(
    request.paid_at,
    request.reviewed_at,
    request.preferred_delivery_at,
    request.created_at
  ) as occurred_at,
  request.updated_at,
  '{}'::jsonb as evidence,
  jsonb_build_object(
    'seedRequestId', request.id,
    'programId', request.program_id,
    'seedBatchId', request.seed_batch_id,
    'farmerNote', request.farmer_note,
    'responseNote', request.response_note,
    'reservationExpiresAt', request.reservation_expires_at
  ) as metadata,
  ''::text as acknowledgement_action,
  null::uuid as acknowledge_seed_issue_id
from public.fpc_seed_requests request
left join public.fpcs fpc on fpc.id = request.fpc_id

union all

select
  ('seed_delivery:' || issue.id::text) as timeline_id,
  'seed_delivery'::text as record_type,
  issue.fpc_id,
  coalesce(fpc.name, 'FPC')::text as fpc_name,
  enrollment.farmer_id,
  enrollment.farm_id::text as farm_id,
  'Seed delivery'::text as title,
  issue.status,
  coalesce(request.payment_status, '')::text as payment_status,
  issue.quantity_kg,
  case
    when request.amount_paise is null then null::numeric
    else (request.amount_paise::numeric / 100)
  end as amount,
  coalesce(request.currency, 'INR')::text as currency,
  coalesce(issue.delivered_at, issue.acknowledged_at, issue.created_at) as occurred_at,
  issue.updated_at,
  issue.delivery_evidence as evidence,
  jsonb_build_object(
    'seedIssueId', issue.id,
    'seedBatchId', issue.seed_batch_id,
    'enrollmentId', issue.enrollment_id,
    'assignedOfficerId', issue.assigned_officer_id,
    'scheduledFor', issue.scheduled_for,
    'deliveredAt', issue.delivered_at,
    'acknowledgedAt', issue.acknowledged_at,
    'seedRequestId', request.id
  ) as metadata,
  case
    when issue.status = 'delivered' then 'acknowledge_seed'
    else ''
  end as acknowledgement_action,
  case
    when issue.status = 'delivered' then issue.id
    else null::uuid
  end as acknowledge_seed_issue_id
from public.fpc_seed_issues issue
join public.fpc_program_enrollments enrollment
  on enrollment.id = issue.enrollment_id
left join public.fpc_seed_requests request
  on request.enrollment_id = issue.enrollment_id
left join public.fpcs fpc on fpc.id = issue.fpc_id

union all

select
  ('procurement_delivery:' || receipt.id::text) as timeline_id,
  'procurement_delivery'::text as record_type,
  coalesce(receipt.fpc_organization_id, receipt.fpc_id) as fpc_id,
  coalesce(fpc.name, 'FPC')::text as fpc_name,
  receipt.farmer_id,
  receipt.farm_id,
  'Procurement delivery'::text as title,
  receipt.delivery_status as status,
  ''::text as payment_status,
  receipt.net_weight_kg as quantity_kg,
  receipt.total_value as amount,
  'INR'::text as currency,
  coalesce(receipt.received_at, receipt.created_at) as occurred_at,
  receipt.updated_at,
  '{}'::jsonb as evidence,
  jsonb_build_object(
    'receiptId', receipt.id,
    'receiptNumber', receipt.receipt_number,
    'batchId', receipt.batch_id
  ) as metadata,
  ''::text as acknowledgement_action,
  null::uuid as acknowledge_seed_issue_id
from public.fpc_procurement_records receipt
left join public.fpcs fpc
  on fpc.id = coalesce(receipt.fpc_organization_id, receipt.fpc_id)

union all

select
  ('procurement_lot:' || lot.id::text) as timeline_id,
  'procurement_lot'::text as record_type,
  lot.fpc_id,
  coalesce(fpc.name, 'FPC')::text as fpc_name,
  lot.farmer_id,
  lot.farm_id,
  'Procurement lot'::text as title,
  lot.status,
  ''::text as payment_status,
  lot.net_weight_kg as quantity_kg,
  null::numeric as amount,
  'INR'::text as currency,
  coalesce(lot.received_at, lot.created_at) as occurred_at,
  lot.updated_at,
  '{}'::jsonb as evidence,
  jsonb_build_object(
    'lotId', lot.id,
    'receiptId', lot.receipt_id,
    'batchId', lot.batch_id,
    'crop', lot.crop,
    'traceabilityCode', lot.traceability_code
  ) as metadata,
  ''::text as acknowledgement_action,
  null::uuid as acknowledge_seed_issue_id
from public.procurement_lots lot
left join public.fpcs fpc on fpc.id = lot.fpc_id

union all

select
  ('farmer_payment:' || payment.id::text) as timeline_id,
  'farmer_payment'::text as record_type,
  payment.fpc_id,
  coalesce(fpc.name, 'FPC')::text as fpc_name,
  payment.farmer_id,
  coalesce(lot.farm_id, '')::text as farm_id,
  'Farmer payment'::text as title,
  payment.status,
  payment.status as payment_status,
  payment.net_weight_kg as quantity_kg,
  payment.final_amount as amount,
  'INR'::text as currency,
  payment.created_at as occurred_at,
  payment.updated_at,
  '{}'::jsonb as evidence,
  jsonb_build_object(
    'paymentId', payment.id,
    'lotId', payment.lot_id,
    'crop', lot.crop,
    'batchId', lot.batch_id,
    'paymentMode', payment.payment_mode,
    'paymentReference', payment.payment_reference
  ) as metadata,
  ''::text as acknowledgement_action,
  null::uuid as acknowledge_seed_issue_id
from public.farmer_payment_ledger payment
left join public.procurement_lots lot on lot.id = payment.lot_id
left join public.fpcs fpc on fpc.id = payment.fpc_id

union all

select
  ('buyer_dispatch:' || dispatch.id::text || ':' || lot.id::text) as timeline_id,
  'buyer_dispatch'::text as record_type,
  dispatch.fpc_id,
  coalesce(fpc.name, 'FPC')::text as fpc_name,
  lot.farmer_id,
  lot.farm_id,
  'Buyer dispatch'::text as title,
  dispatch.status,
  coalesce(sales.payment_reference, '')::text as payment_status,
  item.quantity as quantity_kg,
  item.line_total as amount,
  'INR'::text as currency,
  coalesce(dispatch.delivered_at, dispatch.dispatched_at, dispatch.created_at) as occurred_at,
  dispatch.updated_at,
  dispatch.proof_of_delivery as evidence,
  jsonb_build_object(
    'dispatchId', dispatch.id,
    'salesOrderId', sales.id,
    'orderNumber', sales.order_number,
    'invoiceNumber', sales.invoice_number,
    'lotId', lot.id,
    'crop', lot.crop
  ) as metadata,
  ''::text as acknowledgement_action,
  null::uuid as acknowledge_seed_issue_id
from public.dispatches dispatch
join public.sales_orders sales on sales.id = dispatch.sales_order_id
join public.sales_order_items item on item.sales_order_id = sales.id
join public.procurement_lots lot on lot.id = item.procurement_lot_id
left join public.fpcs fpc on fpc.id = dispatch.fpc_id;

revoke all on public.farmer_delivery_timeline from anon;
grant select on public.farmer_delivery_timeline to authenticated;

comment on view public.farmer_delivery_timeline is
  'RLS-filtered Farmer/FPC delivery timeline joining seed delivery, procurement delivery, payments, and farmer-linked buyer dispatches.';
