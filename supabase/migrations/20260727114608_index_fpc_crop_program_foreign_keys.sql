create index fpc_crop_programs_created_by_idx
  on public.fpc_crop_programs(created_by);
create index fpc_seed_batches_created_by_idx
  on public.fpc_seed_batches(created_by);
create index fpc_program_enrollments_farm_idx
  on public.fpc_program_enrollments(farm_id);
create index fpc_program_enrollments_officer_idx
  on public.fpc_program_enrollments(assigned_officer_id)
  where assigned_officer_id is not null;
create index fpc_program_enrollments_created_by_idx
  on public.fpc_program_enrollments(created_by);
create index fpc_seed_issues_officer_idx
  on public.fpc_seed_issues(assigned_officer_id)
  where assigned_officer_id is not null;
create index fpc_seed_issues_acknowledged_by_idx
  on public.fpc_seed_issues(acknowledged_by)
  where acknowledged_by is not null;
create index fpc_seed_issues_created_by_idx
  on public.fpc_seed_issues(created_by);
create index fpc_program_checks_fpc_idx
  on public.fpc_program_checks(fpc_id);
create index fpc_compliance_fpc_idx
  on public.fpc_compliance_evaluations(fpc_id);
create index fpc_compliance_decided_by_idx
  on public.fpc_compliance_evaluations(decided_by)
  where decided_by is not null;
