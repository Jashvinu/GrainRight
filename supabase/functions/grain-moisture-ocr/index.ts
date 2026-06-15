import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
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

function num(value: unknown, fallback: number): number {
  const n = typeof value === "number"
    ? value
    : Number(String(value ?? "").match(/-?\d+(\.\d+)?/)?.[0]);
  return Number.isFinite(n) ? n : fallback;
}

async function signUrl(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  path: string,
): Promise<string> {
  const { data, error } = await supabase.storage
    .from("moisture-images")
    .createSignedUrl(path, 60 * 10);
  if (error || !data?.signedUrl) {
    throw new Error(`Failed to sign moisture image: ${error?.message ?? "no url"}`);
  }
  return data.signedUrl;
}

async function callVlm(imageUrl: string): Promise<Record<string, unknown>> {
  const { apiKey, baseUrl, model } = vlmEnv();
  const prompt = [
    "You read the number shown on a handheld grain moisture meter display.",
    "Return only JSON: {\"percent\": number|null, \"confidence\": 0..1, \"raw_text\": string}.",
    "percent is the moisture percentage shown, for example 11.8.",
    "If unreadable, set percent to null and confidence below 0.4.",
  ].join("\n");
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
      max_tokens: 300,
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

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const body = await req.json();
    const moisturePath = body.moisture_image_path
      ? String(body.moisture_image_path)
      : "";
    const manualPercent = body.manual_moisture_percent != null
      ? Number(body.manual_moisture_percent)
      : null;

    if (!moisturePath && (manualPercent == null || !Number.isFinite(manualPercent))) {
      return errorResponse("moisture_image_path or manual_moisture_percent is required", 400);
    }

    if (!moisturePath && manualPercent != null) {
      return successResponse({
        moisture: {
          percent: manualPercent,
          source: "manual",
          confidence: 1,
        },
      });
    }

    const supabase = createServiceClient();
    const url = await signUrl(supabase, moisturePath);
    const parsed = await callVlm(url);
    const percentRaw = parsed.percent;
    const percent = percentRaw == null ? null : num(percentRaw, NaN);
    const validPercent = percent != null &&
      Number.isFinite(percent) &&
      percent > 0 &&
      percent <= 50;

    if (!validPercent && manualPercent != null && manualPercent > 0) {
      return successResponse({
        moisture_image_path: moisturePath,
        moisture: {
          percent: manualPercent,
          source: "manual",
          confidence: 1,
        },
      });
    }

    return successResponse({
      moisture_image_path: moisturePath,
      moisture: {
        percent: validPercent ? percent : null,
        source: validPercent ? "meter_ocr" : "unknown",
        confidence: num(parsed.confidence, validPercent ? 0.7 : 0.2),
        raw_text: String(parsed.raw_text ?? ""),
      },
    });
  } catch (error) {
    return errorResponse("grain-moisture-ocr failed", 500, error);
  }
});
