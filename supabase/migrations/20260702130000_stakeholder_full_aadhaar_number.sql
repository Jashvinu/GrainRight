alter table public.farmer_phone_registry
  add column if not exists aadhaar_number text not null default '';

alter table public.farmer_phone_profiles
  add column if not exists aadhaar_number text not null default '';

alter table public.stakeholder_applications
  add column if not exists aadhaar_number text not null default '',
  add column if not exists farmer_aadhaar_number text not null default '';

update public.stakeholder_applications
set
  farmer_aadhaar_number = aadhaar_number
where
  farmer_aadhaar_number = ''
  and aadhaar_number <> '';
