import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  assertLinkedFarm,
  normalizePhone,
  requireUserId,
  text,
} from "../_shared/farmer-links.ts";
import {
  formatKnowledge,
  resolveKnowledgeCrop,
  retrieveKnowledge,
} from "../_shared/knowledge-retrieval.ts";
import type { KnowledgeChunk } from "../_shared/knowledge-retrieval.ts";
import fingerMillet from "../_shared/knowledge/finger_millet.json" with {
  type: "json",
};
import riceLifecycle from "../_shared/knowledge/rice_lifecycle.json" with {
  type: "json",
};
import pearlMilletLifecycle from "../_shared/knowledge/pearl_millet_lifecycle.json" with {
  type: "json",
};
import fingerMilletLifecycle from "../_shared/knowledge/finger_millet_lifecycle.json" with {
  type: "json",
};
import assetFingerMillet from "../_shared/knowledge/asset_finger_millet_deep_2026.json" with {
  type: "json",
};
import assetPearlMillet from "../_shared/knowledge/asset_pearl_millet_deep_2026.json" with {
  type: "json",
};
import assetRice from "../_shared/knowledge/asset_rice_deep_2026.json" with {
  type: "json",
};

type Row = Record<string, unknown>;
type Confidence = "high" | "medium" | "low";

type AssistantAnswer = {
  answer: string;
  summary?: string;
  actions: string[];
  warnings: string[];
  confidence: Confidence;
  model?: string;
};

type KnowledgeRecord = {
  chunk_type: string;
  disease?: string | null;
  growth_stage?: string | null;
  district?: string | null;
  content: string;
};

type KnowledgeDoc = {
  doc_source: string;
  crop: string;
  records: KnowledgeRecord[];
};

const DEFAULT_QWEN_MODELS = ["qwen3-235b-a22b", "qwen3-72b", "qwen3-32b"];
const BUNDLED_DOCS: KnowledgeDoc[] = [
  fingerMillet as KnowledgeDoc,
  riceLifecycle as KnowledgeDoc,
  pearlMilletLifecycle as KnowledgeDoc,
  fingerMilletLifecycle as KnowledgeDoc,
  assetFingerMillet as KnowledgeDoc,
  assetPearlMillet as KnowledgeDoc,
  assetRice as KnowledgeDoc,
];

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function rows(data: unknown): Row[] {
  return Array.isArray(data) ? data as Row[] : [];
}

function splitEnvList(name: string, fallback: string[]) {
  const raw = Deno.env.get(name)?.trim();
  return raw == null || raw.length === 0
    ? fallback
    : raw.split(",").map((item) => item.trim()).filter(Boolean);
}

