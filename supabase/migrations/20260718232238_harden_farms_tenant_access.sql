-- Remove legacy permissive farm policies that bypass farmer ownership and FPC tenancy.
drop policy if exists "Allow public insert to farms" on public.farms;
drop policy if exists "Allow public read access to farms" on public.farms;
drop policy if exists "Allow public update to farms" on public.farms;
drop policy if exists "Enable delete for authenticated users" on public.farms;
drop policy if exists "Enable insert for authenticated users" on public.farms;
drop policy if exists "Enable read access for all users" on public.farms;
drop policy if exists "Enable update for authenticated users" on public.farms;
drop policy if exists "Users can delete their own farms" on public.farms;
drop policy if exists "Users can insert farms" on public.farms;
drop policy if exists "Users can update their own farms" on public.farms;
drop policy if exists "Users can view farms" on public.farms;

revoke all on table public.farms from anon;
revoke all on table public.farms from authenticated;
grant select, insert, update, delete on table public.farms to authenticated;

-- The retained policies are intentionally limited to:
-- 1. the authenticated farmer who owns the row,
-- 2. an active FPC Admin linked through fpc_farmer_links, or
-- 3. a Field Officer assigned to the farm.
