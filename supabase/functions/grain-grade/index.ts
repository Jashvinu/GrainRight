import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  applyRagiRules,
  type Grade,
  type GrainSignals,
  moistureRiskFromPercent,
  RAGI_RULE_PROMPT,
  RULE_VERSION,
} from "../_shared/grain-rules.ts";

// Grain grading edge function. Mirrors disease-image-diagnose: the app uploads
// the grain + moisture photos to private storage, then calls this function with
// the storage paths. We sign the URLs, run Qwen-VL for moisture OCR and grain
// vision, apply the deterministic ragi rules, persist to analysis_jobs, and
// return an AnalyzeResponse-shaped payload the Flutter client maps to GradeResult.

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  // Service role: insert analysis_jobs and sign private storage URLs even when
  // the caller is a guest session whose auth.uid() does not satisfy owner RLS.
  return createClient(url, key);
}

function vlmEnv() {
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
  return { apiKey, baseUrl, model };
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

async function callVlm(prompt: string, imageUrl: string): Promise<Record<string, unknown>> {
  const { apiKey, baseUrl, model } = vlmEnv();
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: imageUrl } },
          ],
        },
      ],
      temperature: 0.1,
      max_tokens: 700,
      response_format: { type: "json_object" },
    }),
  });
  if (!response.ok) {
    throw new Error(`VLM request failed: ${response.status} ${await response.text()}`);
  }
  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;
  const text = typeof content === "string" ? content : JSON.stringify(content ?? {});
  const parsed = safeJsonParse(text);
  if (!parsed) throw new Error("VLM returned invalid JSON");
  return parsed;
}

function num(value: unknown, fallback: number): number {
  const n = typeof value === "number" ? value : Number(String(value ?? "").match(/-?\d+(\.\d+)?/)?.[0]);
  return Number.isFinite(n) ? n : fallback;
}

function gradeValue(value: unknown): Grade {
  const t = String(value ?? "B").toUpperCase();
  if (t.includes("A")) return "A";
  if (t.includes("C")) return "C";
  return "B";
}

async function signUrl(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  bucket: string,
  path: string,
): Promise<string> {
  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, 60 * 10);
  if (error || !data?.signedUrl) {
    throw new Error(`Failed to sign ${bucket}/${path}: ${error?.message ?? "no url"}`);
  }
  return data.signedUrl;
}

async function readMoisture(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  moisturePath: string | null,
  manualPercent: number | null,
): Promise<{ percent: number | null; source: string; confidence: number | null }> {
  if (moisturePath) {
    try {
      const url = await signUrl(supabase, "moisture-images", moisturePath);
      const prompt = [
        "You read the number shown on a handheld grain moisture meter display.",
        "Return only JSON: {\"percent\": number, \"confidence\": 0..1, \"raw_text\": string}.",
        "percent is the moisture percentage shown (e.g. 11.8). If unreadable, set percent to null.",
      ].join("\n");
      const parsed = await callVlm(prompt, url);
      const percentRaw = parsed.percent;
      const percent = percentRaw == null ? null : num(percentRaw, NaN);
      if (percent != null && Number.isFinite(percent) && percent > 0 && percent <= 50) {
        return { percent, source: "meter_ocr", confidence: num(parsed.confidence, 0.7) };
      }
    } catch (_) {
      // fall through to manual
    }
  }
  if (manualPercent != null && manualPercent > 0) {
    return { percent: manualPercent, source: "manual", confidence: 1 };
  }
  return { percent: null, source: "unknown", confidence: null };
}

async function readGrain(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  grainPath: string,
  crop: string,
  variety: string,
): Promise<GrainSignals> {
  const url = await signUrl(supabase, "grain-images", grainPath);
  const prompt = [
    "You are a conservative grain-quality vision assistant for finger millet (ragi).",
    "Inspect the grain lot photo and estimate physical quality signals. Return ONLY JSON.",
    "Do not invent precision; if unsure, estimate conservatively (worse).",
    "",
    RAGI_RULE_PROMPT,
    "",
    `Crop: ${crop}  Variety: ${variety || "unknown"}`,
    "",
    "Return this shape:",
    JSON.stringify({
      broken_grain_percent: 0.0,
      foreign_matter_percent: 0.0,
      damaged_percent: 0.0,
      uniformity_score: 0,
      mold_visible: false,
      grade: "A|B|C",
    }),
  ].join("\n");
  const parsed = await callVlm(prompt, url);
  return {
    brokenGrainPercent: Math.max(0, num(parsed.broken_grain_percent, 2)),
    foreignMatterPercent: Math.max(0, num(parsed.foreign_matter_percent, 0.5)),
    damagedPercent: Math.max(0, num(parsed.damaged_percent, 3)),
    uniformityScore: Math.max(0, Math.min(100, num(parsed.uniformity_score, 70))),
    moldVisible: parsed.mold_visible === true,
    modelGrade: gradeValue(parsed.grade),
  };
}

