create table if not exists public.analysis_jobs (
    id uuid primary key default gen_random_uuid(),
    operator_id uuid,
    tenant_id uuid,
    batch_id text,
    crop_type text not null,
    variety text not null default '',
    status text not null default 'created',
    grain_image_path text,
    moisture_image_path text,
    manual_moisture_percent numeric,
    confidence_threshold integer not null default 60,
    final_grade text,
    grain_grade text,
    final_score numeric,
    grain_score numeric,
    moisture_percent numeric,
    moisture_risk text,
    moisture_source text,
    moisture_confidence numeric,
    reject_recommended boolean not null default false,
    reject_reasons jsonb not null default '[]'::jsonb,
    applied_rules jsonb not null default '[]'::jsonb,
    quality_metrics jsonb not null default '{}'::jsonb,
    score_breakdown jsonb not null default '{}'::jsonb,
    result_payload jsonb not null default '{}'::jsonb,
    model_version text,
    rule_version text,
    route_version text,
    error_message text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    completed_at timestamptz
);

create table if not exists public.analysis_logs (
    id uuid primary key default gen_random_uuid(),
    analysis_id uuid not null references public.analysis_jobs(id) on delete cascade,
    service text not null,
    stage text not null,
    payload jsonb not null default '{}'::jsonb,
    latency_ms integer,
    created_at timestamptz not null default now()
);

create table if not exists public.operator_corrections (
    id uuid primary key default gen_random_uuid(),
    analysis_id uuid not null references public.analysis_jobs(id) on delete cascade,
    operator_id uuid,
    predicted_final_grade text,
    corrected_final_grade text not null,
    predicted_grain_grade text,
    corrected_grain_grade text,
    predicted_moisture_percent numeric,
    corrected_moisture_percent numeric,
    notes text not null default '',
    created_at timestamptz not null default now()
);

create table if not exists public.crop_rule_versions (
    id uuid primary key default gen_random_uuid(),
    crop_type text not null,
    variety text,
    version text not null,
    rules jsonb not null,
    active boolean not null default false,
    created_at timestamptz not null default now()
);

create index if not exists analysis_jobs_status_created_idx on public.analysis_jobs(status, created_at);
create index if not exists analysis_jobs_operator_created_idx on public.analysis_jobs(operator_id, created_at desc);
create index if not exists analysis_logs_analysis_idx on public.analysis_logs(analysis_id, created_at);
create index if not exists operator_corrections_analysis_idx on public.operator_corrections(analysis_id, created_at);

alter table public.analysis_jobs enable row level security;
alter table public.analysis_logs enable row level security;
alter table public.operator_corrections enable row level security;
alter table public.crop_rule_versions enable row level security;

drop policy if exists "operators can read own analysis jobs" on public.analysis_jobs;
create policy "operators can read own analysis jobs"
on public.analysis_jobs for select
to authenticated
using (operator_id = auth.uid());

drop policy if exists "operators can create own analysis jobs" on public.analysis_jobs;
create policy "operators can create own analysis jobs"
on public.analysis_jobs for insert
to authenticated
with check (operator_id = auth.uid());

drop policy if exists "operators can read own analysis logs" on public.analysis_logs;
create policy "operators can read own analysis logs"
on public.analysis_logs for select
to authenticated
using (
    exists (
        select 1
        from public.analysis_jobs jobs
        where jobs.id = analysis_logs.analysis_id
          and jobs.operator_id = auth.uid()
    )
);

drop policy if exists "operators can create own corrections" on public.operator_corrections;
create policy "operators can create own corrections"
on public.operator_corrections for insert
to authenticated
with check (operator_id = auth.uid());

drop policy if exists "operators can read own corrections" on public.operator_corrections;
create policy "operators can read own corrections"
on public.operator_corrections for select
to authenticated
using (operator_id = auth.uid());

drop policy if exists "operators can read active crop rules" on public.crop_rule_versions;
create policy "operators can read active crop rules"
on public.crop_rule_versions for select
to authenticated
using (active = true);

insert into storage.buckets (id, name, public)
values ('grain-images', 'grain-images', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('moisture-images', 'moisture-images', false)
on conflict (id) do nothing;

drop policy if exists "operators can upload grain images" on storage.objects;
create policy "operators can upload grain images"
on storage.objects for insert
to authenticated
with check (
    bucket_id in ('grain-images', 'moisture-images')
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "operators can read own grading images" on storage.objects;
create policy "operators can read own grading images"
on storage.objects for select
to authenticated
using (
    bucket_id in ('grain-images', 'moisture-images')
    and (storage.foldername(name))[1] = auth.uid()::text
);
