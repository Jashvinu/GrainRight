import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function normalizePhone(raw: unknown): string {
  return String(raw ?? "").replace(/\D/g, "").slice(-10);
}

function rowToProfile(row: Record<string, unknown>) {
  const phone = String(row.phone ?? "");
  const farmerId = String(row.farmer_id ?? `FMR-${phone}`);
  const farmerName = String(row.farmer_name ?? "Farmer");
  const defaultLocation = String(row.default_location ?? "");
  return {
    phone,
    farmerId,
    farmerName,
    defaultLocation,
    preferredLanguage: String(row.preferred_language ?? "en"),
    profileComplete: Boolean(row.profile_completed_at) &&
      farmerId.trim().length > 0 &&
      farmerName.trim().length > 0,
    lots: [],
  };
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const body = await req.json();
    const phone = normalizePhone(body.phone);
    if (phone.length !== 10) {
      return errorResponse("Enter a valid 10 digit mobile number", 400);
    }

    const supabase = createServiceClient();
    const { data: registryRows, error: registryError } = await supabase
      .from("farmer_phone_registry")
      .select(
        "phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at",
      )
      .eq("phone", phone);

    if (registryError) throw registryError;
    const registry = Array.isArray(registryRows) ? registryRows : [];

    if (registry.length > 1) {
      return errorResponse("This number has duplicate farmer records. Contact admin.", 409);
    }
    if (registry.length === 1) {
      const row = registry[0] as Record<string, unknown>;
      const status = String(row.status ?? "active");
      if (status !== "active") {
        return errorResponse("This farmer profile is not active. Contact admin.", 403);
      }
      return successResponse({ farmer: rowToProfile(row) });
    }

    // Backward-compatible fallback for projects that already seeded
    // farmer_phone_profiles before the dedicated registry table existed.
    const { data: profileRows, error: profileError } = await supabase
      .from("farmer_phone_profiles")
      .select(
        "phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at",
      )
      .eq("phone", phone);

    if (profileError) throw profileError;
    const profiles = Array.isArray(profileRows) ? profileRows : [];
    if (profiles.length > 1) {
      return errorResponse("This number has duplicate farmer records. Contact admin.", 409);
    }
    if (profiles.length === 0) {
      return errorResponse("No approved farmer profile found for this number.", 404);
    }

    const row = profiles[0] as Record<string, unknown>;
    const status = String(row.status ?? "active");
    if (status !== "active") {
      return errorResponse("This farmer profile is not active. Contact admin.", 403);
    }
    return successResponse({ farmer: rowToProfile(row) });
  } catch (error) {
    return errorResponse("verify-farmer-phone failed", 500, error);
  }
});
