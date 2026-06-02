import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type DbRow = Record<string, unknown>;

const PAGE_SIZE = 1000;
const DEFAULT_YEARLY_YEARS = [2023, 2024, 2025];
const KHARIF_POSITIONS = [1, 2, 3, 4, 5, 6, 7, 8];
const PRACTICE_ROLES = ["main", "other"];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const farmerColumns = [
  "id",
  "user_id",
  "survey_date",
  "language",
  "farmer_name",
  "gender",
  "date_of_birth",
  "category",
  "education_level",
  "village_gp",
  "gram_panchayat",
  "block",
  "district",
  "aadhar_no",
  "mobile_no",
  "sources_of_income",
  "income_sources_other",
  "farming_type",
  "farming_type_other",
  "owns_farmland",
  "land_owned",
  "land_leased",
  "total_rainfed_land",
  "total_irrigated_land",
  "dry_land_acre",
  "fallow_land_acre",
  "has_forest_patta",
  "forest_patta_acre",
  "applied_for_forest_patta",
  "main_crop",
  "main_crop_other",
  "land_under_millet",
  "land_under_other_crops",
  "other_crop_details",
  "farm_polygon",
  "annual_agri_income",
  "annual_non_agri_income",
  "total_cultivation_cost",
  "total_annual_income",
  "makes_food_products",
  "food_products_list",
  "food_product_training_received",
  "food_product_training_source",
  "disease_present",
  "disease_name",
  "affected_crop",
  "disease_severity",
  "symptoms_observed",
  "treatment_taken",
  "form_latitude",
  "form_longitude",
  "form_location_accuracy",
  "form_started_at",
  "submitted_at",
  "created_at",
  "updated_at",
  "extra_details",
];

const kharifColumns = [
  "crop_name",
  "other_crop_name",
  "other_crop_details",
  "cultivated_area_acre",
  "crop_variety",
  "production_qty",
  "production_qty_unit",
  "avg_estimated_cost",
  "extra_details",
];

const yearlyColumns = [
  "area_acre",
  "total_production",
  "total_production_unit",
  "yield_avg_per_acre",
  "yield_avg_per_acre_unit",
  "home_consumption",
  "home_consumption_unit",
  "quantity_sold",
  "quantity_sold_unit",
  "sold_where",
  "sold_where_options",
  "sold_where_other",
  "selling_price",
  "extra_details",
];

const practiceColumns = [
  "grown_on",
  "grown_on_other",
  "same_land_every_year",
  "land_topology",
  "land_topology_other",
  "seed_sources",
  "seed_source_other",
  "pop_training_received",
  "pop_training_source",
  "farming_method",
  "treats_seeds",
  "seed_treatment_materials",
  "seed_treatment_materials_other",
  "seedling_method",
  "seedling_method_other",
  "seedling_ready_days",
  "seedling_method_difference",
  "land_prep_tractor_days",
  "land_prep_tractor_cost",
  "land_prep_bullock_days",
  "land_prep_bullock_cost",
  "land_prep_by_hand",
  "transplant_method",
  "transplant_method_other",
  "dip_in_jeevamrut",
  "plant_spacing_cm",
  "transplant_days",
  "needs_transplant_labour",
  "transplant_labourers",
  "transplant_daily_wage",
  "does_weeding",
  "weeding_after_days",
  "sprays_for_pest",
  "spray_methods",
  "matka_per_acre",
  "matka_per_acre_unit",
  "neem_per_acre",
  "neem_per_acre_unit",
  "jeevamrut_per_acre",
  "jeevamrut_per_acre_unit",
  "pesticide_per_acre",
  "pesticide_per_acre_unit",
  "spray_methods_other",
  "organic_fert_helps_disease",
  "planting_to_flowering_days",
  "uses_fertilizer",
  "fertilizer_names",
  "fertilizer_qty_per_acre",
  "flowering_pest_problem",
  "flowering_pest_type",
  "flowering_sprays_used",
  "maturity_days",
  "monitors_crop",
  "monitoring_methods",
  "monitoring_methods_other",
  "harvest_method",
  "harvest_labour_type",
  "harvest_daily_wage",
  "harvest_labourers",
  "harvest_days",
  "ready_to_eat_or_sell_days",
  "sells_main_crop",
  "selling_time",
  "extra_details",
];

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "GET") {
    return jsonResponse({ error: "Only GET is supported" }, 405);
  }

  try {
    const url = new URL(req.url);
    const summaryOnly = url.searchParams.get("summary") === "1";
    const supabase = createServerClient();

    if (summaryOnly) {
      const summary = await loadSummary(supabase);
      return jsonResponse(summary);
    }

    const [farmers, kharifRows, yearlyRows, practiceRows] = await Promise.all([
      fetchAllRows(supabase, "farmer_surveys_export", ["created_at"]),
      fetchAllRows(supabase, "survey_kharif_crops_export", ["survey_id", "position"]),
      fetchAllRows(supabase, "survey_main_crop_yearly_export", ["survey_id", "year"]),
      fetchAllRows(supabase, "survey_crop_practices_export", ["survey_id", "crop_role"]),
    ]);

    const payload = buildExportPayload(farmers, kharifRows, yearlyRows, practiceRows);
    return jsonResponse(payload);
  } catch (error) {
    console.error("admin-survey-export error:", error);
    return jsonResponse({ error: (error as Error).message }, 500);
  }
});

function createServerClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }

  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

