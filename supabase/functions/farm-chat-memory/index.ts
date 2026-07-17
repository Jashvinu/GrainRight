import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  assertLinkedFarm,
  normalizePhone,
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

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405, undefined, "method_not_allowed");
  }

  try {
    const body = await req.json();
    const action = text(body.action || "list").toLowerCase();
    const phone = normalizePhone(body.phone ?? body.farmerPhone ?? body.farmer_phone);
    const farmerId = text(body.farmerId ?? body.farmer_id);
    const farmId = text(body.farmId ?? body.farm_id);

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

    if (action === "list") {
      const limitRaw = Number(body.limit ?? 30);
      const limit = Number.isFinite(limitRaw)
        ? Math.max(1, Math.min(80, Math.floor(limitRaw)))
        : 30;
      const { data, error } = await supabase
        .from("farm_chat_messages")
        .select("id,farm_id,farmer_id,farmer_phone,role,source,message,language,growth_stage,days_after_sowing,weather_snapshot,farm_context,created_at")
        .eq("farm_id", farmId)
        .order("created_at", { ascending: false })
        .limit(limit);
      if (error) throw error;
      const messages = Array.isArray(data) ? [...data].reverse() : [];
      return successResponse({ messages }, 200, "farm_chat_memory_listed");
    }

    if (action === "create") {
      const rawMessages = Array.isArray(body.messages)
        ? body.messages
        : [body.message ?? body];
      const createdAtFallback = new Date().toISOString();
      const rows = rawMessages
        .filter((raw: unknown) => raw != null && typeof raw === "object")
        .map((raw: unknown) => {
          const item = raw as Row;
          return {
            farm_id: farmId,
            farmer_id: farmerId || null,
            farmer_phone: phone,
            role: role(item.role),
            source: text(item.source) || "ai_chat",
            message: text(item.message).slice(0, 8000),
            language: text(item.language) || "en",
            growth_stage: text(item.growthStage ?? item.growth_stage) || null,
            days_after_sowing: intOrNull(item.daysAfterSowing ?? item.days_after_sowing),
            weather_snapshot: objectOrEmpty(item.weatherSnapshot ?? item.weather_snapshot),
            farm_context: objectOrEmpty(item.farmContext ?? item.farm_context),
            created_at: text(item.createdAt ?? item.created_at) || createdAtFallback,
          };
        })
        .filter((row: Row) => text(row.message).length > 0);

      if (rows.length === 0) {
        return errorResponse("message is required", 400, undefined, "missing_message");
      }

      const { data, error } = await supabase
        .from("farm_chat_messages")
        .insert(rows)
        .select("id,farm_id,farmer_id,farmer_phone,role,source,message,language,growth_stage,days_after_sowing,weather_snapshot,farm_context,created_at");
      if (error) throw error;
      return successResponse(
        { messages: Array.isArray(data) ? data : [] },
        200,
        "farm_chat_memory_saved",
      );
    }

    return errorResponse("Unsupported action", 400, undefined, "unsupported_action");
  } catch (error) {
    return errorResponse(
      "farm-chat-memory failed",
      500,
      error,
      "farm_chat_memory_failed",
    );
  }
});
