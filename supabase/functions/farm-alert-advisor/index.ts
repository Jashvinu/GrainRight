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
  category?: string;
  source_type?: string;
  confidence?: AlertSeverity;
  risk_score?: number;
  hotspot_count?: number;
  focus_cell?: Record<string, unknown>;
  evidence?: string[];
  research_refs?: string[];
};

type FarmAlertAdvice = {
  important_alerts: FarmAlert[];
  weather_alerts: FarmAlert[];
  next_actions: string[];
  confidence: AlertSeverity;
  model?: string;
  alerts?: FarmAlert[];
};

type AlertSignals = {
  maxRisk: number;
  highRiskCells: number;
  hotspotCount: number;
  significantHotspots: number;
  maxHotspotZ: number;
  waterStress: number;
  weatherRisk: number;
  rainMm: number;
  focusCell: Record<string, unknown> | null;
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
  const rawFocusCell = map.focus_cell;
  const evidence = Array.isArray(map.evidence)
    ? map.evidence.map((item) => String(item).trim()).filter(Boolean)
    : [];
  const researchRefs = Array.isArray(map.research_refs)
    ? map.research_refs.map((item) => String(item).trim()).filter(Boolean)
    : [];
  return {
    title,
    detail,
    severity,
    action,
    category: String(map.category ?? "").trim(),
    source_type: String(map.source_type ?? "").trim(),
    confidence: normalizeSeverity(map.confidence),
    risk_score: finiteNumber(map.risk_score),
    hotspot_count: Math.max(0, Math.round(finiteNumber(map.hotspot_count) ?? 0)),
    focus_cell: rawFocusCell != null && typeof rawFocusCell === "object"
      ? rawFocusCell as Record<string, unknown>
      : undefined,
    evidence,
    research_refs: researchRefs,
  };
}

function normalizeSeverity(value: unknown): AlertSeverity {
  const raw = String(value ?? "medium").toLowerCase();
  return raw === "high" || raw === "low" ? raw : "medium";
}

