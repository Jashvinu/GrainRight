import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  assertLinkedFarm,
  normalizePhone,
  optionalSchemaError,
  requireUserId,
  text,
} from "../_shared/farmer-links.ts";

type Row = Record<string, unknown>;

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function objectOrEmpty(raw: unknown): Row {
  return raw != null && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Row
    : {};
}

function role(raw: unknown): "farmer" | "assistant" | "system" {
  const value = text(raw).toLowerCase();
  if (value === "farmer" || value === "assistant" || value === "system") {
    return value;
  }
  return "system";
}

function intOrNull(raw: unknown): number | null {
  const value = Number(raw);
  if (!Number.isFinite(value)) return null;
  return Math.max(0, Math.floor(value));
}

function statusChatRows(args: {
  rawMessages: unknown;
  farmId: string;
  farmerId: string;
  phone: string;
  stage: string;
  daysAfterSowing: number | null;
  statusText: string;
  source: string;
  weatherSnapshot: Row;
  farmContext: Row;
  createdAt: string;
}) {
  const rawList = Array.isArray(args.rawMessages) ? args.rawMessages : [];
  const rows = rawList
    .filter((raw: unknown) => raw != null && typeof raw === "object")
    .map((raw: unknown) => {
      const item = raw as Row;
      const itemWeather = objectOrEmpty(item.weatherSnapshot ?? item.weather_snapshot);
      const itemContext = objectOrEmpty(item.farmContext ?? item.farm_context);
      return {
        farm_id: args.farmId,
        farmer_id: args.farmerId || null,
        farmer_phone: args.phone,
        role: role(item.role),
        source: text(item.source) || args.source,
        message: text(item.message).slice(0, 8000),
        language: text(item.language) || "en",
        growth_stage: text(item.growthStage ?? item.growth_stage) || args.stage,
        days_after_sowing: intOrNull(item.daysAfterSowing ?? item.days_after_sowing) ??
          args.daysAfterSowing,
        weather_snapshot: Object.keys(itemWeather).length === 0
          ? args.weatherSnapshot
          : itemWeather,
        farm_context: Object.keys(itemContext).length === 0
          ? args.farmContext
          : itemContext,
        created_at: text(item.createdAt ?? item.created_at) || args.createdAt,
      };
    })
    .filter((row: Row) => text(row.message).length > 0);

  if (rows.length > 0) return rows;
  return [{
    farm_id: args.farmId,
    farmer_id: args.farmerId || null,
    farmer_phone: args.phone,
    role: "farmer",
    source: args.source,
    message: args.statusText,
    language: "en",
    growth_stage: args.stage,
    days_after_sowing: args.daysAfterSowing,
    weather_snapshot: args.weatherSnapshot,
    farm_context: args.farmContext,
    created_at: args.createdAt,
  }];
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
    const statusText = text(body.statusText ?? body.status_text);
    const stage = text(body.stage ?? body.growth_stage);

    if (phone.length !== 10) {
      return errorResponse("Enter a valid 10 digit mobile number", 400, undefined, "invalid_phone");
    }
    if (farmId.length === 0) {
      return errorResponse("farm_id is required", 400, undefined, "missing_farm_id");
    }
    if (statusText.length === 0 || stage.length === 0) {
      return errorResponse("stage and statusText are required", 400, undefined, "invalid_status_update");
    }

    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;
    const linkedFarm = await assertLinkedFarm(
      supabase,
      userId,
      phone,
      farmerId,
      farmId,
    );
    if (linkedFarm instanceof Response) return linkedFarm;

    const row = {
      farm_id: farmId,
      farmer_id: farmerId || null,
      farmer_phone: phone,
      farmer_name: text(body.farmerName ?? body.farmer_name),
      farm_name: text(body.farmName ?? body.farm_name),
      crop: text(body.crop),
      variety: text(body.variety),
      growth_stage: stage,
      stage_question: text(body.stageQuestion ?? body.stage_question),
      days_after_sowing: Number.isFinite(Number(body.daysAfterSowing ?? body.days_after_sowing))
        ? Number(body.daysAfterSowing ?? body.days_after_sowing)
        : null,
      status_text: statusText,
      prior_status: body.priorStatus == null
        ? null
        : text(body.priorStatus ?? body.prior_status),
      source: text(body.source) || "farmer_dashboard_status_chat",
      created_at: text(body.updatedAt ?? body.updated_at) || new Date().toISOString(),
    };
    const weatherSnapshot = objectOrEmpty(
      body.weatherSnapshot ?? body.weather_snapshot,
    );
    const farmContext = objectOrEmpty(body.farmContext ?? body.farm_context);

    const { data: statusRow, error: insertError } = await supabase
      .from("farm_status_updates")
      .insert(row)
      .select()
      .maybeSingle();
    if (insertError) throw insertError;

    const { error: updateError } = await supabase
      .from("farms")
      .update({
        current_status: statusText,
        current_status_stage: stage,
        current_status_updated_at: row.created_at,
      })
      .eq("id", farmId);
    if (updateError) throw updateError;

    const chatRows = statusChatRows({
      rawMessages: body.chatMessages ?? body.chat_messages,
      farmId,
      farmerId,
      phone,
      stage,
      daysAfterSowing: row.days_after_sowing,
      statusText,
      source: row.source,
      weatherSnapshot,
      farmContext,
      createdAt: row.created_at,
    });
    const { data: chatMemoryRows, error: chatMemoryError } = await supabase
      .from("farm_chat_messages")
      .insert(chatRows)
      .select("id");
    if (chatMemoryError && !optionalSchemaError(chatMemoryError)) {
      throw chatMemoryError;
    }
    const chatMessageIds = Array.isArray(chatMemoryRows)
      ? chatMemoryRows.map((item) => text(item.id)).filter(Boolean)
      : [];

    const { data: timelineEvent, error: timelineError } = await supabase
      .from("farm_timeline_events")
      .insert({
        farm_id: farmId,
        farmer_id: farmerId || null,
        farmer_phone: phone,
        event_type: "farm_status_update",
        title: `${row.farm_name || "Farm"} status updated`,
        message: statusText,
        stage,
        severity: "info",
        payload: {
          status_update_id: statusRow?.id ?? null,
          farm_name: row.farm_name,
          crop: row.crop,
          variety: row.variety,
          days_after_sowing: row.days_after_sowing,
          stage_question: row.stage_question,
          prior_status: row.prior_status,
          chat_message_ids: chatMessageIds,
          weather: weatherSnapshot,
          farm_context: farmContext,
          source: row.source,
        },
        created_at: row.created_at,
      })
      .select("*")
      .maybeSingle();

    return successResponse(
      {
        status_update: statusRow,
        timeline_event: timelineError ? null : timelineEvent,
        timeline_error: timelineError?.message ?? null,
        chat_memory_count: chatMessageIds.length,
        chat_memory_error: chatMemoryError?.message ?? null,
        farm: {
          id: farmId,
          current_status: statusText,
          current_status_stage: stage,
          current_status_updated_at: row.created_at,
        },
      },
      200,
      "farm_status_updated",
    );
  } catch (error) {
    return errorResponse(
      "farm-status-update failed",
      500,
      error,
      "farm_status_update_failed",
    );
  }
});
