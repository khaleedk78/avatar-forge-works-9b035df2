# Step 11 — RunPod Integration (Phase 1) — Setup & Deployment

This wires the Generate page to the real RunPod endpoint through a **secure
server-side edge function**. The RunPod API key never reaches the browser.

```
Generate page → runpodService → supabase.functions.invoke("runpod-submit")
              → [edge function holds RUNPOD_API_KEY] → RunPod /run → Supabase
```

## What was added

| Area | File |
|------|------|
| DB migration (run manually) | `EXTERNAL_SUPABASE_RUNPOD_MIGRATION.sql` |
| DB migration (repo copy) | `supabase/migrations/20260625000000_runpod_phase1.sql` |
| Secure submit function | `supabase/functions/runpod-submit/index.ts` |
| Phase 2 status placeholder | `supabase/functions/runpod-status/index.ts` (returns 501) |
| Frontend service | `src/services/runpodService.ts` |
| Generate page wiring | `src/routes/_authenticated/generate.tsx` |

`generation_jobs` now stores `runpod_job_id`, `submitted_at`, `status`,
`error_message`, and `payload_snapshot`.

## Fixed pipeline rules (enforced in the edge function)

- `fps = 16`, `num_scenes = 10`, `sampling_steps = 6`
- `frames_per_scene` from the Duration option, **never above 257**:
  - **Short** → 81 · **Medium** → 160 · **Long** → 257
- Exactly 10 non-empty scene prompts required.

## Single project: `ixkzdnowlbjeiwqzfctu`

The entire repo now consistently targets the external Supabase project
**`ixkzdnowlbjeiwqzfctu`** — `src/integrations/supabase/client.ts`,
`supabase/config.toml`, and `.env` all point at it. The previous Lovable Cloud
project reference has been removed. The CLI commands below pass
`--project-ref ixkzdnowlbjeiwqzfctu` explicitly, which also matches `config.toml`.

## Setup steps

### 1. Run the SQL migration
Open the SQL Editor of project `ixkzdnowlbjeiwqzfctu` and run
`EXTERNAL_SUPABASE_RUNPOD_MIGRATION.sql`. It adds the tracking columns and
creates the private `reference-images` storage bucket.

### 2. Set the RunPod secret (server-side only)
```bash
supabase secrets set RUNPOD_API_KEY=your_real_runpod_key --project-ref ixkzdnowlbjeiwqzfctu
# Optional override (defaults to the Step 11 endpoint id):
supabase secrets set RUNPOD_ENDPOINT_ID=7ga3thvfic0t8a --project-ref ixkzdnowlbjeiwqzfctu
```
The key lives only in the function runtime. It is never sent to or referenced by
the browser bundle.

### 3. Deploy the edge functions
```bash
supabase functions deploy runpod-submit --project-ref ixkzdnowlbjeiwqzfctu
supabase functions deploy runpod-status --project-ref ixkzdnowlbjeiwqzfctu
```
`runpod-submit` requires a valid user JWT (the frontend sends it automatically).
`runpod-status` is an intentional Phase 2 stub and returns HTTP 501.

### 4. Try it
Sign in as the admin, open **Content Generation → Video**, upload a reference
image, pick a Duration, fill all 10 scene prompts, and click **Generate Video**.
On success the summary panel shows a "Job processing" card with the RunPod job
id, and a `generation_jobs` row is created with `status = processing`.

## Error handling
The edge function validates input and records failures in
`generation_jobs.error_message` with `status = failed` for: missing image,
wrong scene count, empty prompts, RunPod request failures, non-JSON / id-less
responses, network errors, and timeouts (30s).

## Phase 2 (NOT done — by design)
- `runpodService.getJobStatus()` throws "not implemented".
- `runpod-status` edge function returns 501.
- No response formats are assumed. Implement both once the RunPod **status
  endpoint** and **completed-response structure** are provided. Only then move
  finished content into Library / Review Queue / Schedule.
