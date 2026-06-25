import { supabase } from "@/integrations/supabase/client";

// ---- Fixed pipeline rules (Step 11) — mirrored from the edge function -------
export const RUNPOD_FIXED = {
  fps: 16,
  numScenes: 10,
  samplingSteps: 6,
  maxFramesPerScene: 257,
} as const;

export type DurationOption = "Short" | "Medium" | "Long";

// Duration → frames_per_scene. Never exceeds maxFramesPerScene.
export const DURATION_FRAMES: Record<DurationOption, number> = {
  Short: 81,
  Medium: 160,
  Long: 257,
};

export const DURATION_OPTIONS: { value: DurationOption; label: string; hint: string }[] = [
  { value: "Short", label: "Short", hint: "81 frames / scene" },
  { value: "Medium", label: "Medium", hint: "160 frames / scene" },
  { value: "Long", label: "Long", hint: "257 frames / scene" },
];

const REFERENCE_BUCKET = "reference-images";
const SIGNED_URL_TTL_SECONDS = 60 * 60 * 24; // 24h — RunPod fetches at job start

export interface SubmitVideoJobInput {
  characterId?: string | null;
  file: File;
  scenes: string[];
  negativePrompt: string;
  duration: DurationOption;
}

export interface SubmitVideoJobResult {
  jobId: string;
  runpodJobId: string;
  status: string;
}

function sanitizeFileName(name: string) {
  return name.replace(/[^a-zA-Z0-9._-]/g, "_").slice(-80);
}

export const runpodService = {
  /**
   * Uploads the reference image to private storage and returns a signed URL
   * RunPod can fetch. Kept separate so it can be reused/tested.
   */
  async uploadReferenceImage(file: File, userId: string): Promise<string> {
    const path = `${userId}/${Date.now()}-${sanitizeFileName(file.name)}`;
    const { error: uploadErr } = await supabase.storage
      .from(REFERENCE_BUCKET)
      .upload(path, file, { cacheControl: "3600", upsert: false });
    if (uploadErr) {
      throw new Error(`Reference image upload failed: ${uploadErr.message}`);
    }
    const { data, error: signErr } = await supabase.storage
      .from(REFERENCE_BUCKET)
      .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);
    if (signErr || !data?.signedUrl) {
      throw new Error(`Could not sign reference image URL: ${signErr?.message ?? "unknown"}`);
    }
    return data.signedUrl;
  },

  /**
   * Validates, uploads the reference image, then dispatches the job through the
   * secure `runpod-submit` edge function. The RunPod API key is NEVER touched
   * here — only the edge function holds it.
   */
  async submitVideoJob(input: SubmitVideoJobInput): Promise<SubmitVideoJobResult> {
    // Client-side validation (the edge function re-validates authoritatively).
    if (!input.file) throw new Error("A reference image is required.");
    if (input.scenes.length !== RUNPOD_FIXED.numScenes) {
      throw new Error(
        `Exactly ${RUNPOD_FIXED.numScenes} scenes are required (you have ${input.scenes.length}).`,
      );
    }
    if (input.scenes.some((p) => p.trim().length === 0)) {
      throw new Error("Every scene prompt must be filled in.");
    }

    const { data: userData } = await supabase.auth.getUser();
    const userId = userData.user?.id;
    if (!userId) throw new Error("You must be signed in to queue a job.");

    const imageUrl = await this.uploadReferenceImage(input.file, userId);

    const { data, error } = await supabase.functions.invoke("runpod-submit", {
      body: {
        characterId: input.characterId ?? null,
        imageUrl,
        scenes: input.scenes.map((s) => s.trim()),
        negativePrompt: input.negativePrompt.trim(),
        duration: input.duration,
      },
    });

    if (error) {
      // Surface the structured error the edge function returned, if present.
      let serverMessage = error.message;
      try {
        const ctx = (error as { context?: Response }).context;
        if (ctx && typeof ctx.json === "function") {
          const parsed = await ctx.json();
          if (parsed?.error) serverMessage = parsed.error;
        }
      } catch {
        /* fall back to error.message */
      }
      throw new Error(serverMessage);
    }

    if (data?.error) throw new Error(data.error);
    return data as SubmitVideoJobResult;
  },

  /**
   * PHASE 2 PLACEHOLDER — status polling.
   *
   * Intentionally NOT implemented. We do not yet have the RunPod status endpoint
   * specification or the completed-response structure, and we must not invent
   * them. When that contract is provided, implement the `runpod-status` edge
   * function and finish this method to call it. Do NOT guess response formats.
   */
  async getJobStatus(_runpodJobId: string): Promise<never> {
    throw new Error(
      "runpodService.getJobStatus is not implemented yet (Phase 2). " +
        "Awaiting the RunPod status endpoint + completed-response specification.",
    );
  },
};
