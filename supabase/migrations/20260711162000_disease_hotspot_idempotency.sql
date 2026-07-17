with ranked as (
  select
    id,
    row_number() over (
      partition by farm_id, scan_date, cell_lat, cell_lng
      order by created_at desc nulls last, id desc
    ) as row_rank
  from public.disease_risk_cells
)
delete from public.disease_risk_cells cells
using ranked
where cells.id = ranked.id
  and ranked.row_rank > 1;

create unique index if not exists disease_risk_cells_farm_scan_coordinate_unique
  on public.disease_risk_cells (farm_id, scan_date, cell_lat, cell_lng);

with ranked as (
  select
    id,
    row_number() over (
      partition by farm_id, scan_date, zone_rank
      order by updated_at desc nulls last, created_at desc nulls last, id desc
    ) as row_rank
  from public.disease_scout_zones
)
delete from public.disease_scout_zones zones
using ranked
where zones.id = ranked.id
  and ranked.row_rank > 1;

create unique index if not exists disease_scout_zones_farm_scan_rank_unique
  on public.disease_scout_zones (farm_id, scan_date, zone_rank);
