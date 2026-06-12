# Supabase Functions, Satellite Math, and AI Advisory

This document explains the Supabase Edge Functions used by the Kalsubai / GrainRight Flutter app, the satellite disease-screening math, and the Qwen advisory layer.

The important boundary: satellite and AI outputs are **risk screening and farmer guidance**, not confirmed disease diagnosis, yield prediction, income prediction, pesticide prescription, or fertilizer-dose recommendation.

## Runtime Bases

The Flutter app uses two Supabase config classes:

- `SupabaseConfig.edgeFunctionsBase`: general survey / sheet / notification functions.
- `SatelliteConfig.edgeFunctionsBase`: satellite, farm, disease, and advisory functions.

Both point to:

```text
https://udbnskydigoqpxmmduvr.supabase.co/functions/v1
```

The app also uses direct Supabase REST endpoints for tables such as `farms`, `disease_scout_zones`, `disease_risk_cells`, and `farmer_phone_profiles`. Those are not Edge Functions, but they are part of the same backend contract.

## Function Inventory

| Function route | Called by app | Local source present | Purpose |
|---|---:|---:|---|
| `sync-to-sheets` | Yes | Yes | Append sanitized survey data into Google Sheets. |
| `delete-from-sheets` | Yes | Yes | Delete a survey row from Google Sheets by farmer/date/mobile match. |
| `farm-status-notify` | Yes | Yes | Acknowledge farm status updates so the app does not fail on missing notification backend. |
| `disease-risk-screen` | Yes | Yes | Run satellite disease-risk screening and write risk cells/scout zones. |
| `farm-alert-advisor` | Yes | Yes | Use Qwen to convert disease/weather data into simple Farm tab alerts. |
| `get-available-dates` | Yes | No local source in this checkout | Expected deployed dependency for satellite date availability. |
| `agricultural-indices` | Yes | No local source in this checkout | Expected deployed dependency for map tiles and index stats. |
| `farm-timeline` | Yes | No local source in this checkout | Expected deployed dependency for per-farm historical index timeline. |
| `diagnostics` | Yes | Yes | Satellite diagnostics for polygon/farm health analysis. |
| `advanced-monitoring` | Yes | No local source in this checkout | Expected deployed dependency for multi-window trend monitoring. |
| `sync-satellite-dates` | Yes, fire-and-forget | No local source in this checkout | Expected deployed dependency to refresh/crawl satellite date metadata. |
| `admin-survey-export` | Not from Flutter user flow | Yes | Admin export of survey data from Supabase views. |
| `setup-sheet-headers` | Not from Flutter user flow | Yes | One-off Google Sheet header setup helper. |
| `disease-image-diagnose` | Not wired in current Flutter service | Yes | Qwen/VLM image triage scaffold for disease photo submissions. RAG-grounded. |
| `farm-alert-advisor` (grounded) | Yes | Yes | RAG-grounded Qwen alerts (see Knowledge Base section). |
| `knowledge-ingest` | One-off admin | Yes | Embeds curated agronomy knowledge into `agronomy_knowledge` for RAG. |
| `weather` | Not wired in current Flutter service | Yes | Open-Meteo historical hourly weather proxy endpoint. |

## App Call Map

### Survey to Google Sheets

Client:

- `lib/services/sheets_sync_service.dart`

Functions:

- `sync-to-sheets`
- `delete-from-sheets`

Flow:

1. The app sanitizes survey data with `sanitizeSurveyForSheet`.
2. It posts JSON to `sync-to-sheets`.
3. The function authenticates to Google Sheets using service-account env vars.
4. It appends the row into spreadsheet tab `FarmerSurveys_updated`.
5. Deletion posts farmer matching fields to `delete-from-sheets`, which finds a row and deletes it through Google Sheets `batchUpdate`.

Required Supabase function env:

- `GOOGLE_CLIENT_EMAIL`
- `GOOGLE_PRIVATE_KEY`

Important note: these functions use Google service-account JWT signing. They should never receive private-key material from the client.

### Farm Status Notification

Client:

- `lib/services/farm_status_notification_service.dart`
- Triggered after a status-chat update in `lib/screens/farmer_home_screen.dart`.

Function:

- `farm-status-notify`

Input shape:

