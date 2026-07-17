alter table public.stakeholder_applications
  add column if not exists pan_number text not null default '',
  add column if not exists pan_holder_name text not null default '',
  add column if not exists pan_document_path text not null default '',
  add column if not exists account_holder_name text not null default '',
  add column if not exists bank_name text not null default '',
  add column if not exists bank_account_number text not null default '',
  add column if not exists ifsc_code text not null default '',
  add column if not exists upi_id text not null default '',
  add column if not exists passbook_document_path text not null default '',
  add column if not exists payment_method text not null default 'none',
  add column if not exists payment_status text not null default 'pending',
  add column if not exists razorpay_order_id text not null default '',
  add column if not exists razorpay_payment_id text not null default '',
  add column if not exists razorpay_signature text not null default '',
  add column if not exists bank_transfer_reference text not null default '',
  add column if not exists bank_transfer_proof_path text not null default '',
  add column if not exists payment_reviewed_at timestamptz,
  add column if not exists kyc_reviewed_at timestamptz;

create index if not exists stakeholder_applications_payment_status_idx
  on public.stakeholder_applications(payment_status, updated_at desc);

update public.stakeholder_plans
set
  title = 'Kalsubai Farms Farmer Stakeholder Plan',
  summary = 'Apply to buy farmer stakeholder shares. Final allocation is confirmed only after Kalsubai Farms review.',
  currency = 'INR',
  share_unit_value = 100,
  min_amount = 100,
  max_amount = 25000,
  purpose = '[
    "Let registered farmers apply to buy Kalsubai Farms stakeholder shares.",
    "Keep farmer identity, PAN, bank, selected amount and payment details in one review-ready record.",
    "Prepare an auditable application before final approval and allocation."
  ]'::jsonb,
  stages = '[
    "Submit farmer account, KYC, bank and payment details",
    "Kalsubai Farms reviews farmer record, payment and plan capacity",
    "Approved allocation and documents are updated after admin review"
  ]'::jsonb,
  risk_notes = '[
    "Payment confirmation is not a confirmed share issue.",
    "Returns are not guaranteed and depend on final approval and business performance.",
    "Final terms must be reviewed before any allocation."
  ]'::jsonb,
  terms = '[
    "The selected amount starts an application for review.",
    "Estimated shares are calculated from the current plan share value.",
    "Kalsubai Farms may approve, revise, or reject the application after review."
  ]'::jsonb,
  updated_at = now()
where plan_code = 'kalsubai-farmer-stakeholder-v1';

insert into storage.buckets (id, name, public)
values ('stakeholder-documents', 'stakeholder-documents', false)
on conflict (id) do nothing;

drop policy if exists "farmers can read own stakeholder documents"
  on storage.objects;
create policy "farmers can read own stakeholder documents"
on storage.objects for select to authenticated
using (
  bucket_id = 'stakeholder-documents'
  and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "farmers can upload own stakeholder documents"
  on storage.objects;
create policy "farmers can upload own stakeholder documents"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'stakeholder-documents'
  and split_part(name, '/', 1) = auth.uid()::text
);
