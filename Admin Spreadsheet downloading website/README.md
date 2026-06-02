# GrainRight Admin Export

Download-only admin website for exporting submitted survey data as one flat Excel file.

## Local setup

1. Copy `.env.example` to `.env`.
2. Set `VITE_ADMIN_EXPORT_FUNCTION_URL` to the deployed Supabase function URL.
3. Set `VITE_SUPABASE_ANON_KEY` if the function is deployed with JWT verification enabled.
4. Run `npm install`.
5. Run `npm run dev`.

The Supabase Edge Function `admin-survey-export` must have `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` configured as function secrets.
