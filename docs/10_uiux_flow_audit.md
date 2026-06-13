# 10 — UI/UX Flow Audit & Redesign Plan

**Status:** Living document. Tracks the end-to-end UI/UX pass on the farmer-facing app.
**Last updated:** 2026-06-12
**Owner:** product + engineering
**Related:** [02_design_system.md](02_design_system.md) · [04_information_architecture.md](04_information_architecture.md) · [11_grain_grading_integration.md](11_grain_grading_integration.md)

---

## 1. Goal

Make the Kalsubai Farms app **feature-rich but simple, not redundant**, conforming to
[Material 3](https://m3.material.io/) and tuned for **smallholder farmers in India**.

Three decisions frame this work (locked 2026-06-12):

1. **Grading** — grading runs in **Supabase Edge Functions** (re-pointed 2026-06-13 from the
   earlier vendored-FastAPI plan, to match the app's other AI). The GrainGrade-Detection Python
   project is kept as the rule reference. See [11_grain_grading_integration.md](11_grain_grading_integration.md).
2. **UX scope** — polish **core farmer flows first**; FPO/satellite/admin get a later pass.
3. **Audience** — **Marathi/Hindi-first, minimal text, low-literacy**: icon-first, big touch
   targets, visual cues over paragraphs.

---

## 2. Design principles for Indian smallholder farmers (M3-aligned)

These extend the "Mountain Roots" design system (`02_design_system.md`) with audience rules.

| # | Principle | Concrete rule |
| - | --------- | ------------- |
| P1 | **Language first** | Regional language (mr) is the default render; every new string ships in `en`/`hi`/`mr`. No English-only UI. |
| P2 | **Show, don't tell** | Each action has a recognizable icon + 1–3 word label. Avoid sentences in primary UI; move detail to optional "more" reveals. |
| P3 | **Big targets** | Minimum 56dp tap targets for primary actions (M3 min is 48dp); 64dp for the main farmer journey buttons. |
| P4 | **One decision per screen** | Multi-step flows (grading, survey) use one clear question/action per screen with a visible step indicator. |
| P5 | **Forgiving + offline-aware** | Always show network state; queue what can be queued; never lose user input. Grading needs connectivity — say so plainly with an icon. |
| P6 | **Numbers as visuals** | Prefer gauges, color bands, and large numerals over tables. A/B/C grade = big colored badge, not a row in a grid. |
| P7 | **Voice/visual cues (progressive)** | Reserve space for optional audio prompts and illustrative mascot (Kalu) guidance in empty/error states. |
| P8 | **Consistent navigation** | Same bottom bar everywhere in the farmer shell; back always goes one logical step up. |

M3 components we standardize on: `NavigationBar` (mobile) / `NavigationRail` (large),
`FilledButton` / `FilledButton.tonal`, `Card` (outlined, no harsh elevation), `Chip`,
`ListTile`, `ModalBottomSheet`, `SegmentedButton` (for crop/variety/grade pickers),
`LinearProgressIndicator` (step + score), `Badge` (alerts).

---

## 3. Current-state map (farmer-facing)

Routes from `lib/app.dart`; screens from `lib/screens/`.

| Route | Screen | Role | State |
| ----- | ------ | ---- | ----- |
| `/` | `splash_screen.dart` | all | OK |
| `/login` | `main_login_screen.dart` | all | review |
| `/farmer/login` | `farmer_login_screen.dart` | farmer | review |
| `/farmer` | `farmer_home_screen.dart` | farmer | **god-file, 10k lines** |
| `/farmer/ai-chat` | `farmer_ai_chat_screen.dart` | farmer | OK |
| `/farmer/ai-grading` | `farmer_ai_grading_screen.dart` | farmer | **mock data → rebuild** |
| `/farmer/harvest-qr` | `harvest_qr_screen.dart` | farmer | depends on grading |
| info screens | `farmer_info_screens.dart` (Weather/Market/News/Schemes) | farmer | review |
| `profile_screen.dart` | farmer | review |
| FPO/satellite/admin | (multiple) | FPO/admin | **out of scope this pass** |

### 3.1 Redundancy & complexity findings

- **`farmer_home_screen.dart` is 10,185 lines / ~90 classes.** It contains the dashboard,
  inventory, harvest home, farm pages, NDVI/soil/yield detail pages, market, news, schemes,
  profile, settings, and the entire side-nav implementation. This is the single biggest
  simplicity risk. **Plan:** do **not** rewrite wholesale (high regression risk); extract in
  safe, verifiable slices — start by moving self-contained page widgets (`MarketPage`,
  `NewsPage`, `SchemesPage`, `_ProfilePage`, `_SettingsPage`) into their own files, leaving
  behavior identical. Track each extraction as its own task.
- **Two grading representations.** The mock screen shows a 0–100 score + letter "A"; the real
  backend returns **A/B/C grades + moisture risk bands**. We standardize on the backend model
  and drop the invented 0–100 score from the primary result (keep confidence % only).
- **Translations are Marathi-only** (`lib/config/translations.dart` maps English→Marathi; no
  Hindi map, no `hi`). The app advertises `hi` support in `app.dart`. **Gap:** add a Hindi map
  so `hi` is real, at least for the grading flow and core nav.

---

## 4. Target farmer journey (information architecture)

```
Splash
  └─ Login (role select: Farmer / FPO)
       └─ Farmer Login (phone / guest)
            └─ Farmer Shell  ── bottom nav ──┐
                 • Home (dashboard)          │
                 • Weather                   │
                 • Market                    │
                 • News                       │  (info-first nav, per SPEC.md)
                 • Schemes                   │
                 • Profile                   ┘
                 └─ Primary actions (from Home / FAB):
                      • Krishi Mitra AI chat     → /farmer/ai-chat
                      • AI Grain Grading         → /farmer/ai-grading   ← rebuilt flow
                      • Harvest QR               → /farmer/harvest-qr
                      • Farm diagnostics / maps  → (existing)
```

### 4.1 Rebuilt grading sub-flow (the centerpiece)

One decision per screen (P4), all steps in mr/hi/en:

```
[1] Choose crop + variety      (SegmentedButton / chips, from /api/crops)
        ↓
[2] Photograph the grain       (camera/gallery, on-screen framing guide)
        ↓
[3] Photograph moisture meter  (camera/gallery, "point at the number")
        ↓
[4] Analyzing…                 (progress + what's happening, cancelable)
        ↓
[5] Result                     (big A/B/C badge, moisture risk band,
                                confidence %, plain-language summary,
                                "needs human check" state when flagged)
        ↓  ├─ Looks wrong? → correction sheet (feedback to /api/feedback)
        └─ Continue → Generate Harvest QR (carries grade into QR)
```

See [11_grain_grading_integration.md](11_grain_grading_integration.md) §4 for the exact API
contract behind each step.

---

## 5. Screen-by-screen plan (core flows)

> Legend: ⬜ todo · 🔄 in progress · ✅ done

| Screen | Changes | Status |
| ------ | ------- | ------ |
| Splash | M3 spacing, mascot, locale-aware tagline | ⬜ |
| Login (role) | Localized en/hi/mr via `ui_strings.dart`; **added language selector** (screen had none); kept the polished role cards | ✅ |
| Farmer login | Localized en/hi/mr (title, mobile field, CTA, note, support, secure strip) | ✅ |
| Home dashboard | Reduce density; group quick actions; ensure grading entry is prominent | ⬜ (god-file — deferred) |
| **AI Grain Grading** | **Full rebuild to real 5-step flow + backend wiring** | ✅ |
| Harvest QR | Consume real grade (A/B/C), localized labels | 🔄 (now receives real A/B/C grade; label i18n pending) |
| Weather/Market/News/Schemes | Consistent card system, minimal text, icons | ⬜ (Weather standalone; Market/News/Schemes live in god-file) |
| Profile | Fully localized en/hi/mr (header, identity, personal info, farm stats, rewards, settings, footer) | ✅ |
| Weather | Structural headers localized (title, hourly-temp section, metric tiles, agro signals); mock forecast prose left for when real data is wired | ✅ (headers) |

**New shared i18n helpers** (sidestep the Marathi-only legacy system):
`lib/config/ui_strings.dart` (shell/login) and `lib/config/grading_strings.dart` (grading) —
both resolve en/hi/mr from `Get.locale`. New screens should use these going forward.

---

## 6. Workstreams & tracking

1. **Tracking docs** (this file + integration doc) — ✅
2. **Vendor grading backend** → `grading_service/` — ✅ (see integration doc §3)
3. **Flutter grading service + models** — ✅ (`lib/services/grain_grading_service.dart`, `lib/models/grading/`)
4. **Rebuild grading screen** — ✅ (`lib/screens/farmer_ai_grading_screen.dart`, real 5-step flow)
5. **Grading i18n (mr/hi/en)** — ✅ (`lib/config/grading_strings.dart`)
6. **M3 polish pass on core farmer flows** — 🔄 ongoing (login ✅, profile ✅, weather headers ✅;
   splash + Market/News/Schemes still to do)
7. **Grading backend moved into Supabase Edge Functions** — ✅ (see integration doc)
8. **(Stretch) Extract pages out of the home god-file** — ⬜ backlog

> Deploy host for the grading backend is still open (Q1) — grading runs against a configurable
> `GRADING_API_BASE_URL` and degrades gracefully until one is chosen.

Progress is mirrored in the in-session task list.

---

## 7. Open questions / assumptions

- **A1** Grading backend is deployed as a network service the app calls; offline grading is not
  attempted (vision model needs connectivity). Offline behavior = clear "connect to grade" state.
- **A2** We keep the existing info-first bottom nav from `SPEC.md` (Home/Weather/Market/News/
  Schemes/Profile); grading is reached from Home, not the nav bar.
- **A3** Hindi (`hi`) translations are currently missing; we add them incrementally starting with
  grading + core nav rather than translating the entire legacy survey at once.
- **Q1** Where will the grading backend be hosted (Render, the existing Supabase project's
  functions, or a separate container)? Tracked in integration doc §6.