```json
{
  "type": "farm_status_update",
  "farmerId": "FMR-2026-001",
  "farmerName": "Farmer Name",
  "farmName": "Farm Name",
  "crop": "Millet",
  "variety": "Local",
  "location": "Kalsubai",
  "stage": "Vegetative",
  "stageQuestion": "question shown to farmer",
  "daysAfterSowing": 32,
  "statusText": "farmer answer",
  "priorStatus": "previous status",
  "source": "farmer_dashboard_status_chat",
  "updatedAt": "ISO timestamp"
}
```

Current behavior:

- Validates required fields.
- Returns `success: true`, `delivered: true`, and echoes a normalized event.
- It does not yet send SMS, push, WhatsApp, or persist to a notification table.

Why it exists:

- The app already called `/farm-status-notify`.
- Without a deployed function, Supabase returned `404 Requested function was not found`.
- The current function stabilizes the backend contract and can later be extended to insert into a table or call a messaging provider.

### Satellite Dates, Map Indices, Timeline

Client:

- `lib/services/satellite_service.dart`

Routes:

- `get-available-dates?farm_id=...&months=6`
- `agricultural-indices?index=...&start=...&end=...&farm_id=...`
- `farm-timeline?farm_id=...`
- `sync-satellite-dates?farm_id=...`

Expected outputs:

- `get-available-dates`: `available_dates[]` with date, satellite, cloud cover, tile id, and available indices.
- `agricultural-indices`: `satellites[]` with tile URL format and summary stats.
- `farm-timeline`: `timeline` map keyed by observation date, with index rows inside each date.
- `sync-satellite-dates`: no critical response; app calls it fire-and-forget.

Local source status:

- These routes are referenced by the Flutter client but their source directories are not present in this checkout.
- Treat them as deployed dependencies. If they are missing in Supabase, the app will need local function sources restored or rewritten.

### Diagnostics

Client:

- `SatelliteService.getDiagnostics`

Route:

- `diagnostics?polygon=...&farm_id=...&indices=...&days=14&cloud=50`

Purpose:

- Analyze satellite indices over a farm polygon.
- Return per-index summary stats, problem flags, cell stats, raster URL formats, metadata, cache state, and bounds.

Core outputs parsed by Flutter:

- `analysis`: map of index to `mean`, `min`, `max`, `stdDev`, threshold state, trend data, confidence, and map tile URL format.
- `problems`: list of index-level detected issues.
- `cell_stats`: sampled cell values for map/problem visualization.
- `raster_urls`: URL formats for rendered map rasters.
- `metadata`: analysis window and image count information.

Local implementation notes:

- `diagnostics/index.ts` currently inlines several shared satellite utilities instead of importing the new `_shared` files.
- It uses Google Earth Engine and Supabase caching/storage concepts.

### Advanced Monitoring

Client:

- `SatelliteService.postAdvancedMonitoring`

Route:

- `advanced-monitoring`

Expected output parsed by Flutter:

- `timeseries[]`: algorithm name plus windows with mean, std dev, min, max, pixel count, and cloud cover.
- `trends[]`: Theil-Sen slope, trend direction, p-value, R-squared, confidence interval, and window count.
- `metadata`: farm id, window count, window size, and algorithm count.

Local source status:

- The app calls this route, but local function source is not present in this checkout.

## Disease Risk Screening

Function:

- `disease-risk-screen`

Client:

- `SatelliteService.runDiseaseScreen`
- Called by Farm tab refresh in `FarmerHomeScreen`.

Purpose:

1. Load farm geometry from request body or Supabase `farms`.
2. Pull recent Sentinel-2 imagery from Google Earth Engine.
3. Compute disease-specific optical indices.
4. Compute per-cell disease risk scores.
5. Compute statistically significant scout zones.
6. Persist `disease_risk_cells` and `disease_scout_zones`.
7. Return the scan summary to Flutter.

Input:

```json
{
  "farm_id": "uuid",
  "crop": "rice | millet",
  "growth_stage": "seedling/tillering/vegetative/etc.",
  "season": "kharif | rabi",
  "geometry": { "type": "Polygon", "coordinates": [] },
  "start_date": "optional ISO date",
  "end_date": "optional ISO date"
}
```

Output:

