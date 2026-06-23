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
