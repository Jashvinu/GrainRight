# 11 — Grain Grading Integration (GrainGrade-Detection → Kalsubai Farms)

**Status:** Living document.
**Last updated:** 2026-06-12
**Source repo:** https://github.com/Atharva-007/GrainGrade-Detection
**Related:** [10_uiux_flow_audit.md](10_uiux_flow_audit.md) · [09_supabase_functions_and_ai.md](09_supabase_functions_and_ai.md)

---

## 1. What we're integrating

GrainGrade-Detection grades a grain lot (finger millet / ragi, plus rice, bajra, etc.) from
**two photos** — the grain and a moisture-meter display — and returns an **A/B/C grade**,
**moisture risk band**, confidence, the rules it applied, and a plain-language operator summary.

Pipeline (server side, unchanged from source repo):

```
grain image ─┐
              ├─ OpenCV physics proxies ─┐
moisture img ─┘                          ├─ crop rule engine ─┐
crop + variety ── RAG over BIS/FAO docs ─┘                    ├─ Qwen-VL vision ─┐
                                                              │  safety gate     ├─ deterministic
                                                              └──────────────────┘  grade + moisture risk
```

The app already uses the **same Qwen-VL provider** (`VLM_API_KEY` / `qwen-vl-max`) for disease
diagnosis (see `.env.example` and `09_supabase_functions_and_ai.md`), so no new model vendor.

---

## 2. Integration decision

**Grading runs entirely in Supabase Edge Functions** (decision locked 2026-06-13, superseding the
earlier vendored-FastAPI plan). Rationale:

- The app's other AI (disease diagnosis, agronomy RAG, diagnostics) already runs as Supabase Edge
  Functions calling the Qwen-VL provider. Grading now follows the **same pattern** — one backend,
  one deployment, one auth/RLS model, one set of secrets.
- The heavy bits of the Python reference (OpenCV physics proxies) are a calibration layer; the
  grade decision is a deterministic threshold engine that ports cleanly to TypeScript, and the
  Qwen-VL model supplies the visual signals — exactly like `disease-image-diagnose`.
- No separate Python host (Render/Docker) to run, scale, or secure.

`grading_service/` (the vendored Python project) is kept as the **reference implementation** the
TypeScript rule engine is derived from — not a deployed service.

The previous Flutter grading screen was **mock data** (`grade='A'`, `score=86`); it is now a real
client of the Supabase functions.

---

## 3. Where grading lives in this repo

```
GrainRight/
├── lib/
│   ├── services/grain_grading_service.dart   # Supabase Storage upload + Edge Function client
│   ├── models/grading/                       # CropOption, GradeResult
│   ├── screens/farmer_ai_grading_screen.dart # real 5-step flow
│   └── config/grading_strings.dart           # en/hi/mr
├── supabase/
│   ├── functions/
│   │   ├── _shared/grain-rules.ts            # ragi thresholds + grade engine (ported from Python)
│   │   ├── grain-grade/index.ts              # sign URLs → Qwen-VL → rules → persist → return
│   │   ├── grain-grade-feedback/index.ts     # operator corrections
│   │   └── grain-crops/index.ts              # crop + variety catalog
│   └── migrations/20260614090000_grain_grading_microservices.sql
│                                             # analysis_jobs/logs/corrections + storage buckets + RLS
└── grading_service/                          # REFERENCE ONLY — vendored Python source the TS rules
                                              # derive from; not deployed.
```

Image buckets (`grain-images`, `moisture-images`) are private; uploads are scoped per user via
RLS (`{uid}/...`). The Edge Functions run as **service role** so guest sessions can grade and the
result is returned inline (see [[guest-session-rls-pattern]]).

---

## 4. API contract the Flutter client targets

Base URL is `SupabaseConfig.edgeFunctionsBase` (`{project}.supabase.co/functions/v1`). All calls
send `apikey` + `Authorization: Bearer <session jwt>`. Flow: **upload photos to Storage → POST the
storage paths to `grain-grade`.**

### `GET grain-crops` → crop + variety catalog
```jsonc
{ "success": true, "crops": [
  { "value": "finger_millets", "label": "Finger Millet (Ragi)",
    "aliases": ["ragi","nachni"], "rule_summary": ["…"],
    "varieties": [ { "value": "local", "label": "Local" } ] }
] }
```

### Storage upload (before analyze)
`POST {url}/storage/v1/object/grain-images/{uid}/{ts}.jpg` (and `moisture-images/...`), body =
raw JPEG bytes, `Content-Type: image/jpeg`. Path **must** start with the caller's `uid` (RLS).

### `POST grain-grade` (JSON) → grade result
| field | required | notes |
| ----- | -------- | ----- |
| `grain_image_path` | ✅ | storage path returned by the grain upload |
| `moisture_image_path` | ✅* | storage path of the moisture-meter photo |
| `manual_moisture_percent` | ✅* | fallback if no meter photo |
| `crop_type` | ✅ | e.g. `finger_millets` |
| `crop_variety` | – | variety value |
| `confidence_threshold` | – | 0–100 review floor (default 60) |
| `operator_id` | – | caller uid, stored for ownership |

\* one of `moisture_image_path` **or** `manual_moisture_percent` is required. The function signs
the URLs, runs Qwen-VL (moisture OCR + grain vision), applies `_shared/grain-rules.ts`, writes a
row to `analysis_jobs`, and returns inline:

