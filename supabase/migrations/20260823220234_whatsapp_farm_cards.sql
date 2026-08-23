insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'whatsapp-farm-cards',
  'whatsapp-farm-cards',
  false,
  5242880,
  array['image/svg+xml', 'image/png']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