```json
{
  "success": true,
  "scan_date": "YYYY-MM-DD",
  "crop": "rice",
  "growth_stage": "tillering",
  "season": "kharif",
  "images_analyzed": 4,
  "risk_cells_count": 120,
  "high_risk_cells": 18,
  "scout_zones": [],
  "weather_context": {
    "hours_blast_temp_window": 40,
    "leaf_wetness_hours": 30,
    "total_rain_mm": 30,
    "mean_temp_c": 26
  },
  "top_disease_risks": {
    "rice_blast": 0.42,
    "sheath_blight": 0.31
  }
}
```

### Data Sources

Satellite:

- Sentinel-2 Surface Reflectance Harmonized: `COPERNICUS/S2_SR_HARMONIZED`
- Current scan window defaults to last 14 days.
- Cloud filter: `CLOUDY_PIXEL_PERCENTAGE < 30`.

Baseline:

- Prior 56 days of Sentinel-2 NDVI.
- Used for per-pixel NDVI baseline and standard deviation.

Thermal confounder:

- Landsat 8/9 Collection 2 L2 `ST_B10`, widened by 21 days around the optical window.
- Fallback to MODIS `MODIS/061/MOD11A2` if Landsat thermal is unavailable.
- Used only to suppress likely abiotic/drought stress, never to raise disease risk.

Weather:

- Open-Meteo hourly temperature, relative humidity, precipitation.
- Seven-day lookback plus one forecast day.
- Used for wetness, rain, and disease-conducive temperature windows.

### Optical Disease Indices

The disease pipeline computes these per-pixel features:

| Feature | Formula / meaning | Used for |
|---|---|---|
| `NDVI` | `(NIR - RED) / (NIR + RED)` | Vegetation vigor and decline from baseline. |
| `NDVI_CV` | local NDVI standard deviation divided by local absolute mean | Patchiness / spatial heterogeneity. |
| `RBVI` | red-edge blast vegetation index from Sentinel-2 bands | Rice blast signal. |
| `CIre` | `(B8 / B5) - 1` | Red-edge chlorophyll decline. |
| `MTCI` | `(B8 - B5) / (B5 - B4)` | Chlorophyll/red-edge stress support. |
| `DWS` | `0.6 * NDMI + 0.4 * NMDI` | Wetness / water stress disease signal. |
| `RIBInir` | approx `(B7 - B8A) / (B4 + B8A)` | Published blast-index proxy. |
| `RIBIred` | approx `(B5 - B8A) / (B4 + B8A)` | Interim BLB red-edge proxy. |
| `REDSI` | red-edge disease stress triangle proxy | Low-weight cross-check. |
| `thermal_stress` | within-field normalized LST stress in `[0,1]` | Suppresses abiotic water-stress false positives. |
| `anomaly_z` | `(NDVI_baseline - NDVI_current) / NDVI_baseline_sd` | Per-cell temporal decline severity. |

Known caveats:

- Several red-edge disease indices are proxy implementations for Sentinel-2 band availability.
- `RIBInir`, `RIBIred`, and `REDSI` are treated as provisional cross-checks, not standalone proof.
- Thermal data is coarser than optical data and should be read as field context, not pixel-precise disease evidence.

### Weather Risk Math

Blast weather risk:

```text
tempScore = hours_temp_20_28c / 72
wetnessScore = leaf_wetness_hours / 60
rhScore = (max_rh_pct - 70) / 30
blastWeatherRisk = 0.45*tempScore + 0.35*wetnessScore + 0.20*rhScore
```

Wet canopy risk:

```text
rainScore = total_rain_mm / 80
wetnessScore = leaf_wetness_hours / 50
wetCanopyRisk = 0.45*rainScore + 0.55*wetnessScore
```

Downy mildew weather risk:

```text
coolScore = (28 - mean_temp_c) / 10
wetnessScore = leaf_wetness_hours / 50
downyMildewWeatherRisk = 0.40*coolScore + 0.60*wetnessScore
```

Dry stress risk:

```text
lowMoisture = (20 - moisture) / 20
dryWeather = max(0, 20 - total_rain_mm) / 20
dryStressRisk = 0.55*lowMoisture + 0.45*dryWeather
```

All component scores are clamped to `[0,1]`.

### Thermal Confounder

The disease model computes a water-stress signature:

