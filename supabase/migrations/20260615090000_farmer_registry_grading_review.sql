create table if not exists public.farmer_phone_registry (
  id uuid primary key default gen_random_uuid(),
  phone text not null unique,
  farmer_id text not null,
  farmer_name text not null,
  default_location text not null default '',
  preferred_language text not null default 'en',
  status text not null default 'active'
    check (status in ('active', 'blocked', 'pending', 'inactive')),
  profile_completed_at timestamptz,
  source text not null default 'admin_registry',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists farmer_phone_registry_status_idx
on public.farmer_phone_registry(status);

alter table public.farmer_phone_registry enable row level security;

drop policy if exists "admins can read farmer phone registry" on public.farmer_phone_registry;
create policy "admins can read farmer phone registry"
on public.farmer_phone_registry for select
to authenticated
using (
  coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') in
  ('admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc')
);

alter table public.farmer_phone_profiles
  add column if not exists status text not null default 'active'
    check (status in ('active', 'blocked', 'pending', 'inactive'));

alter table public.farmer_phone_profiles
  add column if not exists phone_verified_at timestamptz;

alter table public.farmer_phone_profiles
  add column if not exists profile_completed_at timestamptz;

alter table public.farmer_phone_profiles
  add column if not exists source text not null default 'app';

alter table public.analysis_jobs
  add column if not exists farmer_id text;

alter table public.analysis_jobs
  add column if not exists farm_id text;

alter table public.analysis_jobs
  add column if not exists bag_size_kg numeric;

alter table public.analysis_jobs
  add column if not exists bag_count integer;

alter table public.analysis_jobs
  add column if not exists total_kg numeric;

alter table public.analysis_jobs
  add column if not exists review_status text not null default 'not_required'
    check (review_status in ('not_required', 'pending', 'approved', 'corrected', 'rejected', 'recapture_requested'));

alter table public.analysis_jobs
  add column if not exists reviewed_by uuid;

alter table public.analysis_jobs
  add column if not exists reviewed_at timestamptz;

alter table public.analysis_jobs
  add column if not exists review_notes text not null default '';

create index if not exists analysis_jobs_review_status_created_idx
on public.analysis_jobs(review_status, created_at desc);

drop policy if exists "fpo admins can read grading review jobs" on public.analysis_jobs;
create policy "fpo admins can read grading review jobs"
on public.analysis_jobs for select
to authenticated
using (
  coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') in
  ('admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc')
);

drop policy if exists "fpo admins can update grading review jobs" on public.analysis_jobs;
create policy "fpo admins can update grading review jobs"
on public.analysis_jobs for update
to authenticated
using (
  coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') in
  ('admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc')
)
with check (
  coalesce((auth.jwt() -> 'user_metadata' ->> 'role'), '') in
  ('admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc')
);
