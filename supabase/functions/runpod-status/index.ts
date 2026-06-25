// =============================================================================
// runpod-status — STEP 11 RunPod integration (PHASE 2 PLACEHOLDER)
//
// ⚠️  NOT IMPLEMENTED ON PURPOSE.
//
// This is the isolated home for status polling. We intentionally do NOT call
// RunPod or interpret any response yet, because we do not have:
//   - the status endpoint specification, or
//   - the completed-response structure.
//
// DO NOT invent response formats. DO NOT guess. When the RunPod status/output
// contract is provided, implement it HERE (and finish runpodService.getJobStatus
// on the frontend). For now this returns 501 so any accidental call is obvious.
//
// Planned shape (to be confirmed against the real API, not assumed):
//   GET https://api.runpod.ai/v2/<endpoint>/status/<runpod_job_id>
//   Authorization: Bearer RUNPOD_API_KEY
// =============================================================================

import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

Deno.serve((req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  return jsonResponse(
    {
      error: "not_implemented",
      message:
        "RunPod status polling is Phase 2. Awaiting the status endpoint and completed-response specification before implementation.",
    },
    501,
  );
});