function num(raw: unknown): number | null {
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw === "string" && raw.trim().length > 0) {
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function rowNum(row: Row, keys: string[]): number | null {
  for (const key of keys) {
    const value = num(row[key]);
    if (value !== null) return value;
  }
  return null;
}

function scanDate(row: Row): string {
  return text(row.scan_date ?? row.created_at ?? row.updated_at);
}

function latestScanDate(data: Row[]): string {
  return data.map(scanDate).find((value) => value.length > 0) ?? "";
}

function sameScanRows(data: Row[], scan: string): Row[] {
  if (scan.length === 0) return data;
  const latest = data.filter((row) => scanDate(row) === scan);
  return latest.length > 0 ? latest : data;
}

function diseaseScores(row: Row): Record<string, number> {
  const scores: Record<string, number> = {};
  const perDisease = row.per_disease;
  if (perDisease && typeof perDisease === "object" && !Array.isArray(perDisease)) {
    for (const [name, value] of Object.entries(perDisease as Row)) {
      const parsed = num(value);
      if (parsed !== null) scores[name] = parsed;
    }
  }
  for (const key of [
    "rice_blast_risk",
    "sheath_blight_risk",
    "blb_risk",
    "downy_mildew_risk",
    "leaf_spot_risk",
    "charcoal_rot_risk",
  ]) {
    const parsed = num(row[key]);
    if (parsed !== null) scores[key.replace(/_risk$/, "")] = parsed;
  }
  return scores;
}

function topDiseaseRisks(data: Row[]): Record<string, number> {
  const risks: Record<string, number> = {};
  for (const row of data) {
    for (const [name, value] of Object.entries(diseaseScores(row))) {
      risks[name] = Math.max(risks[name] ?? 0, value);
    }
  }
  return risks;
}

function maxDiseaseRisk(data: Row[], risks: Record<string, number>): number {
  let max = 0;
  for (const row of data) {
    max = Math.max(max, rowNum(row, [
      "composite_risk",
      "max_risk_score",
      "risk_score",
    ]) ?? 0);
  }
  for (const value of Object.values(risks)) max = Math.max(max, value);
  return max;
}

async function safeRows(query: PromiseLike<{ data: unknown; error: unknown }>) {
  try {
    const { data, error } = await query;
    if (error) return [];
    return rows(data);
  } catch {
    return [];
  }
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

function normalizeList(raw: unknown, limit: number): string[] {
  return (Array.isArray(raw) ? raw : [])
    .map((item) => String(item).trim())
    .filter(Boolean)
    .slice(0, limit);
}

function normalizeAnswer(raw: unknown, model: string): AssistantAnswer | null {
  if (raw == null || typeof raw !== "object") return null;
  const map = raw as Row;
  const answer = text(map.answer);
  if (answer.length === 0) return null;
  const rawConfidence = text(map.confidence).toLowerCase();
  const confidence: Confidence = rawConfidence === "high" || rawConfidence === "low"
    ? rawConfidence
    : "medium";
  return {
    answer,
    summary: text(map.summary) || undefined,
    actions: normalizeList(map.actions ?? map.next_actions, 4),
    warnings: normalizeList(map.warnings ?? map.cautions, 3),
    confidence,
    model,
  };
}

function languageName(code: string): string {
  if (code === "hi") return "Hindi";
  if (code === "mr") return "Marathi";
  return "English";
}

function selectedFarmLabel(code: string): string {
  if (code === "hi") return "चुना गया खेत";
  if (code === "mr") return "निवडलेले शेत";
  return "selected farm";
}

function compactFarmContext(
  farm: Row,
  question: string,
  stage: string,
  daysAfterSowing: number | null,
  scan: string,
  risks: Record<string, number>,
  maxRisk: number,
  timeline: Row[],
) {
  return {
    farm_id: text(farm.id),
    farm_name: text(farm.name),
    crop: text(farm.crop),
    variety: text(farm.variety),
    season: text(farm.season),
    irrigation: text(farm.irrigation),
    soil_type: text(farm.soil_type),
    current_status: text(farm.current_status),
    growth_stage: stage,
    sowing_date: text(farm.sowing_date),
    days_after_sowing: daysAfterSowing,
    disease_scan_date: scan,
    top_disease_risks: risks,
    max_disease_risk: maxRisk,
    timeline_events: timeline.length,
    latest_timeline: timeline.slice(0, 5).map((row) => ({
      event_type: text(row.event_type),
      title: text(row.title),
      message: text(row.message),
      stage: text(row.stage),
      created_at: text(row.created_at),
    })),
    question,
  };
}

function buildPrompt(params: {
  question: string;
  language: string;
  farmContext: Row;
  diseaseRows: Row[];
  scoutRows: Row[];
  knowledge: string;
}) {
  return [
    "You are a conservative AI farm assistant for smallholder farmers in Maharashtra, India.",
    `Answer in ${languageName(params.language)} only.`,
    `Every JSON string value you return, including answer, summary, actions, and warnings, must be written in ${languageName(params.language)}.`,
    "Do not leave English headings, labels, cautions, or action text unless it is an unavoidable crop, disease, unit, or technical index name.",
    "Use the farmer's selected farm context and reference knowledge. Do not answer as a generic chatbot.",
    "Rules:",
    "- Return ONLY valid JSON.",
    "- Answer the actual question directly first.",
    "- Give 2 to 4 practical next actions when useful.",
    "- Treat satellite disease data as risk screening, not confirmed diagnosis.",
    "- Do not recommend pesticide brands, chemical doses, exact fertilizer rates, yield guarantees, or income claims.",
    "- If data is missing or stale, say what data the farmer should refresh or capture.",
    "- Keep the answer farmer-facing and concise.",
    "",
    "Selected farm context:",
    JSON.stringify(params.farmContext),
    "",
    "Recent disease context:",
    JSON.stringify({
      scout_zones: params.scoutRows.slice(0, 8),
      risk_cells: params.diseaseRows.slice(0, 12),
    }),
    ...(params.knowledge.length > 0
      ? ["", "Reference knowledge for grounding:", params.knowledge]
      : []),
    "",
    `Farmer question: ${params.question}`,
    "",
    "Return this exact JSON shape:",
    JSON.stringify({
      answer: "direct farmer-facing answer",
      summary: "one short reason",
      actions: ["next action 1", "next action 2"],
      warnings: ["important caution"],
      confidence: "high|medium|low",
    }),
  ].join("\n");
}

async function callQwen(prompt: string): Promise<AssistantAnswer> {
  const apiKey = Deno.env.get("QWEN_API_KEY") ?? Deno.env.get("QWEN3_API_KEY");
  const baseUrl = Deno.env.get("QWEN_BASE_URL") ??
    Deno.env.get("QWEN3_BASE_URL") ??
    "https://dashscope-intl.aliyuncs.com/compatible-mode/v1";
  const envModel = Deno.env.get("QWEN_MODEL") ?? Deno.env.get("QWEN3_MODEL");
  const models = envModel == null || envModel.trim().length === 0
    ? splitEnvList("QWEN_MODELS", DEFAULT_QWEN_MODELS)
    : [envModel.trim(), ...splitEnvList("QWEN_MODELS", DEFAULT_QWEN_MODELS)];

  if (!apiKey) throw new Error("QWEN_API_KEY is not configured");

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
        temperature: 0.2,
        max_tokens: 1000,
        response_format: { type: "json_object" },
        enable_thinking: false,
      }),
    });

    if (!response.ok) {
      lastError = `${model}: ${response.status} ${await response.text()}`;
      if (response.status === 404 || response.status === 400) continue;
      break;
    }

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content ?? "";
    const parsed = safeJsonParse<AssistantAnswer>(
      typeof content === "string" ? content : JSON.stringify(content),
    );
    const answer = normalizeAnswer(parsed, `qwen/${model}`);
    if (answer != null) return answer;
    lastError = `${model}: invalid JSON assistant response`;
  }

  throw new Error(lastError || "Qwen assistant generation failed");
}