```text
dryCanopy = (20 - moisture) / 20
uniform = (0.20 - NDVI_CV) / 0.20
waterStress = 0.50*thermal_stress + 0.30*dryCanopy + 0.20*uniform
likely_abiotic = waterStress >= 0.60
thermalMultiplier = 1 - waterStress*0.45
```

This multiplier is applied to most disease scores:

```text
finalDiseaseScore = rawScore * stageMultiplier * thermalMultiplier
```

The thermal gate prevents hot, dry, spatially uniform decline from being misread as a disease cluster. It only lowers disease risk.

### Growth Stage Multipliers

The model uses crop-stage susceptibility tables:

- Rice blast: highest at tillering, high through panicle initiation and heading.
- Sheath blight: highest at tillering/panicle initiation.
- Bacterial leaf blight: highest in seedling/tillering.
- Millet downy mildew: highest at seedling.
- Millet leaf spot: highest at panicle initiation and heading.
- Charcoal rot: highest at grain fill and late season, only included for rabi millet.

### Per-Disease Models

Rice blast:

```text
spectralAnomaly =
  0.35*RBVI_anomaly +
  0.30*RIBInir_anomaly +
  0.20*CIre_anomaly +
  0.15*MTCI_anomaly

raw =
  0.42*spectralAnomaly +
  0.18*NDVI_decline +
  0.15*moistureScore +
  0.15*blastWeatherRisk +
  0.05*REDSI_check +
  0.05*stageMultiplier

score = clamp01(raw * stageMultiplier * thermalMultiplier)
```

Sheath blight:

```text
heterogeneity = NDVI_CV * 3
warmScore = (mean_temp_c - 20) / 12

raw =
  0.35*heterogeneity +
  0.25*NDVI_decline +
  0.25*wetCanopyRisk +
  0.15*warmScore

score = clamp01(raw * stageMultiplier * thermalMultiplier)
```

Bacterial leaf blight:

```text
waterSignal = (DWS + 1) / 2
stormScore = total_rain_mm / 60

raw =
  0.30*waterSignal +
  0.10*RIBIred_proxy +
  0.20*NDVI_decline +
  0.25*wetCanopyRisk +
  0.15*stormScore

score = clamp01(raw * stageMultiplier * thermalMultiplier)
```

Millet downy mildew:

```text
moistureSignal = (moisture - 15) / 60

raw =
  0.30*NDVI_decline +
  0.25*CIre_signal +
  0.30*downyMildewWeatherRisk +
  0.15*moistureSignal

score = clamp01(raw * stageMultiplier * thermalMultiplier)
```

Millet leaf spot:

```text
heterogeneity = NDVI_CV * 2.5
dwsSignal = (DWS + 1) / 2

raw =
  0.30*heterogeneity +
  0.25*NDVI_decline +
  0.25*wetCanopyRisk +
  0.15*dwsSignal +
  0.05*REDSI_check

score = clamp01(raw * stageMultiplier * thermalMultiplier)
```

Charcoal rot:

```text
raw = 0.55*dryStressRisk + 0.45*NDVI_decline
score = clamp01(raw * stageMultiplier)
```

### Composite Risk

For each sampled cell:

```text
applicable_diseases = crop-specific disease model scores
composite_risk = max(applicable disease scores)
top_disease = highest disease if score > 0.10
scout_priority = low/medium/high based on composite_risk
```

Disease candidates are added to a cell only when individual disease score is above `0.30`.

Severity labels:

- `high`: score `>= 0.65`
- `medium`: score `>= 0.40`
- `low`: below `0.40`

### Scout Zone Hotspot Math

The function samples up to 500 cells at 30 m scale and then clusters risk cells into scout zones.

Constants:

```text
SCOUT_ZONE_MIN_RISK = 0.40
SCOUT_ZONE_MERGE_M = 50
SCOUT_ZONE_MAX = 5
HOTSPOT_DIST_M = 90
HOTSPOT_Z_SIG = 1.96
```

It computes Getis-Ord Gi* z-score for each risk cell:

```text
Gi* = (sum(w*x) - mean(x)*sum(w)) /
      (S * sqrt((n*sum(w^2) - sum(w)^2) / (n-1)))
```

Because weights are binary, `w^2 = w`.

Meaning:

