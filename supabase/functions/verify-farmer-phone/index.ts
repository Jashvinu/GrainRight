import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { normalizePhone, phoneVariants } from "../_shared/farmer-links.ts";

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function rowToProfile(row: Record<string, unknown>) {
  const phone = normalizePhone(row.phone);
  const farmerId = String(row.farmer_id ?? `FMR-${phone}`);
  const farmerName = String(row.farmer_name ?? "Farmer");
  const defaultLocation = String(row.default_location ?? "");
  return {
    phone,
    farmerId,
    farmerName,
    defaultLocation,
    agriRecordId: String(row.agri_record_id ?? ""),
    aadhaarMasked: String(row.aadhaar_masked ?? ""),
    aadhaarLast4: String(row.aadhaar_last4 ?? ""),
    identityDocumentPath: String(row.identity_document_path ?? ""),
    preferredLanguage: String(row.preferred_language ?? "en"),
    profileComplete: Boolean(row.profile_completed_at) &&
      farmerId.trim().length > 0 &&
      farmerName.trim().length > 0,
    lots: [],
  };
}

function hasStakeholderAgriRecord(profile: ReturnType<typeof rowToProfile>) {
  return profile.agriRecordId.trim().length > 0 &&
    profile.identityDocumentPath.trim().length > 0;
}

function agriRecordRequiredResponse() {
  return errorResponse(
    "Stakeholder login needs a government agri record. Complete farmer signup with your agri record card first.",
    403,
    undefined,
    "farmer_agri_record_required",
  );
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
    const requireAgriRecord = body.require_agri_record === true ||
      body.requireAgriRecord === true;
    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid 10 digit mobile number",
        400,
        undefined,
        "invalid_phone",
      );
    }

    const supabase = createServiceClient();
    const phoneValues = phoneVariants(phone);
    const { data: registryRows, error: registryError } = await supabase
      .from("farmer_phone_registry")
      .select(
        "phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at, agri_record_id, aadhaar_masked, aadhaar_last4, identity_document_path",
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

    if (registry.length > 1) {
      return errorResponse(
        "This number has duplicate farmer records. Contact admin.",
        409,
      );
    }
    if (registry.length === 1) {
      const row = registry[0] as Record<string, unknown>;
      const status = String(row.status ?? "active");
      if (status !== "active") {
        return errorResponse(
          "This farmer profile is not active. Contact admin.",
          403,
          undefined,
          "farmer_profile_inactive",
        );
      }
      const profile = rowToProfile(row);
      if (!profile.profileComplete) {
        return errorResponse(
          "Create a new farmer account. Tap Sign up to continue.",
          404,
          undefined,
          "farmer_not_found",
        );
      }
      if (requireAgriRecord && !hasStakeholderAgriRecord(profile)) {
        return agriRecordRequiredResponse();
      }
      return successResponse({ farmer: profile }, 200, "farmer_verified");
    }

    // Backward-compatible fallback for projects that already seeded
    // farmer_phone_profiles before the dedicated registry table existed.
    const { data: profileRows, error: profileError } = await supabase
      .from("farmer_phone_profiles")
      .select(
        "phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at, agri_record_id, aadhaar_masked, aadhaar_last4, identity_document_path",
      )
      .in("phone", phoneValues)
      .order("profile_completed_at", { ascending: false, nullsFirst: false });

    if (profileError) throw profileError;
    const profiles = Array.isArray(profileRows)
      ? profileRows.filter(
        (row) =>
          normalizePhone((row as Record<string, unknown>).phone) ===
            phone,
      )
      : [];
    if (profiles.length === 0) {
      return errorResponse(
        "Create a new farmer account. Tap Sign up to continue.",
        404,
        undefined,
        "farmer_not_found",
      );
    }

    const activeProfiles = profiles.filter((profile) =>
      String((profile as Record<string, unknown>).status ?? "active") ===
        "active"
    );
    if (activeProfiles.length === 0) {
      return errorResponse(
        "This farmer profile is not active. Contact admin.",
        403,
        undefined,
        "farmer_profile_inactive",
      );
    }
    const row = activeProfiles[0] as Record<string, unknown>;
    const profile = rowToProfile(row);
    if (!profile.profileComplete) {
      return errorResponse(
        "Create a new farmer account. Tap Sign up to continue.",
        404,
        undefined,
        "farmer_not_found",
      );
    }
    if (requireAgriRecord && !hasStakeholderAgriRecord(profile)) {
      return agriRecordRequiredResponse();
    }
    return successResponse({ farmer: profile }, 200, "farmer_verified");
  } catch (error) {
    return errorResponse("verify-farmer-phone failed", 500, error);
  }
});
