import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  normalizePhone,
  phoneVariants,
  pruneDuplicateActiveFarmerProfiles,
} from "../_shared/farmer-links.ts";

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function bearerToken(req: Request): string {
  const header = req.headers.get("Authorization") ?? "";
  return header.replace(/^Bearer\s+/i, "").trim();
}

function text(raw: unknown): string {
  return String(raw ?? "").trim();
}

function isDuplicateKey(error: unknown): boolean {
  const value = String(
    (error as { code?: unknown; message?: unknown })?.code ??
      (error as { message?: unknown })?.message ??
      error ??
      "",
  ).toLowerCase();
  return value.includes("23505") || value.includes("duplicate key");
}

function rowToProfile(row: Record<string, unknown>) {
  const phone = normalizePhone(row.phone);
  return {
    phone,
    farmerId: String(row.farmer_id ?? `FMR-${phone}`),
    farmerName: String(row.farmer_name ?? "Farmer"),
    defaultLocation: String(row.default_location ?? ""),
    preferredLanguage: String(row.preferred_language ?? "en"),
    profileComplete: Boolean(row.profile_completed_at),
    lots: [],
  };
}

function createFarmerId(): string {
  const random = crypto.randomUUID().replaceAll("-", "").slice(0, 12)
    .toUpperCase();
  return `FMR-${random}`;
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
    const token = bearerToken(req);
    if (token.length === 0) {
      return errorResponse(
        "Missing auth token",
        401,
        undefined,
        "missing_auth_token",
      );
    }

    const body = await req.json();
    const phone = normalizePhone(body.phone);
    const farmerName = text(body.farmerName);
    const defaultLocation = text(body.defaultLocation) || "Kalsubai Farms";

    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid 10 digit mobile number",
        400,
        undefined,
        "invalid_phone",
      );
    }
    if (farmerName.length === 0) {
      return errorResponse(
        "Enter farmer name",
        400,
        undefined,
        "missing_farmer_name",
      );
    }

    const supabase = createServiceClient();
    const { data: userData, error: userError } = await supabase.auth.getUser(
      token,
    );
    if (userError || !userData.user) {
      return errorResponse(
        "Invalid auth token",
        401,
        userError,
        "invalid_auth_token",
      );
    }
    const userId = userData.user.id;

    const phoneValues = phoneVariants(phone);
    const { data: registryRows, error: registryError } = await supabase
      .from("farmer_phone_registry")
      .select(
        "phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at",
      )
      .in("phone", phoneValues);

    if (registryError) throw registryError;
    const registry = Array.isArray(registryRows)
      ? registryRows.filter(
        (row) =>
          normalizePhone((row as Record<string, unknown>).phone) ===
            phone,
      )
      : [];
    if (registry.length > 0) {
      if (registry.length > 1) {
        return errorResponse(
          "This number has duplicate farmer records. Contact admin.",
          409,
          undefined,
          "farmer_duplicate_profiles",
        );
      }
      const activeRegistry = registry.find((row) =>
        String((row as Record<string, unknown>).status ?? "active") === "active"
      ) as Record<string, unknown> | undefined;
      if (!activeRegistry) {
        return errorResponse(
          "This farmer profile is not active. Contact admin.",
          403,
          undefined,
          "farmer_profile_inactive",
        );
      }
      if (Boolean(activeRegistry.profile_completed_at)) {
        return errorResponse(
          "This mobile number already has a farmer profile. Please login instead.",
          409,
          undefined,
          "farmer_already_exists",
        );
      }
    }

    const { data: profileRows, error: profileError } = await supabase
      .from("farmer_phone_profiles")
      .select(
        "user_id, phone, farmer_id, farmer_name, default_location, preferred_language, status",
      )
      .in("phone", phoneValues);

    if (profileError) throw profileError;
    const profiles = Array.isArray(profileRows)
      ? profileRows.filter(
        (row) =>
          normalizePhone((row as Record<string, unknown>).phone) ===
            phone,
      )
      : [];
    const activeProfiles = profiles.filter((row) =>
      String((row as Record<string, unknown>).status ?? "active") === "active"
    ) as Record<string, unknown>[];
    const otherActiveProfile = activeProfiles.find((row) =>
      String(row.user_id ?? "") !== userId
    );
    const currentActiveProfile = activeProfiles.find((row) =>
      String(row.user_id ?? "") === userId
    );

    if (otherActiveProfile) {
      await pruneDuplicateActiveFarmerProfiles(supabase, {
        phone,
        farmerId: text(otherActiveProfile.farmer_id),
        keepUserId: userId,
      });
    }

    const now = new Date().toISOString();
    const registryProfile = registry.length === 1
      ? registry[0] as Record<string, unknown>
      : null;
    const farmerId = text(registryProfile?.farmer_id).length > 0
      ? text(registryProfile?.farmer_id)
      : currentActiveProfile?.farmer_id
      ? String(currentActiveProfile.farmer_id)
      : createFarmerId();
    const profile = {
      phone,
      farmer_id: farmerId,
      farmer_name: farmerName,
      default_location: defaultLocation,
      preferred_language: "en",
      status: "active",
      profile_completed_at: now,
      source: "mobile_signup",
    };

    let registryRecord: Record<string, unknown> | null = null;
    if (registryProfile) {
      const registryPhone = text(registryProfile.phone) || phone;
      const { data: registryUpdate, error: registryUpdateError } =
        await supabase
          .from("farmer_phone_registry")
          .update(profile)
          .eq("phone", registryPhone)
          .select(
            "phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at",
          )
          .maybeSingle();

      if (registryUpdateError) throw registryUpdateError;
      registryRecord = registryUpdate as Record<string, unknown> | null;
    } else {
      const { data: registryInsert, error: registryInsertError } =
        await supabase
          .from("farmer_phone_registry")
          .insert(profile)
          .select(
            "phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at",
          )
          .single();

      if (registryInsertError) {
        if (isDuplicateKey(registryInsertError)) {
          return errorResponse(
            "This mobile number already has a farmer profile. Please login instead.",
            409,
            undefined,
            "farmer_already_exists",
          );
        }
        throw registryInsertError;
      }
      registryRecord = registryInsert as Record<string, unknown>;
    }

    if (!registryRecord) {
      return errorResponse(
        "Could not complete farmer profile. Try again.",
        500,
        undefined,
        "farmer_registration_failed",
      );
    }

    const { error: profileUpsertError } = await supabase
      .from("farmer_phone_profiles")
      .upsert(
        {
          user_id: userId,
          ...profile,
          auth_method: "anonymous_link",
          phone_verified_at: now,
        },
        { onConflict: "user_id" },
      );

    if (profileUpsertError) throw profileUpsertError;

    await pruneDuplicateActiveFarmerProfiles(supabase, {
      phone,
      farmerId,
      keepUserId: userId,
    });

    return successResponse(
      {
        farmer: rowToProfile(registryRecord),
      },
      200,
      "farmer_registered",
    );
  } catch (error) {
    return errorResponse("register-farmer-phone failed", 500, error);
  }
});
