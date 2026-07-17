import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  normalizePhone,
  phoneVariants,
  pruneDuplicateActiveFarmerProfiles,
} from "../_shared/farmer-links.ts";

const farmerIdentitySelect =
  "phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at, agri_record_id, aadhaar_number, aadhaar_masked, aadhaar_last4, identity_document_path";
const farmerProfileIdentitySelect =
  "user_id, phone, farmer_id, farmer_name, default_location, preferred_language, status, agri_record_id, aadhaar_number, aadhaar_masked, aadhaar_last4, identity_document_path";

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

function missingAadhaarNumberColumn(error: unknown): boolean {
  const value = String(
    (error as { code?: unknown; message?: unknown; details?: unknown })?.code ??
      (error as { message?: unknown })?.message ??
      (error as { details?: unknown })?.details ??
      error ??
      "",
  ).toLowerCase();
  return value.includes("aadhaar_number") &&
    (value.includes("42703") ||
      value.includes("schema cache") ||
      value.includes("column") ||
      value.includes("does not exist"));
}

async function selectPhoneRows(
  supabase: any,
  table: string,
  selectColumns: string,
  phoneValues: string[],
) {
  return await supabase
    .from(table)
    .select(selectColumns)
    .in("phone", phoneValues);
}

async function updateRegistryProfile(
  supabase: any,
  profile: Record<string, unknown>,
  registryPhone: string,
) {
  return await supabase
    .from("farmer_phone_registry")
    .update(profile)
    .eq("phone", registryPhone)
    .select(farmerIdentitySelect)
    .maybeSingle();
}

async function insertRegistryProfile(
  supabase: any,
  profile: Record<string, unknown>,
) {
  return await supabase
    .from("farmer_phone_registry")
    .insert(profile)
    .select(farmerIdentitySelect)
    .single();
}

async function upsertFarmerProfile(
  supabase: any,
  profile: Record<string, unknown>,
) {
  return await supabase
    .from("farmer_phone_profiles")
    .upsert(profile, { onConflict: "user_id" })
    .select(farmerProfileIdentitySelect)
    .single();
}

async function rollbackRegistryRegistration(
  supabase: any,
  phone: string,
  registryWasCreated: boolean,
) {
  if (registryWasCreated) {
    await supabase
      .from("farmer_phone_registry")
      .delete()
      .eq("phone", phone);
    return;
  }
  await supabase
    .from("farmer_phone_registry")
    .update({ profile_completed_at: null })
    .eq("phone", phone);
}

