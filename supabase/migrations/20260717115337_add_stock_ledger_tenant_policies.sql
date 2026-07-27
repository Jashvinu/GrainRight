create policy "tenant read"
on public.stock_ledger for select to authenticated
using (private.can_access_fpc(fpc_id));

create policy "fpc admin insert"
on public.stock_ledger for insert to authenticated
with check (private.can_manage_fpc(fpc_id));
