// =============================================================================
// runpod-submit — STEP 11 RunPod integration (Phase 1)
//
// Secure server-side layer:  Frontend → THIS edge function → RunPod → Supabase.
// The RUNPOD_API_KEY secret lives only here and is NEVER returned to the client.
//
// Flow:
//   1. Authenticate the caller (their JWT is forwarded by supabase-js).
//   2. Validate the payload (reference image, exactly 10 non-empty prompts).
//   3. Insert a generation_jobs row (as the user — RLS still applies).
//   4. POST the job to RunPod with the Bearer key.
//   5. Persist the returned RunPod job id + status (or the error).
//
// Required secrets / env:
//   RUNPOD_API_KEY        (set via `supabase secrets set RUNPOD_API_KEY=...`)
//   RUNPOD_ENDPOINT_ID    (optional; defaults to the Step 11 endpoint)
//   SUPABASE_URL          (auto-injected)
//   SUPABASE_ANON_KEY     (auto-injected)
// =============================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

// ---- Fixed pipeline rules (Step 11) ----------------------------------------
const FPS = 16;
const NUM_SCENES = 10;
const SAMPLING_STEPS = 6;
const MAX_FRAMES_PER_SCENE = 257;

// Duration option → frames_per_scene. Never exceeds MAX_FRAMES_PER_SCENE.
const DURATION_FRAMES: Record<string, number> = {
  Short: 81,
  Medium: 160,
  Long: 257,
};

const RUNPOD_ENDPOINT_ID =
  Deno.env.get("RUNPOD_ENDPOINT_ID") ?? "7ga3thvfic0t8a";
const RUNPOD_RUN_URL = `https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/run`;
const RUNPOD_TIMEOUT_MS = 30_000;

interface SubmitBody {
  characterId?: string | null;
  imageUrl?: string;
  scenes?: string[];
  negativePrompt?: string;
  duration?: "Short" | "Medium" | "Long";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // --- Server secret guard --------------------------------------------------
  const runpodKey = Deno.env.get("RUNPOD_API_KEY");
  if (!runpodKey) {
    return jsonResponse(
      { error: "RunPod is not configured. Set the RUNPOD_API_KEY secret." },
      500,
    );
  }

  // --- Authenticate the caller ---------------------------------------------
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) {
    return jsonResponse({ error: "Not authenticated" }, 401);
  }
  const userId = userData.user.id;

  // --- Parse + validate the payload ----------------------------------------
  let body: SubmitBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const imageUrl = (body.imageUrl ?? "").trim();
  const scenes = Array.isArray(body.scenes) ? body.scenes : [];
  const negativePrompt = (body.negativePrompt ?? "").trim();
  const duration = body.duration ?? "Long";

  if (!imageUrl) {
    return jsonResponse({ error: "A reference image is required." }, 400);
  }
  if (scenes.length !== NUM_SCENES) {
    return jsonResponse(
      { error: `Exactly ${NUM_SCENES} scenes are required (received ${scenes.length}).` },
      400,
    );
  }
  if (scenes.some((p) => typeof p !== "string" || p.trim().length === 0)) {
    return jsonResponse({ error: "Every scene prompt must be non-empty." }, 400);
  }
  const framesPerScene = DURATION_FRAMES[duration];
  if (!framesPerScene) {
    return jsonResponse({ error: `Invalid duration option: ${duration}` }, 400);
  }
  // Hard safety clamp — never exceed the endpoint maximum.
  const safeFramesPerScene = Math.min(framesPerScene, MAX_FRAMES_PER_SCENE);

  // --- Build the RunPod input payload --------------------------------------
  const runpodInput = {
    image_url: imageUrl,
    fps: FPS,
    frames_per_scene: safeFramesPerScene,
    num_scenes: NUM_SCENES,
    sampling_steps: SAMPLING_STEPS,
    prompts: scenes.map((p) => p.trim()),
    negative_prompt: negativePrompt,
  };

  const payloadSnapshot = {
    duration,
    referenceImageUrl: imageUrl,
    runpodInput,
    endpointId: RUNPOD_ENDPOINT_ID,
  };

  // --- Insert the tracking row (status: queued) ----------------------------
  const submittedAt = new Date().toISOString();
  const { data: job, error: insertErr } = await supabase
    .from("generation_jobs")
    .insert({
      type: "video",
      character_id: body.characterId ?? null,
      created_by: userId,
      status: "queued",
      submitted_at: submittedAt,
      input_payload: runpodInput,
      payload_snapshot: payloadSnapshot,
    })
    .select()
    .single();

  if (insertErr || !job) {
    return jsonResponse(
      { error: `Could not create job record: ${insertErr?.message ?? "unknown"}` },
      500,
    );
  }

  // --- Submit to RunPod -----------------------------------------------------
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), RUNPOD_TIMEOUT_MS);
  try {
    const res = await fetch(RUNPOD_RUN_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${runpodKey}`,
      },
      body: JSON.stringify({ input: runpodInput }),
      signal: controller.signal,
    });

    const raw = await res.text();
    let parsed: Record<string, unknown> = {};
    try {
      parsed = raw ? JSON.parse(raw) : {};
    } catch {
      // Non-JSON response — keep raw text for the error message.
    }

    if (!res.ok) {
      const message = `RunPod request failed (${res.status}): ${raw.slice(0, 500)}`;
      await supabase
        .from("generation_jobs")
        .update({ status: "failed", error_message: message })
        .eq("id", job.id);
      return jsonResponse({ error: message, jobId: job.id }, 502);
    }

    // RunPod /run returns at least an `id`. We do NOT interpret anything else
    // here — completion parsing is Phase 2 (see runpod-status).
    const runpodJobId =
      typeof parsed.id === "string" ? parsed.id : null;

    if (!runpodJobId) {
      const message = `RunPod response missing job id: ${raw.slice(0, 500)}`;
      await supabase
        .from("generation_jobs")
        .update({ status: "failed", error_message: message })
        .eq("id", job.id);
      return jsonResponse({ error: message, jobId: job.id }, 502);
    }

    await supabase
      .from("generation_jobs")
      .update({ runpod_job_id: runpodJobId, status: "processing" })
      .eq("id", job.id);

    return jsonResponse({
      jobId: job.id,
      runpodJobId,
      status: "processing",
    });
  } catch (err) {
    const isTimeout = err instanceof DOMException && err.name === "AbortError";
    const message = isTimeout
      ? "RunPod request timed out."
      : `Network error contacting RunPod: ${err instanceof Error ? err.message : String(err)}`;
    await supabase
      .from("generation_jobs")
      .update({ status: "failed", error_message: message })
      .eq("id", job.id);
    return jsonResponse({ error: message, jobId: job.id }, 502);
  } finally {
    clearTimeout(timeout);
  }
});
