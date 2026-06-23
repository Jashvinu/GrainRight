import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  assertLinkedFarm,
  loadLinkedUserIds,
  normalizePhone,
  requireUserId,
} from "../_shared/farmer-links.ts";

type FarmStatusPayload = {
  action?: string;
  notificationId?: string;
  type?: string;
  farmerId?: string;
  farmId?: string;
  farmerPhone?: string;
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
  title?: string;
  message?: string;
  source?: string;
  updatedAt?: string;
  payload?: Record<string, unknown>;
};

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function text(value: unknown): string {
  return String(value ?? "").trim();
}

function phoneDigits(value: unknown): string {
  return normalizePhone(value);
}

type AuthorizedFarmerPayload = {
  farmerId: string;
  farmerPhone: string;
};

async function loadLinkedUserIdsForFarmerId(
  supabase: ReturnType<typeof createServiceClient>,
  userId: string,
  farmerId: string,
): Promise<string[] | Response> {
  if (farmerId.length === 0) {
    return errorResponse(
      "farmerId or farmerPhone is required",
      400,
      undefined,
      "missing_farmer_identity",
    );
  }

  const { data: currentProfiles, error: currentProfileError } = await supabase
    .from("farmer_phone_profiles")
    .select("user_id, farmer_id, status")
    .eq("user_id", userId)
    .eq("farmer_id", farmerId)
    .eq("status", "active");
  if (currentProfileError) throw currentProfileError;
  if (!Array.isArray(currentProfiles) || currentProfiles.length === 0) {
    return errorResponse(
      "This session is not linked to that farmer number.",
      403,
      undefined,
      "farmer_session_not_linked",
    );
  }

  const { data: linkedProfiles, error: linkedProfileError } = await supabase
    .from("farmer_phone_profiles")
    .select("user_id")
    .eq("farmer_id", farmerId)
    .eq("status", "active");
  if (linkedProfileError) throw linkedProfileError;

  return Array.from(
    new Set(
      (Array.isArray(linkedProfiles) ? linkedProfiles : [])
        .map((row) => text(row.user_id))
        .filter((value) => value.length > 0),
    ),
  );
}

async function authorizeNotificationRequest(
  req: Request,
  supabase: ReturnType<typeof createServiceClient>,
  payload: FarmStatusPayload,
): Promise<AuthorizedFarmerPayload | Response> {
  const farmerId = text(payload.farmerId);
  const farmerPhone = phoneDigits(payload.farmerPhone);
  if (farmerId.length === 0 && farmerPhone.length === 0) {
    return errorResponse(
      "farmerId or farmerPhone is required",
      400,
      undefined,
      "missing_farmer_identity",
    );
  }

  const userId = await requireUserId(supabase, req);
  if (userId instanceof Response) return userId;

  let linkedUserIds: string[] | Response;
  if (farmerPhone.length > 0) {
    linkedUserIds = await loadLinkedUserIds(
      supabase,
      userId,
      farmerPhone,
      farmerId,
    );
  } else {
    linkedUserIds = await loadLinkedUserIdsForFarmerId(
      supabase,
      userId,
      farmerId,
    );
  }

  if (linkedUserIds instanceof Response) return linkedUserIds;
  if (!linkedUserIds.includes(userId)) {
    return errorResponse(
      "This session is not linked to that farmer number.",
      403,
      undefined,
      "farmer_session_not_linked",
    );
  }

  const farmId = text(payload.farmId);
  if (farmId.length > 0) {
    if (farmerPhone.length > 0) {
      const linkedFarm = await assertLinkedFarm(
        supabase,
        userId,
        farmerPhone,
        farmerId,
        farmId,
      );
      if (linkedFarm instanceof Response) return linkedFarm;
    } else {
      const { data: farm, error: farmError } = await supabase
        .from("farms")
        .select("id, user_id")
        .eq("id", farmId)
        .in("user_id", linkedUserIds)
        .maybeSingle();
      if (farmError) throw farmError;
      if (!farm) {
        return errorResponse(
          "Farm not found for this farmer",
          404,
          undefined,
          "farmer_farm_not_found",
        );
      }
    }
  }

  return { farmerId, farmerPhone };
}

function notificationCreatedAt(row: Record<string, unknown>): number {
  const time = Date.parse(text(row.created_at));
  return Number.isFinite(time) ? time : 0;
}

function mergeNotifications(
  primary: Record<string, unknown>[],
  secondary: Record<string, unknown>[],
): Record<string, unknown>[] {
  const byId = new Map<string, Record<string, unknown>>();
  for (const row of [...primary, ...secondary]) {
    const id = text(row.id);
    if (id.length > 0 && !byId.has(id)) {
      byId.set(id, row);
    }
  }
  return [...byId.values()]
    .sort((a, b) => notificationCreatedAt(b) - notificationCreatedAt(a))
    .slice(0, 80);
}

