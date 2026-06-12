import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";

type FarmStatusPayload = {
  type?: string;
  farmerId?: string;
  farmerName?: string;
  farmName?: string;
  crop?: string;
  variety?: string;
  location?: string;
  stage?: string;
  stageQuestion?: string;
  daysAfterSowing?: number;
  statusText?: string;
  priorStatus?: string | null;
  source?: string;
  updatedAt?: string;
};

function text(value: unknown): string {
  return String(value ?? "").trim();
}

function validatePayload(payload: FarmStatusPayload) {
  const missing = [
    ["farmerId", payload.farmerId],
    ["farmerName", payload.farmerName],
    ["farmName", payload.farmName],
    ["stage", payload.stage],
    ["statusText", payload.statusText],
  ]
    .filter(([, value]) => text(value).length === 0)
    .map(([key]) => key);

  if (missing.length > 0) {
    return `Missing required fields: ${missing.join(", ")}`;
  }
  return null;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const payload = await req.json() as FarmStatusPayload;
    const validationError = validatePayload(payload);
    if (validationError != null) return errorResponse(validationError, 400);

    const event = {
      type: text(payload.type) || "farm_status_update",
      farmer_id: text(payload.farmerId),
      farmer_name: text(payload.farmerName),
      farm_name: text(payload.farmName),
      crop: text(payload.crop),
      variety: text(payload.variety),
      location: text(payload.location),
      stage: text(payload.stage),
      stage_question: text(payload.stageQuestion),
      days_after_sowing: Number(payload.daysAfterSowing ?? 0),
      status_text: text(payload.statusText),
      prior_status: payload.priorStatus == null
        ? null
        : text(payload.priorStatus),
      source: text(payload.source) || "farmer_dashboard_status_chat",
      updated_at: text(payload.updatedAt) || new Date().toISOString(),
    };

    return successResponse({
      delivered: true,
      channel: "edge-function-ack",
      event,
    });
  } catch (error) {
    return errorResponse("farm-status-notify failed", 500, error);
  }
});
