import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  encode as base64url,
} from "https://deno.land/std@0.177.0/encoding/base64url.ts";

const SPREADSHEET_ID = "1fBcF0aSwT0m0YKb12DsNos8Ou_jrRLO0PWpVU048Lqg";
const SHEET_TAB = "FarmerSurveys_updated";

// Column order must match the Google Sheet headers exactly.
// id is filled from Supabase after insert; sl_no can be maintained in the sheet.
const COLUMNS = [
  "id",
  "sl_no",
  "survey_date",
  "season",
  "farmer_name",
  "gender",
  "date_of_birth",
  "category",
  "education_level",
  "village_gp",
  "block",
  "district",
  "fpc_name",
  "aadhar_no",
  "mobile_no",
  "land_owned",
  "land_leased",
  "total_rainfed_land",
  "total_irrigated_land",
  "land_under_millet",
  "land_under_other_crops",
  "cropping_intensity",
  "major_crops_grown",
  "millet_seed_type",
  "millet_seed_variety",
  "seed_used_kg_per_acre",
  "fertilizer_used_kg_per_acre",
  "pesticide_used_litres_per_acre",
  "use_bio_fertilizer",
  "access_to_credit",
  "access_to_extension_services",
  "mechanization_access",
  "millet_productivity",
  "other_crops_productivity",
  "total_millet_production",
  "quantity_millet_sold",
  "quantity_home_consumption",
  "quantity_used_as_seed",
  "avg_millet_selling_price",
  "post_harvest_practices",
  "where_produce_sold",
  "kharif_crop_production_units",
  "main_crop_yearly_total_production_units",
  "main_crop_yearly_home_consumption_units",
  "main_crop_yearly_quantity_sold_units",
  "main_crop_yearly_sold_where",
  "main_crop_yearly_sold_where_other",
  "crop_practice_spray_units",
  "training_received",
  "training_source",
  "avg_cost_cultivation_millets",
  "net_income_millets",
  "avg_cost_cultivation_other",
  "net_income_other_crops",
  "sources_of_income",
  "annual_agri_income",
  "annual_non_agri_income",
  "total_annual_income",
  "created_at",
  "updated_at",
  "millet_land_areas",
  "form_latitude",
  "form_longitude",
  "form_location_accuracy",
  "form_started_at",
  "language",
  "gram_panchayat",
  "income_sources_other",
  "farming_type",
  "farming_type_other",
  "owns_farmland",
  "dry_land_acre",
  "fallow_land_acre",
  "has_forest_patta",
  "forest_patta_acre",
  "applied_for_forest_patta",
  "main_crop",
  "main_crop_other",
  "other_crop_land_acre",
  "other_crop_details",
  "farm_polygon",
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
  "submitted_at",
];

// --- JWT / Google Auth helpers ---

const textEncoder = new TextEncoder();

async function createJWT(
  serviceEmail: string,
  privateKeyPem: string
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: serviceEmail,
    scope: "https://www.googleapis.com/auth/spreadsheets",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const headerB64 = base64url(textEncoder.encode(JSON.stringify(header)));
  const payloadB64 = base64url(textEncoder.encode(JSON.stringify(payload)));
  const unsignedToken = `${headerB64}.${payloadB64}`;

  const key = await importPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    textEncoder.encode(unsignedToken)
  );

  const signatureB64 = base64url(new Uint8Array(signature));
  return `${unsignedToken}.${signatureB64}`;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");

  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

async function getAccessToken(
  serviceEmail: string,
  privateKey: string
): Promise<string> {
  const jwt = await createJWT(serviceEmail, privateKey);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Token exchange failed: ${res.status} ${text}`);
  }

  const data = await res.json();
  return data.access_token;
}

// --- Google Sheets helpers ---

async function getSheetTabName(
  accessToken: string,
  spreadsheetId: string
): Promise<string> {
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}?fields=sheets.properties`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to get sheet metadata: ${res.status} ${text}`);
  }
  const data = await res.json();
  const sheets = data.sheets || [];

  // Try to find the tab matching SHEET_TAB, otherwise use first sheet
  for (const s of sheets) {
    if (s.properties?.title === SHEET_TAB) return SHEET_TAB;
  }
  // Fallback: first sheet
  if (sheets.length > 0) return sheets[0].properties.title;
  throw new Error("No sheets found in spreadsheet");
}

async function appendRow(
  accessToken: string,
  spreadsheetId: string,
  sheetTab: string,
  values: (string | number | boolean | null)[]
): Promise<void> {
  const range = encodeURIComponent(`${sheetTab}!A:A`);
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/${range}:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      values: [values],
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Sheets append failed: ${res.status} ${text}`);
  }
}

async function getAllRows(
  accessToken: string,
  spreadsheetId: string,
  tabName: string
): Promise<string[][]> {
  const range = encodeURIComponent(tabName);
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/${range}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to read sheet: ${res.status} ${text}`);
  }
  const data = await res.json();
  return data.values || [];
}

async function updateRow(
  accessToken: string,
  spreadsheetId: string,
  sheetTab: string,
  rowIndex: number,
  values: (string | number | boolean | null)[]
): Promise<void> {
  const range = encodeURIComponent(`${sheetTab}!A${rowIndex + 1}`);
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/${range}?valueInputOption=USER_ENTERED`;

  const res = await fetch(url, {
    method: "PUT",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      values: [values],
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Sheets update failed: ${res.status} ${text}`);
  }
}

// --- Main handler ---

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  try {
    const surveyData = await req.json();

    // Read credentials from environment (set via `supabase secrets set`)
    const clientEmail = Deno.env.get("GOOGLE_CLIENT_EMAIL");
    const privateKey = Deno.env.get("GOOGLE_PRIVATE_KEY");

    if (!clientEmail || !privateKey) {
      throw new Error("Missing Google service account credentials in env");
    }

    // Unescape newlines in private key (stored as literal \n in env)
    const key = privateKey.replace(/\\n/g, "\n");

    const accessToken = await getAccessToken(clientEmail, key);

    const spreadsheetId = SPREADSHEET_ID;

    // Auto-detect the correct sheet tab name
    const sheetTab = await getSheetTabName(accessToken, spreadsheetId);

    // Build row values from survey data in column order
    const row = COLUMNS.map((col) => {
      const val = surveyData[col];
      if (val === null || val === undefined) return "";
      if (Array.isArray(val)) return val.join(", ");
      if (typeof val === "object") return JSON.stringify(val);
      return val;
    });

    const surveyId = surveyData["id"] || surveyData["_id"];
    let action = "appended";

    if (surveyId) {
      // Try to find the existing row by id (column A, index 0) and update it
      const rows = await getAllRows(accessToken, spreadsheetId, sheetTab);
      let matchIndex = -1;
      for (let i = 1; i < rows.length; i++) {
        if ((rows[i][0] || "").trim() === surveyId.toString().trim()) {
          matchIndex = i;
          break;
        }
      }

      if (matchIndex !== -1) {
        // Preserve the original id and sl_no from the sheet row
        row[0] = rows[matchIndex][0] || row[0]; // id
        row[1] = rows[matchIndex][1] || row[1]; // sl_no
        await updateRow(accessToken, spreadsheetId, sheetTab, matchIndex, row);
        action = "updated";
      } else {
        await appendRow(accessToken, spreadsheetId, sheetTab, row);
      }
    } else {
      await appendRow(accessToken, spreadsheetId, sheetTab, row);
    }

    return new Response(JSON.stringify({ success: true, action }), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (error) {
    console.error("sync-to-sheets error:", error);
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }
});