- A cell must have composite risk at least `0.40`.
- A cell must also be in a statistically hot neighborhood with `Gi* >= 1.96`.
- Nearby hot cells within 50 m are merged.
- The function returns at most five scout zones.

Each scout zone contains:

- centroid lat/lng
- radius
- candidate disease names
- max risk score
- cell count
- hotspot z-score
- significance label

### Persistence Tables

The function writes:

- `disease_risk_cells`
- `disease_scout_zones`

Risk cells include:

- location
- composite risk
- per-disease risk columns
- optical indices
- weather risk
- thermal stress
- anomaly z-score
- Gi* z-score
- likely abiotic flag

Scout zones include:

- scan date
- rank
- centroid
- radius
- disease candidates
- max risk
- cell count
- hotspot significance
- crop and growth stage

## Farm Alert Advisor and Qwen

Function:

- `farm-alert-advisor`

Client:

- `SatelliteService.getFarmAlertAdvice`
- Called after `disease-risk-screen` in Farm tab refresh.

Purpose:

- Convert numeric disease/weather screening output into a simple farmer-facing alert list for the Farm tab.
- Use Qwen as a language/planning layer, not as the source of disease detection.

Input from Flutter:

```json
{
  "farm_id": "uuid",
  "farm_name": "Farm Name",
  "crop": "rice | millet",
  "growth_stage": "Vegetative",
  "season": "kharif",
  "local_status": "farmer status text",
  "disease_screen": {},
  "scout_zones": [],
  "risk_cells": [],
  "weather_context": {}
}
```

Output:

```json
{
  "success": true,
  "advice": {
    "important_alerts": [
      {
        "title": "short alert title",
        "detail": "why this matters based on supplied data",
        "severity": "high | medium | low",
        "action": "one concrete next step"
      }
    ],
    "weather_alerts": [],
    "next_actions": [],
    "confidence": "high | medium | low",
    "model": "qwen/qwen3-235b-a22b"
  }
}
```

Qwen env vars:

- `QWEN_API_KEY` or `QWEN3_API_KEY`
- `QWEN_BASE_URL` or `QWEN3_BASE_URL`
- `QWEN_MODEL` or `QWEN3_MODEL`
- optional `QWEN_MODELS` comma-separated fallback list

Default model order:

```text
qwen3-235b-a22b, qwen3-72b, qwen3-32b
```

Request behavior:

- Endpoint: `{baseUrl}/chat/completions`
- Temperature: `0.15`
- `response_format`: `json_object`
- `extra_body.enable_thinking`: `false`
- If a model returns `400` or `404`, the function tries the next configured model.

Prompt rules:

- Return only valid JSON.
- Do not recommend pesticide brands.
- Do not provide chemical doses.
- Do not provide exact fertilizer rates.
- Do not make yield or income claims.
- Treat disease screening as risk pre-screening, not confirmed diagnosis.
- Use plain action language.
- Prefer scout, verify, drain, cover, delay, and monitor actions before treatment advice.

Normalization:

- Invalid or incomplete alerts are dropped.
- Severity is normalized to `high`, `medium`, or `low`.
- Alerts are capped to three important alerts and three weather alerts.
- Next actions are capped to four.

Failure behavior:

- If Qwen is not configured or returns invalid output, the function returns a Supabase error response.
- Flutter shows the error in the Farm tab alert area.

## Disease Image Diagnosis

Function:

- `disease-image-diagnose`

Current app status:

- Local function source exists.
- The current Flutter Farm tab does not call it.
- The recent Qwen integration uses text advisory only, not image diagnosis.

Purpose:

- Given a `farmer_photo_submissions` row, signs a private storage URL from bucket `disease-photos`.
- Calls a vision-language model using `VLM_API_KEY`, `QWEN_VL_API_KEY`, or `QWEN_API_KEY`.
- Updates the photo submission with normalized triage JSON.

Safety boundary:

- It is visual triage only.
- It must not claim lab confirmation.
- It should say visual review is needed when image quality is unclear.

## Knowledge Base and RAG Grounding

The Qwen advisory layer (`disease-image-diagnose` and `farm-alert-advisor`) is grounded with retrieved ICAR crop knowledge instead of relying on the model's generic prior. This is the single highest-leverage improvement to diagnosis and mitigation quality, and it keeps the system inside the existing Supabase stack.

