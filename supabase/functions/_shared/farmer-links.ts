import { errorResponse } from "./response.ts";

export function normalizePhone(raw: unknown): string {
  return String(raw ?? "").replace(/\D/g, "").slice(-10);
}

export function phoneVariants(raw: unknown): string[] {
  const phone = normalizePhone(raw);
  if (phone.length !== 10) return [];

  return Array.from(
    new Set(
      [
        phone,
        `91${phone}`,
        `+91${phone}`,
      ],
    ),
  );
}

export function text(raw: unknown): string {
  return String(raw ?? "").trim();
}

export function bearerToken(req: Request): string {
  const header = req.headers.get("Authorization") ?? "";
  return header.replace(/^Bearer\s+/i, "").trim();
}

export async function requireUserId(
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
  return userData.user.id;
}

export function optionalSchemaError(error: unknown): boolean {
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

function rows(data: unknown): Array<Record<string, unknown>> {
  return Array.isArray(data) ? data as Array<Record<string, unknown>> : [];
}

function isActiveProfile(row: Record<string, unknown>): boolean {
  return String(row.status ?? "active") === "active";
}

async function selectActiveProfilesForPhone(
  supabase: any,
  phoneValues: string[],
): Promise<Array<Record<string, unknown>>> {
  const result = await supabase
    .from("farmer_phone_profiles")
    .select("id, user_id, phone, farmer_id, status, created_at, updated_at")
    .in("phone", phoneValues)
    .eq("status", "active");

  if (!result.error) return rows(result.data);
  if (!optionalSchemaError(result.error)) throw result.error;

  const fallback = await supabase
    .from("farmer_phone_profiles")
    .select("id, user_id, phone, farmer_id, created_at, updated_at")
    .in("phone", phoneValues);
  if (fallback.error) throw fallback.error;
  return rows(fallback.data).filter(isActiveProfile);
}

async function selectProfilesForUser(
  supabase: any,
  userId: string,
): Promise<Array<Record<string, unknown>>> {
  const result = await supabase
    .from("farmer_phone_profiles")
    .select("user_id, phone, farmer_id, status")
    .eq("user_id", userId);

  if (!result.error) return rows(result.data);
  if (!optionalSchemaError(result.error)) throw result.error;

  const fallback = await supabase
    .from("farmer_phone_profiles")
    .select("user_id, phone, farmer_id")
    .eq("user_id", userId);
  if (fallback.error) throw fallback.error;
  return rows(fallback.data);
}

async function selectProfilesByPhone(
  supabase: any,
  phoneValues: string[],
  { activeOnly = false }: { activeOnly?: boolean } = {},
): Promise<Array<Record<string, unknown>>> {
  let query = supabase
    .from("farmer_phone_profiles")
    .select("user_id, phone, farmer_id, status")
    .in("phone", phoneValues);
  if (activeOnly) query = query.eq("status", "active");
  const result = await query;

  if (!result.error) return rows(result.data);
  if (!optionalSchemaError(result.error)) throw result.error;

  const fallback = await supabase
    .from("farmer_phone_profiles")
    .select("user_id, phone, farmer_id")
    .in("phone", phoneValues);
  if (fallback.error) throw fallback.error;
  return rows(fallback.data);
}

async function selectProfilesByFarmerId(
  supabase: any,
  farmerId: string,
): Promise<Array<Record<string, unknown>>> {
  const result = await supabase
    .from("farmer_phone_profiles")
    .select("user_id, phone, farmer_id, status")
    .eq("farmer_id", farmerId)
    .eq("status", "active");

  if (!result.error) return rows(result.data);
  if (!optionalSchemaError(result.error)) throw result.error;

  const fallback = await supabase
    .from("farmer_phone_profiles")
    .select("user_id, phone, farmer_id")
    .eq("farmer_id", farmerId);
  if (fallback.error) throw fallback.error;
  return rows(fallback.data);
}

export async function pruneDuplicateActiveFarmerProfiles(
  supabase: any,
  options: { phone: string; farmerId?: string; keepUserId?: string },
): Promise<void> {
  const normalizedPhone = normalizePhone(options.phone);
  if (normalizedPhone.length !== 10) return;

  const phoneValues = phoneVariants(normalizedPhone);
  if (phoneValues.length === 0) return;

  const farmerId = text(options.farmerId);
  const keepUserId = text(options.keepUserId);
  const activeProfiles =
    (await selectActiveProfilesForPhone(supabase, phoneValues))
      .filter((row) => {
        if (normalizePhone(row.phone) !== normalizedPhone) return false;
        if (farmerId.length === 0) return true;
        const rowFarmerId = text(row.farmer_id);
        return rowFarmerId.length === 0 || rowFarmerId === farmerId;
      });

  const userIds = Array.from(
    new Set(
      activeProfiles.map((row) => text(row.user_id))
        .filter((value) => value.length > 0),
    ),
  );
  if (userIds.length <= 1) return;

  const { data: farmRows, error: farmError } = await supabase
    .from("farms")
    .select("user_id")
    .in("user_id", userIds);
  if (farmError) throw farmError;

  const farmOwnerIds = new Set(
    rows(farmRows).map((row) => text(row.user_id))
      .filter((value) => value.length > 0),
  );

  const keepIds = new Set<string>(farmOwnerIds);
  if (keepUserId.length > 0) keepIds.add(keepUserId);

  if (keepIds.size === 0) {
    const newestProfile = [...activeProfiles].sort((a, b) => {
      const aTime = Date.parse(text(a.updated_at) || text(a.created_at));
      const bTime = Date.parse(text(b.updated_at) || text(b.created_at));
      return (Number.isFinite(bTime) ? bTime : 0) -
        (Number.isFinite(aTime) ? aTime : 0);
    })[0];
    const newestUserId = text(newestProfile?.user_id);
    if (newestUserId.length > 0) keepIds.add(newestUserId);
  }

  const staleUserIds = Array.from(
    new Set(
      activeProfiles.map((row) => text(row.user_id))
        .filter((userId) => userId.length > 0 && !keepIds.has(userId)),
    ),
  );
  if (staleUserIds.length === 0) return;

  const { error: updateError } = await supabase
    .from("farmer_phone_profiles")
    .update({ status: "inactive", updated_at: new Date().toISOString() })
    .in("user_id", staleUserIds)
    .eq("status", "active");
  if (updateError && !optionalSchemaError(updateError)) throw updateError;
}

export async function loadLinkedUserIds(
  supabase: any,
  userId: string,
  phone: string,
  farmerId: string,
): Promise<string[] | Response> {
  const normalizedPhone = normalizePhone(phone);
  if (normalizedPhone.length !== 10) {
    return errorResponse(
      "Enter a valid 10 digit mobile number",
      400,
      undefined,
      "invalid_phone",
    );
  }

  const phoneValues = phoneVariants(phone);
  if (phoneValues.length === 0) {
    return errorResponse(
      "Enter a valid 10 digit mobile number",
      400,
      undefined,
      "invalid_phone",
    );
  }

  const currentProfiles = await selectProfilesForUser(supabase, userId);
  const activeCurrentProfile = currentProfiles.find(
    (row) =>
      isActiveProfile(row) &&
      normalizePhone(row.phone) === normalizedPhone,
  );

  const { data: legacyCurrentProfiles, error: legacyCurrentProfileError } =
    await supabase
      .from("farmer_ai_profiles")
      .select("user_id, phone")
      .eq("user_id", userId);
  if (legacyCurrentProfileError) throw legacyCurrentProfileError;

  const hasLegacyCurrentProfile =
    (Array.isArray(legacyCurrentProfiles) ? legacyCurrentProfiles : [])
      .some((row) => normalizePhone(row.phone) === normalizedPhone);

  if (!activeCurrentProfile && !hasLegacyCurrentProfile) {
    return errorResponse(
      "This session is not linked to that farmer number.",
      403,
      undefined,
      "farmer_session_not_linked",
    );
  }

  const currentFarmerId = text(activeCurrentProfile?.farmer_id);
  if (
    currentFarmerId.length > 0 &&
    farmerId.length > 0 &&
    currentFarmerId !== farmerId
  ) {
    return errorResponse(
      "This session is not linked to that farmer number.",
      403,
      undefined,
      "farmer_id_mismatch",
    );
  }

  const linkedProfiles: Array<Record<string, unknown>> = [];
  const phoneProfiles = await selectProfilesByPhone(
    supabase,
    phoneValues,
    { activeOnly: true },
  );
  for (const row of phoneProfiles) {
    if (normalizePhone(row.phone) === normalizedPhone) {
      linkedProfiles.push(row);
    }
  }

  if (farmerId.length > 0) {
    const farmerProfiles = await selectProfilesByFarmerId(supabase, farmerId);
    linkedProfiles.push(...farmerProfiles);
  }

  const { data: legacyProfiles, error: legacyProfileError } = await supabase
    .from("farmer_ai_profiles")
    .select("user_id, phone")
    .in("phone", phoneValues);
  if (legacyProfileError) throw legacyProfileError;
  if (Array.isArray(legacyProfiles)) {
    for (const row of legacyProfiles) {
      if (normalizePhone(row.phone) === normalizedPhone) {
        linkedProfiles.push(row);
      }
    }
  }

  return Array.from(
    new Set(
      linkedProfiles.map((row) => String(row.user_id ?? ""))
        .filter((value) => value.length > 0),
    ),
  );
}

export async function assertLinkedFarm(
  supabase: any,
  userId: string,
  phone: string,
  farmerId: string,
  farmId: string,
): Promise<Record<string, unknown> | Response> {
  const linkedUserIds = await loadLinkedUserIds(
    supabase,
    userId,
    phone,
    farmerId,
  );
  if (linkedUserIds instanceof Response) return linkedUserIds;
  if (linkedUserIds.length === 0) {
    return errorResponse(
      "This session is not linked to this farm owner.",
      403,
      undefined,
      "farmer_session_not_linked",
    );
  }

  const { data: farm, error: farmError } = await supabase
    .from("farms")
    .select("id, user_id, geometry, bounds")
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
  return farm as Record<string, unknown>;
}
