-- Normalize grade labels case-insensitively without duplicating the large
-- tenant-scoped snapshot query. The raw security-invoker function remains in
-- the private schema; this public wrapper only normalizes its JSON contract.

alter function public.fpc_procurement_dashboard_snapshot(uuid)
set schema private;

alter function private.fpc_procurement_dashboard_snapshot(uuid)
rename to fpc_procurement_dashboard_snapshot_raw;

create or replace function private.normalize_fpc_dashboard_grade(p_grade text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when nullif(btrim(coalesce(p_grade, '')), '') is null
      or lower(btrim(p_grade)) = 'not graded'
      then 'Not graded'
    when regexp_replace(lower(p_grade), '[^a-z0-9]+', '', 'g')
      in ('a', 'gradea', 'premium', 'premiumgrade')
      then 'Grade A'
    when regexp_replace(lower(p_grade), '[^a-z0-9]+', '', 'g')
      in ('b', 'gradeb', 'standard', 'standardgrade')
      then 'Grade B'
    when regexp_replace(lower(p_grade), '[^a-z0-9]+', '', 'g')
      in ('c', 'gradec', 'commercial', 'commercialgrade')
      then 'Grade C'
    else btrim(p_grade)
  end;
$$;

create or replace function public.fpc_procurement_dashboard_snapshot(
  p_cluster_id uuid default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_payload jsonb;
  v_farms jsonb;
  v_grade_mix jsonb;
begin
  v_payload :=
    private.fpc_procurement_dashboard_snapshot_raw(p_cluster_id);

  select coalesce(
    jsonb_agg(
      jsonb_set(
        farm,
        '{latest_grade}',
        to_jsonb(
          private.normalize_fpc_dashboard_grade(farm ->> 'latest_grade')
        ),
        true
      )
    ),
    '[]'::jsonb
  )
  into v_farms
  from jsonb_array_elements(coalesce(v_payload -> 'farms', '[]'::jsonb))
    as farm;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'grade', mix.grade,
        'count', mix.grade_count
      )
      order by
        case mix.grade
          when 'Grade A' then 1
          when 'Grade B' then 2
          when 'Grade C' then 3
          when 'Not graded' then 99
          else 50
        end,
        mix.grade
    ),
    '[]'::jsonb
  )
  into v_grade_mix
  from (
    select
      private.normalize_fpc_dashboard_grade(item ->> 'grade') as grade,
      sum((item ->> 'count')::integer)::integer as grade_count
    from jsonb_array_elements(
      coalesce(v_payload #> '{summary,grade_mix}', '[]'::jsonb)
    ) as item
    group by private.normalize_fpc_dashboard_grade(item ->> 'grade')
  ) mix;

  v_payload := jsonb_set(v_payload, '{farms}', v_farms, true);
  v_payload := jsonb_set(
    v_payload,
    '{summary,grade_mix}',
    v_grade_mix,
    true
  );
  return v_payload;
end;
$$;

comment on function public.fpc_procurement_dashboard_snapshot(uuid) is
'Returns the tenant-scoped live procurement dashboard with normalized verified grade labels.';

revoke all on function private.fpc_procurement_dashboard_snapshot_raw(uuid)
from public;
revoke all on function private.fpc_procurement_dashboard_snapshot_raw(uuid)
from anon;
grant execute
on function private.fpc_procurement_dashboard_snapshot_raw(uuid)
to authenticated;

revoke all on function private.normalize_fpc_dashboard_grade(text)
from public;
revoke all on function private.normalize_fpc_dashboard_grade(text)
from anon;
grant execute
on function private.normalize_fpc_dashboard_grade(text)
to authenticated;

revoke all on function public.fpc_procurement_dashboard_snapshot(uuid)
from public;
revoke all on function public.fpc_procurement_dashboard_snapshot(uuid)
from anon;
grant execute on function public.fpc_procurement_dashboard_snapshot(uuid)
to authenticated;
