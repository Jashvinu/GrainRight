create table if not exists public.apmc_market_rates (
  id uuid primary key default gen_random_uuid(),
  market_key text not null,
  market_name text not null,
  crop text not null,
  min_rate numeric(10, 2) not null,
  modal_rate numeric(10, 2) not null,
  max_rate numeric(10, 2) not null,
  arrival_qty numeric(10, 2) not null default 0,
  demand text not null default 'Stable',
  trend numeric(6, 2) not null default 0,
  distance_km numeric(8, 2) not null default 0,
  note text not null default '',
  active boolean not null default true,
  rate_date date not null default current_date,
  updated_at timestamptz not null default now()
);

create index if not exists apmc_market_rates_active_updated_idx
  on public.apmc_market_rates (active, updated_at desc);

create index if not exists apmc_market_rates_crop_idx
  on public.apmc_market_rates (crop);

create unique index if not exists apmc_market_rates_market_crop_uidx
  on public.apmc_market_rates (market_key, crop);

alter table public.apmc_market_rates enable row level security;

drop policy if exists "apmc_market_rates_read_all" on public.apmc_market_rates;
create policy "apmc_market_rates_read_all"
  on public.apmc_market_rates
  for select
  to anon, authenticated
  using (active = true);

grant select on public.apmc_market_rates to anon, authenticated;

insert into public.apmc_market_rates (
  market_key,
  market_name,
  crop,
  min_rate,
  modal_rate,
  max_rate,
  arrival_qty,
  demand,
  trend,
  distance_km,
  note
)
values
  ('apmc_market_name_akole', 'Akole APMC', 'Finger Millet', 2760, 3040, 3310, 42, 'High', 4.8, 18, 'Clean graded lots are getting faster bids.'),
  ('apmc_market_name_sangamner', 'Sangamner APMC', 'Foxtail Millet', 2480, 2790, 3060, 31, 'Good', 2.6, 44, 'Buyers prefer dry lots below 12 percent moisture.'),
  ('apmc_market_name_nashik', 'Nashik APMC', 'Little Millet', 2920, 3180, 3460, 26, 'High', 5.2, 92, 'Premium for sorted grain and uniform bag weight.'),
  ('apmc_market_name_pune', 'Pune APMC', 'Kodo Millet', 2650, 2915, 3200, 54, 'Stable', -1.4, 166, 'Arrival is higher today; hold if moisture is high.'),
  ('apmc_market_name_rahuri', 'Rahuri APMC', 'Pearl Millet', 2180, 2390, 2575, 68, 'Stable', 1.1, 71, 'Bulk buyers active for clean farm-gate pickup.')
on conflict (market_key, crop) do update
set
  market_name = excluded.market_name,
  min_rate = excluded.min_rate,
  modal_rate = excluded.modal_rate,
  max_rate = excluded.max_rate,
  arrival_qty = excluded.arrival_qty,
  demand = excluded.demand,
  trend = excluded.trend,
  distance_km = excluded.distance_km,
  note = excluded.note,
  active = true,
  rate_date = current_date,
  updated_at = now();
