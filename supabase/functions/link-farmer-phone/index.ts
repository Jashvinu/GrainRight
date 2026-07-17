import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  normalizePhone,
  optionalSchemaError,
  phoneVariants,
  pruneDuplicateActiveFarmerProfiles,
  requireUserId,
  text,
} from "../_shared/farmer-links.ts";

const linkedFarmerSelect =
  "phone, farmer_id, farmer_name, default_location, preferred_language, status, agri_record_id, aadhaar_number, aadhaar_masked, aadhaar_last4, identity_document_path, identity_document_bucket, identity_ocr_confidence, identity_source, identity_verified_at";
const linkedFarmerLegacySelect =
  "phone, farmer_id, farmer_name, default_location, preferred_language, status, agri_record_id, aadhaar_masked, aadhaar_last4, identity_document_path, identity_document_bucket, identity_ocr_confidence, identity_source, identity_verified_at";
const linkedProfileSelect =
  "user_id, phone, farmer_id, farmer_name, default_location, preferred_language, status, agri_record_id, aadhaar_number, aadhaar_masked, aadhaar_last4, identity_document_path";
const linkedProfileLegacySelect =
  "user_id, phone, farmer_id, farmer_name, default_location, preferred_language, status, agri_record_id, aadhaar_masked, aadhaar_last4, identity_document_path";

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function missingAadhaarNumberColumn(error: unknown): boolean {
  return optionalSchemaError(error) &&
    String(
      (error as { code?: unknown; message?: unknown; details?: unknown })
        ?.code ??
        (error as { message?: unknown })?.message ??
        (error as { details?: unknown })?.details ??
        error ??
        "",
    ).toLowerCase().includes("aadhaar_number");
}

function withoutAadhaarNumber(row: Record<string, unknown>) {
  const copy = { ...row };
  delete copy.aadhaar_number;
  return copy;
}

async function selectLinkedFarmerRows(
  supabase: any,
  table: string,
  phoneValues: string[],
) {
  const result = await supabase
    .from(table)
    .select(linkedFarmerSelect)
    .in("phone", phoneValues);
  if (!result.error || !missingAadhaarNumberColumn(result.error)) {
    return result;
  }
  return await supabase
    .from(table)
    .select(linkedFarmerLegacySelect)
    .in("phone", phoneValues);
}

async function upsertLinkedProfile(
  supabase: any,
  row: Record<string, unknown>,
) {
  const result = await supabase
    .from("farmer_phone_profiles")
    .upsert(row, { onConflict: "user_id" })
    .select(linkedProfileSelect)
    .maybeSingle();
  if (!result.error || !missingAadhaarNumberColumn(result.error)) {
    return result;
  }
  return await supabase
    .from("farmer_phone_profiles")
    .upsert(withoutAadhaarNumber(row), { onConflict: "user_id" })
    .select(linkedProfileLegacySelect)
    .maybeSingle();
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
    const farmerId = text(body.farmerId ?? body.farmer_id);
    const farmerName = text(body.farmerName ?? body.farmer_name) || "Farmer";
    const defaultLocation = text(body.defaultLocation ?? body.default_location);
    const preferredLanguage = text(body.preferredLanguage) || "en";

    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid 10 digit mobile number",
        400,
        undefined,
        "invalid_phone",
      );
    }
    if (farmerId.length === 0) {
      return errorResponse(
        "farmer_id is required",
        400,
        undefined,
        "missing_farmer_id",
      );
    }

    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;

    const phoneValues = phoneVariants(phone);
    const { data: registryRows, error: registryError } =
      await selectLinkedFarmerRows(
        supabase,
        "farmer_phone_registry",
        phoneValues,
      );

    if (registryError) throw registryError;
    const registry = Array.isArray(registryRows)
      ? registryRows.filter(
        (row) =>
          normalizePhone((row as Record<string, unknown>).phone) ===
            phone,
      )
      : [];
    const activeRegistry = registry.find((row) =>
      String((row as Record<string, unknown>).status ?? "active") === "active"
    ) as Record<string, unknown> | undefined;
    if (registry.length > 0 && !activeRegistry) {
      return errorResponse(
        "This farmer profile is not active. Contact admin.",
        403,
        undefined,
        "farmer_profile_inactive",
      );
    }

    let verifiedProfile = activeRegistry;
    if (!verifiedProfile) {
      const { data: profileRows, error: profileLookupError } =
        await selectLinkedFarmerRows(
          supabase,
          "farmer_phone_profiles",
          phoneValues,
        );

      if (profileLookupError) throw profileLookupError;
      const normalizedProfileRows =
        (Array.isArray(profileRows) ? profileRows : [])
          .filter(
            (row) =>
              normalizePhone((row as Record<string, unknown>).phone) === phone,
          );
      verifiedProfile = normalizedProfileRows.find(
        (row) =>
          String((row as Record<string, unknown>).status ?? "active") ===
            "active",
      ) as Record<string, unknown> | undefined;
      if (!verifiedProfile) {
        return errorResponse(
          "Create a new farmer account. Tap Sign up to continue.",
          404,
          undefined,
          "farmer_not_found",
        );
      }
    }

    const verifiedFarmerId = text(verifiedProfile.farmer_id);
    if (verifiedFarmerId.length > 0 && verifiedFarmerId !== farmerId) {
      return errorResponse(
        "Farmer profile does not match this mobile number.",
        403,
        undefined,
        "farmer_mismatch",
      );
    }

    const now = new Date().toISOString();
    const linkedProfile = {
      user_id: userId,
      phone,
      farmer_id: verifiedFarmerId || farmerId,
      farmer_name: text(verifiedProfile.farmer_name) || farmerName,
      default_location: text(verifiedProfile.default_location) ||
        defaultLocation,
      preferred_language: text(verifiedProfile.preferred_language) ||
        preferredLanguage,
      agri_record_id: text(verifiedProfile.agri_record_id),
      aadhaar_number: text(verifiedProfile.aadhaar_number),
      aadhaar_masked: text(verifiedProfile.aadhaar_masked),
      aadhaar_last4: text(verifiedProfile.aadhaar_last4),
      identity_document_bucket:
        text(verifiedProfile.identity_document_bucket) ||
        "farmer-identity-documents",
      identity_document_path: text(verifiedProfile.identity_document_path),
      identity_ocr_confidence: verifiedProfile.identity_ocr_confidence ?? null,
      identity_source: text(verifiedProfile.identity_source),
      identity_verified_at: verifiedProfile.identity_verified_at ?? null,
      auth_method: "anonymous_link",
      status: "active",
      phone_verified_at: now,
      source: "phone_login",
      updated_at: now,
    };

    const { data: profile, error: profileError } = await upsertLinkedProfile(
      supabase,
      linkedProfile,
    );

    if (profileError) throw profileError;

    await pruneDuplicateActiveFarmerProfiles(supabase, {
      phone,
      farmerId: verifiedFarmerId || farmerId,
      keepUserId: userId,
    });

    return successResponse({ profile }, 200, "farmer_linked");
  } catch (error) {
    return errorResponse("link-farmer-phone failed", 500, error);
  }
});
