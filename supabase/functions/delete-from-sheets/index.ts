import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  encode as base64url,
} from "https://deno.land/std@0.177.0/encoding/base64url.ts";

const SPREADSHEET_ID = "1fBcF0aSwT0m0YKb12DsNos8Ou_jrRLO0PWpVU048Lqg";
const SHEET_TAB = "FarmerSurveys_updated";

// Column indices must match the Google Sheet layout (0-indexed).
// Sheet order: id(0), sl_no(1), survey_date(2), season(3), farmer_name(4),
// gender(5), date_of_birth(6), category(7), education_level(8), village_gp(9),
// block(10), district(11), fpc_name(12), aadhar_no(13), mobile_no(14), ...
const FARMER_NAME_COL = 4; // column E (farmer_name)
const SURVEY_DATE_COL = 2; // column C (survey_date)
const MOBILE_NO_COL = 14; // column O (mobile_no)

// --- JWT / Google Auth helpers (shared with sync-to-sheets) ---

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

async function getSheetInfo(
  accessToken: string,
  spreadsheetId: string
): Promise<{ tabName: string; sheetId: number }> {
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

  for (const s of sheets) {
    if (s.properties?.title === SHEET_TAB) {
      return { tabName: SHEET_TAB, sheetId: s.properties.sheetId };
    }
  }
  if (sheets.length > 0) {
    return {
      tabName: sheets[0].properties.title,
      sheetId: sheets[0].properties.sheetId,
    };
  }
  throw new Error("No sheets found in spreadsheet");
}

async function getAllRows(
  accessToken: string,
  spreadsheetId: string,
  tabName: string
): Promise<string[][]> {
  const range = encodeURIComponent(`${tabName}`);
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

async function deleteRow(
  accessToken: string,
  spreadsheetId: string,
  sheetId: number,
  rowIndex: number
): Promise<void> {
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}:batchUpdate`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      requests: [
        {
          deleteDimension: {
            range: {
              sheetId,
              dimension: "ROWS",
              startIndex: rowIndex,
              endIndex: rowIndex + 1,
            },
          },
        },
      ],
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to delete row: ${res.status} ${text}`);
  }
}

// --- Main handler ---

serve(async (req: Request) => {
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
    const body = await req.json();
    const { farmer_name, survey_date, mobile_no } = body;

    if (!farmer_name) {
      return new Response(
        JSON.stringify({ error: "farmer_name is required" }),
        { status: 400, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    const clientEmail = Deno.env.get("GOOGLE_CLIENT_EMAIL");
    const privateKey = Deno.env.get("GOOGLE_PRIVATE_KEY");

    if (!clientEmail || !privateKey) {
      throw new Error("Missing Google service account credentials in env");
    }

    const key = privateKey.replace(/\\n/g, "\n");
    const accessToken = await getAccessToken(clientEmail, key);

    const { tabName, sheetId } = await getSheetInfo(accessToken, SPREADSHEET_ID);
    const rows = await getAllRows(accessToken, SPREADSHEET_ID, tabName);

    // Find the matching row (skip header row at index 0)
    let matchIndex = -1;
    for (let i = 1; i < rows.length; i++) {
      const row = rows[i];
      const nameMatch = (row[FARMER_NAME_COL] || "").trim().toLowerCase() === farmer_name.trim().toLowerCase();
      const dateMatch = !survey_date || (row[SURVEY_DATE_COL] || "").trim() === survey_date.trim();
      const mobileMatch = !mobile_no || (row[MOBILE_NO_COL] || "").trim() === mobile_no.trim();

      if (nameMatch && dateMatch && mobileMatch) {
        matchIndex = i;
        break;
      }
    }

    if (matchIndex === -1) {
      return new Response(
        JSON.stringify({ success: false, message: "Row not found in sheet" }),
        { status: 404, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
      );
    }

    await deleteRow(accessToken, SPREADSHEET_ID, sheetId, matchIndex);

    return new Response(
      JSON.stringify({ success: true, deletedRow: matchIndex }),
      { status: 200, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
    );
  } catch (error) {
    console.error("delete-from-sheets error:", error);
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } }
    );
  }
});
