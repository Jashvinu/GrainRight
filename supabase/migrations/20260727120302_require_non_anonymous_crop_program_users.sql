create or replace function private.guard_crop_program_farmer_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from auth.users user_account
    where user_account.id = new.farmer_user_id
      and coalesce(user_account.is_anonymous, false) = false
  ) then
    raise exception
      'Crop programs require a verified non-anonymous farmer login';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_crop_program_farmer_identity
  on public.fpc_program_enrollments;
create trigger guard_crop_program_farmer_identity
before insert or update of farmer_user_id
on public.fpc_program_enrollments
for each row execute function private.guard_crop_program_farmer_identity();

create or replace function private.can_read_crop_program_enrollment(
  target_enrollment_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
    and exists (
      select 1
      from public.fpc_program_enrollments enrollment
      where enrollment.id = target_enrollment_id
        and (
          enrollment.farmer_user_id = (select auth.uid())
          or private.can_manage_fpc(enrollment.fpc_id)
          or exists (
            select 1
            from public.field_assignments assignment
            where assignment.crop_program_enrollment_id = enrollment.id
              and assignment.officer_user_id = (select auth.uid())
              and assignment.status <> 'cancelled'
          )
        )
    );
$$;

drop policy if exists "crop programs related read"
  on public.fpc_crop_programs;
create policy "crop programs related read"
on public.fpc_crop_programs for select to authenticated
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and (
    private.can_manage_fpc(fpc_id)
    or exists (
      select 1
      from public.fpc_program_enrollments enrollment
      where enrollment.program_id = fpc_crop_programs.id
        and private.can_read_crop_program_enrollment(enrollment.id)
    )
  )
);

drop policy if exists "seed batches related read"
  on public.fpc_seed_batches;
create policy "seed batches related read"
on public.fpc_seed_batches for select to authenticated
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and (
    private.can_manage_fpc(fpc_id)
    or exists (
      select 1
      from public.fpc_seed_issues issue
      where issue.seed_batch_id = fpc_seed_batches.id
        and private.can_read_crop_program_enrollment(issue.enrollment_id)
    )
  )
);

drop policy if exists "program enrollments related read"
  on public.fpc_program_enrollments;
create policy "program enrollments related read"
on public.fpc_program_enrollments for select to authenticated
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and private.can_read_crop_program_enrollment(id)
);

drop policy if exists "seed issues related read"
  on public.fpc_seed_issues;
create policy "seed issues related read"
on public.fpc_seed_issues for select to authenticated
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and private.can_read_crop_program_enrollment(enrollment_id)
);

drop policy if exists "program checks related read"
  on public.fpc_program_checks;
create policy "program checks related read"
on public.fpc_program_checks for select to authenticated
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and private.can_read_crop_program_enrollment(enrollment_id)
);

drop policy if exists "compliance evaluations related read"
  on public.fpc_compliance_evaluations;
create policy "compliance evaluations related read"
on public.fpc_compliance_evaluations for select to authenticated
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and private.can_read_crop_program_enrollment(enrollment_id)
);

revoke all on function private.guard_crop_program_farmer_identity()
  from public, anon, authenticated;
