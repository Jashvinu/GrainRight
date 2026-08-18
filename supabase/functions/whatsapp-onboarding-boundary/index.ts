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
  return geometry;
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

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  try {
    const body = object(await req.json());
    const token = text(body.token);
    if (token.length < 32) return errorResponse("This boundary link is invalid.", 400);
    const geometry = validateGeometry(body.geometry ?? body.geojson);
    const supabase = serviceClient();
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
        token_hash: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", onboarding.id)
      .eq("status", "active")
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
    }, 200, "whatsapp_boundary_saved");
  } catch (error) {
    return errorResponse(error instanceof Error ? error.message : "Could not save boundary", 400);
  }
});
