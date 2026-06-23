import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  loadLinkedUserIds,
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

function optionalSchemaError(error: unknown): boolean {
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

async function syncLegacyFarmsToPublic(
  supabase: any,
  linkedUserIds: string[],
  phone: string,
): Promise<void> {
  if (!Array.isArray(linkedUserIds) || linkedUserIds.length === 0) return;
  const normalizedPhone = normalizePhone(phone);
  if (normalizedPhone.length !== 10) return;

  const { data: legacyProfiles, error: legacyProfileError } = await supabase
    .from("farmer_ai_profiles")
    .select("id, user_id, phone")
    .in("user_id", linkedUserIds);

  if (legacyProfileError) throw legacyProfileError;
  const matchedProfiles = (Array.isArray(legacyProfiles) ? legacyProfiles : [])
    .filter((row) => normalizePhone(row.phone) === normalizedPhone);
  if (matchedProfiles.length === 0) return;

  const profileIds = matchedProfiles
    .map((row) => String(row.id ?? ""))
    .filter((id) => id.length > 0);
  if (profileIds.length === 0) return;

  const profileUserById = new Map<string, string>();
  for (const row of matchedProfiles) {
    const id = String(row.id ?? "");
    const userId = String(row.user_id ?? "");
    if (id.length > 0 && userId.length > 0) {
      profileUserById.set(id, userId);
    }
  }

  const { data: legacyFarms, error: legacyFarmError } = await supabase
    .from("farmer_ai_farms")
    .select(
      "id,profile_id,name,geometry,area_hectares,area_acres,created_at",
    )
    .in("profile_id", profileIds);
  if (legacyFarmError) throw legacyFarmError;
  const farms = Array.isArray(legacyFarms) ? legacyFarms : [];
  if (farms.length === 0) return;

  const { data: existingRows, error: existingRowsError } = await supabase
    .from("farms")
    .select("source_id")
    .eq("source_table", "farmer_ai_farms")
    .in(
      "source_id",
      farms.map((row) => String(row.id ?? "")).filter((id) => id.length > 0),
    );
  if (existingRowsError) {
    if (optionalSchemaError(existingRowsError)) return;
    throw existingRowsError;
  }

  const existingIds = new Set<string>(
    (Array.isArray(existingRows) ? existingRows : [])
      .map((row) => String(row.source_id ?? ""))
      .filter((id) => id.length > 0),
  );

  const toSync = farms
    .map((farm) => {
      const id = String(farm.id ?? "");
      const profileId = String(farm.profile_id ?? "");
      const geometry = farm.geometry;
      const name = String(farm.name ?? "");
      return {
        id,
        profileId,
        geometry,
        name,
        areaHectares: farm.area_hectares,
        areaAcres: farm.area_acres,
        createdAt: farm.created_at,
      };
    })
    .filter((farm) =>
      farm.id.length > 0 &&
      farm.profileId.length > 0 &&
      !existingIds.has(farm.id) &&
      farm.geometry != null &&
      farm.name.trim().length > 0
    )
    .map((farm): Record<string, unknown> | null => {
      const ownerUserId = profileUserById.get(farm.profileId);
      if (!ownerUserId) return null;
      return {
        source_table: "farmer_ai_farms",
        source_id: farm.id,
        name: farm.name,
        geometry: farm.geometry,
        bounds: null,
        area_hectares: farm.areaHectares,
        area_acres: farm.areaAcres,
        user_id: ownerUserId,
        created_at: farm.createdAt,
      };
    })
    .filter((row): row is Record<string, unknown> => row !== null);

  if (toSync.length === 0) return;

  const upserted = await supabase
    .from("farms")
    .upsert(toSync, { onConflict: "source_table,source_id" });
  if (upserted.error) {
    if (optionalSchemaError(upserted.error)) return;
    throw upserted.error;
  }
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
    const phone = normalizePhone(body.phone);
    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid 10 digit mobile number",
        400,
        undefined,
        "invalid_phone",
      );
    }
    const farmerId = text(body.farmerId ?? body.farmer_id);
    const preferredFarmId = text(
      body.farmId ?? body.farm_id ?? body.preferredFarmId ??
        body.preferred_farm_id,
    );

    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;
    const userIds = await loadLinkedUserIds(
      supabase,
      userId,
      phone,
      farmerId,
    );
    if (userIds instanceof Response) return userIds;
    if (userIds.length > 0) {
      try {
        await syncLegacyFarmsToPublic(supabase, userIds, phone);
      } catch (legacySyncError) {
        if (!optionalSchemaError(legacySyncError)) throw legacySyncError;
      }
    }

    if (userIds.length === 0) {
      return successResponse({ farms: [], count: 0 }, 200, "farms_not_found");
    }

    const { data: farms, error: farmsError } = await supabase
      .from("farms")
      .select("*")
      .in("user_id", userIds)
      .order("created_at", { ascending: false });

    if (farmsError) throw farmsError;
    const rawFarms = Array.isArray(farms) ? farms : [];
    const sorted = rawFarms.sort((left, right) => {
      const leftTime = Date.parse(String(left?.created_at ?? ""));
      const rightTime = Date.parse(String(right?.created_at ?? ""));
      return rightTime - leftTime;
    });
    const deduped: Record<string, any> = {};
    for (const farm of sorted) {
      const id = String(farm?.id ?? "").trim();
      if (!id || deduped[id] != null) continue;
      deduped[id] = farm;
    }
    const merged = Object.values(deduped);
    const selectedFarm = preferredFarmId.length === 0
      ? null
      : merged.find((farm) =>
        String(farm?.id ?? "").trim() === preferredFarmId
      ) ??
        null;
    const ordered = selectedFarm == null ? merged : [
      selectedFarm,
      ...merged.filter(
        (farm) => String(farm?.id ?? "").trim() !== preferredFarmId,
      ),
    ];
    return successResponse(
      {
        farms: ordered,
        count: ordered.length,
        selectedFarm,
        selectedFarmId: selectedFarm == null ? null : preferredFarmId,
      },
      200,
      "farms_synced",
    );
  } catch (error) {
    return errorResponse("farmer-phone-farms failed", 500, error);
  }
});
