-- Farmer-initiated FPC seed requests, connected to the existing crop-program,
-- Field Officer delivery, acknowledgement, dashboard, and audit contracts.

create table public.fpc_seed_requests (
  id uuid primary key default gen_random_uuid(),
  fpc_id uuid not null references public.fpcs(id) on delete cascade,
  program_id uuid not null references public.fpc_crop_programs(id) on delete restrict,
  farmer_link_id uuid not null references public.fpc_farmer_links(id) on delete restrict,
  farmer_user_id uuid not null references auth.users(id) on delete restrict,
  farmer_id text not null,
  farm_id uuid not null references public.farms(id) on delete restrict,
  requested_quantity_kg numeric(14,3) not null check (requested_quantity_kg > 0),
  preferred_delivery_at timestamptz,
  farmer_note text not null default '',
  status text not null default 'submitted'
    check (status in (
      'submitted', 'approved', 'declined', 'cancelled',
      'seed_issued', 'delivered', 'acknowledged'
    )),
  response_note text not null default '',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  enrollment_id uuid unique
    references public.fpc_program_enrollments(id) on delete set null,
  client_request_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (farmer_user_id, client_request_id)
);

create unique index fpc_seed_requests_active_program_farm_idx
  on public.fpc_seed_requests(program_id, farm_id)
  where status in ('submitted', 'approved', 'seed_issued', 'delivered');

create index fpc_seed_requests_fpc_status_idx
  on public.fpc_seed_requests(fpc_id, status, updated_at desc);

create index fpc_seed_requests_farmer_farm_idx
  on public.fpc_seed_requests(farmer_user_id, farm_id, created_at desc);

alter table public.fpc_seed_requests enable row level security;

grant select on public.fpc_seed_requests to authenticated;
grant select, insert, update, delete on public.fpc_seed_requests to service_role;
revoke insert, update, delete on public.fpc_seed_requests from anon, authenticated;

create policy "seed requests related read"
on public.fpc_seed_requests for select to authenticated
using (
  farmer_user_id = (select auth.uid())
  or private.can_manage_fpc(fpc_id)
);

drop trigger if exists set_fpc_seed_requests_updated_at
  on public.fpc_seed_requests;
create trigger set_fpc_seed_requests_updated_at
before update on public.fpc_seed_requests
for each row execute function public.set_updated_at();

