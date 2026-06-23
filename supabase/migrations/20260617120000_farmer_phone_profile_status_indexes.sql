create index if not exists farmer_phone_profiles_user_status_phone_idx
  on public.farmer_phone_profiles (user_id, status, phone);

create index if not exists farmer_phone_profiles_phone_status_idx
  on public.farmer_phone_profiles (phone, status);

create index if not exists farmer_phone_profiles_farmer_id_status_idx
  on public.farmer_phone_profiles (farmer_id, status);
