create table if not exists public.role_account_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'fpc')),
  email text not null,
  display_name text not null,
  organization_name text not null,
  phone text,
  status text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists role_account_profiles_email_idx
  on public.role_account_profiles (lower(email));

create index if not exists role_account_profiles_role_status_idx
  on public.role_account_profiles (role, status, updated_at desc);

drop trigger if exists set_role_account_profiles_updated_at
on public.role_account_profiles;
create trigger set_role_account_profiles_updated_at
before update on public.role_account_profiles
for each row
execute function public.set_updated_at();

alter table public.role_account_profiles enable row level security;

drop policy if exists "role accounts can read own profile"
  on public.role_account_profiles;
create policy "role accounts can read own profile"
on public.role_account_profiles for select
to authenticated
using (
  user_id = auth.uid()
  or public.has_server_role(array['admin'])
);

grant select on public.role_account_profiles to authenticated;
