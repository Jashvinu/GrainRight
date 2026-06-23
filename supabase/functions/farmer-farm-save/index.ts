import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  loadLinkedUserIds,
  normalizePhone,
  pruneDuplicateActiveFarmerProfiles,
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

function record(raw: unknown): Record<string, unknown> {
  return raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Record<string, unknown>
    : {};
}

function finiteNumber(raw: unknown): number | null {
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

function optionalText(raw: unknown): string | null {
  const value = text(raw);
  return value.length === 0 ? null : value;
}

function hasPolygonRing(geometry: Record<string, unknown>): boolean {
  if (text(geometry.type).toLowerCase() !== "polygon") return false;
  const coordinates = geometry.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length === 0) return false;
  const ring = coordinates[0];
  return Array.isArray(ring) && ring.length >= 4;
}

function columnSchemaError(error: unknown): boolean {
  const raw = String(
    (error as { code?: unknown; message?: unknown; details?: unknown })?.code ??
      (error as { message?: unknown })?.message ??
      (error as { details?: unknown })?.details ??
      error ??
      "",
  ).toLowerCase();
  return raw.includes("column") ||
    raw.includes("schema cache") ||
    raw.includes("pgrst204") ||
    raw.includes("42703");
}

async function insertFarmWithFallback(
  supabase: any,
  fullRow: Record<string, unknown>,
) {
  const attempts = [
    fullRow,
    {
      name: fullRow.name,
      geometry: fullRow.geometry,
      bounds: fullRow.bounds,
      area_hectares: fullRow.area_hectares,
      area_acres: fullRow.area_acres,
      user_id: fullRow.user_id,
      crop: fullRow.crop,
      variety: fullRow.variety,
      previous_crop: fullRow.previous_crop,
      season: fullRow.season,
      irrigation: fullRow.irrigation,
      soil_type: fullRow.soil_type,
      ownership_type: fullRow.ownership_type,
      seed_source: fullRow.seed_source,
      harvest_intent: fullRow.harvest_intent,
    },
    {
      name: fullRow.name,
      geometry: fullRow.geometry,
      bounds: fullRow.bounds,
      area_hectares: fullRow.area_hectares,
      area_acres: fullRow.area_acres,
      user_id: fullRow.user_id,
    },
    {
      name: fullRow.name,
      geometry: fullRow.geometry,
      area_hectares: fullRow.area_hectares,
      user_id: fullRow.user_id,
    },
  ];

  let lastError: unknown = null;
  for (const row of attempts) {
    const { data, error } = await supabase
      .from("farms")
      .insert(row)
      .select("*")
      .maybeSingle();
    if (!error) return { farm: data, error: null };
    lastError = error;
    if (!columnSchemaError(error)) break;
  }
  return { farm: null, error: lastError };
}