### Why RAG, not a trained model

- No labeled image dataset exists yet (`farmer_photo_submissions.diagnosis_result` is model output, not ground truth). For a handful of crops with scarce labels, grounding a strong VLM with retrieved reference symptoms beats training a custom classifier.
- `pgvector` on the existing Supabase Postgres is the cheapest production-grade vector store below ~50M vectors. No separate vector service (Pinecone/Qdrant) and no multi-step agent are needed at this scale.
- Future fine-tuning trigger: once the data loop accumulates roughly 150–300 confirmed-labeled photos per disease, a CLIP/VLM adapter fine-tune (e.g. on Colab Pro) becomes worthwhile. Until then, retrieval grounding is the right tool.

### Storage

Migration: `supabase/migrations/20260613090000_agronomy_knowledge_rag.sql`.

- Table `agronomy_knowledge`: `crop`, `doc_source`, `chunk_type` (`symptom`/`mitigation`/`idm`/`variety`/`crop_cycle`/`grading`/`climate`/`district`), nullable `disease`/`growth_stage`/`district`, `content`, `metadata` jsonb, `embedding vector(1024)`. HNSW cosine index plus a `(crop, chunk_type)` btree.
- RPC `match_agronomy_knowledge(query_embedding, filter_crop, match_count, filter_disease)` returns top-k by cosine similarity with a crop pre-filter.
- Data loop: `farmer_photo_submissions` gains `confirmed_label`, `label_source`, `labeled_at` so an agronomist/scout can confirm the true disease, building the dataset for future fine-tuning. (Pairs with the existing `disease_scout_zones.status` `confirmed`/`cleared` field.)

### Knowledge content

`supabase/functions/_shared/knowledge/finger_millet.json` holds curated records authored from the ICAR Finger Millet (Maharashtra 2026) report — per-disease symptom and mitigation pairs (blast, rust, downy mildew, seedling blight/foot rot, brown spot), the IDM checklist, varietal disease resistance, stage-wise disease watch, district notes, and grading. Rice and bajra are extensible: add `rice.json` / `bajra.json` (you supply the source docs), register them in `knowledge-ingest`, and re-run.

Mitigation safety policy: farmer-facing `content` stays on cultural/IDM/varietal advice. Chemical actives are kept in `metadata` (`*_agronomist_only`) and the prompts instruct the model to say "consult a KVK/agronomist for the dose" rather than prescribing — consistent with the existing advisor rules.

### Retrieval flow

`supabase/functions/_shared/knowledge-retrieval.ts` exposes `retrieveKnowledge({ crop, growthStage, diseaseCandidates, queryText, k })`: it embeds the query via DashScope `text-embedding-v3` (1024-dim, reuses `QWEN_API_KEY`), calls the RPC, and `formatKnowledge` renders the chunks into a reference block. Crop labels are normalized to `rice`/`millet`. Retrieval is best-effort — any failure returns no chunks so the underlying Qwen call still proceeds ungrounded.

Both consumers extract candidate diseases from `top_disease_risks` (satellite context / `disease_screen`) and inject the reference block before the model call. Response schemas are unchanged, so the Flutter contracts (`DiagnosisPayload`, `FarmAlertAdvice`) are unaffected.

### Ingestion

`knowledge-ingest` (one-off, admin) embeds each record and upserts idempotently by `doc_source` (delete-then-insert). Optionally gated by `INGEST_SECRET` via the `x-ingest-secret` header. Run once after the migration, and again whenever a knowledge file changes.

### Env vars

- `QWEN_EMBED_MODEL` (default `text-embedding-v3`), optional `QWEN_EMBED_API_KEY` / `QWEN_EMBED_BASE_URL` (fall back to `QWEN_API_KEY` / `QWEN_BASE_URL`).
- Optional `INGEST_SECRET`.

## Weather Function

Function:

- `weather`

Current app status:

- Local source exists.
- The current Flutter service does not call it directly.
- `disease-risk-screen` fetches Open-Meteo internally for disease screening.

Purpose:

- GET archived Open-Meteo hourly weather for a lat/lng and date window.

Required query params:

- `latitude`
- `longitude`
- `start_date`
- `end_date`

Returns:

