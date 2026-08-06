-- Harden the deployed Farmer seed request contract.
alter policy "seed requests related read"
on public.fpc_seed_requests
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and (
    farmer_user_id = (select auth.uid())
    or private.can_manage_fpc(fpc_id)
  )
);

create index fpc_seed_requests_farm_id_idx
  on public.fpc_seed_requests(farm_id);

create index fpc_seed_requests_farmer_link_id_idx
  on public.fpc_seed_requests(farmer_link_id);

create index fpc_seed_requests_reviewed_by_idx
  on public.fpc_seed_requests(reviewed_by)
  where reviewed_by is not null;

alter function public.fpc_workspace_dashboard_snapshot(uuid)
  security invoker;