async function upsertCurrentFarmerLink(
  supabase: any,
  userId: string,
  phone: string,
  farmerId: string,
) {
  if (farmerId.length === 0) return;
  const now = new Date().toISOString();
  const attempts = [
    {
      user_id: userId,
      phone,
      farmer_id: farmerId,
      farmer_name: "Farmer",
      status: "active",
      auth_method: "anonymous_link",
      source: "phone_login",
      phone_verified_at: now,
      updated_at: now,
    },
    {
      user_id: userId,
      phone,
      farmer_id: farmerId,
      farmer_name: "Farmer",
      auth_method: "anonymous_link",
      updated_at: now,
    },
    {
      user_id: userId,
      phone,
      farmer_id: farmerId,
      auth_method: "anonymous_link",
    },
  ];

  let lastError: unknown = null;
  for (const row of attempts) {
    const { error } = await supabase
      .from("farmer_phone_profiles")
      .upsert(row, { onConflict: "user_id" });
    if (!error) return;
    lastError = error;
    if (!columnSchemaError(error)) throw error;
  }
  if (lastError) throw lastError;
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
    const body = await req.json();
    const phone = normalizePhone(
      body.phone ?? body.farmerPhone ?? body.farmer_phone,
    );
    const farmerId = text(body.farmerId ?? body.farmer_id);
    const farmInput = record(body.farm ?? body);
    const name = text(farmInput.name);
    const geometry = record(farmInput.geometry);

    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid 10 digit mobile number",
        400,
        undefined,
        "invalid_phone",
      );
    }
    if (name.length === 0) {
      return errorResponse(
        "Farm name is required",
        400,
        undefined,
        "missing_farm_name",
      );
    }
    if (!hasPolygonRing(geometry)) {
      return errorResponse(
        "Farm boundary is required",
        400,
        undefined,
        "farm_geometry_required",
      );
    }

    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;

    await upsertCurrentFarmerLink(supabase, userId, phone, farmerId);
    await pruneDuplicateActiveFarmerProfiles(supabase, {
      phone,
      farmerId,
      keepUserId: userId,
    });

    const linkedUserIds = await loadLinkedUserIds(
      supabase,
      userId,
      phone,
      farmerId,
    );
    if (linkedUserIds instanceof Response) return linkedUserIds;
    if (!linkedUserIds.includes(userId)) {
      return errorResponse(
        "This session is not linked to that farmer number.",
        403,
        undefined,
        "farmer_session_not_linked",
      );
    }

    const areaHectares = finiteNumber(farmInput.area_hectares);
    const areaAcres = finiteNumber(farmInput.area_acres);
    if (areaHectares == null || areaHectares <= 0) {
      return errorResponse(
        "Farm boundary area is required",
        400,
        undefined,
        "farm_area_required",
      );
    }

    const row = {
      name,
      geometry,
      bounds: Object.keys(record(farmInput.bounds)).length > 0
        ? record(farmInput.bounds)
        : null,
      area_hectares: areaHectares,
      area_acres: areaAcres,
      user_id: userId,
      crop: optionalText(farmInput.crop),
      variety: optionalText(farmInput.variety),
      previous_crop: optionalText(farmInput.previous_crop),
      season: optionalText(farmInput.season),
      irrigation: optionalText(farmInput.irrigation),
      soil_type: optionalText(farmInput.soil_type),
      ownership_type: optionalText(farmInput.ownership_type),
      seed_source: optionalText(farmInput.seed_source),
      harvest_intent: optionalText(farmInput.harvest_intent),
      sowing_date: optionalText(farmInput.sowing_date),
    };

    const { farm, error } = await insertFarmWithFallback(supabase, row);
    if (error) throw error;
    if (!farm) {
      return errorResponse(
        "Farm could not be saved",
        500,
        undefined,
        "farm_save_failed",
      );
    }

    const savedFarmId = text(farm.id);
    if (savedFarmId.length === 0) {
      return errorResponse(
        "Farm was saved but the saved id was missing",
        500,
        undefined,
        "farm_saved_id_missing",
      );
    }

    const confirmedLinkedUserIds = await loadLinkedUserIds(
      supabase,
      userId,
      phone,
      farmerId,
    );
    if (confirmedLinkedUserIds instanceof Response) {
      return confirmedLinkedUserIds;
    }
    const { data: confirmedFarm, error: confirmedFarmError } = await supabase
      .from("farms")
      .select("*")
      .eq("id", savedFarmId)
      .in("user_id", confirmedLinkedUserIds)
      .maybeSingle();
    if (confirmedFarmError) throw confirmedFarmError;
    if (!confirmedFarm) {
      return errorResponse(
        "Farm was saved but is not visible for this farmer phone.",
        500,
        undefined,
        "farm_saved_not_linked",
      );
    }

    await pruneDuplicateActiveFarmerProfiles(supabase, {
      phone,
      farmerId,
      keepUserId: userId,
    });

    return successResponse(
      {
        farm: confirmedFarm,
        selectedFarmId: savedFarmId,
        farmerPhone: phone,
        farmerId,
      },
      201,
      "farmer_farm_saved",
    );
  } catch (error) {
    return errorResponse(
      "farmer-farm-save failed",
      500,
      error,
      "farmer_farm_save_failed",
    );
  }
});
