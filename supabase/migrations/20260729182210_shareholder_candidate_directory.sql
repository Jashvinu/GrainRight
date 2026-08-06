create table if not exists public.shareholder_candidate_roster (
  id uuid primary key default gen_random_uuid(),
  source_record_key text not null unique
    check (source_record_key ~ '^[0-9a-f]{64}$'),
  source_file text not null,
  source_part_no integer not null check (source_part_no > 0),
  source_page integer not null check (source_page > 0),
  source_ordinal integer not null check (source_ordinal > 0),
  full_name text not null check (length(btrim(full_name)) between 4 and 90),
  gender text not null default ''
    check (gender in ('', 'Male', 'Female')),
  village text not null check (length(btrim(village)) >= 2),
  main_village text not null default '',
  taluka text not null check (length(btrim(taluka)) >= 2),
  district text not null check (length(btrim(district)) >= 2),
  proposed_share_count integer not null default 1
    check (proposed_share_count = 1),
  share_unit_value numeric(12, 2) not null default 100.00
    check (share_unit_value = 100.00),
  proposed_total_amount numeric(12, 2)
    generated always as (
      proposed_share_count::numeric * share_unit_value
    ) stored,
  farmer_status text not null default 'unverified'
    check (farmer_status in ('unverified', 'verified')),
  candidate_status text not null default 'pending_consent_kyc_payment'
    check (
      candidate_status in (
        'pending_consent_kyc_payment',
        'consent_verified',
        'kyc_verified',
        'payment_verified',
        'allotted',
        'rejected'
      )
    ),
  ocr_confidence numeric(5, 2) not null default 0
    check (ocr_confidence between 0 and 100),
  linked_application_id uuid
    references public.stakeholder_applications(id) on delete set null,
  consent_verified_at timestamptz,
  kyc_verified_at timestamptz,
  payment_verified_at timestamptz,
  allotted_at timestamptz,
  imported_by uuid references auth.users(id) on delete set null,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    candidate_status <> 'consent_verified'
    or consent_verified_at is not null
  ),
  check (
    candidate_status <> 'kyc_verified'
    or (
      consent_verified_at is not null
      and kyc_verified_at is not null
      and farmer_status = 'verified'
    )
  ),
  check (
    candidate_status <> 'payment_verified'
    or (
      consent_verified_at is not null
      and kyc_verified_at is not null
      and payment_verified_at is not null
      and farmer_status = 'verified'
    )
  ),
  check (
    candidate_status <> 'allotted'
    or (
      consent_verified_at is not null
      and kyc_verified_at is not null
      and payment_verified_at is not null
      and allotted_at is not null
      and linked_application_id is not null
      and farmer_status = 'verified'
    )
  )
);

comment on table public.shareholder_candidate_roster is
  'Privacy-minimized electoral-roll candidate roster. Rows are not farmer verification, payment proof, membership, or legal share allotments.';
comment on column public.shareholder_candidate_roster.source_record_key is
  'Deterministic SHA-256 of source file/page/ordinal/name; no EPIC number is retained.';
comment on column public.shareholder_candidate_roster.proposed_share_count is
  'One proposed share only. This is not an allotment until the server-enforced gates pass.';
comment on column public.shareholder_candidate_roster.share_unit_value is
  'Proposed INR unit value aligned with the active shareholder plan.';

create index if not exists shareholder_candidate_roster_location_idx
  on public.shareholder_candidate_roster (
    lower(district),
    lower(taluka),
    lower(village),
    lower(full_name)
  );

create index if not exists shareholder_candidate_roster_status_idx
  on public.shareholder_candidate_roster (
    candidate_status,
    farmer_status,
    updated_at desc
  );

create index if not exists shareholder_candidate_roster_source_idx
  on public.shareholder_candidate_roster (
    source_part_no,
    source_page,
    source_ordinal
  );

drop trigger if exists set_shareholder_candidate_roster_updated_at
  on public.shareholder_candidate_roster;
create trigger set_shareholder_candidate_roster_updated_at
before update on public.shareholder_candidate_roster
for each row execute function public.set_updated_at();

alter table public.shareholder_candidate_roster enable row level security;
alter table public.shareholder_candidate_roster force row level security;

drop policy if exists "admins can read shareholder candidates"
  on public.shareholder_candidate_roster;
create policy "admins can read shareholder candidates"
on public.shareholder_candidate_roster
for select
to authenticated
using ((select public.has_server_role(array['admin'])));

revoke all on table public.shareholder_candidate_roster
  from public, anon, authenticated;
grant select on table public.shareholder_candidate_roster
  to authenticated;
