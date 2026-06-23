import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  assertLinkedFarm,
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

function payloadMap(raw: unknown): Record<string, unknown> {
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    return raw as Record<string, unknown>;
  }
  return {};
}

function toNumber(raw: unknown): number | null {
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw === "string" && raw.trim().length > 0) {
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function toInt(raw: unknown): number {
  const parsed = toNumber(raw);
  return parsed == null ? 0 : Math.max(0, Math.round(parsed));
}

function dateKey(raw: unknown): string {
  const parsed = new Date(text(raw) || Date.now());
  if (Number.isNaN(parsed.getTime())) {
    return new Date().toISOString().slice(0, 10);
  }
  return parsed.toISOString().slice(0, 10);
}

function compactAfterForDate(date: string): string {
  const parsed = new Date(`${date}T00:00:00.000Z`);
  parsed.setUTCDate(parsed.getUTCDate() + 4);
  return parsed.toISOString();
}

function uniqueStrings(values: unknown[]): string[] {
  return Array.from(
    new Set(
      values
        .flatMap((value) => Array.isArray(value) ? value : [value])
        .map((value) => text(value))
        .filter((value) => value.length > 0),
    ),
  );
}

function compactSnapshot(
  rawSnapshot: Record<string, unknown>,
  source: string,
  collectedAt: string,
): Record<string, unknown> {
  return {
    source,
    collected_at: collectedAt,
    farm: payloadMap(rawSnapshot.farm),
    crop: payloadMap(rawSnapshot.crop),
    status: payloadMap(rawSnapshot.status),
    weather: payloadMap(rawSnapshot.weather),
    disease: payloadMap(rawSnapshot.disease),
    lifecycle: payloadMap(rawSnapshot.lifecycle),
    timeline: payloadMap(rawSnapshot.timeline),
  };
}

function derivedColumns(snapshot: Record<string, unknown>) {
  const farm = payloadMap(snapshot.farm);
  const crop = payloadMap(snapshot.crop);
  const status = payloadMap(snapshot.status);
  const weather = payloadMap(snapshot.weather);
  const disease = payloadMap(snapshot.disease);
  return {
    farm_name: text(farm.name),
    crop: text(crop.name),
    variety: text(crop.variety),
    growth_stage: text(status.stage || crop.growth_stage),
    current_status: text(status.current),
    days_after_sowing: toNumber(crop.days_after_sowing),
    temperature_c: toNumber(weather.temperature_c),
    humidity_percent: toNumber(weather.humidity_percent),
    rain_mm: toNumber(weather.rain_mm),
    total_rain_mm: toNumber(weather.total_rain_mm),
    wind_kmh: toNumber(weather.wind_kmh),
    weather_risk: toNumber(weather.weather_risk),
    water_stress_label: text(weather.water_stress_label),
    water_stress_score: toNumber(weather.water_stress_score),
    crop_weather_label: text(weather.crop_weather_label),
    crop_weather_score: toNumber(weather.crop_weather_score),
    disease_risk: toNumber(disease.max_risk),
    risk_cells_count: toInt(disease.risk_cells_count),
    scout_zones_count: toInt(disease.scout_zones_count),
  };
}

function mergeSnapshot(
  existingRow: Record<string, unknown> | null,
  next: Record<string, unknown>,
  source: string,
  collectedAt: string,
): Record<string, unknown> {
  const previous = payloadMap(existingRow?.snapshot);
  const refreshCount = toInt(existingRow?.refresh_count) + 1;
  return {
    ...previous,
    ...next,
    sources: uniqueStrings([previous.sources, source]),
    refresh_count: refreshCount,
    first_collected_at: text(previous.first_collected_at) || collectedAt,
    last_collected_at: collectedAt,
  };
}

function average(values: Array<number | null>): number | null {
  const numbers = values.filter((value): value is number => value != null);
  if (numbers.length === 0) return null;
  return numbers.reduce((sum, value) => sum + value, 0) / numbers.length;
}

function maximum(values: Array<number | null>): number | null {
  const numbers = values.filter((value): value is number => value != null);
  if (numbers.length === 0) return null;
  return Math.max(...numbers);
}

function compactSummary(rows: Array<Record<string, unknown>>) {
  const latest = rows[rows.length - 1] ?? {};
  const refreshCount = rows.reduce(
    (sum, row) => sum + toInt(row.refresh_count),
    0,
  );
  const actions = uniqueStrings(
    rows.map((row) => payloadMap(payloadMap(row.snapshot).lifecycle).next_action),
  ).slice(-8);
  const firstDate = text(rows[0]?.snapshot_date);
  const lastDate = text(latest.snapshot_date);

  return {
    farm_name: text(latest.farm_name),
    crop: text(latest.crop),
    variety: text(latest.variety),
    latest_status: text(latest.current_status),
    latest_growth_stage: text(latest.growth_stage),
    avg_temperature_c: average(rows.map((row) => toNumber(row.temperature_c))),
    total_rain_mm: rows.reduce(
      (sum, row) => sum + (toNumber(row.total_rain_mm) ?? toNumber(row.rain_mm) ?? 0),
      0,
    ),
    avg_water_stress_score: average(
      rows.map((row) => toNumber(row.water_stress_score)),
    ),
    max_disease_risk: maximum(rows.map((row) => toNumber(row.disease_risk))),
    compact_summary: {
      compacted_from: firstDate,
      compacted_to: lastDate,
      snapshot_count: rows.length,
      refresh_count: refreshCount,
      latest_status: text(latest.current_status),
      latest_growth_stage: text(latest.growth_stage),
      max_weather_risk: maximum(rows.map((row) => toNumber(row.weather_risk))),
      max_disease_risk: maximum(rows.map((row) => toNumber(row.disease_risk))),
      avg_water_stress_score: average(
        rows.map((row) => toNumber(row.water_stress_score)),
      ),
      lifecycle_actions: actions,
    },
  };
}

async function compactDueSnapshots(
  supabase: ReturnType<typeof createServiceClient>,
  farmId: string,
  farmerId: string,
  phone: string,
) {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from("farm_data_snapshots")
    .select("*")
    .eq("farm_id", farmId)
    .eq("compacted", false)
    .lte("compact_after", now)
    .order("snapshot_date", { ascending: true })
    .limit(32);
  if (error) throw error;

  const rows = Array.isArray(data) ? data as Array<Record<string, unknown>> : [];
  if (rows.length === 0) return { compacted_count: 0 };

  const firstDate = text(rows[0].snapshot_date);
  const lastDate = text(rows[rows.length - 1].snapshot_date);
  const summary = compactSummary(rows);
  const refreshCount = rows.reduce(
    (sum, row) => sum + toInt(row.refresh_count),
    0,
  );

  const { data: compacted, error: compactError } = await supabase
    .from("farm_data_compactions")
    .upsert(
      {
        farm_id: farmId,
        farmer_id: farmerId || null,
        farmer_phone: phone,
        compacted_from: firstDate,
        compacted_to: lastDate,
        snapshot_count: rows.length,
        refresh_count: refreshCount,
        ...summary,
        updated_at: now,
      },
      { onConflict: "farm_id,compacted_from,compacted_to" },
    )
    .select("id")
    .single();
  if (compactError) throw compactError;

  const compactId = text(compacted?.id);
  const ids = rows.map((row) => text(row.id)).filter((id) => id.length > 0);
  if (ids.length > 0) {
    const { error: markError } = await supabase
      .from("farm_data_snapshots")
      .update({
        compacted: true,
        compacted_at: now,
        snapshot: {
          compacted: true,
          compact_id: compactId || null,
          compacted_from: firstDate,
          compacted_to: lastDate,
          snapshot_count: rows.length,
          refresh_count: refreshCount,
        },
        updated_at: now,
      })
      .in("id", ids);
    if (markError) throw markError;
  }

  return {
    compacted_count: rows.length,
    compact_id: compactId || null,
  };
}

Deno.serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405, undefined, "method_not_allowed");
  }

  try {
    const body = await req.json();
    const action = text(body.action || "record").toLowerCase();
    const phone = normalizePhone(body.phone ?? body.farmerPhone ?? body.farmer_phone);
    const farmerId = text(body.farmerId ?? body.farmer_id);
    const farmId = text(body.farmId ?? body.farm_id);

    if (action !== "record") {
      return errorResponse("Unsupported snapshot action", 400, undefined, "invalid_action");
    }
    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid 10 digit mobile number",
        400,
        undefined,
        "invalid_phone",
      );
    }
    if (farmId.length === 0) {
      return errorResponse("farm_id is required", 400, undefined, "missing_farm_id");
    }

    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;
    const linkedFarm = await assertLinkedFarm(
      supabase,
      userId,
      phone,
      farmerId,
      farmId,
    );
    if (linkedFarm instanceof Response) return linkedFarm;

    const collectedAt = text(body.collectedAt ?? body.collected_at) ||
      new Date().toISOString();
    const snapshotDate = dateKey(collectedAt);
    const source = text(body.source) || "farm_refresh";
    const nextSnapshot = compactSnapshot(payloadMap(body.snapshot), source, collectedAt);

    const { data: existing, error: existingError } = await supabase
      .from("farm_data_snapshots")
      .select("*")
      .eq("farm_id", farmId)
      .eq("snapshot_date", snapshotDate)
      .maybeSingle();
    if (existingError) throw existingError;

    const existingRow = existing
      ? existing as Record<string, unknown>
      : null;
    const merged = mergeSnapshot(existingRow, nextSnapshot, source, collectedAt);
    const columns = derivedColumns(merged);
    const refreshCount = toInt(merged.refresh_count);
    const payload = {
      farm_id: farmId,
      farmer_id: farmerId || null,
      farmer_phone: phone,
      snapshot_date: snapshotDate,
      collected_at: collectedAt,
      source,
      ...columns,
      refresh_count: refreshCount,
      snapshot: merged,
      compacted: false,
      compacted_at: null,
      updated_at: new Date().toISOString(),
    };

    let saved: Record<string, unknown> | null = null;
    if (existingRow?.id) {
      const { data: updated, error: updateError } = await supabase
        .from("farm_data_snapshots")
        .update(payload)
        .eq("id", existingRow.id)
        .select("*")
        .single();
      if (updateError) throw updateError;
      saved = updated as Record<string, unknown>;
    } else {
      const { data: inserted, error: insertError } = await supabase
        .from("farm_data_snapshots")
        .insert({
          ...payload,
          compact_after: compactAfterForDate(snapshotDate),
        })
        .select("*")
        .single();
      if (insertError) throw insertError;
      saved = inserted as Record<string, unknown>;
    }

    const compacted = await compactDueSnapshots(
      supabase,
      farmId,
      farmerId,
      phone,
    );

    return successResponse(
      { snapshot: saved, ...compacted },
      200,
      "farm_data_snapshot_saved",
    );
  } catch (error) {
    return errorResponse(
      "farm-data-snapshots failed",
      500,
      error,
      "farm_data_snapshots_failed",
    );
  }
});