function operatorSummary(grade: Grade, risk: string, reject: boolean): string {
  if (reject) return "This lot needs human review before sale or storage.";
  const base: Record<Grade, string> = {
    A: "Premium lot — suitable for premium packaging.",
    B: "Good lot — sell as standard grade.",
    C: "Fair lot — clean and dry further before premium sale.",
  };
  const moisture = risk === "LOW"
    ? "Moisture is safe for storage."
    : risk === "MODERATE"
    ? "Dry a little more before long storage."
    : "Dry the grain before storing.";
  return `${base[grade]} ${moisture}`;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const body = await req.json();
    const grainPath = String(body.grain_image_path ?? "");
    if (!grainPath) return errorResponse("grain_image_path is required", 400);

    const moisturePath = body.moisture_image_path ? String(body.moisture_image_path) : null;
    const manualPercent = body.manual_moisture_percent != null
      ? Number(body.manual_moisture_percent)
      : null;
    if (!moisturePath && (manualPercent == null || !Number.isFinite(manualPercent))) {
      return errorResponse("moisture_image_path or manual_moisture_percent is required", 400);
    }

    const cropType = String(body.crop_type ?? "finger_millets");
    const variety = String(body.crop_variety ?? body.variety ?? "");
    const confidenceThreshold = Number(body.confidence_threshold ?? 60);
    const operatorId = body.operator_id ? String(body.operator_id) : null;
    const batchId = body.batch_id ? String(body.batch_id) : null;

    const supabase = createServiceClient();

    const moisture = await readMoisture(supabase, moisturePath, manualPercent);
    const moistureRisk = moistureRiskFromPercent(moisture.percent);
    const signals = await readGrain(supabase, grainPath, cropType, variety);
    const rules = applyRagiRules(signals, moisture.percent, moistureRisk);

    const overallConfidence = Math.round(
      ((moisture.confidence ?? 0.6) * 100 + rules.finalScore) / 2,
    );
    const manualReviewRequired = rules.rejectRecommended ||
      overallConfidence < confidenceThreshold;

    const quality = {
      grade: rules.grade,
      grain_grade: rules.grainGrade,
      score: rules.finalScore,
      grain_score: rules.grainScore,
      moisture_score: rules.moistureScore,
      broken_grain_percent: signals.brokenGrainPercent,
      foreign_matter_percent: signals.foreignMatterPercent,
      uniformity_score: signals.uniformityScore,
      mold_visible: signals.moldVisible,
      reject_recommended: rules.rejectRecommended,
      reject_reasons: rules.rejectReasons,
    };
    const moisturePayload = {
      risk_level: moistureRisk,
      percent_estimate: moisture.percent,
      machine_percent: moisture.source === "manual" ? moisture.percent : null,
      source: moisture.source,
      ocr_confidence: moisture.confidence,
    };

    // Persist (service role bypasses RLS; operator_id stored for ownership).
    let analysisId: string = crypto.randomUUID();
    const { data: inserted, error: insertError } = await supabase
      .from("analysis_jobs")
      .insert({
        operator_id: operatorId,
        batch_id: batchId,
        crop_type: cropType,
        variety,
        status: "completed",
        grain_image_path: grainPath,
        moisture_image_path: moisturePath,
        manual_moisture_percent: moisture.source === "manual" ? moisture.percent : null,
        confidence_threshold: confidenceThreshold,
        final_grade: rules.grade,
        grain_grade: rules.grainGrade,
        final_score: rules.finalScore,
        grain_score: rules.grainScore,
        moisture_percent: moisture.percent,
        moisture_risk: moistureRisk,
        moisture_source: moisture.source,
        moisture_confidence: moisture.confidence,
        reject_recommended: rules.rejectRecommended,
        reject_reasons: rules.rejectReasons,
        applied_rules: rules.appliedRules,
        quality_metrics: quality,
        rule_version: RULE_VERSION,
        completed_at: new Date().toISOString(),
      })
      .select("id")
      .maybeSingle();
    if (!insertError && inserted?.id) analysisId = String(inserted.id);

    return successResponse({
      analysis_id: analysisId,
      grain_image_name: grainPath.split("/").pop() ?? grainPath,
      moisture_image_name: moisturePath?.split("/").pop() ?? null,
      quality,
      moisture: moisturePayload,
      confidence: {
        overall: overallConfidence,
        pass1_safety_gate: overallConfidence,
        pass2_grading: rules.finalScore,
      },
      selection: { selected_crop: cropType, selected_variety: variety },
      applied_rules: rules.appliedRules,
      manual_review_required: manualReviewRequired,
      operator_summary: operatorSummary(rules.grade, moistureRisk, rules.rejectRecommended),
      signal_highlights: rules.signalHighlights,
    });
  } catch (error) {
    return errorResponse("grain-grade failed", 500, error);
  }
});