function finiteNumber(value: unknown): number | undefined {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function maxSignal(values: unknown[]): number {
  return values.reduce<number>((max, value) => {
    const parsed = finiteNumber(value) ?? 0;
    return Math.max(max, parsed);
  }, 0);
}

function mapNumber(map: Record<string, unknown>, keys: string[]): number {
  return maxSignal(keys.map((key) => map[key]));
}

function summarizeSignals(body: Record<string, unknown>): AlertSignals {
  const riskCells = Array.isArray(body.risk_cells)
    ? body.risk_cells.filter((item): item is Record<string, unknown> =>
      item != null && typeof item === "object")
    : [];
  const scoutZones = Array.isArray(body.scout_zones)
    ? body.scout_zones.filter((item): item is Record<string, unknown> =>
      item != null && typeof item === "object")
    : [];
  const rankedCells = [...riskCells].sort(
    (a, b) => mapNumber(b, ["composite_risk", "risk_score"]) -
      mapNumber(a, ["composite_risk", "risk_score"]),
  );
  const maxRisk = maxSignal([
    ...riskCells.map((cell) => mapNumber(cell, [
      "composite_risk",
      "risk_score",
      "max_risk_score",
    ])),
    ...scoutZones.map((zone) => mapNumber(zone, ["max_risk_score", "risk_score"])),
  ]);
  const highRiskCells = riskCells.filter((cell) =>
    mapNumber(cell, ["composite_risk", "risk_score"]) >= 0.55).length;
  const cellHotspots = riskCells.filter((cell) =>
    mapNumber(cell, ["gi_star_z", "hotspot_z"]) >= 1.96).length;
  const zoneHotspots = scoutZones.filter((zone) =>
    String(zone.significance ?? "").toLowerCase() === "significant" ||
    mapNumber(zone, ["hotspot_z", "gi_star_z"]) >= 1.96).length;
  const maxHotspotZ = maxSignal([
    ...riskCells.map((cell) => mapNumber(cell, ["gi_star_z", "hotspot_z"])),
    ...scoutZones.map((zone) => mapNumber(zone, ["hotspot_z", "gi_star_z"])),
  ]);
  const weather = body.weather_context != null &&
      typeof body.weather_context === "object"
    ? body.weather_context as Record<string, unknown>
    : {};
  const waterStressMap = weather.water_stress != null &&
      typeof weather.water_stress === "object"
    ? weather.water_stress as Record<string, unknown>
    : {};
  const cropWeather = weather.crop_health_weather != null &&
      typeof weather.crop_health_weather === "object"
    ? weather.crop_health_weather as Record<string, unknown>
    : {};
  const currentWeather = weather.live_current != null &&
      typeof weather.live_current === "object"
    ? weather.live_current as Record<string, unknown>
    : {};
  const waterStress = maxSignal([
    weather.water_stress,
    weather.water_stress_score,
    waterStressMap.score,
  ]);
  const weatherRisk = maxSignal([
    weather.weather_risk,
    weather.weather_risk_max,
    cropWeather.score,
  ]);
  const rainMm = maxSignal([
    weather.total_rain_mm,
    weather.rain_24h_mm,
    weather.rain_7d_mm,
    currentWeather.rain_mm,
  ]);
  return {
    maxRisk,
    highRiskCells,
    hotspotCount: Math.max(riskCells.length, scoutZones.reduce(
      (sum, zone) => sum + Math.max(0, Math.round(mapNumber(zone, ["cell_count"]))),
      0,
    )),
    significantHotspots: cellHotspots + zoneHotspots,
    maxHotspotZ,
    waterStress,
    weatherRisk,
    rainMm,
    focusCell: rankedCells[0] ?? null,
  };
}

function normalizeAdvice(
  value: FarmAlertAdvice,
  model: string,
  signals: AlertSignals,
  crop: string,
): FarmAlertAdvice {
  const important = Array.isArray(value.important_alerts)
    ? value.important_alerts
      .map(normalizeAlert)
      .filter((item): item is FarmAlert => item != null)
      .map((item) => enrichAlert(item, signals, crop))
    : [];
  const weather = Array.isArray(value.weather_alerts)
    ? value.weather_alerts
      .map(normalizeAlert)
      .filter((item): item is FarmAlert => item != null)
      .map((item) => enrichAlert(item, signals, crop))
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
    important_alerts: important.slice(0, 20),
    weather_alerts: weather.slice(0, 20),
    next_actions: nextActions.slice(0, 4),
    confidence,
    model,
    alerts: [...important, ...weather].slice(0, 20),
  };
}

function alertCategory(alert: FarmAlert): string {
  const supplied = String(alert.category ?? "").toLowerCase();
  if (supplied.length > 0) return supplied;
  const text = `${alert.title} ${alert.detail} ${alert.action}`.toLowerCase();
  if (text.includes("water") || text.includes("moisture") ||
      text.includes("irrigat")) return "water";
  if (text.includes("rain") || text.includes("weather") ||
      text.includes("humidity") || text.includes("wind")) return "weather";
  if (text.includes("stage") || text.includes("flower") ||
      text.includes("harvest")) return "crop_stage";
  return "hotspot";
}

function minimumSeverity(current: AlertSeverity, required: AlertSeverity) {
  const rank: Record<AlertSeverity, number> = { low: 0, medium: 1, high: 2 };
  return rank[required] > rank[current] ? required : current;
}

