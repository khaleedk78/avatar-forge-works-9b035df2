-- =============================================================================
-- STEP 11 — RUNPOD INTEGRATION (PHASE 1) — schema additions
-- Run in the SQL Editor of the EXTERNAL Supabase project (ref ixkzdnowlbjeiwqzfctu).
-- Idempotent — safe to run and re-run.
-- =============================================================================

-- 1) Extend generation_jobs with RunPod tracking columns ----------------------
alter table public.generation_jobs
  add column if not exists runpod_job_id   text,
  add column if not exists submitted_at    timestamptz,
  add column if not exists payload_snapshot jsonb not null default '{}'::jsonb;
-- (status + error_message already exist from the base schema.)

create index if not exists idx_generation_jobs_runpod on public.generation_jobs(runpod_job_id);

-- 2) Reference-images storage bucket (private; RunPod fetches via signed URL) --
insert into storage.buckets (id, name, public)
values ('reference-images', 'reference-images', false)
on conflict (id) do nothing;

-- Admin-only access to the studio buckets (guarded so it coexists with any
-- policies created by the base storage migration).
do $$ begin
  create policy "Admins read studio buckets"
    on storage.objects for select to authenticated
    using (
      bucket_id in ('reference-images','generated-images','generated-videos','character-assets')
      and public.has_role(auth.uid(), 'admin')
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "Admins insert studio buckets"
    on storage.objects for insert to authenticated
    with check (
      bucket_id in ('reference-images','generated-images','generated-videos','character-assets')
      and public.has_role(auth.uid(), 'admin')
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "Admins update studio buckets"
    on storage.objects for update to authenticated
    using (
      bucket_id in ('reference-images','generated-images','generated-videos','character-assets')
      and public.has_role(auth.uid(), 'admin')
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "Admins delete studio buckets"
    on storage.objects for delete to authenticated
    using (
      bucket_id in ('reference-images','generated-images','generated-videos','character-assets')
      and public.has_role(auth.uid(), 'admin')
    );
exception when duplicate_object then null; end $$;

-- 3) Reload PostgREST schema cache -------------------------------------------
notify pgrst, 'reload schema';
