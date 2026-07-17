alter table public.stakeholder_applications
  add column if not exists land_record_details text not null default '',
  add column if not exists land_record_document_path text not null default '';

update public.stakeholder_plans
set
  purpose = '[
    "Let registered farmers apply to buy Kalsubai Farms stakeholder shares.",
    "Keep farmer identity, PAN, 7/12 land record, bank, selected amount and payment details in one review-ready record.",
    "Prepare an auditable application before final approval and allocation."
  ]'::jsonb,
  stages = '[
    "Submit farmer account, KYC, 7/12 land record, bank and payment details",
    "Kalsubai Farms reviews farmer record, payment and plan capacity",
    "Approved allocation and documents are updated after admin review"
  ]'::jsonb,
  updated_at = now()
where plan_code = 'kalsubai-farmer-stakeholder-v1';
