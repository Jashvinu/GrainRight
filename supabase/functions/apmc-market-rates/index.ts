import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCors } from "../_shared/cors.ts";
import { errorResponse, successResponse } from "../_shared/response.ts";
import { requireUserId, text } from "../_shared/farmer-links.ts";

const resourceId = "9ef84268-d588-465a-a308-a864a43d0070";
const endpoint = `https://api.data.gov.in/resource/${resourceId}`;

type JsonRecord = Record<string, unknown>;

function record(raw: unknown): JsonRecord {
  return raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as JsonRecord
    : {};
}

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Supabase environment is incomplete.");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function requireCronToken(
  supabase: ReturnType<typeof createServiceClient>,
  req: Request,
): Promise<Response | null> {
  const provided = text(req.headers.get("x-apmc-cron-token"));
  const { data, error } = await supabase.from("apmc_sync_control")
    .select("cron_token")
    .eq("id", true)
    .single();
  if (error) throw error;
  if (!provided || provided !== text(data?.cron_token)) {
    return errorResponse(
      "Invalid scheduled sync token",
      401,
      undefined,
      "invalid_cron_token",
    );
  }
  return null;
}

async function updateSyncControl(
  supabase: ReturnType<typeof createServiceClient>,
  values: JsonRecord,
) {
  const { error } = await supabase.from("apmc_sync_control")
    .update({ ...values, updated_at: new Date().toISOString() })
    .eq("id", true);
  if (error) throw error;
}

function field(row: JsonRecord, name: string): string {
  const wanted = name.toLowerCase().replaceAll(" ", "_");
  for (const [key, value] of Object.entries(row)) {
    if (key.toLowerCase().replaceAll(" ", "_") === wanted) return text(value);
  }
  return "";
}

function numberValue(raw: unknown): number | null {
  const value = Number(String(raw ?? "").replaceAll(",", ""));
  return Number.isFinite(value) && value >= 0 ? value : null;
}

function isoDate(raw: unknown): string | null {
  const value = text(raw);
  const indian = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(value);
  if (indian) {
    const [, day, month, year] = indian;
    return `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed)
    ? new Date(parsed).toISOString().slice(0, 10)
    : null;
}

function normalizeRate(raw: unknown): JsonRecord | null {
  const row = record(raw);
  const state = field(row, "state");
  const district = field(row, "district");
  const market = field(row, "market");
  const commodity = field(row, "commodity");
  const arrivalDate = isoDate(field(row, "arrival_date"));
  const minPrice = numberValue(field(row, "min_price"));
  const maxPrice = numberValue(field(row, "max_price"));
  const modalPrice = numberValue(field(row, "modal_price"));
  if (
    !state || !district || !market || !commodity || !arrivalDate ||
    minPrice == null || maxPrice == null || modalPrice == null
  ) return null;
  return {
    source: "data.gov.in",
    state,
    district,
    market,
    commodity,
    variety: field(row, "variety"),
    grade: field(row, "grade"),
    arrival_date: arrivalDate,
    min_price: minPrice,
    max_price: maxPrice,
    modal_price: modalPrice,
    source_record: row,
    synced_at: new Date().toISOString(),
  };
}

async function refreshOfficialRates(
  supabase: ReturnType<typeof createServiceClient>,
  body: JsonRecord,
) {
  const apiKey = Deno.env.get("DATA_GOV_IN_API_KEY");
  if (!apiKey) {
    return { refreshed: false, refreshReason: "api_key_not_configured" };
  }

  const params = new URLSearchParams({
    "api-key": apiKey,
    format: "json",
    limit: String(Math.min(Math.max(Number(body.limit) || 100, 1), 500)),
    offset: "0",
  });
  const filters: Array<[string, string]> = [
    ["state", text(body.state)],
    ["district", text(body.district)],
    ["market", text(body.market)],
    ["commodity", text(body.commodity ?? body.query)],
  ];
  for (const [key, value] of filters) {
    if (value) params.set(`filters[${key}]`, value);
  }

  const response = await fetch(`${endpoint}?${params.toString()}`, {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) {
    throw new Error(`AGMARKNET request failed (${response.status}).`);
  }
  const payload = record(await response.json());
  const rows = (Array.isArray(payload.records) ? payload.records : [])
    .map(normalizeRate)
    .filter((row): row is JsonRecord => row != null);
  if (rows.length > 0) {
    const { error } = await supabase.from("apmc_market_rate_history").upsert(
      rows,
      {
        onConflict:
          "source,state,district,market,commodity,variety,grade,arrival_date",
      },
    );
    if (error) throw error;
  }
  return { refreshed: true, refreshedCount: rows.length };
}

async function localRates(
  supabase: ReturnType<typeof createServiceClient>,
  body: JsonRecord,
) {
  let query = supabase.from("apmc_market_rate_history")
    .select(
      "id,source,state,district,market,commodity,variety,grade,arrival_date,min_price,max_price,modal_price,synced_at",
    )
    .order("arrival_date", { ascending: false })
    .order("market")
    .limit(Math.min(Math.max(Number(body.limit) || 100, 1), 300));
  const exactFilters: Array<[string, string]> = [
    ["state", text(body.state)],
    ["district", text(body.district)],
    ["market", text(body.market)],
  ];
  for (const [column, value] of exactFilters) {
    if (value) query = query.ilike(column, `%${value}%`);
  }
  const commodity = text(body.commodity ?? body.query);
  if (commodity) query = query.ilike("commodity", `%${commodity}%`);
  const { data, error } = await query;
  if (error) throw error;
  return Array.isArray(data) ? data : [];
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
    const supabase = createServiceClient();
    const body = record(await req.json());
    const scheduled = text(body.action) === "daily_refresh";
    if (scheduled) {
      const denied = await requireCronToken(supabase, req);
      if (denied) return denied;
    } else {
      const userId = await requireUserId(supabase, req);
      if (userId instanceof Response) return userId;
    }
    const refresh = scheduled || body.refresh === true;
    let refreshResult: JsonRecord = {
      refreshed: false,
      refreshReason: "not_requested",
    };
    if (refresh) {
      await updateSyncControl(supabase, {
        last_attempt_at: new Date().toISOString(),
        last_error: "",
      });
      try {
        refreshResult = await refreshOfficialRates(supabase, body);
        const refreshed = refreshResult.refreshed === true;
        await updateSyncControl(supabase, {
          last_record_count: Number(refreshResult.refreshedCount) || 0,
          last_error: refreshed ? "" : text(refreshResult.refreshReason),
          ...(refreshed ? { last_success_at: new Date().toISOString() } : {}),
        });
      } catch (error) {
        await updateSyncControl(supabase, { last_error: String(error) });
        throw error;
      }
    }
    const rates = await localRates(supabase, body);
    return successResponse(
      {
        rates,
        count: rates.length,
        source: "Government of India AGMARKNET via data.gov.in",
        unit: "INR/quintal",
        scheduled,
        ...refreshResult,
      },
      200,
      "apmc_market_rates",
    );
  } catch (error) {
    return errorResponse(
      "APMC market rates failed",
      500,
      error,
      "apmc_market_rates_failed",
    );
  }
});
