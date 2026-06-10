alter table if exists public.farmer_ai_plans
  alter column provider drop default,
  alter column model drop default,
  alter column used_fallback set default false,
  alter column used_ai set default true;
