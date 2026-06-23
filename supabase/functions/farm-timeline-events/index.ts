import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  assertLinkedFarm,
  normalizePhone,
  requireUserId,
  text,
} from "../_shared/farmer-links.ts";

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function payloadMap(raw: unknown): Record<string, unknown> {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    return raw as Record<string, unknown>;
  }
  return {};
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

    if (action === "create") {
      const eventType = text(body.eventType ?? body.event_type);
      const title = text(body.title);
      const message = text(body.message);
      if (eventType.length === 0 || title.length === 0 || message.length === 0) {
        return errorResponse(
          "eventType, title, and message are required",
          400,
          undefined,
          "invalid_timeline_event",
        );
      }

      const { data, error } = await supabase
        .from("farm_timeline_events")
        .insert({
          farm_id: farmId,
          farmer_id: farmerId || null,
          farmer_phone: phone,
          event_type: eventType,
          title,
          message,
          stage: text(body.stage) || null,
          severity: text(body.severity) || "info",
          payload: payloadMap(body.payload),
          created_at: text(body.createdAt ?? body.created_at) ||
            new Date().toISOString(),
        })
        .select("*")
        .single();

      if (error) throw error;
      return successResponse({ event: data }, 200, "farm_timeline_event_created");
    }

    const limitRaw = Number(body.limit ?? 80);
    const limit = Number.isFinite(limitRaw)
      ? Math.max(1, Math.min(120, Math.floor(limitRaw)))
      : 80;
    const { data, error } = await supabase
      .from("farm_timeline_events")
      .select("*")
      .eq("farm_id", farmId)
      .order("created_at", { ascending: false })
      .limit(limit);

    if (error) throw error;
    return successResponse(
      { events: Array.isArray(data) ? data : [] },
      200,
      "farm_timeline_events_loaded",
    );
  } catch (error) {
    return errorResponse(
      "farm-timeline-events failed",
      500,
      error,
      "farm_timeline_events_failed",
    );
  }
});