create or replace function private.request_program_seed(
  target_farm_id uuid,
  target_program_id uuid,
  requested_quantity_kg numeric,
  farmer_note text,
  preferred_delivery_at timestamptz,
  request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  farm_row public.farms;
  program_row public.fpc_crop_programs;
  link_row public.fpc_farmer_links;
  saved public.fpc_seed_requests;
  existing public.fpc_seed_requests;
begin
  if actor_id is null then raise exception 'Login required'; end if;
  if exists (
    select 1
    from auth.users user_account
    where user_account.id = actor_id
      and user_account.is_anonymous
  ) then
    raise exception 'A permanent Farmer account is required';
  end if;
  if target_farm_id is null or target_program_id is null then
    raise exception 'Farm and crop program are required';
  end if;
  if requested_quantity_kg is null or requested_quantity_kg <= 0 then
    raise exception 'Requested seed quantity must be greater than zero';
  end if;
  if request_id is null then raise exception 'Request ID is required'; end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'farmer-seed-request:' || actor_id::text || ':' ||
      target_farm_id::text || ':' || target_program_id::text,
      0
    )
  );

  select * into existing
  from public.fpc_seed_requests request_row
  where request_row.farmer_user_id = actor_id
    and request_row.client_request_id = request_id;
  if existing.id is not null then return to_jsonb(existing); end if;

  select * into farm_row
  from public.farms farm
  where farm.id = target_farm_id
    and farm.user_id = actor_id;
  if farm_row.id is null then raise exception 'Farmer farm not found'; end if;

  select program.* into program_row
  from public.fpc_crop_programs program
  join public.fpcs fpc
    on fpc.id = program.fpc_id
   and fpc.status = 'active'
  where program.id = target_program_id
    and program.status = 'active';
  if program_row.id is null then raise exception 'Active FPC crop program not found'; end if;

  select link.* into link_row
  from public.fpc_farmer_links link
  where link.fpc_id = program_row.fpc_id
    and link.farm_id = target_farm_id::text
    and link.status = 'active'
    and lower(coalesce(nullif(farm_row.crop, ''), link.crop, '')) =
        lower(program_row.crop)
  order by link.updated_at desc
  limit 1;
  if link_row.id is null then
    raise exception 'This farm is not actively linked to the selected FPC crop program';
  end if;
  if exists (
    select 1
    from public.fpc_program_enrollments enrollment
    where enrollment.program_id = target_program_id
      and enrollment.farm_id = target_farm_id
  ) then
    raise exception 'This farm is already enrolled in the selected crop program';
  end if;

  select * into existing
  from public.fpc_seed_requests request_row
  where request_row.program_id = target_program_id
    and request_row.farm_id = target_farm_id
    and request_row.status in ('submitted', 'approved', 'seed_issued', 'delivered')
  limit 1;
  if existing.id is not null then
    raise exception 'An active seed request already exists for this farm and program';
  end if;

  insert into public.fpc_seed_requests(
    fpc_id, program_id, farmer_link_id, farmer_user_id, farmer_id, farm_id,
    requested_quantity_kg, preferred_delivery_at, farmer_note, client_request_id
  ) values (
    program_row.fpc_id, program_row.id, link_row.id, actor_id,
    link_row.farmer_id, farm_row.id, requested_quantity_kg,
    preferred_delivery_at, coalesce(farmer_note, ''), request_id
  )
  returning * into saved;

  insert into public.fpc_notifications(
    fpc_id, recipient_user_id, event_key, title, body, data
  )
  select
    saved.fpc_id,
    membership.user_id,
    'farmer_seed_request',
    'New Farmer seed request',
    coalesce(nullif(link_row.farmer_name, ''), link_row.farmer_id) ||
      ' requested ' || trim(to_char(saved.requested_quantity_kg, 'FM999999990.000')) ||
      ' kg of ' || program_row.crop || ' seed.',
    jsonb_build_object(
      'seed_request_id', saved.id,
      'program_id', saved.program_id,
      'farm_id', saved.farm_id,
      'farmer_id', saved.farmer_id
    )
  from public.fpc_memberships membership
  where membership.fpc_id = saved.fpc_id
    and membership.role = 'fpc_admin'
    and membership.status = 'active';

  return to_jsonb(saved) || jsonb_build_object(
    'program', to_jsonb(program_row),
    'fpc', (
      select jsonb_build_object('id', fpc.id, 'name', fpc.name)
      from public.fpcs fpc
      where fpc.id = saved.fpc_id
    )
  );
end;
$$;

