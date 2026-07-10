# MilletsNow Two-App Pivot Plan

MilletsNow pivots from a single farmer survey/monitoring app into a **two-app system** sharing one data spine:

1. **Farmer app** — evolution of the existing Flutter app.
2. **Public marketplace** — new, web-first buyer app. Positioning: "like NAFED/NAFEX, but with farm-level intelligence."

## System overview

One pipeline, two surfaces:

```
FARMER APP                                              MARKETPLACE (web)
farm mapping + baseline survey
        │
   crop_cycle (stage machine: sowing → … → harvest)
        │  weekly checks + satellite health (NDVI, disease risk,
        │  yield + harvest-date prediction)
        ▼
harvest-zone guidance ("Grade-A candidates here first")
        │
   grade_sample (AI vision grader, A–D) ──► lot ──► listing ───► browse / filters /
        │                                                        supply forecasts
   quality_passport (grade, lot ID, QR, custody chain) ────────► traceability page
        │                                                        digital passport
seller responds to RFQs, confirms orders/dispatch ◄────────────  enquiry → order →
                                                                 payment → fulfillment
```

The farmer app **produces** traceability + supply data; the marketplace **consumes** it. Sellers never use the marketplace — all seller actions live in the farmer app.

## Farmer app scope (v-next)

Keep: baseline survey, offline sync, farm polygon mapping, satellite diagnostics, i18n (en/hi/mr).

Add:
- **Crop-cycle stage machine** with week-by-week plan through harvest (already sketched in `plans/crop_stage_grading_weekly_layout_expansion.md`).
- **Harvest-zone map**: satellite health → "collect Grade-A candidates from this zone first; Grade C/D from that zone" during harvest.
- **AI vision grader capture flow**: sample photos → grade A–D + evidence.
- **Packaging / lot creation**: graded produce → lots with quality passport.
- **Listing flow**: list lots + by-products (husk/bran/fodder) with market-based price suggestion.
- **Seller inbox**: respond to marketplace RFQs, accept orders, confirm dispatch (custody events).

## Marketplace scope (v1)

Web-first. Personas: B2B bulk buyers (primary) + retail consumers. **Full commerce flow**: discovery → enquiry/RFQ & negotiation (B2B) or cart/checkout (retail) → order → payment (gateway for retail; offline bank-transfer states for B2B) → fulfillment tracking mapped to custody chain → **digital passport issued on completion**. Plus pre-booking upcoming harvests with advance/token payment. Screens: see `plans/marketplace_design_prompt.md`.

Out of scope v1: live auctions, ratings/reviews, seller-side screens.

## Deep-tech layer: Predictive Supply Intelligence

Lives between the two apps. Per-farm satellite yield + harvest-date predictions aggregate into **region × commodity × predicted-grade supply forecasts**, powering:

- (a) Buyer-side **supply heatmap/dashboard** — "how much Grade-A-likely ragi is coming out of Karnataka in the next 90 days."
- (b) **Demand↔supply matching** — buyers register standing demand ("50t Grade-A ragi quarterly"); system recommends pre-bookable upcoming lots.
- (c) **Alerts wired to forecasts**, not just live listings.

Forecasts always carry confidence levels — honest uncertainty, never fake precision.

New backend pieces: `supply_forecasts` (aggregation job over crop_cycles + satellite predictions), `demand_profiles`, matching/recommendation service.

## Shared backend plan (new tables)

`farms`, `crop_cycles`, `stage_events`, `grade_samples`, `lots`, `listings`, `quality_passports`, `enquiries`, `orders`, `payments`, `custody_events`, `price_suggestions`, `supply_forecasts`, `demand_profiles`.

Migration: existing `farmer_surveys` (+ `survey_crop_practices`, `survey_main_crop_yearly`, `survey_kharif_crops`) backfilled as legacy crop cycles so no data is lost. FK chain: farmer → farm → crop_cycle → grade_sample → lot → quality_passport / listing → order.

## Sequencing

1. **Marketplace design spec** (prompt ready: `plans/marketplace_design_prompt.md`) — first because it defines the data contracts the farmer app must produce.
2. Farmer-app design spec (same pattern, after ①).
3. Backend schema design (tables above, informed by both specs).
4. Build marketplace web (thin — reads projected data).
5. Build farmer-app grading/listing/seller-inbox flows.
6. Wire end-to-end traceability + supply forecast aggregation.

## Open questions (parked)

- Pricing-suggestion data source (mandi/AgMarkNet price APIs?).
- Passport verification model (QR → public URL; upgrade path to signed credentials).
- FPO/aggregator persona.
- Deep-tech candidates considered but deferred: cryptographically verifiable passport, anti-substitution lot fingerprinting (grain-morphology re-verification on delivery), price intelligence, satellite-verified organic claims.
