import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { normalizePhone, text } from "../_shared/farmer-links.ts";

type Row = Record<string, unknown>;
type Identity = {
  whatsapp_phone: string;
  user_id: string;
  role: "farmer" | "fpc";
  farmer_id: string | null;
  fpc_id: string | null;
  language: "en" | "hi" | "mr";
};

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Missing Supabase service credentials");
  return createClient(url, key);
}

function object(raw: unknown): Row {
  return raw != null && typeof raw === "object" && !Array.isArray(raw)
    ? (raw as Row)
    : {};
}

function language(raw: unknown): "en" | "hi" | "mr" {
  const value = text(raw).toLowerCase();
  return value === "hi" || value === "mr" ? value : "en";
}

function marketQueryTerms(raw: string): string[] {
  return raw
    .split(/[,;|\n]+/)
    .flatMap((part) => part.trim().split(/\s+/))
    .map((part) =>
      part
        .replace(/[()%\[\],]/g, "")
        .trim()
        .slice(0, 60),
    )
    .filter((part) => part.length > 0)
    .filter(
      (part, index, all) =>
        all.findIndex(
          (candidate) => candidate.toLowerCase() === part.toLowerCase(),
        ) === index,
    );
}

function addMarketQueryFilters<T extends { or: (filters: string) => T }>(
  request: T,
  terms: string[],
  requireEveryTerm: boolean,
): T {
  if (terms.length === 0) return request;
  const clauses = (term: string) =>
    [
      `commodity.ilike.%${term}%`,
      `market.ilike.%${term}%`,
      `district.ilike.%${term}%`,
      `state.ilike.%${term}%`,
    ].join(",");
  if (requireEveryTerm) {
    for (const term of terms) request = request.or(clauses(term));
    return request;
  }
  return request.or(terms.map(clauses).join(","));
}

