import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  formatKnowledge,
  retrieveKnowledge,
} from "../_shared/knowledge-retrieval.ts";

type AlertSeverity = "high" | "medium" | "low";

type FarmAlert = {
  title: string;
  detail: string;
  severity: AlertSeverity;
  action: string;
};

type FarmAlertAdvice = {
  important_alerts: FarmAlert[];
  weather_alerts: FarmAlert[];
  next_actions: string[];
  confidence: AlertSeverity;
  model?: string;
};

const DEFAULT_QWEN_MODELS = ["qwen3-235b-a22b", "qwen3-72b", "qwen3-32b"];

function splitEnvList(name: string, fallback: string[]) {
  const raw = Deno.env.get(name)?.trim();
  return raw == null || raw.length === 0
    ? fallback
    : raw.split(",").map((item) => item.trim()).filter(Boolean);
}

function safeJsonParse<T>(value: string): T | null {
  try {
    return JSON.parse(value) as T;
  } catch {
    const match = value.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]) as T;
    } catch {
      return null;
    }
  }
}

function normalizeAlert(value: unknown): FarmAlert | null {
  if (value == null || typeof value !== "object") return null;
  const map = value as Record<string, unknown>;
  const title = String(map.title ?? "").trim();
  const detail = String(map.detail ?? map.reason ?? "").trim();
  const action = String(map.action ?? map.next_action ?? "").trim();
  const rawSeverity = String(map.severity ?? "medium").toLowerCase();
  const severity: AlertSeverity =
    rawSeverity === "high" || rawSeverity === "low" ? rawSeverity : "medium";
  if (title.length === 0 || detail.length === 0 || action.length === 0) {
    return null;
  }
  return { title, detail, severity, action };
}

function normalizeAdvice(
  value: FarmAlertAdvice,
  model: string,
): FarmAlertAdvice {
  const important = Array.isArray(value.important_alerts)
    ? value.important_alerts.map(normalizeAlert).filter((
      item,
    ): item is FarmAlert => item != null)
    : [];
  const weather = Array.isArray(value.weather_alerts)
    ? value.weather_alerts.map(normalizeAlert).filter((
      item,
    ): item is FarmAlert => item != null)
    : [];
  const nextActions = Array.isArray(value.next_actions)
    ? value.next_actions.map((item) => String(item).trim()).filter(Boolean)
    : [];
  const rawConfidence = String(value.confidence ?? "medium").toLowerCase();
  const confidence: AlertSeverity =
    rawConfidence === "high" || rawConfidence === "low"
      ? rawConfidence
      : "medium";

  return {
    important_alerts: important.slice(0, 3),
    weather_alerts: weather.slice(0, 3),
    next_actions: nextActions.slice(0, 4),
    confidence,
    model,
  };
}

function extractDiseaseCandidates(body: Record<string, unknown>): string[] {
  const candidates: string[] = [];
  const screen = body.disease_screen;
  if (screen != null && typeof screen === "object") {
    const top = (screen as Record<string, unknown>).top_disease_risks;
    if (top != null && typeof top === "object") {
      candidates.push(...Object.keys(top as Record<string, unknown>));
    }
  }
  const focus = body.focus_cell;
  if (focus != null && typeof focus === "object") {
    const list = (focus as Record<string, unknown>).disease_candidates;
    if (Array.isArray(list)) {
      candidates.push(...list.map((item) => String(item)));
    }
  }
  return [...new Set(candidates)];
}

