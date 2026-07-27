import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { requireUserId, text } from "../_shared/farmer-links.ts";

type JsonRecord = Record<string, unknown>;

function record(raw: unknown): JsonRecord {
  return raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as JsonRecord
    : {};
}

function numberValue(raw: unknown): number | null {
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Supabase environment is incomplete.");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function indiaDate(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

async function canAccessFarm(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  farmId: string,
): Promise<boolean> {
  const { data: farm, error: farmError } = await supabase.from("farms")
    .select("id,user_id")
    .eq("id", farmId)
    .maybeSingle();
  if (farmError) throw farmError;
  const ownerId = text(record(farm).user_id);
  if (!ownerId) return false;
  if (ownerId === userId) return true;

  const { data: profiles, error: profileError } = await supabase
    .from("farmer_phone_profiles")
    .select("user_id,farmer_id,status")
    .in("user_id", [userId, ownerId])
    .eq("status", "active");
  if (profileError) throw profileError;
  const farmerIds = new Map<string, string>();
  for (const raw of Array.isArray(profiles) ? profiles : []) {
    const profile = record(raw);
    farmerIds.set(text(profile.user_id), text(profile.farmer_id));
  }
  const sessionFarmerId = farmerIds.get(userId) ?? "";
  return sessionFarmerId.length > 0 &&
    sessionFarmerId === farmerIds.get(ownerId);
}

function deriveTasks(userId: string, farmId: string, body: JsonRecord) {
  const context = record(body.context);
  const waterStress = numberValue(context.waterStress);
  const soilMoisture = numberValue(context.soilMoisture);
  const rainMm = numberValue(context.rainMm) ?? 0;
  const diseaseRisk = numberValue(context.diseaseRisk) ?? 0;
  const growthStage = text(context.growthStage) || "unknown";
  const needsWater = rainMm < 8 &&
    ((waterStress != null && waterStress >= 0.45) ||
      (soilMoisture != null && soilMoisture < 0.34));
  const taskDate = indiaDate();
  const common = { user_id: userId, farm_id: farmId, task_date: taskDate };
  const tasks: JsonRecord[] = [];

  if (needsWater) {
    tasks.push({
      ...common,
      task_key: "irrigation-check",
      task_type: "irrigation",
      title_key: "irrigation",
      description_key: "weather_rec_monitor_moisture",
      priority: waterStress != null && waterStress >= 0.7 ? "urgent" : "high",
      status: "pending",
      source_type: "weather_satellite",
      action_route: "weather",
      metadata: {
        water_stress: waterStress,
        soil_moisture: soilMoisture,
        rain_mm: rainMm,
      },
    });
  }

  if (diseaseRisk >= 0.55) {
    tasks.push({
      ...common,
      task_key: "crop-health-check",
      task_type: "crop_health",
      title_key: "disease_risk",
      description_key: "open_diagnose_flow",
      priority: diseaseRisk >= 0.72 ? "urgent" : "high",
      status: "pending",
      source_type: "disease_risk",
      action_route: "diagnose",
      metadata: { risk_score: diseaseRisk },
    });
  }

  if (diseaseRisk >= 0.72) {
    tasks.push({
      ...common,
      task_key: "pre-spray-inspection",
      task_type: "crop_inspection",
      title_key: "inspect_before_spray",
      description_key: "inspect_before_spray_desc",
      priority: "high",
      status: "pending",
      source_type: "disease_risk",
      action_route: "diagnose",
      metadata: { risk_score: diseaseRisk },
    });
  }

  tasks.push({
    ...common,
    task_key: "stage-plan-review",
    task_type: "stage_review",
    title_key: "review_crop_plan",
    description_key: "review_crop_plan_desc",
    priority: "normal",
    status: "pending",
    source_type: "crop_stage",
    action_route: "farm",
    metadata: { growth_stage: growthStage },
  });
  return tasks;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") {
    return errorResponse(
      "Method not allowed",
      405,
      undefined,
      "method_not_allowed",
    );
  }

  try {
    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;
    const body = record(await req.json());
    const action = text(body.action) || "sync";

    if (action === "update_status") {
      const taskId = text(body.taskId ?? body.task_id);
      const status = text(body.status).toLowerCase();
      if (!taskId || !["pending", "done", "snoozed"].includes(status)) {
        return errorResponse("A valid task and status are required.", 400);
      }
      const snoozedUntil = status === "snoozed"
        ? text(body.snoozedUntil ?? body.snoozed_until) ||
          new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString()
        : null;
      const { data, error } = await supabase.from("farmer_daily_tasks")
        .update({
          status,
          completed_at: status === "done" ? new Date().toISOString() : null,
          snoozed_until: snoozedUntil,
        })
        .eq("id", taskId)
        .eq("user_id", userId)
        .select("*")
        .single();
      if (error) throw error;
      return successResponse({ task: data }, 200, "farmer_daily_task_updated");
    }

    if (action !== "sync") {
      return errorResponse(
        "Unsupported action",
        400,
        undefined,
        "unsupported_action",
      );
    }

    const farmId = text(body.farmId ?? body.farm_id);
    if (!farmId) return errorResponse("Farm is required.", 400);
    if (!await canAccessFarm(supabase, userId, farmId)) {
      return errorResponse("Farm access denied.", 403);
    }

    const derived = deriveTasks(userId, farmId, body);
    const taskDate = indiaDate();
    const { data: existingRows, error: existingError } = await supabase
      .from("farmer_daily_tasks")
      .select("task_key,status,completed_at,snoozed_until")
      .eq("user_id", userId)
      .eq("farm_id", farmId)
      .eq("task_date", taskDate);
    if (existingError) throw existingError;
    const existing = new Map<string, JsonRecord>();
    for (const row of Array.isArray(existingRows) ? existingRows : []) {
      const item = record(row);
      existing.set(text(item.task_key), item);
    }
    const now = Date.now();
    const payload = derived.map((task) => {
      const saved = existing.get(text(task.task_key));
      if (!saved) return task;
      const snoozedUntil = text(saved.snoozed_until);
      const snoozeActive = text(saved.status) === "snoozed" &&
        snoozedUntil.length > 0 && Date.parse(snoozedUntil) > now;
      return {
        ...task,
        status: snoozeActive
          ? "snoozed"
          : text(saved.status) === "done"
          ? "done"
          : "pending",
        completed_at: text(saved.status) === "done" ? saved.completed_at : null,
        snoozed_until: snoozeActive ? saved.snoozed_until : null,
      };
    });
    const { data, error } = await supabase.from("farmer_daily_tasks")
      .upsert(payload, { onConflict: "user_id,farm_id,task_date,task_key" })
      .select("*");
    if (error) throw error;
    const priorityRank: Record<string, number> = {
      urgent: 0,
      high: 1,
      normal: 2,
    };
    const tasks = (Array.isArray(data) ? data : []).sort((left, right) => {
      return (priorityRank[text(left.priority)] ?? 9) -
        (priorityRank[text(right.priority)] ?? 9);
    });
    return successResponse(
      { tasks, taskDate },
      200,
      "farmer_daily_tasks_synced",
    );
  } catch (error) {
    return errorResponse(
      "Farmer daily tasks failed",
      500,
      error,
      "farmer_daily_tasks_failed",
    );
  }
});
