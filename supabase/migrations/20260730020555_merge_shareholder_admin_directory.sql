-- Merge both shareholder sources while preserving no-KYC override provenance.
alter table public.shareholder_candidate_roster
  add column if not exists admin_promoted boolean not null default false,
  add column if not exists admin_promoted_at timestamptz,
  add column if not exists admin_promotion_basis text not null default '';

comment on column public.shareholder_candidate_roster.admin_promoted is
  'Administrative shareholder-directory override. It does not prove farmer identity, KYC, payment, or legal allotment.';
comment on column public.shareholder_candidate_roster.admin_promotion_basis is
  'Audit label explaining why a candidate is shown as promoted without changing KYC/payment/allotment gates.';

update public.shareholder_candidate_roster
set
  admin_promoted = true,
  admin_promoted_at = coalesce(admin_promoted_at, now()),
  admin_promotion_basis = 'admin_override_without_kyc'
where not admin_promoted
   or admin_promoted_at is null
   or admin_promotion_basis = '';

alter table public.shareholder_register enable row level security;
alter table public.shareholder_register force row level security;

drop policy if exists "admins can read shareholder register"
  on public.shareholder_register;
create policy "admins can read shareholder register"
on public.shareholder_register
for select
to authenticated
using ((select public.has_server_role(array['admin'])));

revoke all on table public.shareholder_register
  from public, anon, authenticated;
grant select on table public.shareholder_register
  to authenticated;
grant all on table public.shareholder_register
  to service_role;