function validateCreatePayload(payload: FarmStatusPayload) {
  const missing = [
    ["farmerId", payload.farmerId],
    ["farmName", payload.farmName],
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
    const action = text(payload.action || "create").toLowerCase();
    const supabase = createServiceClient();
    const authorization = await authorizeNotificationRequest(
      req,
      supabase,
      payload,
    );
    if (authorization instanceof Response) return authorization;

    if (action === "list") {
      const farmerId = authorization.farmerId;
      const farmerPhone = authorization.farmerPhone;
      if (farmerId.length === 0 && farmerPhone.length === 0) {
        return errorResponse("farmerId or farmerPhone is required", 400);
      }
      const farmId = text(payload.farmId);
      let byFarmer: Record<string, unknown>[] = [];
      let byPhone: Record<string, unknown>[] = [];

      if (farmerId.length > 0) {
        let query = supabase
          .from("farmer_notifications")
          .select("*")
          .eq("farmer_id", farmerId);
        if (farmId.length > 0) {
          query = query.eq("farm_id", farmId);
        }
        const { data, error } = await query
          .order("created_at", { ascending: false })
          .limit(80);
        if (error) throw error;
        byFarmer = (data ?? []) as Record<string, unknown>[];
      }

      if (farmerPhone.length > 0) {
        let query = supabase
          .from("farmer_notifications")
          .select("*")
          .eq("farmer_phone", farmerPhone);
        if (farmId.length > 0) {
          query = query.eq("farm_id", farmId);
        }
        const { data, error } = await query
          .order("created_at", { ascending: false })
          .limit(80);
        if (error) throw error;
        byPhone = (data ?? []) as Record<string, unknown>[];
      }

      return successResponse({
        notifications: mergeNotifications(byFarmer, byPhone),
      });
    }

    if (action === "mark_read") {
      const farmerId = authorization.farmerId;
      const farmerPhone = authorization.farmerPhone;
      const notificationId = text(payload.notificationId);
      if (
        (farmerId.length === 0 && farmerPhone.length === 0) ||
        notificationId.length === 0
      ) {
        return errorResponse(
          "farmerId or farmerPhone and notificationId are required",
          400,
        );
      }

      let markedNotification: Record<string, unknown> | null = null;
      if (farmerId.length > 0) {
        const { data, error } = await supabase
          .from("farmer_notifications")
          .update({ read_at: new Date().toISOString() })
          .eq("id", notificationId)
          .eq("farmer_id", farmerId)
          .select("*")
          .maybeSingle();
        if (error) throw error;
        markedNotification = data as Record<string, unknown> | null;
      }

      if (markedNotification == null && farmerPhone.length > 0) {
        const { data, error } = await supabase
          .from("farmer_notifications")
          .update({ read_at: new Date().toISOString() })
          .eq("id", notificationId)
          .eq("farmer_phone", farmerPhone)
          .select("*")
          .maybeSingle();
        if (error) throw error;
        markedNotification = data as Record<string, unknown> | null;
      }

      return successResponse({
        notification: markedNotification,
        marked_read: markedNotification != null,
      });
    }

    if (action !== "create") {
      return errorResponse(
        "Unsupported notification action",
        400,
        undefined,
        "invalid_action",
      );
    }

    const validationError = validateCreatePayload(payload);
    if (validationError != null) return errorResponse(validationError, 400);

    const event = {
      type: text(payload.type) || "farm_status_update",
      farmer_id: authorization.farmerId,
      farm_id: text(payload.farmId),
      farmer_phone: authorization.farmerPhone,
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
      details: payload.payload && typeof payload.payload === "object"
        ? payload.payload
        : {},
    };

    const title = text(payload.title) ||
      `${event.farm_name} status updated`;
    const message = text(payload.message) ||
      [event.stage, event.status_text].filter((item) => item.length > 0).join(
        ": ",
      );

    const { data, error } = await supabase
      .from("farmer_notifications")
      .insert({
        farmer_id: event.farmer_id,
        farm_id: event.farm_id || null,
        farmer_phone: event.farmer_phone || null,
        type: event.type,
        title,
        message,
        farm_name: event.farm_name,
        payload: event,
      })
      .select("*")
      .single();

    if (error) throw error;
    return successResponse({
      delivered: true,
      channel: "in-app-farmer-notification",
      notification: data,
    });
  } catch (error) {
    return errorResponse("farm-status-notify failed", 500, error);
  }
});
