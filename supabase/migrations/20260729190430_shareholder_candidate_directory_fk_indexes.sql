create index if not exists shareholder_candidate_roster_imported_by_idx
  on public.shareholder_candidate_roster (imported_by)
  where imported_by is not null;

create index if not exists shareholder_candidate_roster_linked_application_idx
  on public.shareholder_candidate_roster (linked_application_id)
  where linked_application_id is not null;