create or replace function public.admin_shareholder_directory(
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

  with register_locations as (
    select
      shareholder.*,
      case
        when shareholder.member_address ~* '^At\s+Post\s+' then
          btrim(substring(
            shareholder.member_address
            from '(?i)^At\s+Post\s+(.+?)\s+Tal(?:uka)?\s+'
          ))
        else
          btrim(substring(
            shareholder.member_address
            from '(?i)^At\s+(.+?)(?:\s+Post\s+|\s+Tal(?:uka)?\s+)'
          ))
      end as parsed_village,
      btrim(substring(
        shareholder.member_address
        from '(?i)\s+Post\s+(.+?)\s+Tal(?:uka)?\s+'
      )) as parsed_main_village,
      btrim(substring(
        shareholder.member_address
        from '(?i)\s+Tal(?:uka)?\s+([^\s]+)'
      )) as parsed_taluka,
      btrim(substring(
        shareholder.member_address
        from '(?i)\s+Dist(?:rict)?\s+(.+)$'
      )) as parsed_district
    from public.shareholder_register shareholder
  ),
  directory as (
    select
      candidate.id,
      candidate.source_record_key,
      'candidate_roster'::text as directory_source,
      candidate.source_file,
      ''::text as source_sheet,
      candidate.source_part_no,
      candidate.source_page,
      candidate.source_ordinal,
      candidate.full_name,
      candidate.gender,
      candidate.village,
      candidate.main_village,
      candidate.taluka,
      candidate.district,
      ''::text as member_address,
      false as address_inferred,
      candidate.proposed_share_count,
      candidate.share_unit_value,
      candidate.proposed_total_amount,
      true as amount_recorded,
      'proposed'::text as share_status,
      candidate.farmer_status,
      candidate.candidate_status,
      candidate.ocr_confidence,
      candidate.admin_promoted,
      candidate.admin_promotion_basis,
      case
        when candidate.admin_promoted
          then 'verified_shareholder_override'
        when candidate.farmer_status = 'verified'
          then 'verified_farmer'
        else 'verification_pending'
      end as verification_status
    from public.shareholder_candidate_roster candidate

    union all

    select
      shareholder.id,
      ('register:' || shareholder.id::text) as source_record_key,
      'shareholder_register'::text as directory_source,
      shareholder.source_file,
      shareholder.source_sheet,
      0 as source_part_no,
      0 as source_page,
      shareholder.source_row as source_ordinal,
      shareholder.member_name as full_name,
      ''::text as gender,
      coalesce(
        nullif(shareholder.parsed_village, ''),
        'Location not recorded'
      ) as village,
      coalesce(
        nullif(shareholder.parsed_main_village, ''),
        nullif(shareholder.parsed_village, ''),
        'Location not recorded'
      ) as main_village,
      coalesce(nullif(shareholder.parsed_taluka, ''), '') as taluka,
      case
        when shareholder.parsed_district ~* 'ahil|ahmed' then 'Ahmednagar'
        when lower(coalesce(shareholder.parsed_taluka, '')) = 'akole'
          then 'Ahmednagar'
        else coalesce(shareholder.parsed_district, '')
      end as district,
      shareholder.member_address,
      shareholder.address_inferred,
      shareholder.shares_allotted as proposed_share_count,
      0::numeric as share_unit_value,
      0::numeric as proposed_total_amount,
      false as amount_recorded,
      'allotted'::text as share_status,
      'not_recorded'::text as farmer_status,
      'verified_shareholder'::text as candidate_status,
      0::numeric as ocr_confidence,
      false as admin_promoted,
      'audited_shareholder_register'::text as admin_promotion_basis,
      'verified_shareholder'::text as verification_status
    from register_locations shareholder
  ),
  filtered as (
    select entry.*
    from directory entry
    where
      (
        v_district = ''
        or lower(entry.district) = lower(v_district)
      )
      and (
        v_taluka = ''
        or lower(entry.taluka) = lower(v_taluka)
      )
      and (
        v_village = ''
        or lower(entry.village) = lower(v_village)
      )
      and (
        v_search = ''
        or concat_ws(
          ' ',
          entry.full_name,
          entry.gender,
          entry.village,
          entry.main_village,
          entry.taluka,
          entry.district,
          entry.member_address,
          entry.directory_source,
          entry.share_status,
          entry.candidate_status,
          entry.farmer_status,
          entry.verification_status,
          entry.admin_promotion_basis,
          entry.source_file,
          entry.source_sheet,
          entry.source_part_no::text,
          entry.source_page::text,
          entry.source_ordinal::text
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
      filtered.directory_source,
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
              page_rows.directory_source,
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
              select distinct entry.village as option_value
              from directory entry
              where entry.village <> ''
            ) villages
          ),
          '[]'::jsonb
        ),
      'talukas',
        coalesce(
          (
            select jsonb_agg(option_value order by lower(option_value))
            from (
              select distinct entry.taluka as option_value
              from directory entry
              where entry.taluka <> ''
            ) talukas
          ),
          '[]'::jsonb
        ),
      'districts',
        coalesce(
          (
            select jsonb_agg(option_value order by lower(option_value))
            from (
              select distinct entry.district as option_value
              from directory entry
              where entry.district <> ''
            ) districts
          ),
          '[]'::jsonb
        )
    ),
    'summary', jsonb_build_object(
      'totalRecords', (select count(*) from directory),
      'verifiedShareholders',
        (
          select count(*)
          from directory entry
          where entry.verification_status in (
            'verified_shareholder',
            'verified_shareholder_override'
          )
        ),
      'adminPromotedWithoutKyc',
        (
          select count(*)
          from directory entry
          where entry.verification_status = 'verified_shareholder_override'
        ),
      'candidateRecords',
        (
          select count(*)
          from directory entry
          where entry.directory_source = 'candidate_roster'
        ),
      'verifiedFarmers',
        (
          select count(*)
          from directory entry
          where entry.directory_source = 'candidate_roster'
            and entry.farmer_status = 'verified'
        ),
      'pendingVerification',
        (
          select count(*)
          from directory entry
          where entry.directory_source = 'candidate_roster'
            and entry.farmer_status = 'unverified'
        ),
      'pendingKyc',
        (
          select count(*)
          from public.shareholder_candidate_roster candidate
          where candidate.kyc_verified_at is null
        ),
      'allottedShares',
        (
          select coalesce(sum(entry.proposed_share_count), 0)
          from directory entry
          where entry.share_status = 'allotted'
        ),
      'proposedShares',
        (
          select coalesce(sum(entry.proposed_share_count), 0)
          from directory entry
          where entry.share_status = 'proposed'
        ),
      'totalShares',
        (
          select coalesce(sum(entry.proposed_share_count), 0)
          from directory entry
        ),
      'proposedCapital',
        (
          select coalesce(sum(entry.proposed_total_amount), 0)
          from directory entry
          where entry.amount_recorded
        )
    )
  )
  into v_result;

  return v_result;
end;
$$;

comment on function public.admin_shareholder_directory(
  text,
  text,
  text,
  text,
  integer,
  integer
) is
  'Admin-only merged directory for verified shareholder-register rows and unverified electoral-roll candidates.';

revoke all on function public.admin_shareholder_directory(
  text,
  text,
  text,
  text,
  integer,
  integer
) from public, anon;
grant execute on function public.admin_shareholder_directory(
  text,
  text,
  text,
  text,
  integer,
  integer
) to authenticated;
