import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  formatKnowledge,
  retrieveKnowledge,
} from "../_shared/knowledge-retrieval.ts";

type DiagnosisPayload = {
  diagnosis: string;
  confidence: number;
  severity: "low" | "medium" | "high";
  differential: string[];
  evidence: string[];
  scout_action: string;
};

function createSupabaseClient(req: Request) {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  // Authenticate as service_role: this function signs a private storage URL and
  // updates farmer_photo_submissions (owner-only RLS). Forwarding the caller's
  // JWT would run those as the caller (a guest in the app's session fallback)
  // and be rejected by RLS.
  return createClient(url, key);
}

function safeJsonParse(value: string): Record<string, unknown> | null {
  try {
    return JSON.parse(value);
  } catch {
    const match = value.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

function normalizeDiagnosis(value: Record<string, unknown>): DiagnosisPayload {
  const severityRaw = String(value.severity ?? "medium").toLowerCase();
  const severity = severityRaw === "low" || severityRaw === "high"
    ? severityRaw
    : "medium";
  const confidenceRaw = Number(value.confidence ?? 0.5);
  const confidence = Number.isFinite(confidenceRaw)
    ? Math.max(0, Math.min(1, confidenceRaw))
    : 0.5;

  return {
    diagnosis: String(value.diagnosis ?? "visual review needed").slice(0, 240),
    confidence,
    severity,
    differential: Array.isArray(value.differential)
      ? value.differential.map((item) => String(item)).filter(Boolean).slice(
        0,
        5,
      )
      : [],
    evidence: Array.isArray(value.evidence)
      ? value.evidence.map((item) => String(item)).filter(Boolean).slice(0, 6)
      : [],
    scout_action: String(
      value.scout_action ??
        "Ask an agronomist to review the image with field notes",
    ).slice(0, 500),
  };
}

function extractDiseaseCandidates(context: unknown): string[] {
  if (context == null || typeof context !== "object") return [];
  const top = (context as Record<string, unknown>).top_disease_risks;
  if (top != null && typeof top === "object") {
    return Object.keys(top as Record<string, unknown>);
  }
  return [];
}

async function callVisionModel(args: {
  imageUrl: string;
  crop: string;
  growthStage: string;
  satelliteContext: unknown;
  knowledge: string;
}): Promise<{ model: string; diagnosis: DiagnosisPayload }> {
  const apiKey = Deno.env.get("VLM_API_KEY") ??
    Deno.env.get("QWEN_VL_API_KEY") ??
    Deno.env.get("QWEN_API_KEY");
  const baseUrl = Deno.env.get("VLM_BASE_URL") ??
    Deno.env.get("QWEN_BASE_URL") ??
    "https://dashscope-intl.aliyuncs.com/compatible-mode/v1";
  const model = Deno.env.get("VLM_MODEL") ??
    Deno.env.get("QWEN_VL_MODEL") ??
    "qwen-vl-max";

  if (!apiKey) throw new Error("VLM_API_KEY or QWEN_API_KEY is not configured");

  const prompt = [
    "You are a conservative crop disease image triage assistant.",
    "Return only JSON. Do not claim lab confirmation. If the image is unclear, say visual review needed.",
    "Use the satellite context only as supporting context, not proof.",
    "Use the reference knowledge below to match visible symptoms to the most likely disease and to ground the scout_action in cultural/IDM mitigation (resistant varieties, seed treatment, scouting, drainage). Do not invent diseases not supported by the image. Do not give pesticide brands or chemical doses; if chemical control seems needed, advise consulting a KVK/agronomist for the dose.",
    "",
    `Crop: ${args.crop}`,
    `Growth stage: ${args.growthStage}`,
    `Satellite context: ${JSON.stringify(args.satelliteContext ?? null)}`,
    ...(args.knowledge.length > 0
      ? ["", "Reference knowledge (ICAR — for grounding, not lab confirmation):", args.knowledge]
      : []),
    "",
    "Return this shape:",
    JSON.stringify({
      diagnosis: "short likely diagnosis or visual review needed",
      confidence: 0.0,
      severity: "low|medium|high",
      differential: ["possible alternative"],
      evidence: ["visible image evidence"],
      scout_action: "one practical next scouting action",
    }),
  ].join("\n");

  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: args.imageUrl } },
          ],
        },
      ],
      temperature: 0.1,
      max_tokens: 900,
      response_format: { type: "json_object" },
    }),
  });

  if (!response.ok) {
    throw new Error(
      `VLM request failed: ${response.status} ${await response.text()}`,
    );
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;
  const text = typeof content === "string"
    ? content
    : JSON.stringify(content ?? {});
  const parsed = safeJsonParse(text);
  if (!parsed) throw new Error("VLM returned invalid JSON");

  return { model, diagnosis: normalizeDiagnosis(parsed) };
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const body = await req.json();
    const supabase = createSupabaseClient(req);

    let submissionId = String(body.submission_id ?? body.id ?? "");
    // deno-lint-ignore no-explicit-any
    let submission: any = null;

    if (submissionId) {
      const { data, error: loadError } = await supabase
        .from("farmer_photo_submissions")
        .select("*")
        .eq("id", submissionId)
        .maybeSingle();
      if (loadError) {
        throw new Error(
          `Failed to load photo submission: ${loadError.message}`,
        );
      }
      submission = data;
    } else {
      // No submission row yet: the app uploads the photo to storage and asks this
      // function to create the row. Insert runs as service_role because the
      // caller may be a guest session whose auth.uid() does not own the farm
      // (owner-only RLS would reject the insert client-side).
      const farmId = String(body.farm_id ?? "");
      const storagePath = String(body.storage_path ?? "");
      if (!farmId || !storagePath) {
        return errorResponse(
          "submission_id or farm_id + storage_path is required",
          400,
        );
      }
      const { data, error: insertError } = await supabase
        .from("farmer_photo_submissions")
        .insert({
          farm_id: farmId,
          scout_zone_id: body.scout_zone_id ?? null,
          storage_path: storagePath,
          taken_lat: body.taken_lat ?? null,
          taken_lng: body.taken_lng ?? null,
          crop: String(body.crop ?? "unknown"),
          growth_stage: body.growth_stage ?? null,
          satellite_context: body.satellite_context ?? null,
        })
        .select()
        .maybeSingle();
      if (insertError || !data) {
        throw new Error(
          `Failed to create photo submission: ${
            insertError?.message ?? "no row returned"
          }`,
        );
      }
      submission = data;
      submissionId = String(data.id);
    }

    if (!submission) return errorResponse("Photo submission not found", 404);

    const { data: signed, error: signedError } = await supabase.storage
      .from("disease-photos")
      .createSignedUrl(submission.storage_path, 60 * 10);
    if (signedError || !signed?.signedUrl) {
      throw new Error(
        `Failed to sign disease photo URL: ${
          signedError?.message ?? "missing signed URL"
        }`,
      );
    }

    const crop = String(submission.crop ?? "unknown");
    const growthStage = String(submission.growth_stage ?? "unknown");
    const knowledge = await retrieveKnowledge({
      crop,
      growthStage,
      diseaseCandidates: extractDiseaseCandidates(submission.satellite_context),
      queryText: "leaf disease symptoms diagnosis and mitigation",
    });

    const result = await callVisionModel({
      imageUrl: signed.signedUrl,
      crop,
      growthStage,
      satelliteContext: submission.satellite_context ?? null,
      knowledge: formatKnowledge(knowledge),
    });

    const { error: updateError } = await supabase
      .from("farmer_photo_submissions")
      .update({
        diagnosis_result: result.diagnosis,
        diagnosis_model: result.model,
        diagnosis_at: new Date().toISOString(),
      })
      .eq("id", submissionId);
    if (updateError) {
      throw new Error(
        `Failed to update photo diagnosis: ${updateError.message}`,
      );
    }

    return successResponse({
      submission_id: submissionId,
      model: result.model,
      ...result.diagnosis,
    });
  } catch (error) {
    return errorResponse("disease-image-diagnose failed", 500, error);
  }
});
