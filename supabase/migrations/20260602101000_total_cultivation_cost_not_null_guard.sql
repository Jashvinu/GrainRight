alter table public.farmer_surveys
  add column if not exists total_cultivation_cost numeric;

update public.farmer_surveys
set total_cultivation_cost = 0
where total_cultivation_cost is null;

alter table public.farmer_surveys
  alter column total_cultivation_cost set default 0;

alter table public.farmer_surveys
  alter column total_cultivation_cost set not null;

create or replace function public.set_farmer_survey_total_cultivation_cost_default()
returns trigger
language plpgsql
as $$
begin
  new.total_cultivation_cost := coalesce(new.total_cultivation_cost, 0);
  return new;
end;
$$;

drop trigger if exists farmer_surveys_total_cultivation_cost_default
  on public.farmer_surveys;

create trigger farmer_surveys_total_cultivation_cost_default
before insert or update of total_cultivation_cost
on public.farmer_surveys
for each row
execute function public.set_farmer_survey_total_cultivation_cost_default();

notify pgrst, 'reload schema';
