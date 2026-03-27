/**
 * Supabase Webhook → Google Sheets
 * Table: farmer_surveys
 *
 * SETUP:
 * 1. Open your Google Sheet → Extensions → Apps Script → paste this file
 * 2. Replace SHEET_ID below with your Google Sheet ID (from the URL)
 * 3. Deploy → New deployment → Web app → Execute as: Me → Who has access: Anyone
 * 4. Copy the Web App URL → use it as the Supabase webhook endpoint
 */

const SHEET_ID = 'YOUR_GOOGLE_SHEET_ID_HERE'; // <-- replace this
const SHEET_NAME = 'farmer_surveys';

const SUPABASE_URL  = 'https://hjgevqhpmcuwieqtorfj.supabase.co';
const SUPABASE_KEY  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhqZ2V2cWhwbWN1d2llcXRvcmZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE5MzYwNTMsImV4cCI6MjA4NzUxMjA1M30.WbIz4Uq39NjQqqTCO819Al3niiDxcIJkvO_1bG6k5OI';
const TABLE         = 'farmer_surveys';
const PAGE_SIZE     = 1000;

// These columns will always appear first in that order.
// Any new columns from the payload are appended automatically after these.
const PINNED_COLS = ['id', 'farmer_name', 'survey_date', 'season', 'district'];

// ---------- header helpers ----------

/** Read the current header row from the sheet (row 1). Returns [] if sheet is empty. */
function getHeaders(sheet) {
  if (sheet.getLastColumn() === 0) return [];
  return sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(String);
}

/**
 * Ensure all keys from the record exist as columns.
 * New keys are appended to the right. Returns the updated headers array.
 */
function ensureColumns(sheet, record) {
  let headers = getHeaders(sheet);

  // First time — seed with pinned cols
  if (headers.length === 0) {
    headers = [...PINNED_COLS];
    sheet.appendRow(headers);
    sheet.getRange(1, 1, 1, headers.length).setFontWeight('bold');
    sheet.setFrozenRows(1);
  }

  // Find keys in the record that aren't in the sheet yet
  const allKeys = Object.keys(record);
  const newKeys = allKeys.filter((k) => !headers.includes(k));

  if (newKeys.length > 0) {
    headers = headers.concat(newKeys);
    // Write the full updated header row
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    sheet.getRange(1, headers.length - newKeys.length + 1, 1, newKeys.length)
      .setFontWeight('bold')
      .setBackground('#fff2cc'); // highlight new columns in yellow
  }

  return headers;
}

// ---------- row helpers ----------

function getOrCreateSheet() {
  const ss = SpreadsheetApp.openById(SHEET_ID);
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) sheet = ss.insertSheet(SHEET_NAME);
  return sheet;
}

function findRowById(sheet, headers, id) {
  const idCol = headers.indexOf('id');
  if (idCol < 0 || sheet.getLastRow() < 2) return -1;
  const data = sheet.getRange(2, idCol + 1, sheet.getLastRow() - 1, 1).getValues();
  for (let i = 0; i < data.length; i++) {
    if (String(data[i][0]) === String(id)) return i + 2; // 1-based
  }
  return -1;
}

function recordToRow(headers, record) {
  return headers.map((h) => {
    const val = record[h];
    if (val === null || val === undefined) return '';
    return val;
  });
}

// ---------- main entry point ----------

function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents);
    const eventType = payload.type;       // INSERT | UPDATE | DELETE
    const record    = payload.record;     // new row data
    const oldRecord = payload.old_record; // previous data (UPDATE / DELETE)

    const sheet   = getOrCreateSheet();
    const headers = ensureColumns(sheet, record || oldRecord);
    const row     = recordToRow(headers, record || {});

    if (eventType === 'INSERT') {
      sheet.appendRow(row);

    } else if (eventType === 'UPDATE') {
      const rowNum = findRowById(sheet, headers, record.id);
      if (rowNum > 0) {
        sheet.getRange(rowNum, 1, 1, headers.length).setValues([row]);
      } else {
        sheet.appendRow(row); // not found — append
      }

    } else if (eventType === 'DELETE') {
      const rowNum = findRowById(sheet, headers, oldRecord.id);
      if (rowNum > 0) sheet.deleteRow(rowNum);
    }

    return ContentService
      .createTextOutput(JSON.stringify({ status: 'ok', event: eventType }))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    try {
      const ss = SpreadsheetApp.openById(SHEET_ID);
      let errSheet = ss.getSheetByName('webhook_errors');
      if (!errSheet) errSheet = ss.insertSheet('webhook_errors');
      errSheet.appendRow([new Date().toISOString(), err.toString(), e.postData ? e.postData.contents : '']);
    } catch (_) {}

    return ContentService
      .createTextOutput(JSON.stringify({ status: 'error', message: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// ---------- backfill existing data ----------

/**
 * Run this ONCE manually from the Apps Script editor:
 *   Run → backfill
 * It fetches every row from Supabase and writes it to the sheet.
 * Safe to re-run — it updates existing rows instead of duplicating them.
 */
function backfill() {
  const sheet = getOrCreateSheet();
  let offset = 0;
  let totalWritten = 0;

  while (true) {
    const url = `${SUPABASE_URL}/rest/v1/${TABLE}?select=*&order=created_at.asc&limit=${PAGE_SIZE}&offset=${offset}`;
    const response = UrlFetchApp.fetch(url, {
      method: 'GET',
      headers: {
        'apikey': SUPABASE_KEY,
        'Authorization': `Bearer ${SUPABASE_KEY}`,
        'Range-Unit': 'items',
      },
      muteHttpExceptions: true,
    });

    if (response.getResponseCode() !== 200) {
      Logger.log('Supabase error: ' + response.getContentText());
      break;
    }

    const rows = JSON.parse(response.getContentText());
    if (rows.length === 0) break; // no more data

    // Ensure all columns exist for this page
    ensureColumns(sheet, rows[0]);

    for (const record of rows) {
      // Re-fetch headers each iteration in case ensureColumns added new ones
      const currentHeaders = getHeaders(sheet);
      const row = recordToRow(currentHeaders, record);
      const existingRowNum = findRowById(sheet, currentHeaders, record.id);
      if (existingRowNum > 0) {
        sheet.getRange(existingRowNum, 1, 1, currentHeaders.length).setValues([row]);
      } else {
        sheet.appendRow(row);
      }
      totalWritten++;
    }

    Logger.log(`Written ${totalWritten} rows so far...`);
    if (rows.length < PAGE_SIZE) break; // last page
    offset += PAGE_SIZE;
  }

  Logger.log(`Backfill complete. Total rows written: ${totalWritten}`);
  SpreadsheetApp.getUi().alert(`Backfill complete! ${totalWritten} rows loaded.`);
}

// ---------- manual test ----------

function testInsert() {
  const mockEvent = {
    postData: {
      contents: JSON.stringify({
        type: 'INSERT',
        table: 'farmer_surveys',
        schema: 'public',
        record: {
          id: 'test-uuid-001',
          farmer_name: 'Test Farmer',
          village_gp: 'Test Village',
          district: 'Test District',
          survey_date: '2026-03-27',
          season: 'Kharif',
          // simulate a brand-new field added to the table
          new_experimental_field: 'some_value',
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        },
        old_record: null,
      }),
    },
  };
  const result = doPost(mockEvent);
  Logger.log(result.getContent());
}
