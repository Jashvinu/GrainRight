alter table public.farmer_phone_registry
  add column if not exists agri_record_id text not null default '',
  add column if not exists aadhaar_masked text not null default '',
  add column if not exists aadhaar_last4 text not null default '',
  add column if not exists identity_document_bucket text not null default 'farmer-identity-documents',
  add column if not exists identity_document_path text not null default '',
  add column if not exists identity_ocr_confidence numeric,
  add column if not exists identity_source text not null default '',
  add column if not exists identity_verified_at timestamptz;

alter table public.farmer_phone_profiles
  add column if not exists agri_record_id text not null default '',
  add column if not exists aadhaar_masked text not null default '',
  add column if not exists aadhaar_last4 text not null default '',
  add column if not exists identity_document_bucket text not null default 'farmer-identity-documents',
  add column if not exists identity_document_path text not null default '',
  add column if not exists identity_ocr_confidence numeric,
  add column if not exists identity_source text not null default '',
  add column if not exists identity_verified_at timestamptz;

create index if not exists farmer_phone_registry_agri_record_id_idx
on public.farmer_phone_registry(agri_record_id)
where agri_record_id <> '';

create index if not exists farmer_phone_profiles_agri_record_id_idx
on public.farmer_phone_profiles(agri_record_id)
where agri_record_id <> '';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'farmer-identity-documents',
  'farmer-identity-documents',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "farmer identity document owner read" on storage.objects;
create policy "farmer identity document owner read"
on storage.objects for select to authenticated
using (
  bucket_id = 'farmer-identity-documents'
  and owner = auth.uid()
);

drop policy if exists "farmer identity document owner insert" on storage.objects;
create policy "farmer identity document owner insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'farmer-identity-documents'
  and owner = auth.uid()
);
