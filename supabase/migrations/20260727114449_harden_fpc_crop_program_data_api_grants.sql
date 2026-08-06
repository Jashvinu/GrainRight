-- Supabase default table privileges can include writes for authenticated.
-- Crop-program changes must go only through the audited SECURITY DEFINER RPCs.

revoke all on
  public.fpc_crop_programs,
  public.fpc_seed_batches,
  public.fpc_program_enrollments,
  public.fpc_seed_issues,
  public.fpc_program_checks,
  public.fpc_compliance_evaluations
from anon, authenticated;

grant select on
  public.fpc_crop_programs,
  public.fpc_seed_batches,
  public.fpc_program_enrollments,
  public.fpc_seed_issues,
  public.fpc_program_checks,
  public.fpc_compliance_evaluations
to authenticated;

revoke all on
  public.fpc_crop_programs,
  public.fpc_seed_batches,
  public.fpc_program_enrollments,
  public.fpc_seed_issues,
  public.fpc_program_checks,
  public.fpc_compliance_evaluations
from service_role;

grant select, insert, update on
  public.fpc_crop_programs,
  public.fpc_seed_batches,
  public.fpc_program_enrollments,
  public.fpc_seed_issues,
  public.fpc_program_checks,
  public.fpc_compliance_evaluations
to service_role;