function buildPrompt(body: Record<string, unknown>, knowledge: string) {
  const farmName = String(body.farm_name ?? "active farm");
  const crop = String(body.crop ?? "millet");
  const growthStage = String(body.growth_stage ?? "unknown");
  const season = String(body.season ?? "kharif");
  const daysAfterSowing = Number(body.days_after_sowing ?? NaN);
  const sowingWeek = Number.isFinite(daysAfterSowing)
    ? Math.floor(daysAfterSowing / 7) + 1
    : null;
  const focusCell = body.focus_cell != null && typeof body.focus_cell === "object"
    ? body.focus_cell as Record<string, unknown>
    : null;

  return [
    "You are a conservative farm alert assistant for smallholder farmers in Maharashtra, India.",
    "Your task is to summarize disease-screening and weather-risk data into simple farmer-facing alerts.",
    "Rules:",
    "- Return ONLY valid JSON.",
    "- Do not recommend pesticide brands, chemical doses, exact fertilizer rates, yield, or income claims.",
    "- Treat satellite disease screening as a risk pre-screen, not a confirmed disease diagnosis.",
    "- Keep language plain and action-oriented.",
    "- Prefer scout/verify/drain/cover/delay/monitor actions before treatment advice.",
    "- Ground alerts and actions in the reference knowledge below (symptoms, IDM, resistant varieties, stage and district notes) when it is relevant to the supplied data.",
    "- Relate weather risk to the crop's week after sowing: the same rain or leaf wetness means different risk at germination vs tillering vs grain filling.",
    ...(focusCell != null
      ? [
        "- The farmer tapped ONE spot on their farm map (focus_cell below). Focus every alert and next action on that spot: what the issue likely is, how to walk there and verify it, and what photo of the plants would help confirm it.",
      ]
      : []),
    "",
    `Farm: ${farmName}`,
    `Crop: ${crop}`,
    `Growth stage: ${growthStage}`,
    `Season: ${season}`,
    ...(sowingWeek != null
      ? [`Week after sowing: ${sowingWeek} (day ${daysAfterSowing})`]
      : []),
    ...(knowledge.length > 0
      ? ["", "Reference knowledge (ICAR — for grounding only):", knowledge]
      : []),
    "",
    "Input data:",
    JSON.stringify({
      disease_screen: body.disease_screen ?? null,
      scout_zones: body.scout_zones ?? [],
      risk_cells: body.risk_cells ?? [],
      focus_cell: body.focus_cell ?? null,
      weather_context: body.weather_context ?? null,
      local_status: body.local_status ?? null,
    }),
    "",
    "Return this exact JSON shape:",
    JSON.stringify({
      important_alerts: [
        {
          title: "short alert title",
          detail: "why this matters based on the supplied data",
          severity: "high|medium|low",
          action: "one concrete next step",
        },
      ],
      weather_alerts: [
        {
          title: "short weather alert title",
          detail: "weather reason",
          severity: "high|medium|low",
          action: "one concrete next step",
        },
      ],
      next_actions: ["ordered action 1", "ordered action 2"],
      confidence: "high|medium|low",
    }),
  ].join("\n");
}

async function callQwen(prompt: string): Promise<FarmAlertAdvice> {
  const apiKey = Deno.env.get("QWEN_API_KEY") ?? Deno.env.get("QWEN3_API_KEY");
  const baseUrl = Deno.env.get("QWEN_BASE_URL") ??
    Deno.env.get("QWEN3_BASE_URL") ??
    "https://dashscope-intl.aliyuncs.com/compatible-mode/v1";
  const envModel = Deno.env.get("QWEN_MODEL") ?? Deno.env.get("QWEN3_MODEL");
  const models = envModel == null || envModel.trim().length === 0
    ? splitEnvList("QWEN_MODELS", DEFAULT_QWEN_MODELS)
    : [envModel.trim(), ...splitEnvList("QWEN_MODELS", DEFAULT_QWEN_MODELS)];

  if (!apiKey) {
    throw new Error("QWEN_API_KEY is not configured");
  }

  let lastError = "";
  for (const model of [...new Set(models)]) {
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content: prompt }],
        temperature: 0.15,
        max_tokens: 1200,
        response_format: { type: "json_object" },
        // DashScope compatible-mode reads this top-level (not under extra_body).
        // qwen3 thinking models reject non-streaming calls unless it is false.
        enable_thinking: false,
      }),
    });

    if (!response.ok) {
      lastError = `${model}: ${response.status} ${await response.text()}`;
      if (response.status === 404 || response.status === 400) continue;
      break;
    }

    const data = await response.json();
    const text = data.choices?.[0]?.message?.content ?? "";
    const parsed = safeJsonParse<FarmAlertAdvice>(
      typeof text === "string" ? text : JSON.stringify(text),
    );
    if (parsed != null) {
      return normalizeAdvice(parsed, `qwen/${model}`);
    }
    lastError = `${model}: invalid JSON alert response`;
  }

  throw new Error(lastError || "Qwen alert generation failed");
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const body = await req.json() as Record<string, unknown>;
    const knowledge = await retrieveKnowledge({
      crop: String(body.crop ?? "millet"),
      growthStage: String(body.growth_stage ?? ""),
      diseaseCandidates: extractDiseaseCandidates(body),
      queryText: body.focus_cell != null
        ? "scouting one field hotspot: symptoms to check, photo evidence, mitigation actions"
        : "disease and weather alerts with mitigation actions",
    });
    const advice = await callQwen(buildPrompt(body, formatKnowledge(knowledge)));
    return successResponse({ advice });
  } catch (error) {
    return errorResponse("farm-alert-advisor failed", 500, error);
  }
});
