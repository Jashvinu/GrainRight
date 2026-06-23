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
  resolveKnowledgeCrop,
  retrieveKnowledge,
} from "../_shared/knowledge-retrieval.ts";

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function stageFromDays(days: number): string {
  if (days <= 20) return "germination-seedling";
  if (days <= 45) return "vegetative-tillering";
  if (days <= 75) return "booting-flowering";
  return "grain-filling-maturity";
}

function windowForStage(stage: string): string {
  const key = stage.toLowerCase();
  if (key.includes("seed")) return "0-20 DAS";
  if (key.includes("vegetative") || key.includes("tiller")) return "21-45 DAS";
  if (key.includes("flower") || key.includes("boot")) return "46-75 DAS";
  if (key.includes("grain") || key.includes("maturity")) return "76+ DAS";
  return "Stage window depends on sowing date";
}

function fallbackAdvice(cropKey: string, stage: string) {
  const isRice = cropKey === "rice";
  const isPearl = cropKey === "pearl_millet";
  const isFinger = cropKey === "finger_millet";
  const flowering = stage.toLowerCase().includes("flower") ||
    stage.toLowerCase().includes("boot");
  const grain = stage.toLowerCase().includes("grain") ||
    stage.toLowerCase().includes("maturity");

  return {
    water_need: isRice
      ? "Keep field moisture stable; rice is sensitive to dry spells."
      : flowering
      ? "Avoid moisture stress during booting and flowering."
      : "Maintain available soil moisture and avoid waterlogging.",
    disease_watch: isRice
      ? "Scout for blast, sheath blight, stem borer signs, and leaf spots."
      : isPearl
      ? "Scout for downy mildew, smut, ergot-like panicles, and dry patches."
      : isFinger
      ? "Scout for blast, rust, green ear, and humid canopy hotspots."
      : "Scout for leaf spots, blast-like lesions, rust, and water stress patches.",
    scout_task: grain
      ? "Inspect panicles or heads, grain fill, lodging, and late disease hotspots."
      : "Walk a W pattern and mark affected patches with photos and location.",
    next_action: flowering
      ? "Check water status and disease symptoms before the next irrigation or spray decision."
      : "Refresh farm status after the next field visit and save observations.",
  };
}

function fallbackTimeline(cropKey: string) {
  if (cropKey === "rice") {
    return [
      { stage: "germination-seedling", start_day: 0, end_day: 20, detail: "Rice seedling establishment: keep even shallow moisture, fill gaps, and check early yellowing." },
      { stage: "vegetative-tillering", start_day: 21, end_day: 45, detail: "Rice tillering: maintain field moisture, control weeds, and scout blast or stem borer symptoms." },
      { stage: "panicle-initiation-flowering", start_day: 46, end_day: 75, detail: "Rice flowering: avoid water stress and inspect neck blast, sheath blight, and panicle pests." },
      { stage: "grain-filling-maturity", start_day: 76, end_day: 125, detail: "Rice grain fill: keep moisture early, drain near maturity, and plan harvest when grains harden." },
    ];
  }
  if (cropKey === "pearl_millet") {
    return [
      { stage: "germination-seedling", start_day: 0, end_day: 15, detail: "Pearl millet emergence: check plant stand, crusting, seedling pests, and gap filling." },
      { stage: "vegetative-tillering", start_day: 16, end_day: 35, detail: "Pearl millet vegetative stage: control weeds, balance nutrition, and scout downy mildew or dry patches." },
      { stage: "booting-flowering", start_day: 36, end_day: 60, detail: "Pearl millet flowering: prevent heat or moisture stress and inspect panicle emergence." },
      { stage: "grain-filling-maturity", start_day: 61, end_day: 95, detail: "Pearl millet grain fill: watch lodging, smut, birds, and harvest when heads dry." },
    ];
  }
  return [
    { stage: "germination-seedling", start_day: 0, end_day: 20, detail: "Finger millet seedling stage: protect emergence, avoid waterlogging, and check gaps or seedling blight." },
    { stage: "vegetative-tillering", start_day: 21, end_day: 45, detail: "Finger millet tillering: weed control, balanced nutrition, and early blast scouting." },
    { stage: "booting-flowering", start_day: 46, end_day: 70, detail: "Finger millet flowering: avoid overhead irrigation and inspect neck or finger blast symptoms." },
    { stage: "grain-filling-maturity", start_day: 71, end_day: 110, detail: "Finger millet grain fill: scout rust, green ear, lodging, and harvest maturity." },
  ];
}