async function loadSummary(supabase: ReturnType<typeof createServerClient>) {
  const { data, error, count } = await supabase
    .from("farmer_surveys_export")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(0, 9);

  if (error) {
    throw new Error(`Failed to load survey summary: ${error.message}`);
  }

  const rows = (data ?? []) as DbRow[];
  const latest = newestDate(rows);

  return {
    generatedAt: new Date().toISOString(),
    totalSubmittedForms: count ?? rows.length,
    rowsReadyForExport: count ?? rows.length,
    latestSubmittedAt: latest,
    preview: rows.map(previewRow),
  };
}

async function fetchAllRows(
  supabase: ReturnType<typeof createServerClient>,
  tableName: string,
  orderColumns: string[] = [],
) {
  const allRows: DbRow[] = [];
  let page = 0;

  while (true) {
    let query = supabase.from(tableName).select("*");
    for (const column of orderColumns) {
      query = query.order(column, { ascending: true });
    }
    const from = page * PAGE_SIZE;
    const to = from + PAGE_SIZE - 1;
    const { data, error } = await query.range(from, to);

    if (error) {
      throw new Error(`Failed to load ${tableName}: ${error.message}`);
    }

    const rows = (data ?? []) as DbRow[];
    allRows.push(...rows);
    if (rows.length < PAGE_SIZE) break;
    page += 1;
  }

  return allRows;
}

function buildExportPayload(
  farmers: DbRow[],
  kharifRows: DbRow[],
  yearlyRows: DbRow[],
  practiceRows: DbRow[],
) {
  const yearlyYears = sortedYears(yearlyRows);
  const columns = buildColumns(yearlyYears);
  const kharifBySurvey = groupBy(kharifRows, "survey_id");
  const yearlyBySurvey = groupBy(yearlyRows, "survey_id");
  const practicesBySurvey = groupBy(practiceRows, "survey_id");

  const rows = farmers
    .slice()
    .sort((a, b) => compareDateDesc(exportDate(a), exportDate(b)))
    .map((farmer) => {
      const surveyId = stringValue(farmer.id);
      const row: DbRow = {};

      for (const column of farmerColumns) {
        row[column] = farmer[column] ?? null;
      }

      const kharifForSurvey = kharifBySurvey.get(surveyId) ?? [];
      for (const position of KHARIF_POSITIONS) {
        const cropRow = kharifForSurvey.find((item) => Number(item.position) === position);
        copyPrefixed(row, `kharif_${position}_`, cropRow, kharifColumns);
      }

      const yearlyForSurvey = yearlyBySurvey.get(surveyId) ?? [];
      for (const year of yearlyYears) {
        const yearRow = yearlyForSurvey.find((item) => Number(item.year) === year);
        copyPrefixed(row, `yearly_${year}_`, yearRow, yearlyColumns);
      }

      const practicesForSurvey = practicesBySurvey.get(surveyId) ?? [];
      for (const role of PRACTICE_ROLES) {
        const practiceRow = practicesForSurvey.find(
          (item) => String(item.crop_role ?? "").toLowerCase() === role,
        );
        copyPrefixed(row, `${role}_practice_`, practiceRow, practiceColumns);
      }

      return row;
    });

  return {
    generatedAt: new Date().toISOString(),
    totalSubmittedForms: farmers.length,
    rowsReadyForExport: rows.length,
    latestSubmittedAt: newestDate(farmers),
    columns,
    rows,
    preview: farmers.slice(0, 10).map(previewRow),
  };
}

function buildColumns(yearlyYears: number[]) {
  return [
    ...farmerColumns,
    ...KHARIF_POSITIONS.flatMap((position) =>
      kharifColumns.map((column) => `kharif_${position}_${column}`)
    ),
    ...yearlyYears.flatMap((year) =>
      yearlyColumns.map((column) => `yearly_${year}_${column}`)
    ),
    ...PRACTICE_ROLES.flatMap((role) =>
      practiceColumns.map((column) => `${role}_practice_${column}`)
    ),
  ];
}

function sortedYears(rows: DbRow[]) {
  const years = new Set(DEFAULT_YEARLY_YEARS);
  for (const row of rows) {
    const year = Number(row.year);
    if (Number.isInteger(year)) years.add(year);
  }
  return [...years].sort((a, b) => a - b);
}

function groupBy(rows: DbRow[], key: string) {
  const grouped = new Map<string, DbRow[]>();
  for (const row of rows) {
    const value = stringValue(row[key]);
    if (!value) continue;
    const bucket = grouped.get(value) ?? [];
    bucket.push(row);
    grouped.set(value, bucket);
  }
  return grouped;
}

function copyPrefixed(target: DbRow, prefix: string, source: DbRow | undefined, columns: string[]) {
  for (const column of columns) {
    target[`${prefix}${column}`] = source?.[column] ?? null;
  }
}

function previewRow(row: DbRow) {
  return {
    id: row.id ?? null,
    farmer_name: row.farmer_name ?? null,
    village: row.village_gp ?? null,
    main_crop: row.main_crop ?? null,
    submitted_at: row.submitted_at ?? row.created_at ?? null,
  };
}

function newestDate(rows: DbRow[]) {
  let latest = "";
  for (const row of rows) {
    const candidate = exportDate(row);
    if (compareDateDesc(candidate, latest) < 0) latest = candidate;
  }
  return latest || null;
}

function exportDate(row: DbRow) {
  return stringValue(row.submitted_at) || stringValue(row.created_at);
}

function compareDateDesc(a: string, b: string) {
  return timestampValue(b) - timestampValue(a);
}

function timestampValue(value: string) {
  if (!value) return 0;
  const parsed = Date.parse(value);
  return Number.isNaN(parsed) ? 0 : parsed;
}

function stringValue(value: unknown) {
  return value === null || value === undefined ? "" : String(value);
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
