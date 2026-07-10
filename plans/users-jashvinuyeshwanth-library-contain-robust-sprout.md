//pl# MilletsNow Mobile — Chatbot Baseline Survey + Pencil Polygon + Diagnostics

## Context

The baseline farmer questionnaire delivered as `Base line Que.docx- Swati.docx` (extracted; see [Appendix A](#appendix-a--baseline-questionnaire-content)) is substantially more detailed than the current `farmer_surveys` schema in `millets-now-mobile`. It captures family/farm metadata, Kharif crop tables, granular agronomy steps (seed treatment, raised-bed vs Rab method seedling prep, transplanting, weeding, organic spray practices, harvesting), 3-year production history, post-harvest products, and income breakdown for both the main millet crop and other crops.

Simultaneously, the sister web app at [/Users/jashvinuyeshwanth/Desktop/wrkfarm/sentinel-agro-insight-1/](../../../Desktop/wrkfarm/sentinel-agro-insight-1) added two features the user wants on mobile:
1. **Pencil freehand polygon drawing** for farm boundary capture (with Ramer–Douglas–Peucker simplification, see [src/utils/polygonSimplify.ts](../../../Desktop/wrkfarm/sentinel-agro-insight-1/src/utils/polygonSimplify.ts) and [src/pages/DrawPolygon.tsx](../../../Desktop/wrkfarm/sentinel-agro-insight-1/src/pages/DrawPolygon.tsx)).
2. **Diagnostic plan generation** combining satellite indices + Gemini RAG advisory.

**Goal:** Replace the step-form UI with a guided chatbot conversation that walks the farmer through the new baseline questionnaire, embeds a pencil-style farm boundary capture, supports Marathi/Hindi/English, and exposes a separate "Diagnostics" entry point on the home screen that opens a dedicated diagnostics page after the farmer has submitted their baseline data.

**User decisions captured:**
- Chatbot is the new default; the existing step-form stays accessible at `/form/classic` for fallback.
- Pencil drawing is true freehand drag-to-stroke; simplify on release via RDP.
- Diagnostics is **not** inline in the chatbot — it's a separate page reached from a home-screen button shown after a baseline survey is submitted.
- Languages: English, Hindi, Marathi (the questionnaire uses Marathi terms — Nachani, Jeevamrut, Gomitra, Rab method, Matka spray).
- Chatbot is **rules-based / scripted** — questions come from `form_config` in a fixed order; no LLM in the chat flow.
- No voice input in this phase.
- Database is fully redesigned to match the new questionnaire (a new migration; old `farmer_surveys` rows will be dropped or migrated to a `farmer_surveys_legacy` table — see [Phase 2](#phase-2--database-redesign)).

---

## Phase 1 — Project setup

### 1.1 Branch & toolchain
- Work on the existing worktree branch `claude/priceless-greider-4e94d5`.
- Verify Flutter SDK + Dart version against [pubspec.yaml](pubspec.yaml).
- Run `flutter pub get` after each pubspec change.

### 1.2 New dependencies (add to [pubspec.yaml](pubspec.yaml))
```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2          # already present
  # Markdown rendering for diagnostic advisory bubble
  flutter_markdown: ^0.7.4
  # (Optional, only if Gemini direct-call is preferred over Supabase edge functions)
  # google_generative_ai: ^0.4.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.4
```
*No new map plugins required* — `google_maps_flutter`, `flutter_map`, `latlong2`, `geolocator` already present.

### 1.3 Env additions ([.env](.env))
```
GEMINI_API_KEY=...            # only if direct Gemini call is used; otherwise this lives in the Supabase edge function secret
SATELLITE_FUNCTIONS_BASE=https://udbnskydigoqpxmmduvr.supabase.co/functions/v1
```
The satellite Supabase URL + anon key already live in [lib/config/satellite_config.dart](lib/config/satellite_config.dart) and remain hard-coded there; no migration needed for those.

---

## Phase 2 — Database redesign

Author the migrations inside [supabase/migrations/](supabase/migrations/) on the **main** Supabase project (`hjgevqhpmcuwieqtorfj`). The satellite project schema is unchanged.

### 2.1 Migration: `YYYYMMDDhhmmss_baseline_survey_v2.sql`

**Drop / archive old tables** (in a single migration so RLS policies move atomically):
```sql
alter table public.farmer_surveys rename to farmer_surveys_legacy_v1;
-- form_sections / form_fields / dropdown_options stay but get seeded with new rows in 2.4
```

**New core survey table** (one row per farmer per survey date):
```sql
create table public.farmer_surveys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  survey_date date not null default current_date,
  language text not null default 'en' check (language in ('en','hi','mr')),
  location_lat double precision,
  location_lng double precision,
  location_accuracy_m double precision,
  started_at timestamptz,
  submitted_at timestamptz,

  -- Family
  farmer_name text not null,
  village text,
  gram_panchayat text,
  taluka text,
  district text,
  mobile_number text,
  aadhaar_number text,
  date_of_birth date,
  education text,
  gender text,
  category text,

  -- Land & farming overview
  income_sources text[] default '{}'::text[],    -- farming/business/govt_job/private_job/other
  farming_type text[] default '{}'::text[],       -- rainfed/irrigated/other
  owns_farmland boolean,
  total_land_area_acre numeric,
  irrigated_land_acre numeric,
  dry_land_acre numeric,
  fallow_land_acre numeric,
  leased_land_acre numeric,
  rain_based_area_acre numeric,
  has_forest_patta boolean,
  forest_patta_acre numeric,
  applied_for_forest_patta boolean,

  -- Main millet crop choice
  main_crop text,                                 -- paddy/nachani/bajra/other
  main_crop_other text,
  main_crop_land_acre numeric,

  -- Farm boundary
  farm_polygon jsonb,                             -- GeoJSON Polygon, lng/lat order

  -- Income & food products (rollups)
  annual_agri_income numeric,
  non_agri_income numeric,
  total_annual_income numeric,
  makes_food_products boolean,
  food_products_list text,
  food_product_training_received boolean,
  food_product_training_source text,

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index farmer_surveys_user_idx on public.farmer_surveys(user_id);
create index farmer_surveys_main_crop_idx on public.farmer_surveys(main_crop);
```

**Repeating block: Kharif crops** (the "Crops Taken in Kharif Season" table — I/II/III/IV rows):
```sql
create table public.survey_kharif_crops (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.farmer_surveys(id) on delete cascade,
  position smallint not null check (position between 1 and 8),
  crop_name text,
  cultivated_area_acre numeric,
  crop_variety text,
  production_qty numeric,
  avg_estimated_cost numeric,
  unique (survey_id, position)
);
```

**Repeating block: main-crop annual production (last 3 years)**:
```sql
create table public.survey_main_crop_yearly (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.farmer_surveys(id) on delete cascade,
  year smallint not null,
  area_acre numeric,
  total_production numeric,
  home_consumption numeric,
  quantity_sold numeric,
  sold_where text,
  selling_price numeric,
  unique (survey_id, year)
);
```

**Per-crop agronomy block** (one row per crop_role — `'main'` or `'other'`, since the docx repeats the same agronomy block for both):
```sql
create table public.survey_crop_practices (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.farmer_surveys(id) on delete cascade,
  crop_role text not null check (crop_role in ('main','other')),

  -- Location and continuity
  grown_on text,                                   -- forest_patta / own_land
  same_land_every_year boolean,
  land_topology text,                              -- flat / sloping / other
  land_topology_other text,

  -- Seeds & training
  seed_sources text[] default '{}'::text[],        -- own/market/foundational/other_farmers/breeder/other
  seed_source_other text,
  pop_training_received boolean,
  pop_training_source text,
  farming_method text,                             -- traditional / pop

  -- Seed treatment
  treats_seeds boolean,
  seed_treatment_materials text[] default '{}'::text[],  -- thiram/gomitra/carbendazim/bio_pesticide/other

  -- Seedling prep (paddy/ragi only)
  seedling_method text,                            -- raised_bed / rab / other
  seedling_method_other text,
  seedling_ready_days int,
  seedling_method_difference text,

  -- Land prep
  land_prep_tractor_days numeric,
  land_prep_tractor_cost numeric,
  land_prep_bullock_days numeric,
  land_prep_bullock_cost numeric,
  land_prep_by_hand boolean,

  -- Transplanting (paddy/ragi only)
  transplant_method text,                          -- throwing / dibbling / line_spacing
  dip_in_jeevamrut boolean,
  plant_spacing_cm numeric,
  transplant_days int,
  needs_transplant_labour boolean,
  transplant_labourers int,
  transplant_daily_wage numeric,

  -- Post-planting weeding
  does_weeding boolean,
  weeding_after_days int,

  -- Pest / disease
  sprays_for_pest boolean,
  spray_methods text[] default '{}'::text[],       -- matka / neem / other
  matka_per_acre numeric,
  neem_per_acre numeric,
  spray_methods_other text,
  organic_fert_helps_disease boolean,

  -- Growth
  planting_to_flowering_days int,
  uses_fertilizer boolean,
  fertilizer_names text,
  fertilizer_qty_per_acre numeric,
  flowering_pest_problem boolean,
  flowering_pest_type text,
  flowering_sprays_used text,
  maturity_days int,

  -- Monitoring
  monitors_crop boolean,
  monitoring_methods text[] default '{}'::text[],   -- records / observation / other

  -- Harvest
  harvest_method text,                              -- full_cutting / ear_heads / machine
  harvest_labour_type text,                         -- family / hired
  harvest_daily_wage numeric,
  harvest_labourers int,
  harvest_days int,
  ready_to_eat_or_sell_days int,
  sells_main_crop boolean,
  selling_time text,

  unique (survey_id, crop_role)
);
```

**RLS** (mirror the existing farmer_surveys policies — owner can read/write own rows; service role bypasses).

### 2.2 form_config tables — keep existing shape
[lib/services/form_config_service.dart](lib/services/form_config_service.dart) already pulls from `form_sections` (with nested `form_fields`) and `dropdown_options`. The chatbot will reuse this same fetch.

Extend `form_fields` if any of these columns are missing (check the live schema, add via migration):
- `crop_role text` — `'main' | 'other' | null` — so we can render the same section twice with different `crop_role` context.
- `repeat_group text` — `'kharif_crops' | 'main_crop_yearly' | null` — so the chat can spawn N rows.
- `hint_text_hi text`, `hint_text_mr text`, `label_hi text`, `label_mr text` — language overrides (keeps i18n with the data, not in app bundles).

### 2.3 dropdown_options additions
Seed Marathi/Hindi labels. Add a `label_hi`, `label_mr` column on `dropdown_options` if not present.

### 2.4 Seed migration: `YYYYMMDDhhmmss_baseline_survey_v2_seed.sql`
Generate `form_sections`, `form_fields`, `dropdown_options` rows that cover the full docx. Section order should match the chatbot conversation flow ([Appendix A](#appendix-a--baseline-questionnaire-content) groups them):

1. **Greeting & Language** (synthetic — no DB field, sets `language`).
2. **Family Information** — farmer_name, village, gram_panchayat, taluka, district, mobile_number, aadhaar_number, date_of_birth, education, gender, category.
3. **Income Sources** — income_sources (multiselect), farming_type (multiselect), owns_farmland.
4. **Land Holding** — total_land_area_acre, irrigated_land_acre, dry_land_acre, fallow_land_acre, leased_land_acre, rain_based_area_acre.
5. **Forest Patta** — has_forest_patta, forest_patta_acre, applied_for_forest_patta (visibility rules: forest_patta_acre only if has_forest_patta=true; applied_for_forest_patta only if has_forest_patta=false).
6. **Farm Boundary** — *polygon field* invokes the new freehand drawing UI; saves to `farm_polygon`.
7. **Main Crop** — main_crop dropdown; main_crop_land_acre.
8. **Kharif Crops Table** — repeating group `kharif_crops` (loop up to 4 rows; ask "add another crop?" after each).
9. **Main Crop Agronomy** — full block in `survey_crop_practices` with `crop_role='main'` (sections 1–N of the docx that follow "If Farmers select Ragi/Rice"). Render section-by-section with skip logic.
10. **Main Crop 3-Year Production** — repeating group `main_crop_yearly` (years 2023/2024/2025).
11. **Income & Food Products** — annual_agri_income, non_agri_income, total_annual_income (auto_calc), makes_food_products, food_products_list, food_product_training_*.
12. **Other Crops** — if farmer chose Bajra/other on main_crop OR has other crops, render `survey_crop_practices` with `crop_role='other'`.
13. **Submission summary** — chat bubble listing back key answers + "Submit" button.

For each new `form_fields` row, set `input_type` to one of the values already supported by [lib/widgets/dynamic_field.dart](lib/widgets/dynamic_field.dart) (`text`, `numeric`, `currency`, `acre`, `boolean`, `dropdown`, `date`, `mobile`, `aadhar`, `polygon`, `auto_calc`, `multiselect`) plus three new types defined in Phase 4: `polygon_pencil`, `repeat_group_kharif`, `repeat_group_yearly`.

---

## Phase 3 — Internationalization (Marathi / Hindi / English)

### 3.1 Approach
Use `flutter_localizations` + ARB files for **app-shell strings** (button labels, system messages). Use **DB-side translations** for question/label text, hint text and dropdown labels (so questionnaire can be edited remotely without rebuilding the app).

### 3.2 Files to create
- `lib/l10n/app_en.arb`, `lib/l10n/app_hi.arb`, `lib/l10n/app_mr.arb`.
- Enable code generation in [pubspec.yaml](pubspec.yaml):
```yaml
flutter:
  generate: true
```
- Add `l10n.yaml` at the project root:
```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

### 3.3 Strings to translate (app shell)
- "Welcome, I'm your survey assistant"
- "Continue", "Back", "Skip", "Save draft", "Submit"
- "Draw your farm boundary", "Tap and drag to draw", "Clear", "Done"
- "Locating you…", "Permission denied", "Try again"
- Validation messages

### 3.4 Locale wiring
- [lib/main.dart](lib/main.dart): `Supabase.initialize` already runs first; after that, read `language` from SharedPreferences (default `en`) and pass to `GetMaterialApp.locale`.
- Provide a language picker as the **first** chat bubble (Greeting & Language). On selection, save `'language'` to SharedPreferences and rebuild via `Get.updateLocale`.
- Persist the choice on the `farmer_surveys.language` column.

### 3.5 Question-text resolution
Inside [lib/models/form_config.dart](lib/models/form_config.dart) add `labelHi`, `labelMr`, `hintHi`, `hintMr` getters that fall back to `label` if null. A helper `String localizedLabel(BuildContext)` returns the right one based on the current locale.

---

## Phase 4 — Chatbot UI

### 4.1 Architecture overview

| Layer | File (new) | Responsibility |
|---|---|---|
| UI | `lib/screens/chatbot_survey_screen.dart` | Renders the scrolling list of chat messages, the input area, and the "typing…" indicator. |
| Controller | `lib/controllers/chat_survey_controller.dart` | Sequences sections/fields, derives the next question, validates, calls `FormController` save accessors, exposes `messages: RxList<ChatMessage>`. |
| Messages | `lib/models/chat_message.dart` | Sealed class hierarchy of message kinds (see 4.3). |
| Widgets | `lib/widgets/chat/*.dart` | One widget per message kind (bot text, user text, polygon prompt, polygon answer, repeat-group prompt, summary, etc.). |
| Bridge | extend `lib/controllers/form_controller.dart` | Add a `toFlatJson()` that already exists (the controller already has `_buildJson`) — the chat controller delegates persistence to it via a new `setValue(fieldKey, dynamic)` public method. |

### 4.2 Reuse from existing code
- **`FormController` state stays the source of truth.** The new `ChatSurveyController` owns the conversation order; it writes into `FormController._textControllers / _boolValues / _stringValues / _polygonValues / _multiSelectValues` via new public setters (`setText`, `setBool`, `setDropdown`, `setDate`, `setPolygon`, `setMultiSelect`). On submit, call `FormController.submit()` — `_buildJson` already produces the row.
- Expand `_buildJson` to also serialize the new repeat groups (kharif, yearly) and call `SurveyService.insertWithChildren(survey, kharifRows, yearlyRows, practices[])` — a new method on [lib/services/survey_service.dart](lib/services/survey_service.dart) that does the parent insert then bulk-inserts the child rows in a transaction (use Supabase RPC `rpc('submit_baseline_survey', ...)` or do the inserts sequentially with rollback on failure).

### 4.3 Chat message kinds (`lib/models/chat_message.dart`)
```dart
sealed class ChatMessage { final String id; final DateTime at; }
class BotTextMessage extends ChatMessage { final String text; final List<String>? quickReplies; }
class UserTextMessage extends ChatMessage { final String text; }
class BotFieldPromptMessage extends ChatMessage { final FormFieldConfig field; }
class UserFieldAnswerMessage extends ChatMessage { final FormFieldConfig field; final String displayValue; }
class PolygonPromptMessage extends ChatMessage { /* opens fullscreen pencil map */ }
class PolygonAnswerMessage extends ChatMessage { final List<List<double>> coords; final double areaHectares; }
class RepeatGroupPromptMessage extends ChatMessage { final String groupKey; final int currentIndex; }
class SummaryMessage extends ChatMessage { final Map<String,dynamic> snapshot; }
class TypingIndicatorMessage extends ChatMessage {}
```

### 4.4 Conversation engine
- The controller maintains a `Queue<FormFieldConfig>` derived by walking `form_sections` order, filtering out fields whose `visibility_rule` is not satisfied by the current `FormController` state, and inserting `RepeatGroupPromptMessage`s when a section has `repeat_group` != null.
- After each user answer:
  1. Push a `UserFieldAnswerMessage` with the formatted display value.
  2. Persist into `FormController` via the new public setter (so existing draft save / validation works unchanged).
  3. Show `TypingIndicatorMessage` for ~400 ms.
  4. Re-evaluate visibility rules for downstream fields; recompute queue.
  5. Push the next `BotFieldPromptMessage`.
- At the end, push `SummaryMessage`. The Submit button calls `FormController.submit()`. On success, navigate to `/home` with a snack "Survey submitted — diagnostics now available".

### 4.5 Polygon as a chat step (`lib/widgets/chat/polygon_message_widget.dart`)
- When the queue hits the field whose `input_type == 'polygon_pencil'`, push a `PolygonPromptMessage`. Tapping the bubble pushes `PencilPolygonScreen` (Phase 5) fullscreen.
- On return with a `List<List<double>>` (lng,lat pairs in GeoJSON order), push a `PolygonAnswerMessage` rendering a static map thumbnail (use `google_maps_flutter` in liteMode) + computed area_hectares (via existing geometry helpers in [lib/models/satellite/farm_model.dart](lib/models/satellite/farm_model.dart) or port `@turf/area` minimal logic).
- Save the polygon via `FormController.setPolygon('farm_polygon', coords)`.

### 4.6 Visual style
- Two avatars: bot (millet logo from `assets/`) + farmer (default silhouette).
- Bot bubble: green-tinted background, left-aligned. User bubble: white card, right-aligned. Match existing theme in [lib/config/theme.dart](lib/config/theme.dart).
- Field input rendered inline below the latest bot bubble, **not** in a fixed bottom bar. When user submits, input collapses and the answer bubble appears above the next bot bubble.

### 4.7 Routes & defaults
Modify [lib/app.dart](lib/app.dart):
- `/form` → `ChatbotSurveyScreen` (new default).
- `/form/classic` → existing `SurveyFormScreen` (kept for fallback).
- Edit [lib/screens/home_screen.dart](lib/screens/home_screen.dart) "Start new survey" button → still `/form`. Add a small "Use classic form" link.

---

## Phase 5 — Pencil polygon drawing

### 5.1 New utility: `lib/utils/polygon_simplify.dart`
Port [src/utils/polygonSimplify.ts](../../../Desktop/wrkfarm/sentinel-agro-insight-1/src/utils/polygonSimplify.ts) — Ramer–Douglas–Peucker.
```dart
class PolygonSimplifier {
  /// points are LatLng. Returns a closed ring (first==last) with len >= 4.
  static List<LatLng> simplify(List<LatLng> stroke, {double? tolerance});
  static double _perpendicularDistance(LatLng p, LatLng a, LatLng b);
  static double _bboxDiagonalMeters(List<LatLng> pts);
}
```
- Tolerance: `max(0.5 m, 1.5% of bbox diagonal)` to match the web app.
- Convert meters↔degrees with a flat-earth approximation around the centroid (good enough at farm scale).

### 5.2 New screen: `lib/screens/pencil_polygon_screen.dart`
Build on top of `google_maps_flutter` (preferred — better satellite imagery than flutter_map's OSM tiles, matches the web app):

- Take initial `LatLng` from `LocationService.getCurrentLocation()`. If denied, fall back to `SatelliteConfig.defaultCenter`.
- Modes (toggle button top-right):
  - **Pan/zoom mode** (default): standard gestures.
  - **Pencil mode**: gesture detector overlays the map. Map gestures disabled. `onPanStart/Update/End` collect screen points; convert each to LatLng via `GoogleMapController.getLatLng(ScreenCoordinate)`. On `onPanEnd`, run `PolygonSimplifier.simplify` and replace the current ring.
- Show live stroke as a polyline while drawing; show closed polygon after release.
- Buttons: Clear (clears ring), Undo (last stroke), Re-center (animate to current GPS), Save.
- Return value: `List<List<double>>` in `[lng, lat]` order (GeoJSON friendly).

### 5.3 Geometry helpers
- Reuse area calculation in [lib/models/satellite/farm_model.dart](lib/models/satellite/farm_model.dart) (the satellite module already computes `area_hectares`). If it isn't exposed, extract `polygonAreaHectares(List<LatLng>)` into `lib/utils/polygon_geometry.dart`.

### 5.4 Permissions
- Already declared in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) and [ios/Runner/Info.plist](ios/Runner/Info.plist) (location is in the manifest as confirmed in exploration). Add a one-line iOS purpose string update if missing: `NSLocationWhenInUseUsageDescription` → "Used to center the farm-boundary drawing on your field".

### 5.5 Existing tap-to-vertex screen
Keep [lib/screens/satellite/draw_polygon_screen.dart](lib/screens/satellite/draw_polygon_screen.dart) untouched. The new pencil screen replaces its usage in the chatbot flow only.

---

## Phase 6 — Diagnostics entry point

### 6.1 Home-page button
Edit [lib/screens/home_screen.dart](lib/screens/home_screen.dart) (or the landing screen at `/home` — see [lib/app.dart](lib/app.dart)):
- After loading the user's surveys via `SurveyController`, show a **"View Diagnostics"** button card only when:
  1. At least one row in `farmer_surveys` exists for this user, AND
  2. That row has a non-null `farm_polygon`.
- Tapping it navigates to `/diagnostics` (new route).

### 6.2 New screen: `lib/screens/diagnostics_home_screen.dart`
This is the user-facing entry. It is **separate from** the existing [lib/screens/satellite/diagnostics_screen.dart](lib/screens/satellite/diagnostics_screen.dart) (which is inside the satellite-auth-gated shell). The new screen:
- Loads the latest `farmer_surveys` row (with `farm_polygon`) for the current main-Supabase user.
- Builds a transient `Farm` model and calls `SatelliteService.loadDiagnostics(farmId, geometry)` (see [lib/services/satellite_service.dart](lib/services/satellite_service.dart)). Because the satellite Supabase project is a different auth domain, do **one of**:
  - **Simplest:** call the satellite edge function `/diagnostics` using just the anon key (the function should already accept the anon key and treat the request as public, as the web app does it that way for unauthenticated farm previews). Verify by inspecting `supabase/functions/diagnostics/index.ts` in the sentinel repo.
  - **Or:** sign in to the satellite project anonymously via Supabase Anonymous auth and reuse the existing `SatelliteService.signIn` flow with a generated email/password tied to the main user id.
- Renders the same diagnostic UI as the existing satellite screen but reskinned to match home theme: index toggle, problem cards, heatmap. Reuse `lib/widgets/satellite/problem_card.dart` and the time-series chart.

### 6.3 Future-work stub
- The user said "we need to do more plan to make it more concrete later" — leave the deeper Gemini-advisory + RAG advisory port out of this milestone. The new screen will *only* run the existing diagnostics call. A `// TODO(diagnostics-v2): wire Gemini advisory like web app` marker at the top of `diagnostics_home_screen.dart` documents this.

### 6.4 Route
Add to [lib/app.dart](lib/app.dart):
```dart
GetPage(name: '/diagnostics', page: () => const DiagnosticsHomeScreen()),
```
No new binding — controller is created locally with `Get.put(DiagnosticsHomeController())` inside the screen.

---

## Phase 7 — Wiring, validation, and edge cases

### 7.1 SurveyService extensions
File: [lib/services/survey_service.dart](lib/services/survey_service.dart)
- Add `Future<String> insertWithChildren(Map<String,dynamic> parent, List<Map<String,dynamic>> kharif, List<Map<String,dynamic>> yearly, List<Map<String,dynamic>> practices)`.
- Implement as parent insert → take returned `id` → bulk insert children. Wrap in a `try/catch` that deletes the parent if any child insert fails (Supabase JS-style transactions are not available in the dart client; this manual rollback is the simplest reliable approach).

### 7.2 Visibility rules
The current engine in [lib/controllers/form_controller.dart](lib/controllers/form_controller.dart) supports `depends_on`, `operator`, `value`. The chatbot controller calls `isFieldVisible(field)` before queueing each prompt. Edge cases:
- For dropdown answers, compare against the **DB option_key** not the human label.
- For multiselect answers, support a new operator `contains_any` (extend [lib/controllers/form_controller.dart:isFieldVisible](lib/controllers/form_controller.dart)).

### 7.3 Repeat groups
- Kharif crops: after each row, prompt "Add another crop?" with quick-reply buttons. Stop at 8.
- Main-crop yearly: hardcoded loop over 2023/2024/2025 — no add/remove buttons.

### 7.4 Draft saving
The existing `saveDraft` / `loadDraft` (SharedPreferences) on `FormController` is kept. The chatbot controller also serializes its own `messages` queue (so users can resume mid-conversation) under key `chat_survey_messages`. On resume, replay messages and re-derive the queue position from `FormController` state.

### 7.5 Language switching mid-survey
- The language picker is the first bubble. After that, language is locked for the survey (changing mid-survey would require re-asking already-translated questions). A tiny "globe" icon in the app bar opens a confirmation to restart in a different language; this clears the draft.

---

## Phase 8 — Testing & verification

### 8.1 Unit tests
- `test/utils/polygon_simplify_test.dart` — RDP returns ≥4 points, closes the ring, handles collinear points and single-point strokes.
- `test/utils/polygon_geometry_test.dart` — area within 1% of a known reference (e.g. a 100m × 100m square).
- `test/controllers/chat_survey_controller_test.dart` — given a fixture `form_sections`, the controller emits the expected sequence of `ChatMessage`s, persists into `FormController`, and respects visibility rules.
- `test/services/survey_service_test.dart` — `insertWithChildren` rolls back parent on child failure (mock Supabase client).

### 8.2 Widget tests
- `test/widgets/chat/polygon_message_widget_test.dart` — bubble renders thumbnail and area text from a fixture polygon.
- `test/screens/chatbot_survey_screen_test.dart` — first frame shows language picker; after selection, the family-information section starts.

### 8.3 Integration / manual UAT
Run on a physical Android device (the pencil gesture is hard to validate on the iOS simulator without a touch device):
1. Fresh install → splash → login → home.
2. Tap "Start new survey" → language picker → choose Marathi → all subsequent question text is Marathi.
3. Walk through every section; verify visibility-rule skips (no-forest-patta path skips forest acreage; Bajra path skips Ragi-specific seedling questions).
4. Pencil polygon: enter pencil mode, draw a loop around a field at high zoom, release; verify the polygon snaps to a clean ring and area is reasonable. Switch to pan/zoom, re-center, re-enter pencil, redraw → previous ring is replaced.
5. Submit → check `farmer_surveys`, `survey_kharif_crops`, `survey_main_crop_yearly`, `survey_crop_practices` rows in main Supabase via the Studio.
6. Back to home → confirm "View Diagnostics" card now appears.
7. Tap → diagnostics page renders polygon + index heatmap; problem cards populated.
8. Repeat the run in Hindi and English; check there are no untranslated strings.

### 8.4 Codex / agentic execution hints
For tasks delegated to an agent like Codex, provide:
- A fixture `form_sections.json` (representative slice of the seed migration in Phase 2.4) so the chat-controller test can run offline.
- A fixture `diagnostics_response.json` based on the shape in [lib/models/satellite/diagnostics_model.dart](lib/models/satellite/diagnostics_model.dart).
- Instruction to run `flutter analyze` and `flutter test` after each phase. Fail the phase if either errors.

### 8.5 Pre-merge checklist
- [ ] `flutter analyze` — 0 errors, 0 warnings.
- [ ] `flutter test` — all green.
- [ ] Manual UAT pass on Android device, all three languages.
- [ ] Migrations applied to a staging Supabase project; `farmer_surveys_legacy_v1` retained.
- [ ] `flutter build apk --release` succeeds. Version code bumped in [pubspec.yaml](pubspec.yaml) and `android/app/build.gradle`.

---

## Critical files to modify or create

### Modify
- [pubspec.yaml](pubspec.yaml) — add `flutter_localizations`, `flutter_markdown`, `mocktail`, enable `generate: true`.
- [lib/main.dart](lib/main.dart) — load saved locale, pass to `GetMaterialApp`.
- [lib/app.dart](lib/app.dart) — add `/form/classic`, `/diagnostics` routes; change `/form` to the chatbot screen.
- [lib/controllers/form_controller.dart](lib/controllers/form_controller.dart) — add public setters (`setText`, `setBool`, `setDropdown`, `setDate`, `setPolygon`, `setMultiSelect`); extend `_buildJson` and visibility-rule evaluator (`contains_any` operator); expose child-row lists.
- [lib/services/survey_service.dart](lib/services/survey_service.dart) — `insertWithChildren` with manual rollback.
- [lib/services/form_config_service.dart](lib/services/form_config_service.dart) — select language-suffixed columns (`label_hi`, `label_mr`, etc.).
- [lib/models/form_config.dart](lib/models/form_config.dart) — add `labelHi/labelMr/hintHi/hintMr/cropRole/repeatGroup` fields and a `localizedLabel(BuildContext)` helper.
- [lib/widgets/dynamic_field.dart](lib/widgets/dynamic_field.dart) — recognise `polygon_pencil` input type; delegate to new pencil flow.
- [lib/screens/home_screen.dart](lib/screens/home_screen.dart) — conditional "View Diagnostics" CTA.
- [lib/config/theme.dart](lib/config/theme.dart) — chat bubble colors if not present.
- [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) — verify location permissions present.
- [ios/Runner/Info.plist](ios/Runner/Info.plist) — verify/update location purpose strings.

### Create
- `supabase/migrations/YYYYMMDDhhmmss_baseline_survey_v2.sql` (schema redesign).
- `supabase/migrations/YYYYMMDDhhmmss_baseline_survey_v2_seed.sql` (form_config seed + dropdown translations).
- `lib/l10n/app_en.arb`, `lib/l10n/app_hi.arb`, `lib/l10n/app_mr.arb`, `l10n.yaml`.
- `lib/models/chat_message.dart`.
- `lib/controllers/chat_survey_controller.dart`.
- `lib/screens/chatbot_survey_screen.dart`.
- `lib/screens/pencil_polygon_screen.dart`.
- `lib/screens/diagnostics_home_screen.dart`.
- `lib/controllers/diagnostics_home_controller.dart`.
- `lib/utils/polygon_simplify.dart`, `lib/utils/polygon_geometry.dart`.
- `lib/widgets/chat/bot_text_bubble.dart`, `user_text_bubble.dart`, `bot_field_prompt.dart`, `polygon_message_widget.dart`, `repeat_group_prompt.dart`, `summary_card.dart`, `typing_indicator.dart`.
- Tests as listed in 8.1–8.2.

---

## Appendix A — Baseline questionnaire content

Extracted from `Base line Que.docx- Swati.docx`. The chatbot's question order should follow this structure (with i18n labels seeded in `form_fields.label_hi` and `.label_mr` — Marathi terms are already used in the doc and should appear verbatim in `mr`).

1. **Family Information** — Name, Village, Gram Panchayat, Taluka, District, Mobile, Aadhaar (12 digits), DOB, Education, Gender, Category.
2. **Land / Farming**
   - Income sources (multi): Farming, Business, Govt Job, Private Job, Other.
   - Farming type: Rainfed, Irrigated, Other.
   - Owns farmland (Y/N); Total land area; Irrigated/Dry/Fallow/Leased; Rain-based area.
   - Forest patta (Y/N); if yes → total forest land; if no → applied for forest patta (Y/N).
3. **Main crop** — Paddy (Rice) / Nachani (Ragi) / Bajra / Other; land under main crop.
4. **Kharif crops table** — up to 4 rows: Crop Name, Cultivated Area, Variety, Production, Avg Estimated Cost.
5. **Main-crop growth practices** (if Ragi/Rice path):
   - Where grown (Forest Patta / Own Land); same land every year (Y/N); land type (Flat/Sloping/Other).
   - Seeds: Own / Market / Foundational / Other-farmers / Breeder / Other.
   - POP training received and source; farming method (Traditional / POP).
   - Treat seeds (Y/N); materials: Thiram, Gomitra, Carbendazim 50% WP, Bio-pesticide, Other.
   - Seedling method: Raised Bed / Rab / Other; days till ready; difference noticed.
   - Tools for land prep: Tractor (days, cost), Bullock (days, cost), By Hand.
   - Transplanting: method (throwing/dibbling/line spacing), Jeevamrut dip (Y/N), plant spacing, days, labour need + count + wage.
   - Weeding (Y/N) + days after transplant.
   - Pest/disease spray after planting (Y/N): Matka spray per acre, Neem extract per acre, Other; organic fertilizer helps disease? (Y/N).
   - Days planting → flowering; fertilizer usage and qty/acre; pest at flowering and sprays; maturity days.
   - Monitoring (Y/N): records / observation / other.
   - Harvest: full cutting / ear heads only / machine; labour: family/hired + wage + count; harvest days; ready-to-eat/sell days.
   - Sells main crop (Y/N) + when.
6. **3-Year main-crop production** — 2023/2024/2025: area, production, home consumption, qty sold, sold where, price.
7. **Income totals** — Annual agri income, non-agri, total annual.
8. **Food products** — makes (Y/N), names, training received, source.
9. **Other crops** — if Bajra / Other path or supplementary crops: same agronomy block as section 5 but stored with `crop_role='other'`.

---

## Out of scope (deferred)

- Gemini advisory generation on mobile (Phase 6.3 note — diagnostics screen currently calls only the existing satellite indices function).
- Voice input.
- Migrating legacy `farmer_surveys_legacy_v1` rows into the new schema (kept as cold archive).
- Offline-first sync (the existing draft mechanism remains the only offline support).
