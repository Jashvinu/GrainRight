import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";

type Row = Record<string, unknown>;

function object(raw: unknown): Row {
  return raw != null && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Row
    : {};
}

function text(raw: unknown): string {
  return String(raw ?? "").trim();
}

function whatsappReturnUrl(): string | null {
  const phone = text(Deno.env.get("WHATSAPP_BOT_PHONE")).replace(/\D/g, "");
  if (!/^\d{10,15}$/.test(phone)) return null;
  const url = new URL(`https://wa.me/${phone}`);
  url.searchParams.set("text", "CONTINUE");
  return url.toString();
}

function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Missing Supabase service credentials");
  return createClient(url, key);
}

async function hashToken(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function validateGeometry(raw: unknown): Row {
  const geometry = object(raw);
  const coordinates = geometry.coordinates;
  const ring = Array.isArray(coordinates) && Array.isArray(coordinates[0])
    ? coordinates[0]
    : [];
  if (text(geometry.type).toLowerCase() !== "polygon" || ring.length < 4) {
    throw new Error("A farm boundary with at least three corners is required.");
  }
  const valid = ring.every((point) => Array.isArray(point) && point.length >= 2 &&
    Number.isFinite(Number(point[0])) && Number.isFinite(Number(point[1])) &&
    Math.abs(Number(point[0])) <= 180 && Math.abs(Number(point[1])) <= 90);
  if (!valid) throw new Error("The farm boundary coordinates are invalid.");
  const first = ring[0] as unknown[];
  const last = ring[ring.length - 1] as unknown[];
  const closed = Array.isArray(first) && Array.isArray(last) &&
    Number(first[0]) === Number(last[0]) && Number(first[1]) === Number(last[1]);
  if (!closed) throw new Error("Close the farm boundary before saving it.");
  const openRing = ring.slice(0, -1).map((point) => [
    Number(point[0]),
    Number(point[1]),
  ] as [number, number]);
  if (new Set(openRing.map((point) => `${point[0]}:${point[1]}`)).size < 3) {
    throw new Error("A farm boundary needs at least three different corners.");
  }
  if (hasSelfIntersection(openRing)) {
    throw new Error("The farm boundary cannot cross itself.");
  }
  return {
    type: "Polygon",
    coordinates: [[...openRing, openRing[0]]],
  };
}

function orientation(a: [number, number], b: [number, number], c: [number, number]): number {
  return (b[0] - a[0]) * (c[1] - a[1]) -
    (b[1] - a[1]) * (c[0] - a[0]);
}

function onSegment(a: [number, number], b: [number, number], p: [number, number]): boolean {
  const epsilon = 1e-12;
  return p[0] >= Math.min(a[0], b[0]) - epsilon &&
    p[0] <= Math.max(a[0], b[0]) + epsilon &&
    p[1] >= Math.min(a[1], b[1]) - epsilon &&
    p[1] <= Math.max(a[1], b[1]) + epsilon;
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
  if ((abC > epsilon && abD < -epsilon || abC < -epsilon && abD > epsilon) &&
    (cdA > epsilon && cdB < -epsilon || cdA < -epsilon && cdB > epsilon)) {
    return true;
  }
  return Math.abs(abC) <= epsilon && onSegment(a, b, c) ||
    Math.abs(abD) <= epsilon && onSegment(a, b, d) ||
    Math.abs(cdA) <= epsilon && onSegment(c, d, a) ||
    Math.abs(cdB) <= epsilon && onSegment(c, d, b);
}

function hasSelfIntersection(ring: [number, number][]): boolean {
  for (let first = 0; first < ring.length; first += 1) {
    const firstEnd = (first + 1) % ring.length;
    for (let second = first + 1; second < ring.length; second += 1) {
      const secondEnd = (second + 1) % ring.length;
      if (first === second || firstEnd === second || secondEnd === first) continue;
      if (segmentsIntersect(ring[first], ring[firstEnd], ring[second], ring[secondEnd])) return true;
    }
  }
  return false;
}

function boundsFor(geometry: Row): Row {
  const ring = (geometry.coordinates as unknown[][][])[0] ?? [];
  const longitudes = ring.map((point) => Number(point[0]));
  const latitudes = ring.map((point) => Number(point[1]));
  return {
    min_latitude: Math.min(...latitudes),
    max_latitude: Math.max(...latitudes),
    min_longitude: Math.min(...longitudes),
    max_longitude: Math.max(...longitudes),
  };
}

function centroidFor(geometry: Row): { latitude: number; longitude: number } {
  const ring = (geometry.coordinates as unknown[][][])[0] ?? [];
  const openRing = ring.length > 1 &&
      Number((ring[0] ?? [])[0]) === Number((ring[ring.length - 1] ?? [])[0]) &&
      Number((ring[0] ?? [])[1]) === Number((ring[ring.length - 1] ?? [])[1])
    ? ring.slice(0, -1)
    : ring;
  const longitude = openRing.reduce((sum, point) => sum + Number(point[0]), 0) / openRing.length;
  const latitude = openRing.reduce((sum, point) => sum + Number(point[1]), 0) / openRing.length;
  return { latitude, longitude };
}

type GeocodeResult = {
  label: string | null;
  provider: string;
  status: "saved" | "unavailable" | "failed";
};

function componentValue(components: Row[], types: string[]): string {
  for (const type of types) {
    const match = components.find((item) =>
      Array.isArray(item.types) && item.types.includes(type)
    );
    const value = text(match?.long_name ?? match?.short_name);
    if (value) return value;
  }
  return "";
}

function uniqueParts(parts: string[]): string[] {
  const seen = new Set<string>();
  return parts.filter((part) => {
    const key = part.toLowerCase();
    if (!part || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

async function reverseGeocode(
  latitude: number,
  longitude: number,
  preferredLanguage: string,
): Promise<GeocodeResult> {
  const provider = (Deno.env.get("WHATSAPP_GEOCODER_PROVIDER")?.trim().toLowerCase() || "google");
  let url: URL;
  let requestHeaders: HeadersInit = { accept: "application/json" };

  if (provider === "google") {
    const key = Deno.env.get("GOOGLE_MAPS_API_KEY")?.trim() ?? "";
    if (!key) return { label: null, provider, status: "unavailable" };
    url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
    url.searchParams.set("latlng", `${latitude},${longitude}`);
    url.searchParams.set("language", preferredLanguage);
    url.searchParams.set("key", key);
  } else if (provider === "maptiler") {
    const key = (Deno.env.get("WHATSAPP_GEOCODER_API_KEY") || Deno.env.get("MAPTILER_API_KEY"))?.trim() ?? "";
    if (!key) return { label: null, provider, status: "unavailable" };
    url = new URL(`https://api.maptiler.com/geocoding/${longitude},${latitude}.json`);
    url.searchParams.set("key", key);
    url.searchParams.set("language", preferredLanguage);
    url.searchParams.set("country", "in");
  } else if (provider === "custom") {
    const endpoint = Deno.env.get("WHATSAPP_GEOCODER_URL")?.trim() ?? "";
    if (!endpoint) return { label: null, provider, status: "unavailable" };
    url = new URL(endpoint);
    url.searchParams.set("latitude", String(latitude));
    url.searchParams.set("longitude", String(longitude));
    url.searchParams.set("language", preferredLanguage);
    const key = Deno.env.get("WHATSAPP_GEOCODER_API_KEY")?.trim() ?? "";
    if (key) requestHeaders = { ...requestHeaders, "x-api-key": key };
  } else {
    return { label: null, provider, status: "unavailable" };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);
  try {
    const response = await fetch(url, { headers: requestHeaders, signal: controller.signal });
    const data = object(await response.json().catch(() => ({})));
    if (!response.ok) return { label: null, provider, status: "failed" };

    if (provider === "google") {
      const result = Array.isArray(data.results) ? object(data.results[0]) : {};
      const components = Array.isArray(result.address_components)
        ? result.address_components.map(object)
        : [];
      const parts = uniqueParts([
        componentValue(components, ["locality", "postal_town", "sublocality_level_1", "administrative_area_level_3"]),
        componentValue(components, ["administrative_area_level_3"]),
        componentValue(components, ["administrative_area_level_2"]),
        componentValue(components, ["administrative_area_level_1"]),
      ]);
      const label = parts.join(", ") || text(result.formatted_address) || null;
      return { label, provider, status: label ? "saved" : "failed" };
    }

    if (provider === "maptiler") {
      const features = Array.isArray(data.features) ? data.features : [];
      const feature = object(features[0]);
      const context = Array.isArray(feature.context) ? feature.context.map(object) : [];
      const label = uniqueParts([
        text(feature.text),
        text(feature.properties && object(feature.properties).address),
        ...context.map((item) => text(item.text)),
      ]).join(", ") || null;
      return { label, provider, status: label ? "saved" : "failed" };
    }

    const label = text(data.label ?? data.display_name ?? data.formatted_address) || null;
    return { label, provider, status: label ? "saved" : "failed" };
  } catch (_) {
    return { label: null, provider, status: "failed" };
  } finally {
    clearTimeout(timeout);
  }
}

function rows(raw: unknown): Row[] {
  return Array.isArray(raw)
    ? raw.filter((value): value is Row =>
      value !== null && typeof value === "object" && !Array.isArray(value)
    )
    : [];
}

function numeric(raw: unknown): number | null {
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw === "string" && raw.trim()) {
    const value = Number(raw);
    return Number.isFinite(value) ? value : null;
  }
  return null;
}

function rowNumber(row: Row, keys: string[]): number | null {
  for (const key of keys) {
    const value = numeric(row[key]);
    if (value !== null) return value;
  }
  return null;
}

function scanDate(row: Row): string {
  return text(row.scan_date ?? row.created_at ?? row.updated_at);
}

function latestScanDate(data: Row[]): string {
  return data.reduce((latest, row) => {
    const value = scanDate(row);
    return value > latest ? value : latest;
  }, "");
}

function sameScanRows(data: Row[], scan: string): Row[] {
  if (!scan) return data;
  const latest = data.filter((row) => scanDate(row) === scan);
  return latest.length > 0 ? latest : data;
}

function averageValue(data: Row[], keys: string[]): number | null {
  const values = data
    .map((row) => rowNumber(row, keys))
    .filter((value): value is number => value !== null);
  if (values.length === 0) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function maximumValue(data: Row[], keys: string[]): number | null {
  let maximum: number | null = null;
  for (const row of data) {
    const value = rowNumber(row, keys);
    if (value !== null && (maximum === null || value > maximum)) maximum = value;
  }
  return maximum;
}

function diseaseScores(row: Row): Record<string, number> {
  const scores: Record<string, number> = {};
  const perDisease = row.per_disease;
  if (perDisease && typeof perDisease === "object" && !Array.isArray(perDisease)) {
    for (const [name, value] of Object.entries(perDisease as Row)) {
      const parsed = numeric(value);
      if (parsed !== null) scores[name] = parsed;
    }
  }
  const columns: Record<string, string> = {
    rice_blast_risk: "rice_blast",
    sheath_blight_risk: "sheath_blight",
    blb_risk: "bacterial_leaf_blight",
    downy_mildew_risk: "downy_mildew",
    leaf_spot_risk: "leaf_spot",
    charcoal_rot_risk: "charcoal_rot",
  };
  for (const [column, name] of Object.entries(columns)) {
    const value = numeric(row[column]);
    if (value !== null) scores[name] = Math.max(scores[name] ?? 0, value);
  }
  return scores;
}

function topDiseaseRisks(data: Row[]): Record<string, number> {
  const risks: Record<string, number> = {};
  for (const row of data) {
    for (const [name, value] of Object.entries(diseaseScores(row))) {
      risks[name] = Math.max(risks[name] ?? 0, value);
    }
  }
  return risks;
}

function maxRisk(data: Row[], risks: Record<string, number>): number {
  let maximum = 0;
  for (const row of data) {
    maximum = Math.max(
      maximum,
      rowNumber(row, ["composite_risk", "max_risk_score", "risk_score"]) ?? 0,
    );
  }
  for (const value of Object.values(risks)) maximum = Math.max(maximum, value);
  return maximum;
}

function metric(
  value: number | null,
  index: string,
  date: string,
  source = "disease_risk_cells",
) {
  return value === null
    ? null
    : { value, index, date, source, status: "available" };
}

function recommendationFromSnapshot(snapshot: Row): Row | null {
  const recommendation = snapshot.recommendation;
  return recommendation && typeof recommendation === "object" && !Array.isArray(recommendation)
    ? recommendation as Row
    : null;
}

async function monitoringSummary(
  supabase: ReturnType<typeof serviceClient>,
  farmId: string,
): Promise<Row | null> {
  const { data: farm, error: farmError } = await supabase
    .from("farms")
    .select(
      "id,name,geometry,bounds,area_hectares,area_acres,location_label,crop,variety,season,irrigation,soil_type,ownership_type,seed_source,harvest_intent,sowing_date,current_status,current_status_stage,current_status_updated_at",
    )
    .eq("id", farmId)
    .maybeSingle();
  if (farmError) throw farmError;
  if (!farm) return null;

  const [snapshotResult, zonesResult, cellsResult] = await Promise.all([
    supabase
      .from("farm_data_snapshots")
      .select("snapshot,collected_at,updated_at")
      .eq("farm_id", farmId)
      .order("collected_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from("disease_scout_zones")
      .select("*")
      .eq("farm_id", farmId)
      .order("scan_date", { ascending: false })
      .order("zone_rank", { ascending: true }),
    supabase
      .from("disease_risk_cells")
      .select("*")
      .eq("farm_id", farmId)
      .order("scan_date", { ascending: false })
      .order("composite_risk", { ascending: false })
      .limit(80),
  ]);
  if (snapshotResult.error) throw snapshotResult.error;
  if (zonesResult.error) throw zonesResult.error;
  if (cellsResult.error) throw cellsResult.error;

  const snapshot = object(snapshotResult.data?.snapshot);
  const zones = rows(zonesResult.data);
  const cells = rows(cellsResult.data);
  const scan = latestScanDate([...cells, ...zones]);
  const latestCells = sameScanRows(cells, scan);
  const latestZones = sameScanRows(zones, scan);
  const risks = topDiseaseRisks(latestCells);
  const recommendation = recommendationFromSnapshot(snapshot);
  const recommendationUpdatedAt = text(
    snapshotResult.data?.updated_at ?? snapshotResult.data?.collected_at,
  );
  const weatherRisk = maximumValue(latestCells, ["weather_risk"]);
  const disease = {
    scan_date: scan,
    crop: text(farm.crop),
    season: text(farm.season),
    images_analyzed: 0,
    risk_cells_count: latestCells.length,
    high_risk_cells: latestCells.filter((row) =>
      (rowNumber(row, ["composite_risk", "max_risk_score", "risk_score"]) ?? 0) >= 0.55
    ).length,
    max_risk: maxRisk(latestCells, risks),
    top_disease_risks: risks,
    scout_zones: latestZones,
    risk_cells: latestCells,
  };

  return {
    farm,
    satellite_metrics: {
      water_level: metric(averageValue(latestCells, ["moisture", "ndwi"]), "moisture", scan),
      crop_health: metric(averageValue(latestCells, ["ndvi"]), "ndvi", scan),
      canopy: metric(averageValue(latestCells, ["ndre", "gndvi", "savi"]), "canopy", scan),
      last_update: scan,
    },
    weather_context: {
      weather_data_status: weatherRisk === null ? "missing" : "available",
      weather_risk: weatherRisk,
      scan_date: scan,
      source: "disease_risk_cells",
      ...(recommendation === null ? {} : {
        recommendation,
        recommendation_updated_at: recommendationUpdatedAt,
      }),
    },
    disease,
    advice: null,
    monitoring_status: scan ? "available" : "not_available",
  };
}

async function loadOnboarding(
  supabase: ReturnType<typeof serviceClient>,
  token: string,
): Promise<Row | null> {
  const tokenHash = await hashToken(token);
  const { data, error } = await supabase
    .from("whatsapp_farmer_onboardings")
    .select("id,draft,step,expires_at,status,flow_type,language,farm_id")
    .eq("token_hash", tokenHash)
    .in("status", ["active", "completed"])
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (error) throw error;
  return data as Row | null;
}

async function loadBoundaryState(
  supabase: ReturnType<typeof serviceClient>,
  onboarding: Row,
): Promise<Row> {
  const draft = object(onboarding.draft);
  const draftFarm = object(draft.farm);
  const farmId = text(onboarding.farm_id);
  const summary = farmId ? await monitoringSummary(supabase, farmId) : null;
  return {
    onboardingId: onboarding.id,
    status: text(onboarding.status),
    step: text(onboarding.step),
    farm: summary?.farm ?? draftFarm,
    summary,
    returnToWhatsappUrl: whatsappReturnUrl(),
  };
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const body = object(await req.json());
    const token = text(body.token);
    if (token.length < 32) return errorResponse("This boundary link is invalid.", 400);
    const supabase = serviceClient();
    const action = text(body.action).toLowerCase() || "save";
    if (action === "load" || action === "refresh") {
      const onboarding = await loadOnboarding(supabase, token);
      if (!onboarding) {
        return errorResponse("This boundary link has expired or was already used.", 410);
      }
      return successResponse(
        await loadBoundaryState(supabase, onboarding),
        200,
        "whatsapp_boundary_state_loaded",
      );
    }
    if (action !== "save") return errorResponse("Unsupported boundary action.", 400);
    const geometry = validateGeometry(body.geometry ?? body.geojson);
    const tokenHash = await hashToken(token);
    const { data: onboarding, error: lookupError } = await supabase
      .from("whatsapp_farmer_onboardings")
      .select("id,draft,step,expires_at,status,flow_type,language")
      .eq("token_hash", tokenHash)
      .eq("status", "active")
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (lookupError) throw lookupError;
    if (!onboarding) return errorResponse("This boundary link has expired or was already used.", 410);

    const { data: hectares, error: areaError } = await supabase.rpc(
      "whatsapp_polygon_area",
      { p_geometry: geometry },
    );
    if (areaError) throw areaError;
    const areaHectares = Number(hectares);
    if (!Number.isFinite(areaHectares) || areaHectares <= 0) {
      return errorResponse("The boundary must enclose a valid area.", 400);
    }

    const centroid = centroidFor(geometry);
    const geocode = await reverseGeocode(
      centroid.latitude,
      centroid.longitude,
      text(onboarding.language) || "en",
    );
    const currentDraft = object(onboarding.draft);
    const currentFarm = object(currentDraft.farm);
    const updatedDraft = {
      ...currentDraft,
      farm: {
        ...currentFarm,
        geometry,
        bounds: boundsFor(geometry),
        area_hectares: areaHectares,
        area_acres: areaHectares * 2.47105,
        centroid_latitude: centroid.latitude,
        centroid_longitude: centroid.longitude,
        ...(geocode.label ? { location_label: geocode.label } : {}),
        geocode_provider: geocode.provider,
        geocode_status: geocode.status,
      },
    };
    const { data: updated, error: updateError } = await supabase
      .from("whatsapp_farmer_onboardings")
      .update({
        draft: updatedDraft,
        step: onboarding.flow_type === "existing_farmer_farm" ? "boundary_saved" : "crop",
        updated_at: new Date().toISOString(),
      })
      .eq("id", onboarding.id)
      .eq("status", "active")
      .eq("step", "boundary")
      .select("id,step,expires_at")
      .single();
    if (updateError) throw updateError;
    return successResponse({
      onboardingId: updated.id,
      step: updated.step,
      areaHectares,
      areaAcres: areaHectares * 2.47105,
      locationLabel: geocode.label,
      geocodeStatus: geocode.status,
      status: "boundary_saved",
      farm: updatedDraft.farm,
      summary: null,
      returnToWhatsappUrl: whatsappReturnUrl(),
    }, 200, "whatsapp_boundary_saved");
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : "Could not save boundary", 400);
  }
});
