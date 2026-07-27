-- The legacy status index already covers (status, created_at desc).
drop index if exists public.marketplace_listings_browse_idx;
