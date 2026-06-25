-- STEP 11 — RunPod integration (phase 1): generation_jobs tracking columns +
-- reference-images storage bucket. Idempotent.

alter table public.generation_jobs
  add column if not exists runpod_job_id    text,
  add column if not exists submitted_at     timestamptz,
  add column if not exists payload_snapshot jsonb not null default '{}'::jsonb;

create index if not exists idx_generation_jobs_runpod on public.generation_jobs(runpod_job_id);

insert into storage.buckets (id, name, public)
values ('reference-images', 'reference-images', false)
on conflict (id) do nothing;

notify pgrst, 'reload schema';