- hourly temperature
- precipitation
- apparent temperature
- wind speed
- cloud cover
- weather code

## Admin and Sheet Setup Functions

### `admin-survey-export`

Purpose:

- Exports survey data from Supabase views:
  - `farmer_surveys_export`
  - `survey_kharif_crops_export`
  - `survey_main_crop_yearly_export`
  - `survey_crop_practices_export`

Modes:

- `GET /admin-survey-export?summary=1` returns summary.
- `GET /admin-survey-export` returns structured export payload.

Required env:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

### `setup-sheet-headers`

Purpose:

- Creates or updates the Google Sheet header row to match the survey export column contract.

Required env:

- `GOOGLE_CLIENT_EMAIL`
- `GOOGLE_PRIVATE_KEY`

This is an operational helper, not a normal Flutter user-flow function.

## Shared Utilities

### `_shared/cors.ts`

Defines:

- permissive CORS headers
- `handleCors(req)` for `OPTIONS`

### `_shared/response.ts`

Defines:

- `successResponse(data, status = 200)`
- `errorResponse(message, status = 500, error?)`

Response format:

```json
{
  "success": true
}
```

or

```json
{
  "success": false,
  "error": "message",
  "details": "optional error detail"
}
```

### `_shared/satellite-utils.ts`

Defines:

- Google Earth Engine initialization from server env.
- satellite configs for Sentinel-2, Landsat 8/9, Sentinel-1.
- band harmonization utilities.
- index availability map.

Required env:

- `GOOGLE_PRIVATE_KEY`
- `GOOGLE_CLIENT_EMAIL`

### `_shared/optical-algorithms.ts`

Contains advanced satellite algorithms:

- OPTRAM moisture model.
- PCA-style phosphorus and potassium index scaffolds.
- nitrogen estimation using GNDVI/NDRE.
- disease indices used by disease screening.

### `_shared/thermal-utils.ts`

Contains:

- Landsat/MODIS LST loading.
- cloud/shadow masking.
- within-field thermal stress scaling.
- neutral fallback if no thermal data exists.

### `_shared/disease-models.ts`

Contains:

- disease-specific risk formulas
- growth-stage susceptibility tables
- weather scoring
- thermal confounder
- crop-level risk dispatcher

## Deployment Checklist

Functions that must be deployed for the current app surface:

- `sync-to-sheets`
- `delete-from-sheets`
- `farm-status-notify`
- `disease-risk-screen`
- `farm-alert-advisor`
- `diagnostics`
- `get-available-dates`
- `agricultural-indices`
- `farm-timeline`
- `advanced-monitoring`
- `sync-satellite-dates`

Functions present locally but optional for current app flows:

- `admin-survey-export`
- `setup-sheet-headers`
- `disease-image-diagnose`
- `knowledge-ingest` (run once after applying the agronomy_knowledge migration)
- `weather`

Recommended verification commands:

```bash
deno check supabase/functions/farm-status-notify/index.ts \
  supabase/functions/disease-risk-screen/index.ts \
  supabase/functions/farm-alert-advisor/index.ts

flutter test
```

Live smoke-test pattern:

```bash
curl -i -X POST \
  "$SUPABASE_URL/functions/v1/farm-status-notify" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  --data '{"farmerId":"FMR-test","farmerName":"Test","farmName":"Test Farm","stage":"Vegetative","statusText":"Healthy"}'
```

Expected result:

```text
HTTP 200
{"success":true,"delivered":true,...}
```

## Known Gaps and Risks

- Several app-called satellite routes are not present in local source: `get-available-dates`, `agricultural-indices`, `farm-timeline`, `advanced-monitoring`, and `sync-satellite-dates`.
- `farm-status-notify` currently acknowledges events but does not persist or send a real notification.
- `farm-alert-advisor` depends on Qwen server-side env vars. If keys are missing or invalid, Farm tab alert refresh will show an advisor error.
- `disease-risk-screen` depends on Earth Engine credentials and Supabase table schema for disease risk cells and scout zones.
- Disease math is a triage model. Field scouting is mandatory before agronomic intervention.
- The app currently hardcodes Supabase public anon config in Flutter config files. Public anon keys are expected in client apps, but private service-role, Qwen, and Google private keys must remain only in Supabase Edge Function environment.

