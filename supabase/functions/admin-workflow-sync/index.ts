import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  bearerToken,
  hasServerRole,
  optionalSchemaError,
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

function rows(data: unknown): Row[] {
  return Array.isArray(data) ? data as Row[] : [];
}

function readErrorIsOptional(error: unknown) {
  const raw = String(
    (error as { message?: unknown; details?: unknown; code?: unknown })?.message ??
      (error as { details?: unknown })?.details ??
      (error as { code?: unknown })?.code ??
      error ??
      "",
  ).toLowerCase();
  return optionalSchemaError(error) ||
    raw.includes("relation") ||
    raw.includes("does not exist") ||
    raw.includes("not found");
}

async function requireAdminUserId(
  supabase: any,
  req: Request,
): Promise<string | Response> {
  const token = bearerToken(req);
  if (token.length === 0) {
    return errorResponse(
      "Missing auth token",
      401,
      undefined,
      "missing_auth_token",
    );
  }
  const { data, error } = await supabase.auth.getUser(token);
  const user = data?.user;
  if (error || !user) {
    return errorResponse(
      "Invalid auth token",
      401,
      error,
      "invalid_auth_token",
    );
  }
  if (!hasServerRole(user, ["admin"], token)) {
    return errorResponse(
      "This account is not enabled for admin workflow.",
      403,
      undefined,
      "admin_role_required",
    );
  }
  return user.id;
}

async function fetchRows(
  supabase: any,
  table: string,
  select = "*",
  options: { order?: string; ascending?: boolean; limit?: number } = {},
) {
  let query = supabase.from(table).select(select);
  if (options.order) {
    query = query.order(options.order, {
      ascending: options.ascending ?? false,
    });
  }
  if (options.limit != null) query = query.limit(options.limit);
  const { data, error } = await query;
  if (error) {
    if (readErrorIsOptional(error)) return [];
    throw error;
  }
  return rows(data);
}

function latestBy<T extends Row>(items: T[], key: string) {
  const seen = new Set<string>();
  const result: T[] = [];
  for (const item of items) {
    const id = text(item[key]);
    if (id.length === 0 || seen.has(id)) continue;
    seen.add(id);
    result.push(item);
  }
  return result;
}

function groupEvents(events: Row[]) {
  const grouped: Record<string, Row[]> = {};
  for (const event of events) {
    const appId = text(event.application_id);
    if (appId.length === 0) continue;
    grouped[appId] ??= [];
    grouped[appId].push(event);
  }
  return grouped;
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
    const adminUserId = await requireAdminUserId(supabase, req);
    if (adminUserId instanceof Response) return adminUserId;

    const [
      farmerProfiles,
      farmerFarms,
      farmerActivities,
      fpcJobs,
      fpcProcurements,
      stakeholders,
      stakeholderEvents,
    ] = await Promise.all([
      fetchRows(
        supabase,
        "farmer_phone_profiles",
        "user_id, phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at, source, agri_record_id, aadhaar_last4, identity_document_path, updated_at, created_at",
        { order: "updated_at", limit: 200 },
      ),
      fetchRows(supabase, "v_farmer_farm_export", "*", {
        order: "farm_updated_at",
        limit: 200,
      }),
      fetchRows(supabase, "v_farmer_core_activity_export", "*", {
        order: "created_at",
        limit: 200,
      }),
      fetchRows(supabase, "analysis_jobs", "*", {
        order: "created_at",
        limit: 120,
      }),
      fetchRows(supabase, "fpc_procurement_records", "*", {
        order: "received_at",
        limit: 120,
      }),
      fetchRows(supabase, "stakeholder_applications", "*", {
        order: "updated_at",
        limit: 200,
      }),
      fetchRows(supabase, "stakeholder_application_events", "*", {
        order: "created_at",
        ascending: true,
        limit: 500,
      }),
    ]);

    const activeFarmers = farmerProfiles.filter((row) =>
      text(row.status).toLowerCase() !== "inactive"
    );
    const pendingStakeholders = stakeholders.filter((row) =>
      ["submitted", "under_review"].includes(text(row.status).toLowerCase())
    );
    const approvedStakeholders = stakeholders.filter((row) =>
      text(row.status).toLowerCase() === "approved"
    );
    const paidStakeholders = stakeholders.filter((row) =>
      ["gateway_verified", "bank_transfer_submitted"].includes(
        text(row.payment_status).toLowerCase(),
      )
    );

    return successResponse(
      {
        generatedAt: new Date().toISOString(),
        metrics: {
          farmerProfiles: farmerProfiles.length,
          activeFarmers: activeFarmers.length,
          linkedFarms: latestBy(farmerFarms, "farm_id").length,
          fpcJobs: fpcJobs.length,
          fpcProcurements: fpcProcurements.length,
          stakeholderApplications: stakeholders.length,
          pendingStakeholders: pendingStakeholders.length,
          approvedStakeholders: approvedStakeholders.length,
          paidStakeholders: paidStakeholders.length,
        },
        farmers: farmerProfiles,
        farmerFarms,
        farmerActivities,
        fpcJobs,
        fpcProcurements,
        stakeholders,
        stakeholderEvents,
        stakeholderEventsByApplication: groupEvents(stakeholderEvents),
      },
      200,
      "admin_workflow_synced",
    );
  } catch (error) {
    return errorResponse(
      "admin-workflow-sync failed",
      500,
      error,
      "admin_workflow_sync_failed",
    );
  }
});