function fallbackAnswer(params: {
  language: string;
  farmName: string;
  crop: string;
  question: string;
  maxRisk: number;
  stage: string;
}): AssistantAnswer {
  const wantsWater = /water|irrig|rain|moisture|pani|पानी|सिंच|पाणी|सिंचन/i.test(
    params.question,
  );
  const wantsDisease = /disease|leaf|spot|risk|blast|रोग|पान|जोखीम|धोका/i.test(
    params.question,
  );
  const highRisk = params.maxRisk >= 0.55;

  if (params.language === "hi") {
    return {
      answer: wantsWater
        ? `${params.farmName} के लिए अभी सिंचाई से पहले खेत की नमी और बारिश की संभावना जांचें. ${params.crop} में ज्यादा पानी रुकने से रोग का जोखिम बढ़ सकता है.`
        : wantsDisease || highRisk
        ? `${params.farmName} में रोग जोखिम की जांच करें. प्रभावित पत्तियों और बालियों की साफ फोटो लें और खेत में W आकार में चलकर धब्बे, पीलापन या सड़न देखें.`
        : `${params.farmName} के लिए ताजा खेत स्थिति, फोटो और मौसम डेटा अपडेट करें ताकि अगला सही कदम बताया जा सके.`,
      actions: [
        "आज की खेत स्थिति अपडेट करें.",
        "समस्या वाली जगह की साफ फोटो लें.",
        "तेज रोग लक्षण दिखें तो स्थानीय कृषि अधिकारी से पुष्टि करें.",
      ],
      warnings: ["यह सलाह स्क्रीनिंग डेटा पर आधारित है, पक्का रोग निदान नहीं."],
      confidence: "low",
      model: "fallback",
    };
  }
  if (params.language === "mr") {
    return {
      answer: wantsWater
        ? `${params.farmName} साठी सिंचनापूर्वी मातीतील ओलावा आणि पावसाची शक्यता तपासा. ${params.crop} मध्ये पाणी साचल्यास रोगाचा धोका वाढू शकतो.`
        : wantsDisease || highRisk
        ? `${params.farmName} मध्ये रोगाचा धोका तपासा. प्रभावित पाने किंवा कणसांचे स्पष्ट फोटो घ्या आणि शेतात W पद्धतीने चालून डाग, पिवळेपणा किंवा कुज तपासा.`
        : `${params.farmName} साठी ताजी शेत स्थिती, फोटो आणि हवामान डेटा अपडेट करा म्हणजे पुढील योग्य कृती सांगता येईल.`,
      actions: [
        "आजची शेत स्थिती अपडेट करा.",
        "समस्या असलेल्या ठिकाणाचा स्पष्ट फोटो घ्या.",
        "तीव्र लक्षणे दिसल्यास स्थानिक कृषी अधिकाऱ्याकडून खात्री करा.",
      ],
      warnings: ["ही सूचना स्क्रीनिंग डेटावर आधारित आहे; निश्चित रोग निदान नाही."],
      confidence: "low",
      model: "fallback",
    };
  }
  return {
    answer: wantsWater
      ? `For ${params.farmName}, check soil moisture and rain chance before irrigation. In ${params.crop}, standing water can increase disease risk.`
      : wantsDisease || highRisk
      ? `Check disease risk in ${params.farmName}. Take clear photos of affected leaves or panicles and walk the field in a W pattern to verify spots, yellowing, or rot.`
      : `Update fresh farm status, photos, and weather data for ${params.farmName} so the next action can be more specific.`,
    actions: [
      "Update today's farm status.",
      "Capture a clear photo of the problem area.",
      "Confirm severe symptoms with a local agriculture officer.",
    ],
    warnings: ["This is based on screening data, not a confirmed diagnosis."],
    confidence: "low",
    model: "fallback",
  };
}

