alter policy "fpc admins read operating clusters"
on public.fpc_operating_clusters
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and private.can_manage_fpc(fpc_id)
);

alter policy "fpc admins create operating clusters"
on public.fpc_operating_clusters
with check (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and private.can_manage_fpc(fpc_id)
  and created_by = (select auth.uid())
);

alter policy "fpc admins update operating clusters"
on public.fpc_operating_clusters
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and private.can_manage_fpc(fpc_id)
)
with check (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and private.can_manage_fpc(fpc_id)
);

alter policy "fpc admins delete operating clusters"
on public.fpc_operating_clusters
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and private.can_manage_fpc(fpc_id)
);