function enrichAlert(
  alert: FarmAlert,
  signals: AlertSignals,
  crop: string,
): FarmAlert {
  const category = alertCategory(alert);
  let severity = alert.severity;
  let score = alert.risk_score;
  if (category === "hotspot") {
    score = score ?? signals.maxRisk;
    if (signals.maxRisk >= 0.72 || signals.significantHotspots > 0) {
      severity = minimumSeverity(severity, "high");
    } else if (signals.maxRisk >= 0.55) {
      severity = minimumSeverity(severity, "medium");
    }
  } else if (category === "water") {
    score = score ?? signals.waterStress;
    if (signals.waterStress >= 0.66) {
      severity = minimumSeverity(severity, "high");
    } else if (signals.waterStress >= 0.45) {
      severity = minimumSeverity(severity, "medium");
    }
  } else if (category === "weather") {
    score = score ?? signals.weatherRisk;
    if (signals.weatherRisk >= 0.66 || signals.rainMm >= 50) {
      severity = minimumSeverity(severity, "high");
    } else if (signals.weatherRisk >= 0.45 || signals.rainMm >= 25) {
      severity = minimumSeverity(severity, "medium");
    }
  }
  const defaultRefs = crop.toLowerCase().includes("rice")
    ? ["icar_iirr_idm", "fao_ipm"]
    : ["icar_millet_advisory", "fao_ipm"];
  const evidence = [...(alert.evidence ?? [])];
  if (category === "hotspot" && signals.hotspotCount > 0) {
    evidence.push(`risk_cells:${signals.highRiskCells}`);
    if (signals.significantHotspots > 0) {
      evidence.push(`significant_hotspots:${signals.significantHotspots}`);
    }
  }
  if (category === "weather" && signals.rainMm > 0) {
    evidence.push(`rain_mm:${Number(signals.rainMm.toFixed(1))}`);
  }
  return {
    ...alert,
    severity,
    category,
    source_type: alert.source_type ||
      (category === "hotspot" ? "satellite_screening" :
        category === "weather" ? "weather_observation" : "crop_knowledge"),
    confidence: alert.confidence ?? "medium",
    risk_score: score == null ? undefined : Number(score.toFixed(3)),
    hotspot_count: Math.max(alert.hotspot_count ?? 0, signals.hotspotCount),
    focus_cell: alert.focus_cell ??
      (category === "hotspot" ? signals.focusCell ?? undefined : undefined),
    evidence: [...new Set(evidence)].slice(0, 4),
    research_refs: [...new Set([...(alert.research_refs ?? []), ...defaultRefs])],
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
  const languageCode = String(body.language ?? "en").trim().toLowerCase();
  const responseLanguage = languageCode === "mr"
    ? "Marathi (Devanagari script)"
    : languageCode === "hi"
    ? "Hindi (Devanagari script)"
    : "English";
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
    `- Write every alert title, detail, action and next_actions entry in ${responseLanguage}.`,
    "- Keep only severity and confidence enum values in English: high, medium, or low.",
    "- Prefer scout/verify/drain/cover/delay/monitor actions before treatment advice.",
    "- A high alert must explain the evidence and provide one immediate field action; never state that satellite data confirms disease.",
    "- For hotspot alerts, return category=hotspot and copy the highest-risk focus_cell from the supplied risk_cells when possible.",
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
          category: "hotspot|weather|water|crop_stage",
        },
      ],
      weather_alerts: [
        {
          title: "short weather alert title",
          detail: "weather reason",
          severity: "high|medium|low",
          action: "one concrete next step",
          category: "weather",
        },
      ],
      next_actions: ["ordered action 1", "ordered action 2"],
      confidence: "high|medium|low",
    }),
  ].join("\n");
}

async function callQwen(
  prompt: string,
  body: Record<string, unknown>,
): Promise<FarmAlertAdvice> {
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
      return normalizeAdvice(
        parsed,
        `qwen/${model}`,
        summarizeSignals(body),
        String(body.crop ?? "millet"),
      );
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
        ? [
          "scouting one field hotspot: symptoms to check, photo evidence, mitigation actions",
          String(body.variety ?? ""),
          String(body.district ?? ""),
        ].filter(Boolean).join(" ")
        : [
          "disease and weather alerts with mitigation actions",
          String(body.variety ?? ""),
          String(body.district ?? ""),
        ].filter(Boolean).join(" "),
    });
    const advice = await callQwen(
      buildPrompt(body, formatKnowledge(knowledge)),
      body,
    );
    return successResponse({ advice });
  } catch (error) {
    return errorResponse("farm-alert-advisor failed", 500, error);
  }
});