Response (`AnalyzeResponse`, fields the UI uses — wrapped in `{ "success": true, … }`):
```jsonc
{
  "analysis_id": "…",
  "quality": {
    "grade": "A|B|C",                // ← primary badge
    "grain_grade": "A|B|C",
    "score": 0-100,                  // confidence-ish internal score; NOT shown as the grade
    "broken_grain_percent": 0.0,
    "foreign_matter_percent": 0.0,
    "uniformity_score": 0.0,
    "mold_visible": false,
    "reject_recommended": false,
    "reject_reasons": ["…"]
  },
  "moisture": {
    "risk_level": "LOW|MODERATE|HIGH|CRITICAL",   // ← risk band
    "percent_estimate": 11.2,
    "machine_percent": 11.0,
    "source": "meter_ocr|manual|estimate",
    "ocr_confidence": 0.9
  },
  "confidence": { "overall": 0-100, "pass1_safety_gate": …, "pass2_grading": … },
  "selection": { "selected_crop": "…", "selected_variety": "…" },
  "applied_rules": [ { "rule_name": "…", "evidence": "…", "rule_confidence": 0.0 } ],
  "manual_review_required": true,    // ← "needs human check" state
  "operator_summary": "plain-language sentence",   // ← localized/relayed to farmer
  "signal_highlights": ["…","…"]     // ← shown as visual chips
}
```

### `POST grain-grade-feedback` (JSON) → operator correction
```jsonc
{ "analysis_id": "…", "true_grade": "A|B|C",
  "true_moisture_risk": "LOW|MODERATE|HIGH|CRITICAL", "notes": "", "operator_id": "<uid>" }
```
Writes to `operator_corrections` (service role) for later rule calibration.

---

## 5. Flutter wiring

| Layer | File | Responsibility |
| ----- | ---- | -------------- |
| Models | `lib/models/grading/` | `CropOption`, `CropVariety`, `GradeResult` (maps the response) |
| Service | `lib/services/grain_grading_service.dart` | uploads bytes to Storage, calls `grain-crops` / `grain-grade` / `grain-grade-feedback` with `apikey` + session jwt |
| UI | `lib/screens/farmer_ai_grading_screen.dart` | rebuilt 5-step flow (see audit doc §4.1) |
| QR | `lib/screens/harvest_qr_screen.dart` | consumes real `grade` (A/B/C) |
| i18n | `lib/config/grading_strings.dart` | mr/hi/en strings for all grading copy |

Mapping rules:
- **Primary result = `quality.grade` (A/B/C)** as a big colored badge — green/gold/orange.
  We drop the invented 0–100 "score" from the hero (keep `confidence.overall` as a small %).
- **Moisture** = colored risk band chip (LOW=green … CRITICAL=red) + percent.
- **`manual_review_required`** → a distinct "needs human check" result state, not a hard grade.
- **`operator_summary` + `signal_highlights`** → plain-language guidance + chips.
- **No session** → `isConfigured` is false; the screen shows the localized "sign in to grade" state.

---

## 6. Deployment & config

Nothing extra to host — grading ships with the rest of the Supabase project.

1. **Migration:** `supabase/migrations/20260614090000_grain_grading_microservices.sql` creates the
   `analysis_jobs` / `analysis_logs` / `operator_corrections` / `crop_rule_versions` tables, the
   `grain-images` + `moisture-images` private buckets, and their RLS.
2. **Deploy functions:**
   `supabase functions deploy grain-grade grain-grade-feedback grain-crops`.
3. **Secrets** (already used by `disease-image-diagnose`): `SUPABASE_URL`,
   `SUPABASE_SERVICE_ROLE_KEY`, and the Qwen key as `VLM_API_KEY` (or `QWEN_VL_API_KEY`), with
   optional `VLM_BASE_URL` / `VLM_MODEL`.
4. **App:** no config — `SupabaseConfig` already points at the project.

---

## 7. Status

- [x] Source repo analyzed; API contract captured (this doc)
- [x] `grading_service/` kept as the Python reference implementation
- [x] Supabase Edge Functions — `grain-grade`, `grain-grade-feedback`, `grain-crops` + `_shared/grain-rules.ts` (Deno type-checked)
- [x] Migration — tables + `grain-images`/`moisture-images` buckets + RLS
- [x] Flutter client rewired to Storage upload + Edge Functions
- [x] Rebuilt grading screen + i18n (mr/hi/en)
- [ ] `supabase functions deploy grain-grade grain-grade-feedback grain-crops` + set secrets
- [ ] End-to-end test against the deployed functions

### Implementation notes

- Photos upload as JPEG bytes to private Storage under `{uid}/{ts}.jpg`; the Edge Function signs
  them with the service role, so guest sessions can grade and the result returns inline
  ([[guest-session-rls-pattern]]).
- The crop catalog is **non-critical**: if `grain-crops` is unreachable the screen falls back to a
  built-in Finger Millet option so grading is never blocked.
- `_shared/grain-rules.ts` is a faithful port of the Python `rule_engine.py` thresholds + the
  `moisture_calibration.py` risk bands — keep them in sync if the Python reference changes.
- The OpenCV physics proxies from the Python reference are **not** ported; the Qwen-VL vision pass
  supplies the equivalent visual signals (broken %, foreign %, damaged %, uniformity, mold), as in
  `disease-image-diagnose`. This is the main fidelity trade-off of moving to Supabase.