create or replace function public.farmer_request_program_seed(
  p_farm_id uuid,
  p_program_id uuid,
  p_quantity_kg numeric,
  p_farmer_note text default '',
  p_preferred_delivery_at timestamptz default null,
  p_client_request_id uuid default gen_random_uuid()
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.request_program_seed(
    p_farm_id,
    p_program_id,
    p_quantity_kg,
    p_farmer_note,
    p_preferred_delivery_at,
    p_client_request_id
  );
$$;

create or replace function private.execute_seed_request_operation(
  operation_name text,
  payload jsonb,
  request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  target_fpc_id uuid;
  existing_response jsonb;
  saved public.fpc_seed_requests;
  request_row public.fpc_seed_requests;
  program_row public.fpc_crop_programs;
  link_row public.fpc_farmer_links;
  farm_row public.farms;
  enrollment_row public.fpc_program_enrollments;
  checkpoint jsonb;
  checkpoint_id uuid;
  sequence_value integer := 0;
  assigned_officer_id uuid;
  result jsonb;
begin
  if actor_id is null then raise exception 'Login required'; end if;
  select membership.fpc_id into target_fpc_id
  from public.fpc_memberships membership
  join public.fpcs fpc
    on fpc.id = membership.fpc_id
   and fpc.status = 'active'
  where membership.user_id = actor_id
    and membership.role = 'fpc_admin'
    and membership.status = 'active'
  limit 1;
  if target_fpc_id is null then
    raise exception 'Active FPC Admin membership required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'seed-request-operation:' || target_fpc_id::text || ':' || request_id::text,
      0
    )
  );
  perform pg_advisory_xact_lock(
    hashtextextended('fpc-operation:' || target_fpc_id::text, 0)
  );

  select operation_request.response into existing_response
  from private.fpc_operation_requests operation_request
  where operation_request.fpc_id = target_fpc_id
    and operation_request.client_request_id = request_id;
  if existing_response is not null then return existing_response; end if;

  select * into request_row
  from public.fpc_seed_requests seed_request
  where seed_request.id = (payload->>'seed_request_id')::uuid
    and seed_request.fpc_id = target_fpc_id
  for update;
  if request_row.id is null then raise exception 'Seed request not found'; end if;
  if request_row.status <> 'submitted' then
    raise exception 'Only a submitted seed request can be reviewed';
  end if;

  perform set_config('app.fpc_operation', '1', true);

  if operation_name = 'approve_seed_request' then
    assigned_officer_id := nullif(payload->>'assigned_officer_id', '')::uuid;
    if assigned_officer_id is null then
      raise exception 'A Field Officer is required for seed delivery and tracking';
    end if;
    if not exists (
      select 1
      from public.fpc_memberships membership
      where membership.fpc_id = target_fpc_id
        and membership.user_id = assigned_officer_id
        and membership.role = 'field_officer'
        and membership.status = 'active'
    ) then
      raise exception 'Assigned Field Officer is not active in this FPC';
    end if;

    select * into program_row
    from public.fpc_crop_programs program
    where program.id = request_row.program_id
      and program.fpc_id = target_fpc_id
      and program.status = 'active';
    if program_row.id is null then raise exception 'Active crop program not found'; end if;

    select * into link_row
    from public.fpc_farmer_links link
    where link.id = request_row.farmer_link_id
      and link.fpc_id = target_fpc_id
      and link.status = 'active';
    if link_row.id is null then raise exception 'Active linked farmer not found'; end if;

    select * into farm_row
    from public.farms farm
    where farm.id = request_row.farm_id
      and farm.user_id = request_row.farmer_user_id;
    if farm_row.id is null then raise exception 'Linked farmer farm is not available'; end if;
    if lower(coalesce(nullif(farm_row.crop, ''), link_row.crop, '')) <>
        lower(program_row.crop) then
      raise exception 'Program crop does not match the linked farm crop';
    end if;

    insert into public.fpc_program_enrollments(
      fpc_id, program_id, farmer_link_id, farmer_user_id, farmer_id, farm_id,
      crop, variety, policy_version, policy_snapshot, checkpoint_snapshot,
      price_formula_snapshot, assigned_officer_id, created_by
    ) values (
      target_fpc_id, program_row.id, link_row.id, farm_row.user_id,
      link_row.farmer_id, farm_row.id, program_row.crop, program_row.variety,
      program_row.policy_version, program_row.policy_rules,
      program_row.required_checkpoints, program_row.price_formula,
      assigned_officer_id, actor_id
    )
    returning * into enrollment_row;

    for checkpoint in
      select value
      from jsonb_array_elements(program_row.required_checkpoints)
    loop
      sequence_value := sequence_value + 1;
      insert into public.fpc_program_checks(
        fpc_id, enrollment_id, checkpoint_code, checkpoint_name, sequence, required
      ) values (
        target_fpc_id,
        enrollment_row.id,
        coalesce(nullif(checkpoint->>'code', ''), 'checkpoint_' || sequence_value),
        coalesce(nullif(checkpoint->>'name', ''), 'Checkpoint ' || sequence_value),
        sequence_value,
        coalesce((checkpoint->>'required')::boolean, true)
      )
      returning id into checkpoint_id;

      insert into public.field_assignments(
        fpc_id, officer_user_id, assignment_type, farmer_id, farm_id,
        title, instructions, scheduled_for, created_by,
        crop_program_enrollment_id, crop_program_check_id
      ) values (
        target_fpc_id,
        assigned_officer_id,
        'crop_program_check',
        enrollment_row.farmer_id,
        enrollment_row.farm_id::text,
        'Verify ' || coalesce(nullif(checkpoint->>'name', ''), 'crop checkpoint'),
        coalesce(
          checkpoint->>'instructions',
          'Verify the crop stage and attach field evidence.'
        ),
        nullif(checkpoint->>'scheduled_for', '')::timestamptz,
        actor_id,
        enrollment_row.id,
        checkpoint_id
      );
    end loop;

    update public.fpc_seed_requests
    set status = 'approved',
        response_note = coalesce(payload->>'response_note', ''),
        reviewed_by = actor_id,
        reviewed_at = now(),
        enrollment_id = enrollment_row.id,
        updated_at = now()
    where id = request_row.id
    returning * into saved;

    insert into public.farmer_notifications(
      recipient_user_id, farmer_id, farm_id, farm_name, type,
      title, message, dedupe_key, action_route, payload
    ) values (
      saved.farmer_user_id,
      saved.farmer_id,
      saved.farm_id,
      link_row.farm_name,
      'fpc_seed_request_approved',
      'FPC seed request approved',
      'Accept the crop-program policy so the FPC can schedule your seed delivery.',
      'fpc-seed-request-approved:' || saved.id::text,
      '/farmer',
      jsonb_build_object(
        'seed_request_id', saved.id,
        'enrollment_id', enrollment_row.id,
        'program_id', saved.program_id
      )
    )
    on conflict (recipient_user_id, dedupe_key)
      where recipient_user_id is not null and dedupe_key is not null
    do nothing;

    result := to_jsonb(saved) || jsonb_build_object(
      'enrollment', to_jsonb(enrollment_row)
    );

  elsif operation_name = 'decline_seed_request' then
    update public.fpc_seed_requests
    set status = 'declined',
        response_note = coalesce(
          nullif(payload->>'response_note', ''),
          'The FPC cannot fulfil this seed request.'
        ),
        reviewed_by = actor_id,
        reviewed_at = now(),
        updated_at = now()
    where id = request_row.id
    returning * into saved;

    insert into public.farmer_notifications(
      recipient_user_id, farmer_id, farm_id, type,
      title, message, dedupe_key, action_route, payload
    ) values (
      saved.farmer_user_id,
      saved.farmer_id,
      saved.farm_id,
      'fpc_seed_request_declined',
      'FPC seed request update',
      saved.response_note,
      'fpc-seed-request-declined:' || saved.id::text,
      '/farmer',
      jsonb_build_object('seed_request_id', saved.id)
    )
    on conflict (recipient_user_id, dedupe_key)
      where recipient_user_id is not null and dedupe_key is not null
    do nothing;

    result := to_jsonb(saved);
  else
    raise exception 'Unsupported seed request operation: %', operation_name;
  end if;

  perform private.record_fpc_audit(
    target_fpc_id,
    operation_name,
    'seed_request',
    request_row.id::text,
    to_jsonb(request_row),
    result,
    request_id
  );

  insert into private.fpc_operation_requests(
    fpc_id, client_request_id, operation, response
  ) values (
    target_fpc_id, request_id, operation_name, result
  );

  return result;
