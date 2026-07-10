# Design Brief: MilletsNow Marketplace (Web) — Design Spec Requested

## What I want from you

Produce a **written design specification only** — no code, no HTML mockups. Deliver:

1. Information architecture / sitemap
2. User flows for the journeys listed below
3. Screen-by-screen specs (layout description, components, content hierarchy, states: empty/loading/error/no-results)
4. A component inventory
5. Responsive behavior notes (desktop-first, must degrade gracefully to mobile web)
6. Accessibility and trust/credibility considerations
7. Visual direction (tone, color/typography guidance suited to agri-commerce trust — not final assets)

## Product context

MilletsNow runs a farmer-side app where millet farmers map their farms, get satellite-based crop health monitoring (NDVI, moisture, disease risk, yield prediction), follow week-by-week crop plans, and at harvest grade their produce with an AI vision grader (grades A–D) before packaging it into lots. Every lot therefore carries verified farm-to-harvest data.

The **Marketplace** is the public, buyer-facing web app where these lots are listed. Think of India's NAFED auction portal (nafex.in) as the reference category — but our differentiators are:

1. **Predictive supply intelligence**: because we track every crop cycle via satellite (yield + harvest-date prediction per farm), buyers get more than stock listings — they can filter what's *coming* ("Grade-A-likely foxtail millet harvesting in ~3 months in Karnataka"), see aggregated regional supply forecasts (a supply heatmap/dashboard by commodity × region × grade × time window), register standing demand and get matched to upcoming lots worth pre-booking. This is the deep-tech moat — treat it as a first-class product surface, not a filter option.
2. **Complete traceability**: every lot links to its farm (boundary on a map), seed source, inputs applied (what/when), satellite health history, grading evidence (AI grader results + photos), and custody chain.
3. **Digital passport**: on purchase, the buyer receives a shareable, QR-verifiable digital passport for the lot, so they can pass provenance downstream to *their* customers.

Products: millet grains (foxtail, ragi, pearl, little, kodo, etc.) AND by-products — husk/bran/fodder for cattle feed, value-added items.

## Personas (design for both, in this priority)

1. **B2B bulk buyer** — processors, institutional buyers, cattle-feed manufacturers. Buys by the quintal/tonne. Cares about: consistent grade, volume availability, forward planning (pre-booking future harvests), documentation for their own compliance/marketing. Desktop user, comparison-heavy, filter-heavy.
2. **Retail consumer** — health-conscious individual buying packaged millets. Cares about: authenticity, farm story, "know your farmer," the passport as a trust artifact. Mobile-web likely.

The IA must serve both without confusing either — propose how (e.g., separate entry paths, a mode toggle, or persona-neutral browse with persona-relevant detail pages — you decide and justify).

## V1 scope — the complete buyer flow

Design the **end-to-end commerce journey**, not just discovery: browse/search/filter → supplier & lot detail with traceability → enquiry/RFQ & negotiation (for bulk) or direct purchase (for retail) → cart/order placement → payment → order & fulfillment tracking (dispatch, in-transit, delivered — mapped to custody events) → **digital passport issued with the completed purchase**. Plus: pre-booking upcoming harvests (reserve quantity against a predicted harvest, with advance/token payment), buyer account (saved searches, watchlists, alerts, order history, passports collection), enquiry/order inbox with statuses.

Expect two purchase modes and design both:

- **B2B**: RFQ → seller quote → negotiation/acceptance → order → payment (support offline/bank-transfer confirmation flows common in Indian B2B agri trade, not just gateway payments) → dispatch & custody tracking → passport.
- **Retail**: standard e-commerce — product page → cart → checkout → payment gateway → delivery tracking → passport in account.

Out of scope for v1: live auctions, ratings/reviews, seller-side screens (sellers list and respond from the farmer app).

## Key screens/journeys to spec (minimum set — add what's missing)

1. **Landing/home** — value proposition ("traceable millets, direct from monitored farms"), category entry (grains / cattle feed & by-products), search, featured "harvesting soon" strip, how-traceability-works explainer.
2. **Browse/listings** — the core screen. Filters: commodity, grade (A–D), availability status (**in stock now** vs **harvesting in ~X weeks/months** — predicted from our satellite crop-cycle data), region/state/district, farming method (organic/natural/conventional, from farm records), quantity available, price band, seller type (individual farmer / FPO). Sort options. Card design must surface: grade badge, predicted-or-actual harvest date, origin, traceability indicator.
3. **Supplier directory + supplier profile** — farmer/FPO page: location, farms (map), active + upcoming lots, grading history summary.
4. **Lot/product detail** — grade + evidence, quantity, suggested price band, harvest date (actual or predicted with confidence), farm location, condensed traceability timeline, CTA: enquire / pre-book.
5. **Traceability page / digital passport viewer** — the USP page; must work as a standalone public shareable URL reached via QR. Timeline: farm origin (boundary map), seed source, inputs applied with dates, satellite health snapshots across the season, grading event (AI grader output, sample photos), custody events. Design for skeptical-buyer trust AND for the retail "farm story" emotional read — reconcile these.
6. **Enquiry/RFQ & negotiation flow (B2B)** — request quote on a live lot; seller quote → counter → accept; pre-book an upcoming harvest (quantity + timeframe + advance/token payment); inbox with statuses (sent / quoted / negotiating / accepted / converted to order / closed).
7. **Cart & checkout (retail) / order placement (B2B)** — retail: cart, address, payment gateway; B2B: convert accepted quote to order, payment terms incl. bank-transfer/offline payment confirmation. Order summary must carry grade, lot ID, and traceability promise.
8. **Order tracking & fulfillment** — order states (confirmed / packed / dispatched / in transit / delivered), tied to the lot's custody chain so tracking IS traceability; passport issued/unlocked on completion.
9. **Supply intelligence dashboard (B2B)** — the deep-tech showcase: regional supply forecast heatmap (map + time slider), commodity × grade × time-window breakdowns with confidence bands, drill-down from a forecast region to the actual upcoming lots behind it, and a "standing demand" setup ("I need 50t Grade-A ragi quarterly") that drives match recommendations and alerts. Design honest uncertainty display throughout — forecasts have confidence levels.
10. **Buyer account** — saved searches, watchlists, alerts ("notify me when Grade-A ragi from Karnataka is ≤1 month from harvest"), enquiry history, order history, **passport collection** (all digital passports from past purchases, shareable).
11. **Retail storefront view** — packaged-product presentation of the same lots for consumers, passport as the trust hook.

## Constraints & notes

- Web-first, desktop-optimized for B2B screens; traceability/passport pages must be excellent on mobile (QR scans land there).
- Data realities: harvest dates are *predictions with confidence levels* — design honest uncertainty display, never fake precision. Some lots will have sparse traceability (legacy data) — design graceful degradation of the passport.
- Multilingual future (English first; Hindi/Marathi later) — flag copy-length/layout implications.
- Sellers do NOT use this app (they list from the farmer app); all seller actions (responding to RFQs, accepting orders, confirming dispatch) happen in the farmer app — the marketplace only needs to reflect those state changes to the buyer.
- Payments: assume a standard Indian gateway (UPI/cards/netbanking) for retail; B2B must also handle offline settlement (bank transfer with proof upload / confirmation) — design the states, not the gateway UI.
- Brand: MilletsNow. Trust, transparency, and "technology-verified" are the pillars; avoid generic agri-clipart aesthetics.

## Deliverable format

One structured document: sitemap → flows → screen specs → component inventory → responsive/accessibility notes → visual direction. Where you make a judgment call (e.g., persona handling in IA), state the decision and the reasoning in one or two lines.