function sourceList(knowledge: KnowledgeChunk[]) {
  return knowledge.slice(0, 6).map((chunk) => ({
    chunk_type: chunk.chunk_type,
    disease: chunk.disease,
    growth_stage: chunk.growth_stage,
    district: chunk.district,
    similarity: chunk.similarity,
  }));
}

function bundledKnowledge(args: {
  crop: string;
  growthStage: string;
  question: string;
  diseaseCandidates: string[];
}): KnowledgeChunk[] {
  const cropKey = resolveKnowledgeCrop(
    args.crop,
    [
      args.growthStage,
      args.question,
      ...args.diseaseCandidates,
    ].join(" "),
  );
  const tokens = [
    cropKey,
    args.growthStage,
    args.question,
    ...args.diseaseCandidates,
  ]
    .join(" ")
    .toLowerCase()
    .split(/[^a-z0-9_]+/)
    .filter((token) => token.length >= 3);
  const uniqueTokens = [...new Set(tokens)];
  const docs = BUNDLED_DOCS.filter((doc) => {
    if (doc.crop === cropKey) return true;
    if (cropKey === "millet") return doc.crop === "millet" || doc.crop.includes("millet");
    return doc.crop === "millet" && cropKey.includes("millet");
  });

  return docs
    .flatMap((doc) =>
      (Array.isArray(doc.records) ? doc.records : []).map((record) => {
        const haystack = [
          record.chunk_type,
          record.disease ?? "",
          record.growth_stage ?? "",
          record.district ?? "",
          record.content,
        ].join(" ").toLowerCase();
        let score = 0;
        for (const token of uniqueTokens) {
          if (haystack.includes(token)) score += 1;
        }
        if (
          args.growthStage.length > 0 &&
          haystack.includes(args.growthStage.toLowerCase())
        ) {
          score += 3;
        }
        if (record.chunk_type === "crop_cycle") score += 1;
        return {
          chunk: {
            chunk_type: record.chunk_type,
            disease: record.disease ?? null,
            growth_stage: record.growth_stage ?? null,
            district: record.district ?? null,
            content: record.content,
            similarity: score,
          } satisfies KnowledgeChunk,
          score,
        };
      })
    )
    .filter((item) => text(item.chunk.content).length > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 6)
    .map((item) => item.chunk);
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405, undefined, "method_not_allowed");
  }

  try {
    const body = await req.json();
    const phone = normalizePhone(body.phone ?? body.farmerPhone ?? body.farmer_phone);
    const farmerId = text(body.farmerId ?? body.farmer_id);
    const farmId = text(body.farmId ?? body.farm_id);
    const question = text(body.question).slice(0, 1000);
    const language = ["hi", "mr"].includes(text(body.language))
      ? text(body.language)
      : "en";

    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid 10 digit mobile number",
        400,
        undefined,
        "invalid_phone",
      );
    }
    if (farmId.length === 0) {
      return errorResponse("farm_id is required", 400, undefined, "missing_farm_id");
    }
    if (question.length === 0) {
      return errorResponse("question is required", 400, undefined, "missing_question");
    }

    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;
    const linkedFarm = await assertLinkedFarm(supabase, userId, phone, farmerId, farmId);
    if (linkedFarm instanceof Response) return linkedFarm;

    const { data: farm, error: farmError } = await supabase
      .from("farms")
      .select("id,name,geometry,bounds,area_hectares,area_acres,user_id,created_at,crop,variety,previous_crop,season,irrigation,soil_type,ownership_type,seed_source,harvest_intent,sowing_date,current_status,current_status_stage,current_status_updated_at")
      .eq("id", farmId)
      .maybeSingle();
    if (farmError) throw farmError;
    if (!farm) {
      return errorResponse("Farm not found for this farmer", 404, undefined, "farmer_farm_not_found");
    }

    const [zoneData, cellData, timeline] = await Promise.all([
      safeRows(
        supabase
          .from("disease_scout_zones")
          .select("*")
          .eq("farm_id", farmId)
          .order("scan_date", { ascending: false })
          .order("zone_rank", { ascending: true })
          .limit(40),
      ),
      safeRows(
        supabase
          .from("disease_risk_cells")
          .select("*")
          .eq("farm_id", farmId)
          .order("scan_date", { ascending: false })
          .order("composite_risk", { ascending: false })
          .limit(80),
      ),
      safeRows(
        supabase
          .from("farm_timeline_events")
          .select("event_type,title,message,stage,severity,created_at,payload")
          .eq("farm_id", farmId)
          .order("created_at", { ascending: false })
          .limit(12),
      ),
    ]);

    const scan = latestScanDate(cellData) || latestScanDate(zoneData);
    const latestCells = sameScanRows(cellData, scan);
    const latestZones = sameScanRows(zoneData, scan);
    const risks = topDiseaseRisks(latestCells);
    const maxRisk = maxDiseaseRisk(latestCells, risks);
    const stage = text(body.growthStage ?? body.growth_stage) ||
      text(farm.current_status_stage);
    const daysRaw = num(body.daysAfterSowing ?? body.days_after_sowing);
    const daysAfterSowing = daysRaw === null ? null : Math.max(0, Math.floor(daysRaw));
    const crop = text(farm.crop) || text(body.crop) || "millet";
    const diseaseCandidates = Object.keys(risks);

    const retrievedKnowledge = await retrieveKnowledge({
      crop,
      growthStage: stage,
      diseaseCandidates,
      queryText: [
        question,
        crop,
        text(farm.variety),
        stage,
        text(farm.current_status),
        ...timeline.slice(0, 4).map((row) => `${text(row.title)} ${text(row.message)}`),
      ].filter(Boolean).join(" "),
      k: 6,
    });
    const knowledge = retrievedKnowledge.length > 0
      ? retrievedKnowledge
      : bundledKnowledge({
        crop,
        growthStage: stage,
        question,
        diseaseCandidates,
      });

    const farmContext = compactFarmContext(
      farm as Row,
      question,
      stage,
      daysAfterSowing,
      scan,
      risks,
      maxRisk,
      timeline,
    );
    const fallback = fallbackAnswer({
      language,
      farmName: text(farm.name) || selectedFarmLabel(language),
      crop,
      question,
      maxRisk,
      stage,
    });

    let answer = fallback;
    try {
      answer = await callQwen(
        buildPrompt({
          question,
          language,
          farmContext,
          diseaseRows: latestCells,
          scoutRows: latestZones,
          knowledge: formatKnowledge(knowledge),
        }),
      );
    } catch (_error) {
      answer = fallback;
    }

    return successResponse(
      {
        answer: answer.answer,
        summary: answer.summary,
        actions: answer.actions,
        warnings: answer.warnings,
        sources: sourceList(knowledge),
        farm_context: farmContext,
        confidence: answer.confidence,
        model: answer.model,
      },
      200,
      "farm_assistant_chat_success",
    );
  } catch (error) {
    return errorResponse(
      "farm-assistant-chat failed",
      500,
      error,
      "farm_assistant_chat_failed",
    );
  }
});