end;
$$;

create or replace function public.fpc_execute_operation(
  operation_name text,
  payload jsonb default '{}'::jsonb,
  client_request_id uuid default gen_random_uuid()
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select case
    when operation_name in (
      'approve_seed_request', 'decline_seed_request'
    ) then private.execute_seed_request_operation(
      operation_name,
      payload,
      client_request_id
    )
    when operation_name in (
      'create_crop_program', 'activate_crop_program', 'register_seed_batch',
      'enroll_farmer_program', 'issue_program_seed',
      'review_program_compliance', 'release_program_enrollment'
    ) then private.execute_crop_program_operation(
      operation_name,
      payload,
      client_request_id
    )
    else private.execute_fpc_operation(
      operation_name,
      payload,
      client_request_id
    )
  end;
$$;

create or replace function private.sync_seed_request_delivery_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.fpc_seed_requests
  set status = case new.status
        when 'issued' then 'seed_issued'
        when 'delivered' then 'delivered'
        when 'acknowledged' then 'acknowledged'
        else status
      end,
      updated_at = now()
  where enrollment_id = new.enrollment_id
    and status not in ('declined', 'cancelled', 'acknowledged');
  return new;
end;
$$;

drop trigger if exists sync_seed_request_delivery_status
  on public.fpc_seed_issues;
create trigger sync_seed_request_delivery_status
after insert or update of status on public.fpc_seed_issues
for each row execute function private.sync_seed_request_delivery_status();

create or replace function public.farmer_crop_program_for_farm(p_farm_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := (select auth.uid());
  farm_row public.farms;
  enrollment public.fpc_program_enrollments;
  seed_request public.fpc_seed_requests;
  context_fpc_id uuid;
begin
  if actor_id is null then raise exception 'Login required'; end if;
  select * into farm_row
  from public.farms farm
  where farm.id = p_farm_id
    and farm.user_id = actor_id;
  if farm_row.id is null then raise exception 'Farmer farm not found'; end if;

  select * into enrollment
  from public.fpc_program_enrollments enrollment_row
  where enrollment_row.farm_id = p_farm_id
    and enrollment_row.farmer_user_id = actor_id
  order by enrollment_row.created_at desc
  limit 1;
  if enrollment.id is not null then
    enrollment := private.refresh_crop_program_release(enrollment.id);
  end if;

  select * into seed_request
  from public.fpc_seed_requests request_row
  where request_row.farm_id = p_farm_id
    and request_row.farmer_user_id = actor_id
  order by request_row.created_at desc
  limit 1;

  context_fpc_id := coalesce(enrollment.fpc_id, seed_request.fpc_id);

  return jsonb_build_object(
    'enrollment', case
      when enrollment.id is null then null
      else to_jsonb(enrollment)
    end,
    'program', case
      when enrollment.id is null then null
      else (
        select to_jsonb(program)
        from public.fpc_crop_programs program
        where program.id = enrollment.program_id
      )
    end,
    'fpc', case
      when context_fpc_id is null then null
      else (
        select jsonb_build_object('id', fpc.id, 'name', fpc.name)
        from public.fpcs fpc
        where fpc.id = context_fpc_id
      )
    end,
    'seed_request', case
      when seed_request.id is null then null
      else to_jsonb(seed_request) || jsonb_build_object(
        'program', (
          select to_jsonb(program)
          from public.fpc_crop_programs program
          where program.id = seed_request.program_id
        ),
        'fpc', (
          select jsonb_build_object('id', fpc.id, 'name', fpc.name)
          from public.fpcs fpc
          where fpc.id = seed_request.fpc_id
        ),
        'enrollment_status', (
          select enrollment_row.status
          from public.fpc_program_enrollments enrollment_row
          where enrollment_row.id = seed_request.enrollment_id
        )
      )
    end,
    'available_programs', coalesce((
      select jsonb_agg(
        to_jsonb(program)
        || jsonb_build_object('fpc_name', fpc.name)
        order by program.created_at desc
      )
      from public.fpc_crop_programs program
      join public.fpcs fpc
        on fpc.id = program.fpc_id
       and fpc.status = 'active'
      join public.fpc_farmer_links link
        on link.fpc_id = program.fpc_id
       and link.farm_id = p_farm_id::text
       and link.status = 'active'
      where program.status = 'active'
        and lower(program.crop) =
            lower(coalesce(nullif(farm_row.crop, ''), link.crop, ''))
    ), '[]'::jsonb),
    'seed_issue', case
      when enrollment.id is null then null
      else (
        select to_jsonb(issue) || jsonb_build_object(
          'seed_batch', (
            select to_jsonb(batch)
            from public.fpc_seed_batches batch
            where batch.id = issue.seed_batch_id
          )
        )
        from public.fpc_seed_issues issue
        where issue.enrollment_id = enrollment.id
        order by issue.created_at desc
        limit 1
      )
    end,
    'checks', case
      when enrollment.id is null then '[]'::jsonb
      else coalesce((
        select jsonb_agg(to_jsonb(check_row) order by check_row.sequence)
        from public.fpc_program_checks check_row
        where check_row.enrollment_id = enrollment.id
      ), '[]'::jsonb)
    end,
    'evaluations', case
      when enrollment.id is null then '[]'::jsonb
      else coalesce((
        select jsonb_agg(to_jsonb(evaluation) order by evaluation.attempt_no desc)
        from public.fpc_compliance_evaluations evaluation
        where evaluation.enrollment_id = enrollment.id
      ), '[]'::jsonb)
    end
  );
end;
$$;

create or replace function public.fpc_workspace_dashboard_snapshot(
  p_cluster_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_snapshot jsonb;
  target_fpc_id uuid;
  seed_summary jsonb;
begin
  base_snapshot := public.fpc_procurement_dashboard_snapshot(p_cluster_id);

  select membership.fpc_id into target_fpc_id
  from public.fpc_memberships membership
  join public.fpcs fpc
    on fpc.id = membership.fpc_id
   and fpc.status = 'active'
  where membership.user_id = (select auth.uid())
    and membership.role = 'fpc_admin'
    and membership.status = 'active'
  limit 1;
  if target_fpc_id is null then
    raise exception 'Active FPC Admin membership required';
  end if;

  select jsonb_build_object(
    'total', count(*),
    'submitted', count(*) filter (where request.status = 'submitted'),
    'awaiting_farmer', count(*) filter (
      where request.status = 'approved'
        and enrollment.status = 'pending_farmer_acceptance'
    ),
    'ready_to_issue', count(*) filter (
      where request.status = 'approved'
        and enrollment.status = 'accepted'
    ),
    'in_delivery', count(*) filter (
      where request.status in ('seed_issued', 'delivered')
    ),
    'completed', count(*) filter (where request.status = 'acknowledged')
  )
  into seed_summary
  from public.fpc_seed_requests request
  left join public.fpc_program_enrollments enrollment
    on enrollment.id = request.enrollment_id
  where request.fpc_id = target_fpc_id
    and request.status <> 'cancelled';

  return base_snapshot || jsonb_build_object(
    'seed_requests',
    coalesce(seed_summary, '{}'::jsonb)
  );
end;
$$;

revoke all on function private.request_program_seed(
  uuid, uuid, numeric, text, timestamptz, uuid
) from public, anon;
revoke all on function private.execute_seed_request_operation(text,jsonb,uuid)
  from public, anon, authenticated;
revoke all on function private.sync_seed_request_delivery_status()
  from public, anon, authenticated;

revoke all on function public.farmer_request_program_seed(
  uuid, uuid, numeric, text, timestamptz, uuid
) from public, anon;
revoke all on function public.fpc_execute_operation(text,jsonb,uuid)
  from public, anon;
revoke all on function public.farmer_crop_program_for_farm(uuid)
  from public, anon;
revoke all on function public.fpc_workspace_dashboard_snapshot(uuid)
  from public, anon;

grant execute on function private.request_program_seed(
  uuid, uuid, numeric, text, timestamptz, uuid
) to authenticated;
grant execute on function public.farmer_request_program_seed(
  uuid, uuid, numeric, text, timestamptz, uuid
) to authenticated;
grant execute on function public.fpc_execute_operation(text,jsonb,uuid)
  to authenticated;
grant execute on function public.farmer_crop_program_for_farm(uuid)
  to authenticated;
grant execute on function public.fpc_workspace_dashboard_snapshot(uuid)
  to authenticated;

comment on table public.fpc_seed_requests is
  'Farmer seed demand tracked through FPC review, crop-program enrollment, Field Officer delivery, and farmer acknowledgement.';