function rowToProfile(row: Record<string, unknown>) {
  const phone = normalizePhone(row.phone);
  return {
    phone,
    farmerId: String(row.farmer_id ?? `FMR-${phone}`),
    farmerName: String(row.farmer_name ?? "Farmer"),
    defaultLocation: String(row.default_location ?? ""),
    agriRecordId: String(row.agri_record_id ?? ""),
    aadhaarNumber: String(row.aadhaar_number ?? ""),
    aadhaarMasked: String(row.aadhaar_masked ?? ""),
    aadhaarLast4: String(row.aadhaar_last4 ?? ""),
    identityDocumentPath: String(row.identity_document_path ?? ""),
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

function aadhaarLast4(raw: unknown): string {
  const digits = String(raw ?? "").replace(/\D/g, "");
  return digits.length === 4 ? digits : "";
}

function aadhaarNumber(raw: unknown): string {
  const digits = String(raw ?? "").replace(/\D/g, "");
  return digits.length === 12 ? digits : "";
}

function maskedAadhaar(raw: unknown, last4: string): string {
  const value = text(raw);
  if (/^X{4}\sX{4}\s\d{4}$/i.test(value)) return value.toUpperCase();
  return last4.length === 4 ? `XXXX XXXX ${last4}` : "";
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
    const agriRecordId = text(body.agriRecordId ?? body.agri_record_id);
    const identityDocumentPath = text(
      body.identityDocumentPath ?? body.identity_document_path,
    );
    const requestedIdentitySource = text(
      body.identitySource ?? body.identity_source,
    );
    const last4 = aadhaarLast4(body.aadhaarLast4 ?? body.aadhaar_last4);
    const fullAadhaarNumber = aadhaarNumber(
      body.aadhaarNumber ?? body.aadhaar_number,
    );
    const aadhaarLastDigits = last4.length === 4
      ? last4
      : fullAadhaarNumber.length === 12
      ? fullAadhaarNumber.slice(-4)
      : "";
    const aadhaarMasked = maskedAadhaar(
      body.aadhaarMasked ?? body.aadhaar_masked,
      aadhaarLastDigits,
    );
    const identityOcrConfidenceRaw = body.identityOcrConfidence ??
      body.identity_ocr_confidence;
    const identityOcrConfidence = identityOcrConfidenceRaw == null
      ? null
      : Number(identityOcrConfidenceRaw);
    const hasDocumentProof = identityDocumentPath.length > 0;
    const identitySource = hasDocumentProof
      ? requestedIdentitySource || "agri_record_document"
      : "manual_entry";

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
    if (fullAadhaarNumber.length !== 12 || aadhaarMasked.length === 0) {
      return errorResponse(
        "Enter a 12 digit Aadhaar number",
        400,
        undefined,
        "invalid_aadhaar",
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
    if (
      hasDocumentProof && !identityDocumentPath.startsWith(`${userId}/`)
    ) {
      return errorResponse(
        "Document does not belong to this farmer session",
        403,
        undefined,
        "document_owner_mismatch",
      );
    }

    const phoneValues = phoneVariants(phone);
    const { data: registryRows, error: registryError } = await selectPhoneRows(
      supabase,
      "farmer_phone_registry",
      farmerIdentitySelect,
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

    const { data: profileRows, error: profileError } = await selectPhoneRows(
      supabase,
      "farmer_phone_profiles",
      farmerProfileIdentitySelect,
      phoneValues,
    );

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
      agri_record_id: agriRecordId,
      aadhaar_number: fullAadhaarNumber,
      aadhaar_masked: aadhaarMasked,
      aadhaar_last4: aadhaarLastDigits,
      identity_document_bucket: "farmer-identity-documents",
      identity_document_path: identityDocumentPath,
      identity_ocr_confidence: Number.isFinite(identityOcrConfidence)
        ? identityOcrConfidence
        : null,
      identity_source: identitySource,
      identity_verified_at: now,
    };

    let registryRecord: Record<string, unknown> | null = null;
    if (registryProfile) {
      const registryPhone = text(registryProfile.phone) || phone;
      const { data: registryUpdate, error: registryUpdateError } =
        await updateRegistryProfile(supabase, profile, registryPhone);

      if (registryUpdateError) throw registryUpdateError;
      registryRecord = registryUpdate as Record<string, unknown> | null;
    } else {
      const { data: registryInsert, error: registryInsertError } =
        await insertRegistryProfile(supabase, profile);

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

    const { data: savedProfile, error: profileUpsertError } =
      await upsertFarmerProfile(
        supabase,
        {
          user_id: userId,
          ...profile,
          auth_method: "anonymous_link",
          phone_verified_at: now,
        },
      );

    if (profileUpsertError) {
      await rollbackRegistryRegistration(
        supabase,
        text(registryRecord.phone) || phone,
        registryProfile == null,
      );
      throw profileUpsertError;
    }
    if (
      text(savedProfile?.aadhaar_number) !== fullAadhaarNumber ||
      text(savedProfile?.aadhaar_last4) !== aadhaarLastDigits
    ) {
      await rollbackRegistryRegistration(
        supabase,
        text(registryRecord.phone) || phone,
        registryProfile == null,
      );
      throw new Error("Farmer Aadhaar persistence verification failed");
    }

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
    if (missingAadhaarNumberColumn(error)) {
      return errorResponse(
        "Farmer identity storage is not ready. Apply the Aadhaar schema migration and try again.",
        503,
        undefined,
        "aadhaar_schema_required",
      );
    }
    return errorResponse("register-farmer-phone failed", 500, error);
  }
});
