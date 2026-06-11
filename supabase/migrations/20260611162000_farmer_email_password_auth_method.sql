do $$
begin
  if to_regclass('public.farmer_phone_profiles') is not null then
    alter table public.farmer_phone_profiles
      drop constraint if exists farmer_phone_profiles_auth_method_check;

    alter table public.farmer_phone_profiles
      add constraint farmer_phone_profiles_auth_method_check
      check (auth_method in ('anonymous_link', 'phone_otp', 'email_password'));
  end if;
end $$;
