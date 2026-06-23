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

type Row = Record<string, unknown>;

function rows(value: unknown): Row[] {
  if (!Array.isArray(value) || value.length === 0) return [];
  return value.filter((row): row is Row =>
    row !== null && typeof row === "object" && !Array.isArray(row)
  );
}

function scanDate(row: Row): string {
  return text(row.scan_date ?? row.created_at ?? row.updated_at);
}

function latestScanDate(data: Row[]): string {
  let latest = "";
  for (const row of data) {
    const date = scanDate(row);
    if (date.length > 0 && date > latest) latest = date;
  }
  return latest;
}

function sameScanRows(data: Row[], scan: string): Row[] {
  if (scan.length === 0) return data;
  const latest = data.filter((row) => scanDate(row) === scan);
  return latest.length > 0 ? latest : data;
}

function rowNum(row: Row, keys: string[]): number | null {
  for (const key of keys) {
    const value = row[key];
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string") {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  return null;
}

function riskScore(row: Row): number {
  return rowNum(row, ["composite_risk", "max_risk_score", "risk_score"]) ?? 0;
}

function topDiseaseRisks(data: Row[]): Record<string, number> {
  const columns: Record<string, string> = {
    rice_blast_risk: "rice_blast",
    sheath_blight_risk: "sheath_blight",
    blb_risk: "bacterial_leaf_blight",
    downy_mildew_risk: "downy_mildew",
    leaf_spot_risk: "leaf_spot",
    charcoal_rot_risk: "charcoal_rot",
  };
  const result: Record<string, number> = {};
  for (const [column, disease] of Object.entries(columns)) {
    const values = data
      .map((row) => rowNum(row, [column]))
      .filter((value): value is number => value !== null && value > 0);
    if (values.length === 0) continue;
    const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
    result[disease] = Number(mean.toFixed(3));
  }
  return result;
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
    const action = text(body.action || "disease_data");
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
    const farm = await assertLinkedFarm(
      supabase,
      userId,
      phone,
      farmerId,
      farmId,
    );
    if (farm instanceof Response) return farm;
    void farm;

    if (action === "insert_scout_zone") {
      const payload = body.payload &&
          typeof body.payload === "object" &&
          !Array.isArray(body.payload)
        ? body.payload as Record<string, unknown>
        : {};
      const { data, error } = await supabase
        .from("disease_scout_zones")
        .insert({ ...payload, farm_id: farmId })
        .select()
        .maybeSingle();
      if (error) throw error;
      return successResponse({ scout_zone: data }, 200, "scout_zone_inserted");
    }

    const { data: zones, error: zonesError } = await supabase
      .from("disease_scout_zones")
      .select("*")
      .eq("farm_id", farmId)
      .order("scan_date", { ascending: false })
      .order("zone_rank", { ascending: true });
    if (zonesError) throw zonesError;

    const { data: cells, error: cellsError } = await supabase
      .from("disease_risk_cells")
      .select("*")
      .eq("farm_id", farmId)
      .order("scan_date", { ascending: false })
      .order("composite_risk", { ascending: false })
      .limit(300);
    if (cellsError) throw cellsError;

    const allZones = rows(zones);
    const allCells = rows(cells);
    const scan = latestScanDate(allCells) || latestScanDate(allZones);
    const latestZones = sameScanRows(allZones, scan);
    const latestCells = sameScanRows(allCells, scan)
      .sort((a, b) => riskScore(b) - riskScore(a))
      .slice(0, 60);
    const highRiskCells = latestCells.filter((row) => riskScore(row) >= 0.55)
      .length;
    const maxRisk = latestCells.reduce(
      (max, row) => Math.max(max, riskScore(row)),
      0,
    );

    return successResponse(
      {
        scan_date: scan,
        scout_zones: latestZones,
        risk_cells: latestCells,
        risk_cells_count: latestCells.length,
        high_risk_cells: highRiskCells,
        max_risk: Number(maxRisk.toFixed(3)),
        top_disease_risks: topDiseaseRisks(latestCells),
      },
      200,
      "disease_data_success",
    );
  } catch (error) {
    return errorResponse(
      "farmer-farm-data failed",
      500,
      error,
      "farmer_farm_data_failed",
    );
  }
});
