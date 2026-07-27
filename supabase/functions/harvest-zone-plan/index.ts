import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { assertLinkedFarm } from "../_shared/farmer-links.ts";

class HttpError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Missing Supabase service configuration");
  return createClient(url, key);
}

async function authenticatedUserId(req: Request, supabase: ReturnType<typeof serviceClient>) {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError("Authentication required", 401);
  const { data, error } = await supabase.auth.getUser(token);
  const userId = data.user?.id ? String(data.user.id) : "";
  if (error || !userId) throw new HttpError("Invalid or expired session", 401);
  return userId;
}

async function loadPlan(
  supabase: ReturnType<typeof serviceClient>,
  planId: string,
  farmGeometry: unknown,
) {
  const { data: plan, error: planError } = await supabase
    .from("farm_harvest_zone_plans")
    .select("*")
    .eq("id", planId)
    .single();
  if (planError || !plan) {
    throw new Error(`Failed to load harvest plan: ${planError?.message ?? "not found"}`);
  }

  const { data: zones, error: zoneError } = await supabase
    .from("farm_harvest_zones")
    .select(
      "id,plan_id,farm_id,zone_label,field_grade,field_score,area_acres,area_percent,confidence,source_cell_count,quality_drivers,geometry,created_at,updated_at",
    )
    .eq("plan_id", planId)
    .order("field_grade")
    .order("zone_label");
  if (zoneError) throw new Error(`Failed to load harvest zones: ${zoneError.message}`);

  return {
    plan,
    zones: zones ?? [],
    farm_geometry: farmGeometry,
  };
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const supabase = serviceClient();
    const userId = await authenticatedUserId(req, supabase);
    const body = await req.json().catch(() => ({}));
    const farmId = String(body.farm_id ?? "").trim();
    const farmerPhone = String(body.farmer_phone ?? "").trim();
    const farmerId = String(body.farmer_id ?? "").trim();
    const forceRefresh = body.force_refresh === true;
    if (!farmId) return errorResponse("farm_id is required", 400);

    const farm = await assertLinkedFarm(
      supabase,
      userId,
      farmerPhone,
      farmerId,
      farmId,
    );
    if (farm instanceof Response) return farm;
    if (!farm.geometry) throw new HttpError("Save the farm boundary before grading zones", 422);
    const ownerUserId = String(farm.user_id ?? "");
    if (!ownerUserId) throw new HttpError("Farm owner is missing", 422);

    const [{ data: latestCell }, { data: latestPlan }] = await Promise.all([
      supabase
        .from("disease_risk_cells")
        .select("scan_date")
        .eq("farm_id", farmId)
        .order("scan_date", { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from("farm_harvest_zone_plans")
        .select("id,source_scan_date,scoring_version")
        .eq("farm_id", farmId)
        .eq("user_id", ownerUserId)
        .eq("status", "active")
        .order("generated_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);

    const currentPlan = latestPlan?.scoring_version === "field-grade-v2-three-region" &&
        String(latestPlan.source_scan_date ?? "") === String(latestCell?.scan_date ?? "")
      ? latestPlan
      : null;
    if (!forceRefresh && currentPlan?.id) {
      return successResponse(await loadPlan(supabase, String(currentPlan.id), farm.geometry));
    }

    const { data: planId, error: generationError } = await supabase.rpc(
      "generate_harvest_zone_plan",
      { p_farm_id: farmId, p_user_id: ownerUserId },
    );
    if (generationError || !planId) {
      throw new Error(
        `Failed to generate harvest zones: ${generationError?.message ?? "no plan id returned"}`,
      );
    }

    return successResponse(await loadPlan(supabase, String(planId), farm.geometry));
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    return errorResponse("harvest-zone-plan failed", status, error);
  }
});