function timelineFromKnowledge(knowledge: Array<any>, cropKey: string) {
  const rows = knowledge
    .filter((chunk) => text(chunk.chunk_type) === "crop_cycle")
    .map((chunk) => {
      const metadata = typeof chunk.metadata === "object" && chunk.metadata !== null
        ? chunk.metadata as Record<string, unknown>
        : {};
      const start = Number(metadata.das_start ?? 0);
      const end = Number(metadata.das_end ?? 9999);
      return {
        stage: text(chunk.growth_stage),
        start_day: Number.isFinite(start) ? start : 0,
        end_day: Number.isFinite(end) ? end : 9999,
        detail: text(chunk.content),
      };
    })
    .filter((row) => row.stage.length > 0 || row.detail.length > 0)
    .sort((a, b) => a.start_day - b.start_day);
  return rows.length >= 3 ? rows : fallbackTimeline(cropKey);
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405, undefined, "method_not_allowed");
  }

  try {
    const body = await req.json();
    const phone = normalizePhone(body.phone);
    const farmerId = text(body.farmerId ?? body.farmer_id);
    const farmId = text(body.farmId ?? body.farm_id);
    const crop = text(body.crop) || "millet";
    const daysAfterSowing = Number(body.daysAfterSowing ?? body.days_after_sowing);
    const stage = text(body.growthStage ?? body.growth_stage) ||
      (Number.isFinite(daysAfterSowing) ? stageFromDays(daysAfterSowing) : "");

    if (phone.length !== 10) {
      return errorResponse("Enter a valid 10 digit mobile number", 400, undefined, "invalid_phone");
    }
    if (farmId.length === 0) {
      return errorResponse("farm_id is required", 400, undefined, "missing_farm_id");
    }

    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;
    const linkedFarm = await assertLinkedFarm(supabase, userId, phone, farmerId, farmId);
    if (linkedFarm instanceof Response) return linkedFarm;

    const cropContext = [
      stage,
      text(body.variety),
      text(body.district),
      Number.isFinite(daysAfterSowing) ? `${daysAfterSowing} days after sowing` : "",
    ].filter(Boolean).join(" ");
    const cropKey = resolveKnowledgeCrop(crop, cropContext);
    const knowledge = await retrieveKnowledge({
      crop,
      growthStage: stage,
      queryText: [
        "crop lifecycle",
        crop,
        cropContext,
        stage,
      ].filter(Boolean).join(" "),
      k: 5,
    });
    const fallback = fallbackAdvice(cropKey, stage);
    const cycleChunk = knowledge.find((chunk) => chunk.chunk_type === "crop_cycle") ??
      knowledge[0];
    const waterChunk = knowledge.find((chunk) => chunk.chunk_type === "water");
    const scoutChunk = knowledge.find((chunk) => chunk.chunk_type === "scout_task");
    const timeline = timelineFromKnowledge(knowledge, cropKey);

    return successResponse({
      crop: cropKey,
      growth_stage: stage,
      stage_window: windowForStage(stage),
      water_need: waterChunk?.content ?? fallback.water_need,
      disease_watch: cycleChunk?.content ?? fallback.disease_watch,
      scout_task: scoutChunk?.content ?? fallback.scout_task,
      next_action: fallback.next_action,
      timeline,
      knowledge,
    });
  } catch (error) {
    return errorResponse(
      "crop-lifecycle-advice failed",
      500,
      error,
      "crop_lifecycle_advice_failed",
    );
  }
});