function bridgeAuthorized(req: Request): boolean {
  const expected = Deno.env.get("GRAINRIGHT_WHATSAPP_API_TOKEN")?.trim() ?? "";
  const received =
    (req.headers.get("x-grainright-whatsapp-bridge") ?? "").trim() ||
    (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  return (
    expected.length >= 24 &&
    received.length === expected.length &&
    received === expected
  );
}

function configuredAppUrl(required = true): string | null {
  const raw = Deno.env.get("GRAINRIGHT_APP_URL")?.trim() ?? "";
  if (!raw) {
    if (required)
      throw new HttpError(
        "GrainRight farm boundary link is not configured.",
        503,
      );
    return null;
  }
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch (_) {
    throw new HttpError("GrainRight app URL is invalid.", 503);
  }
  if (
    parsed.protocol !== "https:" ||
    parsed.hostname.endsWith(".supabase.co")
  ) {
    throw new HttpError(
      "GrainRight app URL must be a public HTTPS app host.",
      503,
    );
  }
  return raw.replace(/\/$/, "");
}

function boundaryMapUrl(
  appUrl: string,
  token: string,
  preferredLanguage: "en" | "hi" | "mr",
): string {
  const parameters = new URLSearchParams({
    token,
    lang: preferredLanguage,
  });
  return `${appUrl}/whatsapp-farm-boundary?${parameters.toString()}`;
}

function serviceLinkUrl(
  appUrl: string,
  token: string,
  preferredLanguage: "en" | "hi" | "mr",
): string {
  const parameters = new URLSearchParams({ token, lang: preferredLanguage });
  return `${appUrl}/whatsapp-service?${parameters.toString()}`;
}

function fpcSignupUrl(
  appUrl: string,
  token: string,
  preferredLanguage: "en" | "hi" | "mr",
): string {
  const parameters = new URLSearchParams({
    whatsapp_token: token,
    lang: preferredLanguage,
  });
  return `${appUrl}/fpc/signup?${parameters.toString()}`;
}

const webServices = new Set(["ai", "grading", "daily_tasks"]);

async function farmerIdentity(
  supabase: ReturnType<typeof serviceClient>,
  phone: string,
  preferredLanguage: "en" | "hi" | "mr",
) {
  const values = [phone, `91${phone}`, `+91${phone}`];
  const { data, error } = await supabase
    .from("farmer_phone_profiles")
    .select("user_id,farmer_id,phone,status")
    .in("phone", values)
    .eq("status", "active")
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  if (!data?.user_id || !data?.farmer_id) return null;
  const identity = {
    whatsapp_phone: phone,
    user_id: String(data.user_id),
    role: "farmer",
    farmer_id: String(data.farmer_id),
    fpc_id: null,
    language: preferredLanguage,
    last_seen_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  const { error: upsertError } = await supabase
    .from("whatsapp_identities")
    .upsert(identity, { onConflict: "whatsapp_phone,role" });
  if (upsertError) throw upsertError;
  return identity as unknown as Identity;
}

async function activeIdentity(
  supabase: ReturnType<typeof serviceClient>,
  phone: string,
): Promise<Identity | null> {
  const { data, error } = await supabase
    .from("whatsapp_identities")
    .select("whatsapp_phone,user_id,role,farmer_id,fpc_id,language")
    .eq("whatsapp_phone", phone)
    .order("last_seen_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data ? (data as Identity) : null;
}

async function requireFarmer(
  supabase: ReturnType<typeof serviceClient>,
  phone: string,
  preferredLanguage: "en" | "hi" | "mr",
) {
  const existing = await activeIdentity(supabase, phone);
  if (existing?.role === "farmer") return existing;
  const linked = await farmerIdentity(supabase, phone, preferredLanguage);
  if (!linked)
    throw new HttpError(
      "This WhatsApp number is not linked to an active GrainRight farmer account.",
      403,
    );
  return linked;
}

class HttpError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly details: Row = {},
  ) {
    super(message);
  }
}

async function farmsFor(
  supabase: ReturnType<typeof serviceClient>,
  identity: Identity,
) {
  const { data, error } = await supabase
    .from("farms")
    .select(
      "id,name,crop,variety,location_label,area_hectares,area_acres,current_status,current_status_stage,current_status_updated_at,sowing_date",
    )
    .eq("user_id", identity.user_id)
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return Array.isArray(data) ? data : [];
}

async function resolveFarm(
  supabase: ReturnType<typeof serviceClient>,
  identity: Identity,
  rawFarm: unknown,
) {
  const farms = await farmsFor(supabase, identity);
  const requested = text(rawFarm);
  const farm =
    requested.length === 0
      ? farms[0]
      : farms.find(
          (item) =>
            String(item.id) === requested ||
            String(item.name).toLowerCase() === requested.toLowerCase(),
        );
  if (!farm) {
    throw new HttpError("Choose one of your linked farms first.", 404, {
      farms: farms.slice(0, 8).map((item) => ({
        id: item.id,
        name: item.name,
        crop: item.crop,
        location_label: item.location_label,
      })),
    });
  }
  return farm as Row;
}

async function saveSession(
  supabase: ReturnType<typeof serviceClient>,
  phone: string,
  body: Row,
  identity: Identity | null,
) {
  const row = {
    whatsapp_phone: phone,
    language: language(body.language ?? identity?.language),
    role: identity?.role ?? null,
    selected_farm_id:
      text(body.selectedFarmId ?? body.selected_farm_id) || null,
    flow: text(body.flow),
    draft: object(body.draft),
    updated_at: new Date().toISOString(),
  };
  const { error } = await supabase.from("whatsapp_chat_sessions").upsert(row);
  if (error) throw error;
  return row;
}

function safeOnboardingDraft(raw: unknown): Row {
  const draft = object(raw);
  const safe = { ...draft };
  delete safe.aadhaarNumber;
  delete safe.aadhaar_number;
  if (draft.aadhaarNumber || draft.aadhaar_number) safe.aadhaarCollected = true;
  return safe;
}

function mergeOnboardingDraft(left: unknown, right: unknown): Row {
  const current = object(left);
  const incoming = object(right);
  return {
    ...current,
    ...incoming,
    farm: { ...object(current.farm), ...object(incoming.farm) },
  };
}

async function activeOnboarding(
  supabase: ReturnType<typeof serviceClient>,
  phone: string,
  flowType: "new_farmer" | "existing_farmer_farm" = "new_farmer",
) {
  const { data, error } = await supabase
    .from("whatsapp_farmer_onboardings")
    .select("*")
    .eq("whatsapp_phone", phone)
    .eq("flow_type", flowType)
    .eq("status", "active")
    .gt("expires_at", new Date().toISOString())
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return data as Row | null;
}

async function ensureOnboarding(
  supabase: ReturnType<typeof serviceClient>,
  phone: string,
  preferredLanguage: "en" | "hi" | "mr",
) {
  const existing = await activeOnboarding(supabase, phone, "new_farmer");
  if (existing) return existing;
  const { data, error } = await supabase
    .from("whatsapp_farmer_onboardings")
    .insert({
      onboarding_key: crypto.randomUUID(),
      whatsapp_phone: phone,
      language: preferredLanguage,
      status: "active",
      step: "farmer_name",
      draft: {},
      flow_type: "new_farmer",
    })
    .select("*")
    .single();
  if (error) throw error;
  return data as Row;
}

async function ensureFarmSetup(
  supabase: ReturnType<typeof serviceClient>,
  phone: string,
  preferredLanguage: "en" | "hi" | "mr",
) {
  const identity = await requireFarmer(supabase, phone, preferredLanguage);
  const existing = await activeOnboarding(
    supabase,
    phone,
    "existing_farmer_farm",
  );
  if (existing) return existing;
  const { data, error } = await supabase
    .from("whatsapp_farmer_onboardings")
    .insert({
      onboarding_key: crypto.randomUUID(),
      whatsapp_phone: phone,
      language: preferredLanguage,
      status: "active",
      step: "farm_name",
      draft: {},
      flow_type: "existing_farmer_farm",
      user_id: identity.user_id,
      farmer_id: identity.farmer_id,
    })
    .select("*")
    .single();
  if (error) throw error;
  return data as Row;
}

async function hashToken(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function onboardingResponse(row: Row | null) {
  if (!row) return { onboarding: null };
  return {
    onboarding: {
      id: row.id,
      step: row.step,
      status: row.status,
      flowType: text(row.flow_type) || "new_farmer",
      language: language(row.language),
      draft: safeOnboardingDraft(row.draft),
      mapReady: Boolean(
        object(row.draft).farm && object(object(row.draft).farm).geometry,
      ),
      expiresAt: row.expires_at,
      farmerId: row.farmer_id,
      farmId: row.farm_id,
    },
  };
}

function farmSetupStepToFlow(step: string): string {
  const map: Record<string, string> = {
    farm_name: "farm_setup_farm_name",
    crop: "farm_setup_crop",
    variety: "farm_setup_variety",
    previous_crop: "farm_setup_previous_crop",
    season: "farm_setup_season",
    irrigation: "farm_setup_irrigation",
    soil_type: "farm_setup_soil_type",
    ownership_type: "farm_setup_ownership_type",
    seed_source: "farm_setup_seed_source",
    harvest_intent: "farm_setup_harvest_intent",
    sowing_date: "farm_setup_sowing_date",
    boundary: "farm_setup_boundary",
    boundary_saved: "farm_setup_boundary",
  };
  return map[step] || "farm_setup_farm_name";
}

function onboardingStepToFlow(step: string): string {
  const map: Record<string, string> = {
    farmer_name: "onboarding_farmer_name",
    default_location: "onboarding_default_location",
    agri_record_id: "onboarding_agri_record_id",
    aadhaar: "onboarding_aadhaar",
    farm_name: "onboarding_farm_name",
    farm_location: "onboarding_farm_location",
    boundary: "onboarding_boundary",
    crop: "onboarding_crop",
    variety: "onboarding_variety",
    previous_crop: "onboarding_previous_crop",
    season: "onboarding_season",
    irrigation: "onboarding_irrigation",
    soil_type: "onboarding_soil_type",
    ownership_type: "onboarding_ownership_type",
    seed_source: "onboarding_seed_source",
    harvest_intent: "onboarding_harvest_intent",
    sowing_date: "onboarding_sowing_date",
    review: "onboarding_review",
  };
  return map[step] || "onboarding_farmer_name";
}

function finitePositive(raw: unknown): number | null {
  const value = Number(raw);
  return Number.isFinite(value) && value > 0 ? value : null;
}

function polygonGeometry(raw: unknown): Row {
  const geometry = object(raw);
  const coordinates = geometry.coordinates;
  const ring =
    Array.isArray(coordinates) && Array.isArray(coordinates[0])
      ? coordinates[0]
      : [];
  if (text(geometry.type).toLowerCase() !== "polygon" || ring.length < 4) {
    throw new HttpError("A valid farm boundary is required.", 400, {
      code: "farm_geometry_required",
    });
  }
  const valid = ring.every(
    (point) =>
      Array.isArray(point) &&
      point.length >= 2 &&
      Number.isFinite(Number(point[0])) &&
      Number.isFinite(Number(point[1])) &&
      Math.abs(Number(point[0])) <= 180 &&
      Math.abs(Number(point[1])) <= 90,
  );
  const first = ring[0] as unknown[];
  const last = ring[ring.length - 1] as unknown[];
  const closed =
    Array.isArray(first) &&
    Array.isArray(last) &&
    Number(first[0]) === Number(last[0]) &&
    Number(first[1]) === Number(last[1]);
  if (!valid || !closed) {
    throw new HttpError(
      "A closed farm boundary with valid coordinates is required.",
      400,
      {
        code: "farm_geometry_invalid",
      },
    );
  }
  const openRing = ring
    .slice(0, -1)
    .map((point) => [Number(point[0]), Number(point[1])] as [number, number]);
  if (new Set(openRing.map((point) => `${point[0]}:${point[1]}`)).size < 3) {
    throw new HttpError(
      "A farm boundary needs at least three different corners.",
      400,
      {
        code: "farm_geometry_degenerate",
      },
    );
  }
  if (hasSelfIntersection(openRing)) {
    throw new HttpError("The farm boundary cannot cross itself.", 400, {
      code: "farm_geometry_self_intersection",
    });
  }
  return geometry;
}

function orientation(
  a: [number, number],
  b: [number, number],
  c: [number, number],
): number {
  return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
}

function onSegment(
  a: [number, number],
  b: [number, number],
  p: [number, number],
): boolean {
  const epsilon = 1e-12;
  return (
    p[0] >= Math.min(a[0], b[0]) - epsilon &&
    p[0] <= Math.max(a[0], b[0]) + epsilon &&
    p[1] >= Math.min(a[1], b[1]) - epsilon &&
    p[1] <= Math.max(a[1], b[1]) + epsilon
  );
}

function segmentsIntersect(
  a: [number, number],
  b: [number, number],
  c: [number, number],
  d: [number, number],
): boolean {
  const epsilon = 1e-12;
  const abC = orientation(a, b, c);
  const abD = orientation(a, b, d);
  const cdA = orientation(c, d, a);
  const cdB = orientation(c, d, b);
  if (
    ((abC > epsilon && abD < -epsilon) || (abC < -epsilon && abD > epsilon)) &&
    ((cdA > epsilon && cdB < -epsilon) || (cdA < -epsilon && cdB > epsilon))
  ) {
    return true;
  }
  return (
    (Math.abs(abC) <= epsilon && onSegment(a, b, c)) ||
    (Math.abs(abD) <= epsilon && onSegment(a, b, d)) ||
    (Math.abs(cdA) <= epsilon && onSegment(c, d, a)) ||
    (Math.abs(cdB) <= epsilon && onSegment(c, d, b))
  );
}

function hasSelfIntersection(ring: [number, number][]): boolean {
  for (let first = 0; first < ring.length; first += 1) {
    const firstEnd = (first + 1) % ring.length;
    for (let second = first + 1; second < ring.length; second += 1) {
      const secondEnd = (second + 1) % ring.length;
      if (first === second || firstEnd === second || secondEnd === first)
        continue;
      if (
        segmentsIntersect(
          ring[first],
          ring[firstEnd],
          ring[second],
          ring[secondEnd],
        )
      )
        return true;
    }
  }
  return false;
}

function createFarmerId(): string {
  return `FMR-${crypto.randomUUID().replaceAll("-", "").slice(0, 12).toUpperCase()}`;
}

async function completeOnboarding(
  supabase: ReturnType<typeof serviceClient>,
  phone: string,
  row: Row,
) {
  if (text(row.status) === "completed" && text(row.farm_id)) {
    const { data: farm, error } = await supabase
      .from("farms")
      .select("*")
      .eq("id", row.farm_id)
      .maybeSingle();
    if (error) throw error;
    return {
      farmerId: row.farmer_id,
      farm,
      farmId: row.farm_id,
      idempotent: true,
    };
  }
  const draft = object(row.draft);
  const farmDraft = object(draft.farm);
  const farmerName = text(draft.farmerName);
  const aadhaar = text(draft.aadhaarNumber).replace(/\D/g, "");
  if (!farmerName || aadhaar.length !== 12) {
    throw new HttpError("Farmer identity details are incomplete.", 400);
  }
  const geometry = polygonGeometry(farmDraft.geometry);
  const areaHectares = finitePositive(farmDraft.area_hectares);
  if (!areaHectares)
    throw new HttpError("Farm boundary area is required.", 400);

  const existing = await farmerIdentity(
    supabase,
    phone,
    language(row.language),
  );
  if (existing) {
    throw new HttpError(
      "This WhatsApp number is already registered. Send MENU to continue.",
      409,
      {
        code: "farmer_already_exists",
      },
    );
  }

  const email = `whatsapp-${phone}-${String(row.id).replaceAll("-", "")}@grainright.invalid`;
  const { data: createdUser, error: userError } =
    await supabase.auth.admin.createUser({
      email,
      email_confirm: true,
    });
  if (userError || !createdUser.user)
    throw userError || new Error("Could not create farmer account");

  const userId = createdUser.user.id;
  const farmerId = createFarmerId();
  const now = new Date().toISOString();
  const aadhaarLast4 = aadhaar.slice(-4);
  const profile = {
    phone,
    farmer_id: farmerId,
    farmer_name: farmerName,
    default_location: text(draft.defaultLocation) || "Kalsubai Farms",
    preferred_language: language(row.language),
    status: "active",
    profile_completed_at: now,
    source: "whatsapp_onboarding",
    agri_record_id: text(draft.agriRecordId),
    aadhaar_number: aadhaar,
    aadhaar_masked: `XXXX XXXX ${aadhaarLast4}`,
    aadhaar_last4: aadhaarLast4,
    identity_document_bucket: "farmer-identity-documents",
    identity_document_path: "",
    identity_ocr_confidence: null,
    identity_source: "manual_entry",
    identity_verified_at: now,
  };
  let createdFarmId = "";
  try {
    const registry = await supabase
      .from("farmer_phone_registry")
      .insert(profile)
      .select("farmer_id")
      .single();
    if (registry.error) throw registry.error;
    const linked = await supabase.from("farmer_phone_profiles").insert({
      user_id: userId,
      ...profile,
      auth_method: "anonymous_link",
      phone_verified_at: now,
    });
    if (linked.error) throw linked.error;

    const farmRow = {
      name: text(farmDraft.name),
      location_label: text(farmDraft.location_label) || null,
      geometry,
      bounds: object(farmDraft.bounds),
      area_hectares: areaHectares,
      area_acres:
        finitePositive(farmDraft.area_acres) || areaHectares * 2.47105,
      user_id: userId,
      crop: text(farmDraft.crop) || null,
      variety: text(farmDraft.variety) || null,
      previous_crop: text(farmDraft.previous_crop) || null,
      season: text(farmDraft.season) || null,
      irrigation: text(farmDraft.irrigation) || null,
      soil_type: text(farmDraft.soil_type) || null,
      ownership_type: text(farmDraft.ownership_type) || null,
      seed_source: text(farmDraft.seed_source) || null,
      harvest_intent: text(farmDraft.harvest_intent) || null,
      sowing_date: text(farmDraft.sowing_date) || null,
    };
    if (!farmRow.name) throw new HttpError("Farm name is required.", 400);
    const farm = await supabase.rpc("whatsapp_create_farmer_farm", {
      p_user_id: userId,
      p_farm: farmRow,
    });
    if (farm.error) throw farm.error;
    const savedFarm = (
      Array.isArray(farm.data) ? farm.data[0] : farm.data
    ) as Row;
    if (!savedFarm?.id) throw new Error("Farm was created without an id.");
    createdFarmId = text(savedFarm.id);
    const updated = await supabase
      .from("whatsapp_farmer_onboardings")
      .update({
        status: "completed",
        step: "completed",
        user_id: userId,
        farmer_id: farmerId,
        farm_id: savedFarm.id,
        completed_at: now,
        updated_at: now,
      })
      .eq("id", row.id)
      .eq("status", "active")
      .select("*")
      .single();
    if (updated.error) throw updated.error;
    return {
      farmerId,
      farm: savedFarm,
      farmId: savedFarm.id,
      idempotent: false,
    };
  } catch (error) {
    if (createdFarmId) {
      await supabase.from("farms").delete().eq("id", createdFarmId);
    }
    await supabase.from("farmer_phone_profiles").delete().eq("user_id", userId);
    await supabase
      .from("farmer_phone_registry")
      .delete()
      .eq("phone", phone)
      .eq("farmer_id", farmerId);
    await supabase.auth.admin.deleteUser(userId);
    throw error;
  }
}

async function completeExistingFarmSetup(
  supabase: ReturnType<typeof serviceClient>,
  phone: string,
  row: Row,
  preferredLanguage: "en" | "hi" | "mr",
) {
  const identity = await requireFarmer(supabase, phone, preferredLanguage);
  if (text(row.status) === "completed" && text(row.farm_id)) {
    const { data: farm, error } = await supabase
      .from("farms")
      .select("*")
      .eq("id", row.farm_id)
      .maybeSingle();
    if (error) throw error;
    if (!farm)
      throw new HttpError("The completed farm could not be loaded.", 500);
    return {
      farmerId: identity.farmer_id,
      farm,
      farmId: row.farm_id,
      idempotent: true,
    };
  }

  if (text(row.status) !== "active") {
    throw new HttpError("This farm setup is no longer active.", 409);
  }

  const draft = object(row.draft);
  const farmDraft = object(draft.farm);
  const geometry = polygonGeometry(farmDraft.geometry);
  const areaHectares = finitePositive(farmDraft.area_hectares);
  const farmName = text(farmDraft.name);
  if (!farmName) throw new HttpError("Farm name is required.", 400);
  if (!areaHectares)
    throw new HttpError("Farm boundary area is required.", 400);

  const farmRow = {
    name: farmName,
    location_label: text(farmDraft.location_label) || null,
    geometry,
    bounds: object(farmDraft.bounds),
    area_hectares: areaHectares,
    area_acres: finitePositive(farmDraft.area_acres) || areaHectares * 2.47105,
    user_id: identity.user_id,
    crop: text(farmDraft.crop) || null,
    variety: text(farmDraft.variety) || null,
    previous_crop: text(farmDraft.previous_crop) || null,
    season: text(farmDraft.season) || null,
    irrigation: text(farmDraft.irrigation) || null,
    soil_type: text(farmDraft.soil_type) || null,
    ownership_type: text(farmDraft.ownership_type) || null,
    seed_source: text(farmDraft.seed_source) || null,
    harvest_intent: text(farmDraft.harvest_intent) || null,
    sowing_date: text(farmDraft.sowing_date) || null,
  };
  const { data, error } = await supabase.rpc(
    "whatsapp_complete_existing_farm_setup",
    {
      p_setup_id: row.id,
      p_user_id: identity.user_id,
      p_farm: farmRow,
    },
  );
  if (error) throw error;
  const farm = (Array.isArray(data) ? data[0] : data) as Row;
  if (!farm?.id) throw new HttpError("Farm was saved without an id.", 500);
  return {
    farmerId: identity.farmer_id,
    farm,
    farmId: farm.id,
    idempotent: false,
  };
}

async function importWhatsAppMedia(
  supabase: ReturnType<typeof serviceClient>,
  identity: Identity,
  body: Row,
) {
  const mediaId = text(body.mediaId ?? body.media_id);
  const kind = text(body.kind) === "moisture" ? "moisture" : "grain";
  const inlineBase64 = text(body.mediaBase64 ?? body.media_base64).replace(
    /^data:[^;]+;base64,/,
    "",
  );
  let bytes: Uint8Array;
  let mimeType =
    text(body.mediaMimeType ?? body.media_mime_type) || "image/jpeg";
  if (inlineBase64) {
    try {
      bytes = Uint8Array.from(atob(inlineBase64), (character) =>
        character.charCodeAt(0),
      );
    } catch {
      throw new HttpError("The WhatsApp image payload is invalid.", 400);
    }
  } else {
    if (!mediaId) throw new HttpError("A WhatsApp image is required.", 400);
    const accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
    const graphVersion = Deno.env.get("GRAPH_API_VERSION") || "v25.0";
    if (!accessToken)
      throw new HttpError("WhatsApp media access is not configured.", 503);
    const metadataResponse = await fetch(
      `https://graph.facebook.com/${graphVersion}/${mediaId}`,
      {
        headers: { authorization: `Bearer ${accessToken}` },
      },
    );
    if (!metadataResponse.ok)
      throw new HttpError("Could not load the WhatsApp image.", 422);
    const metadata = object(await metadataResponse.json());
    const downloadUrl = text(metadata.url);
    if (!downloadUrl)
      throw new HttpError("WhatsApp image URL was missing.", 422);
    const imageResponse = await fetch(downloadUrl, {
      headers: { authorization: `Bearer ${accessToken}` },
    });
    if (!imageResponse.ok)
      throw new HttpError("Could not download the WhatsApp image.", 422);
    mimeType = imageResponse.headers.get("content-type") || "image/jpeg";
    bytes = new Uint8Array(await imageResponse.arrayBuffer());
  }
  if (!mimeType.startsWith("image/"))
    throw new HttpError("Only image attachments are supported.", 415);
  const extension = mimeType.includes("png") ? "png" : "jpg";
  const bucket = kind === "moisture" ? "moisture-images" : "grain-images";
  const path = `${identity.user_id}/whatsapp/${crypto.randomUUID()}.${extension}`;
  if (bytes.byteLength > 12 * 1024 * 1024)
    throw new HttpError(
      "The image is too large. Send an image under 12 MB.",
      413,
    );
  const { error } = await supabase.storage
    .from(bucket)
    .upload(path, bytes, { contentType: mimeType, upsert: false });
  if (error) throw error;
  return { path, bucket, mimeType };
}

async function invokeInternal(name: string, body: Row) {
  const url = Deno.env.get("SUPABASE_URL");
  const token = Deno.env.get("GRAINRIGHT_WHATSAPP_INTERNAL_TOKEN");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !token || !anonKey) {
    throw new HttpError(
      "WhatsApp internal service bridge is not configured.",
      503,
    );
  }
  const response = await fetch(`${url}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${anonKey}`,
      apikey: anonKey,
      "x-grainright-whatsapp-internal": token,
    },
    body: JSON.stringify({ ...body, whatsapp_internal: true }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok)
    throw new HttpError(
      text((data as Row).message) || `${name} failed`,
      response.status,
    );
  return data;
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);
  if (!bridgeAuthorized(req))
    return errorResponse("Unauthorized WhatsApp bridge request", 401);

  try {
    const body = object(await req.json());
    const action = text(body.action).toLowerCase();
    const phone = normalizePhone(body.phone);
    const phoneOptional = [
      "webhook_prepare",
      "webhook_complete",
      "webhook_fail",
      "delivery_status",
    ].includes(action);
    if (!phoneOptional && phone.length !== 10)
      return errorResponse("A valid WhatsApp phone number is required", 400);
    const preferredLanguage = language(body.language);
    const supabase = serviceClient();

    if (action === "health") {
      return successResponse(
        { service: "whatsapp-grainright" },
        200,
        "whatsapp_gateway_healthy",
      );
    }

    if (action === "session_load") {
      const { data, error } = await supabase
        .from("whatsapp_chat_sessions")
        .select(
          "language,role,flow,draft,bot_state,verified,selected_farm_id,updated_at",
        )
        .eq("whatsapp_phone", phone)
        .maybeSingle();
      if (error) throw error;
      const active = await activeIdentity(supabase, phone);
      let identity = active;
      if (!identity)
        identity = await farmerIdentity(supabase, phone, preferredLanguage);
      const onboarding = await activeOnboarding(
        supabase,
        phone,
        identity ? "existing_farmer_farm" : "new_farmer",
      );
      const fallback = data
        ? {
            language: data.language,
            role: data.role,
            flow: data.flow,
            draft: data.draft,
            verified: data.verified,
            selectedFarmId: data.selected_farm_id,
          }
        : null;
      const persisted = object(data?.bot_state);
      const persistedFlow = text(data?.flow ?? persisted.flow);
      const persistedManagedFlow = /^(onboarding|farm_setup)_/.test(
        persistedFlow,
      );
      const activeFlow = onboarding
        ? text(onboarding.flow_type) === "existing_farmer_farm"
          ? farmSetupStepToFlow(text(onboarding.step))
          : onboardingStepToFlow(text(onboarding.step))
        : "";
      const session =
        data || onboarding || identity
          ? {
              ...(Object.keys(persisted).length > 0 ? persisted : fallback),
              verified: Boolean(identity) || Boolean(data?.verified),
              role: identity?.role ?? data?.role ?? null,
              registrationStatus: identity ? "existing" : "new",
              onboardingId:
                onboarding?.id ??
                (persistedManagedFlow ? persisted.onboardingId : null) ??
                null,
              flow: activeFlow || (persistedManagedFlow ? "" : persistedFlow),
              draft: onboarding
                ? safeOnboardingDraft(onboarding.draft)
                : persistedManagedFlow
                  ? {}
                  : persisted.draft || data?.draft || {},
              language: onboarding
                ? language(onboarding.language)
                : data?.language || persisted.language || "",
              selectedFarmId:
                data?.selected_farm_id || persisted.selectedFarmId || null,
            }
          : {
              language: "",
              verified: false,
              registrationStatus: "new",
              flow: "",
              draft: {},
            };
      return successResponse(
        {
          session,
          identity: identity
            ? { farmerId: identity.farmer_id, role: identity.role }
            : null,
          onboarding: onboardingResponse(onboarding).onboarding,
        },
        200,
        "whatsapp_session_loaded",
      );
    }

    if (action === "session_save") {
      const identity = await activeIdentity(supabase, phone);
      const snapshot = object(body.session);
      const row = {
        whatsapp_phone: phone,
        language: language(snapshot.language ?? identity?.language),
        role: identity?.role ?? (text(snapshot.role) || null),
        verified: Boolean(identity) || snapshot.verified === true,
        selected_farm_id:
          text(snapshot.selectedFarmId ?? snapshot.selected_farm_id) || null,
        flow: text(snapshot.flow),
        draft: object(snapshot.draft),
        bot_state: snapshot,
        updated_at: new Date().toISOString(),
      };
      const { error } = await supabase
        .from("whatsapp_chat_sessions")
        .upsert(row);
      if (error) throw error;
      return successResponse(
        { session: snapshot },
        200,
        "whatsapp_session_saved",
      );
    }

    if (action === "webhook_claim") {
      const eventKey = text(body.eventKey ?? body.event_key);
      if (!eventKey)
        return errorResponse("A webhook event key is required.", 400);
      const { data, error } = await supabase.rpc(
        "claim_whatsapp_webhook_event",
        {
          p_event_key: eventKey,
          p_provider: text(body.provider) || "openwa",
          p_event_type: text(body.event),
          p_message_id: text(body.messageId ?? body.message_id) || null,
          p_whatsapp_phone: phone,
        },
      );
      if (error) throw error;
      return successResponse(object(data), 200, "whatsapp_webhook_claimed");
    }

    if (action === "webhook_prepare") {
      const eventKey = text(body.eventKey ?? body.event_key);
      const reply = text(body.reply);
      if (!eventKey || !reply)
        return errorResponse("An event key and reply are required.", 400);
      const replyPayload =
        body.replyPayload &&
        typeof body.replyPayload === "object" &&
        !Array.isArray(body.replyPayload)
          ? body.replyPayload
          : { type: "text" };
      const { error } = await supabase
        .from("whatsapp_webhook_events")
        .update({
          status: "reply_pending",
          reply_text: reply,
          reply_payload: replyPayload,
          updated_at: new Date().toISOString(),
        })
        .eq("event_key", eventKey)
        .eq("status", "processing");
      if (error) throw error;
      return successResponse(
        { eventKey, status: "reply_pending" },
        200,
        "whatsapp_webhook_reply_prepared",
      );
    }

    if (action === "webhook_complete" || action === "webhook_fail") {
      const eventKey = text(body.eventKey ?? body.event_key);
      let status = action === "webhook_complete" ? "completed" : "failed";
      if (action === "webhook_fail") {
        const { data: existing, error: existingError } = await supabase
          .from("whatsapp_webhook_events")
          .select("reply_text")
          .eq("event_key", eventKey)
          .maybeSingle();
        if (existingError) throw existingError;
        if (text(existing?.reply_text)) status = "reply_pending";
      }
      const { error } = await supabase
        .from("whatsapp_webhook_events")
        .update({
          status,
          provider_message_id:
            text(body.providerMessageId ?? body.provider_message_id) || null,
          last_error:
            action === "webhook_fail" ? text(body.error).slice(0, 1000) : "",
          processed_at:
            action === "webhook_complete" ? new Date().toISOString() : null,
          updated_at: new Date().toISOString(),
        })
        .eq("event_key", eventKey);
      if (error) throw error;
      return successResponse(
        { eventKey, status },
        200,
        "whatsapp_webhook_updated",
      );
    }

    if (action === "notification_preference") {
      const enabled = body.enabled === true;
      const identity = await activeIdentity(supabase, phone);
      if (!identity)
        return errorResponse(
          "Verify this WhatsApp number before changing alerts.",
          403,
        );
      const { error } = await supabase
        .from("whatsapp_identities")
        .update({
          notifications_enabled: enabled,
          notifications_updated_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("whatsapp_phone", phone);
      if (error) throw error;
      return successResponse(
        { enabled },
        200,
        "whatsapp_notification_preference_saved",
      );
    }

    if (action === "delivery_status") {
      const providerMessageId = text(
        body.providerMessageId ?? body.provider_message_id,
      );
      if (!providerMessageId)
        return successResponse(
          { updated: false },
          200,
          "whatsapp_delivery_ignored",
        );
      const deliveryStatus = text(body.deliveryStatus ?? body.delivery_status);
      const status =
        deliveryStatus === "failed"
          ? "failed"
          : deliveryStatus === "read"
            ? "read"
            : deliveryStatus === "delivered"
              ? "delivered"
              : "sent";
      const patch: Row = {
        status,
        last_error: status === "failed" ? text(body.error).slice(0, 1000) : "",
        updated_at: new Date().toISOString(),
      };
      if (status === "delivered" || status === "read")
        patch.delivered_at = new Date().toISOString();
      if (status === "read") patch.read_at = new Date().toISOString();
      const { data, error } = await supabase
        .from("whatsapp_notification_outbox")
        .update(patch)
        .eq("provider_message_id", providerMessageId)
        .select("id");
      if (error) throw error;
      return successResponse(
        { updated: (data ?? []).length > 0, status },
        200,
        "whatsapp_delivery_updated",
      );
    }

    if (action === "set_language") {
      const identity = await activeIdentity(supabase, phone);
      const session = await saveSession(supabase, phone, body, identity);
      if (identity)
        await supabase
          .from("whatsapp_identities")
          .update({
            language: preferredLanguage,
            last_seen_at: new Date().toISOString(),
          })
          .eq("whatsapp_phone", phone)
          .eq("role", identity.role);
      return successResponse({ session }, 200, "whatsapp_language_saved");
    }

    if (action === "onboarding_save") {
      const row = await ensureOnboarding(supabase, phone, preferredLanguage);
      if (text(row.status) !== "active")
        throw new HttpError("This onboarding is no longer active.", 409);
      const mergedDraft = mergeOnboardingDraft(row.draft, body.draft);
      const step = text(body.step) || text(row.step) || "farmer_name";
      const { data: updated, error } = await supabase
        .from("whatsapp_farmer_onboardings")
        .update({
          language: preferredLanguage,
          step,
          draft: mergedDraft,
          updated_at: new Date().toISOString(),
        })
        .eq("id", row.id)
        .eq("status", "active")
        .select("*")
        .single();
      if (error) throw error;
      return successResponse(
        { onboardingId: updated.id, ...onboardingResponse(updated) },
        200,
        "whatsapp_onboarding_saved",
      );
    }

    if (action === "farm_setup_save") {
      const row = await ensureFarmSetup(supabase, phone, preferredLanguage);
      if (text(row.status) !== "active")
        throw new HttpError("This farm setup is no longer active.", 409);
      const mergedDraft = mergeOnboardingDraft(row.draft, body.draft);
      const step = text(body.step) || text(row.step) || "farm_name";
      const { data: updated, error } = await supabase
        .from("whatsapp_farmer_onboardings")
        .update({
          language: preferredLanguage,
          step,
          draft: mergedDraft,
          updated_at: new Date().toISOString(),
        })
        .eq("id", row.id)
        .eq("flow_type", "existing_farmer_farm")
        .eq("status", "active")
        .select("*")
        .single();
      if (error) throw error;
      return successResponse(
        { onboardingId: updated.id, ...onboardingResponse(updated) },
        200,
        "whatsapp_farm_setup_saved",
      );
    }

    if (action === "onboarding_state") {
      const row = await activeOnboarding(supabase, phone, "new_farmer");
      return successResponse(
        onboardingResponse(row),
        200,
        "whatsapp_onboarding_loaded",
      );
    }

    if (action === "farm_setup_state") {
      const row = await activeOnboarding(
        supabase,
        phone,
        "existing_farmer_farm",
      );
      return successResponse(
        onboardingResponse(row),
        200,
        "whatsapp_farm_setup_loaded",
      );
    }

    if (action === "onboarding_map_link") {
      const row = await ensureOnboarding(supabase, phone, preferredLanguage);
      const token =
        crypto.randomUUID().replaceAll("-", "") +
        crypto.randomUUID().replaceAll("-", "");
      const tokenHash = await hashToken(token);
      const { data: updated, error } = await supabase
        .from("whatsapp_farmer_onboardings")
        .update({
          token_hash: tokenHash,
          step: "boundary",
          language: preferredLanguage,
          expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", row.id)
        .eq("status", "active")
        .select("*")
        .single();
      if (error) throw error;
      const appUrl = configuredAppUrl(true)!;
      return successResponse(
        {
          url: boundaryMapUrl(appUrl, token, preferredLanguage),
          onboardingId: updated.id,
        },
        200,
        "whatsapp_onboarding_map_link",
      );
    }

    if (action === "farm_setup_map_link") {
      const row = await ensureFarmSetup(supabase, phone, preferredLanguage);
      const token =
        crypto.randomUUID().replaceAll("-", "") +
        crypto.randomUUID().replaceAll("-", "");
      const tokenHash = await hashToken(token);
      const { data: updated, error } = await supabase
        .from("whatsapp_farmer_onboardings")
        .update({
          token_hash: tokenHash,
          step: "boundary",
          language: preferredLanguage,
          expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", row.id)
        .eq("flow_type", "existing_farmer_farm")
        .eq("status", "active")
        .select("*")
        .single();
      if (error) throw error;
      const appUrl = configuredAppUrl(true)!;
      return successResponse(
        {
          url: boundaryMapUrl(appUrl, token, preferredLanguage),
          onboardingId: updated.id,
        },
        200,
        "whatsapp_farm_setup_map_link",
      );
    }

    if (action === "onboarding_complete") {
      const row = await supabase
        .from("whatsapp_farmer_onboardings")
        .select("*")
        .eq("id", text(body.onboardingId))
        .eq("whatsapp_phone", phone)
        .maybeSingle();
      if (row.error) throw row.error;
      if (!row.data)
        throw new HttpError("Farmer onboarding was not found.", 404);
      const completed = await completeOnboarding(
        supabase,
        phone,
        row.data as Row,
      );
      const identity = await farmerIdentity(supabase, phone, preferredLanguage);
      if (!identity)
        throw new HttpError(
          "Farmer was created but could not be verified.",
          500,
        );
      await supabase.from("whatsapp_identities").upsert(
        {
          whatsapp_phone: phone,
          user_id: identity.user_id,
          role: "farmer",
          farmer_id: identity.farmer_id,
          language: preferredLanguage,
          last_seen_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        },
        { onConflict: "whatsapp_phone,role" },
      );
      return successResponse(
        {
          ...completed,
          verified: true,
          role: "farmer",
        },
        200,
        "whatsapp_onboarding_completed",
      );
    }

    if (action === "farm_setup_complete") {
      const { data: row, error: lookupError } = await supabase
        .from("whatsapp_farmer_onboardings")
        .select("*")
        .eq("id", text(body.onboardingId))
        .eq("whatsapp_phone", phone)
        .eq("flow_type", "existing_farmer_farm")
        .maybeSingle();
      if (lookupError) throw lookupError;
      if (!row) throw new HttpError("Farm setup was not found.", 404);
      const completed = await completeExistingFarmSetup(
        supabase,
        phone,
        row as Row,
        preferredLanguage,
      );
      const identity = await requireFarmer(supabase, phone, preferredLanguage);
      await saveSession(
        supabase,
        phone,
        {
          language: preferredLanguage,
          role: "farmer",
          verified: true,
          selectedFarmId: completed.farmId,
          flow: "",
          draft: {},
        },
        identity,
      );
      return successResponse(
        {
          ...completed,
          selectedFarmId: completed.farmId,
          synced: true,
          verified: true,
          role: "farmer",
        },
        200,
        "whatsapp_farm_setup_completed",
      );
    }

    if (action === "onboarding_cancel") {
      const { error } = await supabase
        .from("whatsapp_farmer_onboardings")
        .update({ status: "cancelled", updated_at: new Date().toISOString() })
        .eq("whatsapp_phone", phone)
        .eq("flow_type", "new_farmer")
        .eq("status", "active");
      if (error) throw error;
      return successResponse(
        { cancelled: true },
        200,
        "whatsapp_onboarding_cancelled",
      );
    }

    if (action === "farm_setup_cancel") {
      const { error } = await supabase
        .from("whatsapp_farmer_onboardings")
        .update({ status: "cancelled", updated_at: new Date().toISOString() })
        .eq("whatsapp_phone", phone)
        .eq("flow_type", "existing_farmer_farm")
        .eq("status", "active");
      if (error) throw error;
      return successResponse(
        { cancelled: true },
        200,
        "whatsapp_farm_setup_cancelled",
      );
    }

    if (action === "request_otp" || action === "verify_otp") {
      const identity = await farmerIdentity(supabase, phone, preferredLanguage);
      if (!identity)
        return errorResponse(
          "This WhatsApp number is not registered as an active farmer number.",
          403,
        );
      await saveSession(supabase, phone, body, identity);
      return successResponse(
        { verified: true, role: "farmer", farmerId: identity.farmer_id },
        200,
        "whatsapp_farmer_verified",
      );
    }

    if (action === "fpc_request_otp") {
      const email = text(body.email).toLowerCase();
      const { data, error } = await supabase
        .from("fpc_memberships")
        .select("user_id,fpc_id,email,status,role")
        .eq("email", email)
        .eq("status", "active")
        .maybeSingle();
      if (error) throw error;
      if (!data?.user_id)
        return errorResponse(
          "No active FPC account was found for this email.",
          404,
        );
      // Delivery is delegated to the configured mail provider so credentials never reach WhatsApp.
      const sender = Deno.env.get("WHATSAPP_FPC_OTP_SENDER_URL")?.trim();
      if (!sender)
        return errorResponse("FPC email verification is not configured.", 503);
      const code = String(Math.floor(100000 + Math.random() * 900000));
      await supabase.from("whatsapp_chat_sessions").upsert({
        whatsapp_phone: phone,
        language: preferredLanguage,
        role: "fpc",
        flow: "fpc_email_otp",
        draft: {
          email,
          code_hash: await hash(code),
          user_id: data.user_id,
          fpc_id: data.fpc_id,
        },
        updated_at: new Date().toISOString(),
      });
      const sent = await fetch(sender, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, code }),
      });
      if (!sent.ok)
        throw new HttpError("Could not send the FPC verification email.", 502);
      return successResponse({ sent: true }, 200, "whatsapp_fpc_otp_sent");
    }

    if (action === "fpc_verify_otp") {
      const { data: session, error } = await supabase
        .from("whatsapp_chat_sessions")
        .select("draft,language")
        .eq("whatsapp_phone", phone)
        .eq("flow", "fpc_email_otp")
        .maybeSingle();
      if (error) throw error;
      const draft = object(session?.draft);
      if (!session || text(draft.code_hash) !== (await hash(text(body.otp)))) {
        return errorResponse("The FPC verification code is not valid.", 403);
      }
      const identity = {
        whatsapp_phone: phone,
        user_id: text(draft.user_id),
        role: "fpc",
        farmer_id: null,
        fpc_id: text(draft.fpc_id),
        email: text(draft.email),
        language: language(session.language),
        last_seen_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
      const { error: upsertError } = await supabase
        .from("whatsapp_identities")
        .upsert(identity, { onConflict: "whatsapp_phone,role" });
      if (upsertError) throw upsertError;
      await saveSession(
        supabase,
        phone,
        { language: identity.language, flow: "", draft: {} },
        identity as unknown as Identity,
      );
      return successResponse(
        { verified: true, role: "fpc", fpcId: identity.fpc_id },
        200,
        "whatsapp_fpc_verified",
      );
    }

    if (action === "fpc_signup_link_create") {
      const token = crypto.randomUUID().replaceAll("-", "") +
        crypto.randomUUID().replaceAll("-", "");
      const tokenHash = await hashToken(token);
      await supabase.from("whatsapp_role_signup_links")
        .update({ status: "cancelled" })
        .eq("whatsapp_phone", phone)
        .eq("role", "fpc")
        .eq("status", "active");
      const { data: link, error } = await supabase
        .from("whatsapp_role_signup_links")
        .insert({
          token_hash: tokenHash,
          whatsapp_phone: phone,
          role: "fpc",
          language: preferredLanguage,
        })
        .select("id,expires_at")
        .single();
      if (error) throw error;
      const appUrl = configuredAppUrl(true)!;
      return successResponse({
        url: fpcSignupUrl(appUrl, token, preferredLanguage),
        expiresAt: link.expires_at,
      }, 200, "whatsapp_fpc_signup_link_created");
    }

    if (action === "farm_list") {
      const identity = await requireFarmer(supabase, phone, preferredLanguage);
      return successResponse(
        { farms: await farmsFor(supabase, identity) },
        200,
        "whatsapp_farms_listed",
      );
    }

    if (action === "service_link_create") {
      const service = text(body.service).toLowerCase();
      if (!webServices.has(service))
        return errorResponse("This service does not require a web link.", 400);
      const identity = await requireFarmer(supabase, phone, preferredLanguage);
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      await supabase
        .from("whatsapp_service_links")
        .update({ status: "cancelled", updated_at: new Date().toISOString() })
        .eq("whatsapp_phone", phone)
        .eq("service", service)
        .eq("status", "active");
      const token =
        crypto.randomUUID().replaceAll("-", "") +
        crypto.randomUUID().replaceAll("-", "");
      const tokenHash = await hashToken(token);
      const { data: link, error } = await supabase
        .from("whatsapp_service_links")
        .insert({
          token_hash: tokenHash,
          whatsapp_phone: phone,
          user_id: identity.user_id,
          farmer_id: identity.farmer_id,
          farm_id: farm.id,
          service,
          language: preferredLanguage,
        })
        .select("id,service,language,expires_at")
        .single();
      if (error) throw error;
      const appUrl = configuredAppUrl(true)!;
      return successResponse(
        {
          linkId: link.id,
          service,
          url: serviceLinkUrl(appUrl, token, preferredLanguage),
          expiresAt: link.expires_at,
          farm: { id: farm.id, name: farm.name },
        },
        200,
        "whatsapp_service_link_created",
      );
    }

    if (action === "service_result_load") {
      const identity = await requireFarmer(supabase, phone, preferredLanguage);
      const { data: link, error } = await supabase
        .from("whatsapp_service_links")
        .select("id,service,language,result,completed_at,farm_id")
        .eq("whatsapp_phone", phone)
        .eq("user_id", identity.user_id)
        .eq("status", "completed")
        .is("consumed_at", null)
        .order("completed_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      if (!link)
        return successResponse(
          { found: false },
          200,
          "whatsapp_service_result_empty",
        );
      const { error: consumeError } = await supabase
        .from("whatsapp_service_links")
        .update({
          consumed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", link.id)
        .eq("status", "completed")
        .is("consumed_at", null);
      if (consumeError) throw consumeError;
      const farm = await supabase
        .from("farms")
        .select("id,name,location_label,crop,variety")
        .eq("id", link.farm_id)
        .eq("user_id", identity.user_id)
        .maybeSingle();
      if (farm.error) throw farm.error;
      const profile = await supabase
        .from("farmer_phone_profiles")
        .select("farmer_id,farmer_name,default_location")
        .eq("user_id", identity.user_id)
        .eq("farmer_id", identity.farmer_id)
        .maybeSingle();
      if (profile.error) throw profile.error;
      return successResponse(
        {
          found: true,
          service: link.service,
          language: language(link.language),
          result: object(link.result),
          farmer: {
            id: identity.farmer_id,
            name: text(profile.data?.farmer_name) || "Farmer",
            location: text(profile.data?.default_location),
          },
          farm: farm.data ?? null,
          completedAt: link.completed_at,
        },
        200,
        "whatsapp_service_result_loaded",
      );
    }

    if (action === "market_rates") {
      const query = text(body.query);
      const terms = marketQueryTerms(query);
      let officialRequest = supabase
        .from("apmc_market_rate_history")
        .select(
          "commodity,market_name:market,modal_price,min_price,max_price,arrival_date,state,district,variety,grade",
        )
        .order("arrival_date", { ascending: false })
        .order("market", { ascending: true })
        .limit(10);
      officialRequest = addMarketQueryFilters(officialRequest, terms, true);
      const { data: officialRates, error: officialError } =
        await officialRequest;
      if (officialError) throw officialError;
      if ((officialRates ?? []).length > 0) {
        return successResponse(
          {
            rates: officialRates ?? [],
            source: "Government of India AGMARKNET via data.gov.in",
            unit: "INR/quintal",
            requestedQuery: query,
          },
          200,
          "whatsapp_official_market_rates",
        );
      }

      if (terms.length > 1) {
        let relaxedRequest = supabase
          .from("apmc_market_rate_history")
          .select(
            "commodity,market_name:market,modal_price,min_price,max_price,arrival_date,state,district,variety,grade",
          )
          .order("arrival_date", { ascending: false })
          .order("market", { ascending: true })
          .limit(10);
        relaxedRequest = addMarketQueryFilters(relaxedRequest, terms, false);
        const { data: relaxedRates, error: relaxedError } =
          await relaxedRequest;
        if (relaxedError) throw relaxedError;
        if ((relaxedRates ?? []).length > 0) {
          return successResponse(
            {
              rates: relaxedRates,
              source: "Government of India AGMARKNET via data.gov.in",
              unit: "INR/quintal",
              requestedQuery: query,
              fallback: true,
            },
            200,
            "whatsapp_official_market_rates_relaxed",
          );
        }
      }

      let request = supabase
        .from("apmc_market_rates")
        .select(
          "commodity:crop,market_name,modal_price:modal_rate,min_price:min_rate,max_price:max_rate,arrival_date:rate_date,demand,trend,note",
        )
        .eq("active", true)
        .order("rate_date", { ascending: false })
        .limit(10);
      if (terms.length > 0) request = request.ilike("crop", `%${terms[0]}%`);
      const { data, error } = await request;
      if (error) throw error;
      return successResponse(
        {
          rates: data ?? [],
          source: "GrainRight curated rates",
          unit: "INR/quintal",
          requestedQuery: query,
        },
        200,
        "whatsapp_market_rates",
      );
    }

    const existingIdentity = await activeIdentity(supabase, phone);
    if (existingIdentity?.role === "fpc") {
      const { data: membership, error: membershipError } = await supabase
        .from("fpc_memberships")
        .select("fpc_id,role,status,display_name,email")
        .eq("user_id", existingIdentity.user_id)
        .eq("fpc_id", existingIdentity.fpc_id)
        .eq("status", "active")
        .maybeSingle();
      if (membershipError) throw membershipError;
      if (!membership)
        return errorResponse("Your FPC membership is no longer active.", 403);
      if (action === "fpc_dashboard") {
        const { data: fpc, error } = await supabase
          .from("fpcs")
          .select("id,name,status")
          .eq("id", existingIdentity.fpc_id)
          .maybeSingle();
        if (error) throw error;
        const { count, error: countError } = await supabase
          .from("fpc_memberships")
          .select("id", { count: "exact", head: true })
          .eq("fpc_id", existingIdentity.fpc_id)
          .eq("status", "active");
        if (countError) throw countError;
        return successResponse(
          { fpc, membership, activeMembers: count ?? 0 },
          200,
          "whatsapp_fpc_dashboard",
        );
      }
      if (action === "fpc_members") {
        const { data, error } = await supabase
          .from("fpc_memberships")
          .select("id,display_name,email,phone,role,status,created_at")
          .eq("fpc_id", existingIdentity.fpc_id)
          .order("created_at", { ascending: false })
          .limit(50);
        if (error) throw error;
        return successResponse(
          { memberships: data ?? [] },
          200,
          "whatsapp_fpc_members",
        );
      }
      if (action === "fpc_alerts") {
        const { data, error } = await supabase
          .from("fpc_notifications")
          .select("id,title,message,type,created_at,read_at")
          .eq("fpc_id", existingIdentity.fpc_id)
          .order("created_at", { ascending: false })
          .limit(20);
        if (error) throw error;
        return successResponse(
          { alerts: data ?? [] },
          200,
          "whatsapp_fpc_alerts",
        );
      }
      return errorResponse(
        "This FPC WhatsApp service is not available yet.",
        400,
      );
    }

    const identity = await requireFarmer(supabase, phone, preferredLanguage);
    await supabase
      .from("whatsapp_identities")
      .update({
        last_seen_at: new Date().toISOString(),
        language: preferredLanguage,
      })
      .eq("whatsapp_phone", phone)
      .eq("role", "farmer");

    if (action === "farm_alerts") {
      const { data, error } = await supabase
        .from("farmer_notifications")
        .select("id,title,message,type,created_at,farm_id,read_at,action_route")
        .eq("farmer_id", identity.farmer_id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return successResponse(
        { alerts: data ?? [] },
        200,
        "whatsapp_farm_alerts",
      );
    }

    if (action === "farm_summary") {
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      const [snapshots, status] = await Promise.all([
        supabase
          .from("farm_data_snapshots")
          .select(
            "created_at,snapshot_date,crop,variety,growth_stage,current_status,weather_risk,disease_risk,water_stress_label,crop_weather_label,snapshot",
          )
          .eq("farm_id", farm.id)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle(),
        supabase
          .from("farm_status_updates")
          .select("status_text,growth_stage,created_at")
          .eq("farm_id", farm.id)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle(),
      ]);
      if (snapshots.error) throw snapshots.error;
      if (status.error) throw status.error;
      return successResponse(
        {
          farm,
          snapshot: snapshots.data ?? null,
          latestStatus: status.data ?? null,
        },
        200,
        "whatsapp_farm_summary",
      );
    }

    if (action === "status_update") {
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      const statusText = text(body.statusText);
      if (!statusText) return errorResponse("Status text is required.", 400);
      const response = await invokeInternal("farm-status-update", {
        phone,
        farmerId: identity.farmer_id,
        farmId: farm.id,
        farmName: farm.name,
        crop: farm.crop,
        variety: farm.variety,
        stage:
          text(body.stage) || text(farm.current_status_stage) || "field_update",
        statusText,
        language: preferredLanguage,
        source: "whatsapp_chat",
        whatsapp_user_id: identity.user_id,
      });
      return successResponse(response as Row, 200, "whatsapp_status_updated");
    }

    if (action === "ai_chat") {
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      const question = text(body.question);
      if (!question) return errorResponse("A question is required.", 400);
      const response = await invokeInternal("farm-assistant-chat", {
        phone,
        farmerId: identity.farmer_id,
        farmId: farm.id,
        question,
        language: preferredLanguage,
        source: "ai_chat",
        whatsapp_user_id: identity.user_id,
      });
      return successResponse(response as Row, 200, "whatsapp_ai_chat");
    }

    if (action === "grading_media") {
      return successResponse(
        await importWhatsAppMedia(supabase, identity, body),
        201,
        "whatsapp_grading_media_saved",
      );
    }

    if (action === "grading_submit") {
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      const response = await invokeInternal("grain-grade", {
        farmer_phone: phone,
        farmer_id: identity.farmer_id,
        farm_id: farm.id,
        actor_role: "farmer",
        grain_image_path: text(body.grainImagePath),
        moisture_image_path: text(body.moistureImagePath) || null,
        manual_moisture_percent: body.manualMoisturePercent ?? null,
        crop_type: text(body.cropType) || text(farm.crop) || "finger_millets",
        crop_variety: text(body.cropVariety ?? body.crop_variety) ||
          text(farm.variety) || "local",
        source: "whatsapp",
        whatsapp_user_id: identity.user_id,
      });
      return successResponse(response as Row, 200, "whatsapp_grading_complete");
    }

    if (action === "daily_task_photo") {
      const taskId = text(body.taskId ?? body.task_id);
      const captureIndex = Number(body.captureIndex ?? body.capture_index);
      const encoded = text(body.mediaBase64 ?? body.media_base64).replace(
        /^data:[^;]+;base64,/,
        "",
      );
      const mimeType = text(body.mediaMimeType ?? body.media_mime_type) ||
        "image/jpeg";
      if (!taskId || !Number.isInteger(captureIndex) || captureIndex < 1 || captureIndex > 3) {
        throw new HttpError("A valid daily task photo number is required.", 400);
      }
      if (!encoded || !mimeType.startsWith("image/")) {
        throw new HttpError("A valid farm photo is required.", 400);
      }
      const task = await supabase
        .from("farmer_daily_tasks")
        .select("id,user_id,farm_id,status")
        .eq("id", taskId)
        .eq("user_id", identity.user_id)
        .maybeSingle();
      if (task.error) throw task.error;
      if (!task.data || text(task.data.farm_id) !== text(body.farmId ?? body.farm_id)) {
        throw new HttpError("This daily task is not linked to the selected farm.", 403);
      }
      let bytes: Uint8Array;
      try {
        bytes = Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0));
      } catch {
        throw new HttpError("The farm photo payload is invalid.", 400);
      }
      if (bytes.byteLength > 12 * 1024 * 1024) {
        throw new HttpError("Each farm photo must be under 12 MB.", 413);
      }
      const extension = mimeType.includes("png") ? "png" : "jpg";
      const path = `${identity.user_id}/whatsapp/daily-tasks/${taskId}/${captureIndex}-${crypto.randomUUID()}.${extension}`;
      const upload = await supabase.storage.from("farm-stage-evidence").upload(
        path,
        bytes,
        { contentType: mimeType, upsert: false },
      );
      if (upload.error) throw upload.error;
      const evidence = await supabase.from("farmer_daily_task_evidence").upsert({
        task_id: taskId,
        user_id: identity.user_id,
        farmer_id: identity.farmer_id,
        farm_id: task.data.farm_id,
        capture_index: captureIndex,
        photo_path: path,
      }, { onConflict: "task_id,capture_index" }).select("id,capture_index,photo_path").single();
      if (evidence.error) throw evidence.error;
      return successResponse({ taskId, captureIndex, path, evidence: evidence.data }, 201, "whatsapp_daily_task_photo_saved");
    }

    if (action === "daily_task_complete") {
      const taskId = text(body.taskId ?? body.task_id);
      if (!taskId) throw new HttpError("Daily task is required.", 400);
      const evidence = await supabase.from("farmer_daily_task_evidence")
        .select("id,capture_index,photo_path")
        .eq("task_id", taskId)
        .eq("user_id", identity.user_id)
        .order("capture_index", { ascending: true });
      if (evidence.error) throw evidence.error;
      if ((evidence.data ?? []).length < 3) {
        throw new HttpError("Three farm-area photos are required before completing this task.", 400);
      }
      const task = await supabase.from("farmer_daily_tasks")
        .select("*")
        .eq("id", taskId)
        .eq("user_id", identity.user_id)
        .eq("farm_id", text(body.farmId ?? body.farm_id))
        .maybeSingle();
      if (task.error) throw task.error;
      if (!task.data) throw new HttpError("Daily task was not found.", 404);
      const metadata = object(task.data.metadata);
      const updated = await supabase.from("farmer_daily_tasks")
        .update({
          status: "done",
          completed_at: new Date().toISOString(),
          metadata: { ...metadata, whatsapp_photo_evidence_count: 3 },
        })
        .eq("id", taskId)
        .eq("user_id", identity.user_id)
        .select("*")
        .single();
      if (updated.error) throw updated.error;
      return successResponse({ task: updated.data, evidence: evidence.data }, 200, "whatsapp_daily_task_completed");
    }

    if (action === "farm_setup_link") {
      const setup = await ensureFarmSetup(supabase, phone, preferredLanguage);
      return successResponse(
        {
          onboardingId: setup.id,
          step: setup.step,
          instruction:
            "Farm details must be collected in WhatsApp before the boundary-only link is issued.",
        },
        200,
        "whatsapp_farm_setup_started",
      );
    }

    if (action === "daily_tasks") {
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      const { data, error } = await supabase
        .from("farmer_daily_tasks")
        .select(
          "id,title:title_key,description:description_key,priority,status,task_date,due_at,action_route",
        )
        .eq("user_id", identity.user_id)
        .eq("farm_id", farm.id)
        .order("task_date", { ascending: false })
        .order("due_at", { ascending: true, nullsFirst: false })
        .limit(20);
      if (error) throw error;
      return successResponse(
        { tasks: data ?? [] },
        200,
        "whatsapp_daily_tasks",
      );
    }

    if (action === "inventory") {
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      const { data, error } = await supabase
        .from("farmer_inventory_items")
        .select(
          "inventory_id,product_name,crop,variety,quantity,unit,grade,moisture_percent,harvested_at",
        )
        .eq("user_id", identity.user_id)
        .eq("farm_id", farm.id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return successResponse(
        { farm, items: data ?? [] },
        200,
        "whatsapp_inventory_listed",
      );
    }

    if (action === "economics") {
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      const { data, error } = await supabase
        .from("farm_economic_plans")
        .select(
          "plan_type,crop,variety,growth_stage,area_acres,ai_summary,created_at",
        )
        .eq("farm_id", farm.id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return successResponse(
        { farm, plans: data ?? [] },
        200,
        "whatsapp_economics_listed",
      );
    }

    if (action === "harvest") {
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      const { data, error } = await supabase
        .from("farm_harvest_zone_plans")
        .select(
          "id,growth_stage,readiness,confidence,coverage_percent,status,summary,generated_at",
        )
        .eq("user_id", identity.user_id)
        .eq("farm_id", farm.id)
        .order("generated_at", { ascending: false })
        .limit(5);
      if (error) throw error;
      return successResponse(
        { farm, plans: data ?? [] },
        200,
        "whatsapp_harvest_listed",
      );
    }

    if (action === "marketplace") {
      const farm = await resolveFarm(
        supabase,
        identity,
        body.farm ?? body.farmId,
      );
      const { data, error } = await supabase
        .from("marketplace_listings")
        .select(
          "id,product_name,crop,quantity,unit,grade,asking_price_per_unit,status,created_at",
        )
        .eq("farmer_user_id", identity.user_id)
        .eq("farm_id", farm.id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return successResponse(
        { farm, listings: data ?? [] },
        200,
        "whatsapp_marketplace_listed",
      );
    }

    return errorResponse("Unsupported WhatsApp action.", 400);
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    if (error instanceof HttpError && Object.keys(error.details).length > 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: error.message,
          ...error.details,
        }),
        {
          status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    return errorResponse(
      error instanceof Error ? error.message : "WhatsApp gateway failed",
      status,
      error,
    );
  }
});

async function hash(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
