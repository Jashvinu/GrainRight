alter table public.farmer_phone_registry
  add column if not exists aadhaar_number text not null default '';

alter table public.farmer_phone_profiles
  add column if not exists aadhaar_number text not null default '';

alter table public.farmer_phone_registry
  drop constraint if exists farmer_phone_registry_aadhaar_number_format,
  add constraint farmer_phone_registry_aadhaar_number_format check (
    aadhaar_number = '' or aadhaar_number ~ '^[0-9]{12}$'
  ),
  drop constraint if exists farmer_phone_registry_aadhaar_parts_match,
  add constraint farmer_phone_registry_aadhaar_parts_match check (
    aadhaar_number = '' or (
      aadhaar_last4 = right(aadhaar_number, 4)
      and aadhaar_masked = 'XXXX XXXX ' || right(aadhaar_number, 4)
    )
  );

alter table public.farmer_phone_profiles
  drop constraint if exists farmer_phone_profiles_aadhaar_number_format,
  add constraint farmer_phone_profiles_aadhaar_number_format check (
    aadhaar_number = '' or aadhaar_number ~ '^[0-9]{12}$'
  ),
  drop constraint if exists farmer_phone_profiles_aadhaar_parts_match,
  add constraint farmer_phone_profiles_aadhaar_parts_match check (
    aadhaar_number = '' or (
      aadhaar_last4 = right(aadhaar_number, 4)
      and aadhaar_masked = 'XXXX XXXX ' || right(aadhaar_number, 4)
    )
  );
