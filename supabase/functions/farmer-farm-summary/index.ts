import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import {
  assertLinkedFarm,
  normalizePhone,
  requireUserId,
  text,
} from "../_shared/farmer-links.ts";

type Row = Record<string, unknown>;

const diseaseColumns: Record<string, string> = {
  rice_blast_risk: "rice_blast",
  sheath_blight_risk: "sheath_blight",
  blb_risk: "bacterial_leaf_blight",
  downy_mildew_risk: "downy_mildew",
  leaf_spot_risk: "leaf_spot",
  charcoal_rot_risk: "charcoal_rot",
};

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(url, key);
}

function rows(data: unknown): Row[] {
  return Array.isArray(data) ? data as Row[] : [];
}

function num(raw: unknown): number | null {
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw === "string" && raw.trim().length > 0) {
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function rowNum(row: Row, keys: string[]): number | null {
  for (const key of keys) {
    const value = num(row[key]);
    if (value !== null) return value;
  }
  return null;
}

function scanDate(row: Row): string {
  return text(row.scan_date ?? row.created_at ?? row.updated_at);
}

function latestScanDate(data: Row[]): string {
  return data.map(scanDate).find((value) => value.length > 0) ?? "";
}

function sameScanRows(data: Row[], scan: string): Row[] {
  if (scan.length === 0) return data;
  const latest = data.filter((row) => scanDate(row) === scan);
  return latest.length > 0 ? latest : data;
}

function averageValue(data: Row[], keys: string[]): number | null {
  const values: number[] = [];
  for (const row of data) {
    const value = rowNum(row, keys);
    if (value !== null) values.push(value);
  }
  if (values.length === 0) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function maxValue(data: Row[], keys: string[]): number | null {
  let max: number | null = null;
  for (const row of data) {
    const value = rowNum(row, keys);
    if (value !== null && (max === null || value > max)) max = value;
  }
  return max;
}

function metric(
  value: number | null,
  index: string,
  date: string,
  source = "disease_risk_cells",
) {
  if (value === null) return null;
  return {
    value,
    index,
    date,
    source,
    status: "available",
  };
}

function diseaseScores(row: Row): Record<string, number> {
  const scores: Record<string, number> = {};
  const perDisease = row.per_disease;
  if (
    perDisease && typeof perDisease === "object" && !Array.isArray(perDisease)
  ) {
    for (const [name, value] of Object.entries(perDisease as Row)) {
      const parsed = num(value);
      if (parsed !== null) scores[name] = parsed;
    }
  }
  for (const [column, name] of Object.entries(diseaseColumns)) {
    const value = num(row[column]);
    if (value !== null) scores[name] = Math.max(scores[name] ?? 0, value);
  }
  return scores;
}

function topDiseaseRisks(data: Row[]): Record<string, number> {
  const risks: Record<string, number> = {};
  for (const row of data) {
    const scores = diseaseScores(row);
    for (const [name, value] of Object.entries(scores)) {
      risks[name] = Math.max(risks[name] ?? 0, value);
    }
  }
  return risks;
}

function maxRisk(data: Row[], risks: Record<string, number>): number {
  let max = 0;
  for (const row of data) {
    max = Math.max(
      max,
      rowNum(row, [
        "composite_risk",
        "max_risk_score",
        "risk_score",
      ]) ?? 0,
    );
  }
  for (const value of Object.values(risks)) {
    max = Math.max(max, value);
  }
  return max;
}

function ndviTrend(data: Row[]): { value: number; date: string } | null {
  const byScan = new Map<string, Row[]>();
  for (const row of data) {
    const scan = scanDate(row);
    if (scan.length === 0) continue;
    if (!byScan.has(scan)) byScan.set(scan, []);
    byScan.get(scan)!.push(row);
  }
  const scans = Array.from(byScan.keys());
  if (scans.length < 2) return null;
  const latest = averageValue(byScan.get(scans[0]) ?? [], ["ndvi"]);
  const previous = averageValue(byScan.get(scans[1]) ?? [], ["ndvi"]);
  if (latest === null || previous === null) return null;
  return { value: latest - previous, date: scans[0] };
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
    const farmId = text(body.farmId ?? body.farm_id);
    if (phone.length !== 10) {
      return errorResponse(
        "Enter a valid 10 digit mobile number",
        400,
        undefined,
        "invalid_phone",
      );
    }
    if (farmId.length === 0) {
      return errorResponse(
        "farm_id is required",
        400,
        undefined,
        "missing_farm_id",
      );
    }

    const supabase = createServiceClient();
    const userId = await requireUserId(supabase, req);
    if (userId instanceof Response) return userId;
    const authorizedFarm = await assertLinkedFarm(
      supabase,
      userId,
      phone,
      farmerId,
      farmId,
    );
    if (authorizedFarm instanceof Response) return authorizedFarm;

    const { data: farm, error: farmError } = await supabase
      .from("farms")
      .select(
        "id,name,geometry,bounds,area_hectares,area_acres,user_id,created_at,crop,variety,previous_crop,season,irrigation,soil_type,ownership_type,seed_source,harvest_intent,sowing_date,current_status,current_status_stage,current_status_updated_at",
      )
      .eq("id", farmId)
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

    const { data: zoneData, error: zonesError } = await supabase
      .from("disease_scout_zones")
      .select("*")
      .eq("farm_id", farmId)
      .order("scan_date", { ascending: false })
      .order("zone_rank", { ascending: true });
    if (zonesError) throw zonesError;

    const { data: cellData, error: cellsError } = await supabase
      .from("disease_risk_cells")
      .select("*")
      .eq("farm_id", farmId)
      .order("scan_date", { ascending: false })
      .order("composite_risk", { ascending: false })
      .limit(80);
    if (cellsError) throw cellsError;

    const allZones = rows(zoneData);
    const allCells = rows(cellData);
    const scan = latestScanDate(allCells) || latestScanDate(allZones);
    const latestCells = sameScanRows(allCells, scan);
    const latestZones = sameScanRows(allZones, scan);
    const risks = topDiseaseRisks(latestCells);
    const maxDiseaseRisk = maxRisk(latestCells, risks);
    const highRiskCells = latestCells.filter((row) =>
      (rowNum(row, ["composite_risk", "max_risk_score", "risk_score"]) ?? 0) >=
        0.55
    ).length;
    const weatherRisk = maxValue(latestCells, ["weather_risk"]);
    const trend = ndviTrend(allCells);

    return successResponse(
      {
        farm,
        satellite_metrics: {
          water_level: metric(
            averageValue(latestCells, ["moisture", "ndwi"]),
            "moisture",
            scan,
          ),
          crop_health: metric(
            averageValue(latestCells, ["ndvi"]),
            "ndvi",
            scan,
          ),
          canopy: metric(
            averageValue(latestCells, ["ndre", "gndvi", "savi"]),
            "canopy",
            scan,
          ),
          crop_trend: trend === null
            ? null
            : metric(trend.value, "ndvi_delta", trend.date),
          last_update: scan,
        },
        weather_context: weatherRisk === null
          ? {
            weather_data_status: "missing",
            scan_date: scan,
            source: "disease_risk_cells",
          }
          : {
            weather_data_status: "available",
            weather_risk: weatherRisk,
            weather_risk_max: weatherRisk,
            scan_date: scan,
            source: "disease_risk_cells",
          },
        disease: {
          scan_date: scan,
          crop: text(farm.crop),
          season: text(farm.season),
          images_analyzed: 0,
          risk_cells_count: latestCells.length,
          high_risk_cells: highRiskCells,
          max_risk: maxDiseaseRisk,
          top_disease_risks: risks,
          scout_zones: latestZones,
          risk_cells: latestCells,
        },
        advice: null,
      },
      200,
      "farmer_farm_summary_success",
    );
  } catch (error) {
    return errorResponse(
      "farmer-farm-summary failed",
      500,
      error,
      "farmer_farm_summary_failed",
    );
  }
});