grant all on table public.shareholder_candidate_roster
  to service_role;

create or replace function public.admin_shareholder_candidate_directory(
  p_search text default '',
  p_village text default '',
  p_taluka text default '',
  p_district text default '',
  p_offset integer default 0,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_search text := btrim(coalesce(p_search, ''));
  v_village text := btrim(coalesce(p_village, ''));
  v_taluka text := btrim(coalesce(p_taluka, ''));
  v_district text := btrim(coalesce(p_district, ''));
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 200);
  v_result jsonb;
begin
  if (select auth.uid()) is null
    or not (select public.has_server_role(array['admin'])) then
    raise exception using
      errcode = '42501',
      message = 'admin_role_required';
  end if;

  with filtered as (
    select candidate.*
    from public.shareholder_candidate_roster candidate
    where
      (
        v_district = ''
        or lower(candidate.district) = lower(v_district)
      )
      and (
        v_taluka = ''
        or lower(candidate.taluka) = lower(v_taluka)
      )
      and (
        v_village = ''
        or lower(candidate.village) = lower(v_village)
      )
      and (
        v_search = ''
        or concat_ws(
          ' ',
          candidate.full_name,
          candidate.village,
          candidate.main_village,
          candidate.taluka,
          candidate.district,
          candidate.source_part_no::text,
          candidate.candidate_status,
          candidate.farmer_status
        ) ilike ('%' || v_search || '%')
      )
  ),
  page_rows as (
    select filtered.*
    from filtered
    order by
      lower(filtered.district),
      lower(filtered.taluka),
      lower(filtered.village),
      lower(filtered.full_name),
      filtered.source_part_no,
      filtered.source_page,
      filtered.source_ordinal
    offset v_offset
    limit v_limit
  )
  select jsonb_build_object(
    'rows',
      coalesce(
        (
          select jsonb_agg(
            to_jsonb(page_rows)
            order by
              lower(page_rows.district),
              lower(page_rows.taluka),
              lower(page_rows.village),
              lower(page_rows.full_name),
              page_rows.source_part_no,
              page_rows.source_page,
              page_rows.source_ordinal
          )
          from page_rows
        ),
        '[]'::jsonb
      ),
    'totalCount', (select count(*) from filtered),
    'offset', v_offset,
    'limit', v_limit,
    'filters', jsonb_build_object(
      'villages',
        coalesce(
          (
            select jsonb_agg(option_value order by lower(option_value))
            from (
              select distinct candidate.village as option_value
              from public.shareholder_candidate_roster candidate
              where candidate.village <> ''
            ) villages
          ),
          '[]'::jsonb
        ),
      'talukas',
        coalesce(
          (
            select jsonb_agg(option_value order by lower(option_value))
            from (
              select distinct candidate.taluka as option_value
              from public.shareholder_candidate_roster candidate
              where candidate.taluka <> ''
            ) talukas
          ),
          '[]'::jsonb
        ),
      'districts',
        coalesce(
          (
            select jsonb_agg(option_value order by lower(option_value))
            from (
              select distinct candidate.district as option_value
              from public.shareholder_candidate_roster candidate
              where candidate.district <> ''
            ) districts
          ),
          '[]'::jsonb
        )
    ),
    'summary', jsonb_build_object(
      'totalCandidates',
        (select count(*) from public.shareholder_candidate_roster),
      'pendingConsent',
        (
          select count(*)
          from public.shareholder_candidate_roster candidate
          where candidate.candidate_status = 'pending_consent_kyc_payment'
        ),
      'verifiedFarmers',
        (
          select count(*)
          from public.shareholder_candidate_roster candidate
          where candidate.farmer_status = 'verified'
        ),
      'allotted',
        (
          select count(*)
          from public.shareholder_candidate_roster candidate
          where candidate.candidate_status = 'allotted'
        ),
      'proposedCapital',
        (
          select coalesce(sum(candidate.proposed_total_amount), 0)
          from public.shareholder_candidate_roster candidate
        )
    )
  )
  into v_result;

  return v_result;
end;
$$;

comment on function public.admin_shareholder_candidate_directory(
  text,
  text,
  text,
  text,
  integer,
  integer
) is
  'Admin-only paginated candidate roster with server-side search and village/taluka/district filters.';

revoke all on function public.admin_shareholder_candidate_directory(
  text,
  text,
  text,
  text,
  integer,
  integer
) from public, anon;
grant execute on function public.admin_shareholder_candidate_directory(
  text,
  text,
  text,
  text,
  integer,
  integer
) to authenticated;
