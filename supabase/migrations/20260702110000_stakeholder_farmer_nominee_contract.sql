alter table public.stakeholder_applications
  add column if not exists farmer_full_name text not null default '',
  add column if not exists farmer_father_name text not null default '',
  add column if not exists farmer_mobile_number text not null default '',
  add column if not exists farmer_aadhaar_last4 text not null default '',
  add column if not exists farmer_address text not null default '',
  add column if not exists farmer_village text not null default '',
  add column if not exists farmer_taluka text not null default '',
  add column if not exists farmer_district text not null default '',
  add column if not exists farmer_pincode text not null default '',
  add column if not exists farmer_total_land_acres text not null default '',
  add column if not exists farmer_photo_path text not null default '',
  add column if not exists nominee_name text not null default '',
  add column if not exists nominee_address text not null default '',
  add column if not exists nominee_mobile_number text not null default '',
  add column if not exists nominee_signature text not null default '',
  add column if not exists nominee_count integer not null default 1,
  add column if not exists nominee2_name text not null default '',
  add column if not exists nominee2_address text not null default '',
  add column if not exists nominee2_mobile_number text not null default '',
  add column if not exists nominee2_signature text not null default '',
  add column if not exists farmer_signature text not null default '',
  add column if not exists contract_read_accepted boolean not null default false;

create index if not exists stakeholder_applications_nominee_phone_idx
  on public.stakeholder_applications(nominee_mobile_number)
  where nominee_mobile_number <> '';

create index if not exists stakeholder_applications_nominee2_phone_idx
  on public.stakeholder_applications(nominee2_mobile_number)
  where nominee2_mobile_number <> '';

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'stakeholder-documents',
  'stakeholder-documents',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

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
