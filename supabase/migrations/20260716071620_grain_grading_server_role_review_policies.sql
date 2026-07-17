drop policy if exists "fpo admins can read grading review jobs"
  on public.analysis_jobs;

create policy "fpo admins can read grading review jobs"
on public.analysis_jobs for select
to authenticated
using (
  public.has_server_role(
    array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc']
  )
);

drop policy if exists "fpo admins can update grading review jobs"
  on public.analysis_jobs;

create policy "fpo admins can update grading review jobs"
on public.analysis_jobs for update
to authenticated
using (
  public.has_server_role(
    array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc']
  )
)
with check (
  public.has_server_role(
    array['admin', 'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc']
  )
);
