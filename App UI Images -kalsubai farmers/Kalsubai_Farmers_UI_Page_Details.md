# Kalsubai Farmers UI Page Details

This file documents every visible app page and major modal in the current Flutter app under `E:\TraceApp`, and maps them to the UI PNGs already present in this folder.

## 1. Quick UI Summary

- App name in current code: `Kalsubai Farmers`
- Older image pack branding: `MilletsNow`
- Platform: Flutter
- Theme direction: light theme, white surfaces, green primary brand, rounded cards, soft shadow, soft border
- Primary colors from code:
  - Dark green: `#064E3B`
  - Action green: `#0B7A3B`
  - Soft green surface: `#E8F5E9`
  - Grain yellow: `#F9A825`
  - Chain blue: `#1976D2`
- Common layout pattern:
  - `SafeArea`
  - scrollable single-column content
  - rounded `AppCard` blocks
  - `StatusPill` tags
  - bottom navigation for Farmer and FPO home shells

## 2. Image Pack to Screen Mapping

| PNG file | Maps to | Status |
|---|---|---|
| `MilletsNow First page.png` | Legacy splash/loading screen | Reference image only, not a current route |
| `MilletsNow Welcome role selection Page.png` | `LoginScreen` | Current code has this flow with updated Kalsubai branding |
| `Farmer Login.png` | Legacy phone/OTP login page | Reference image only, not implemented in current code |
| `MilletsNow Home Page.png` | `DashboardScreen` | Current code has similar structure with different labels |
| `Diagnostics.png` | Legacy diagnostics upload concept | Reference concept, different from current farm diagnostics page |
| `Farm Diagnostics page.png` | `FarmDiagnosticsScreen` | Current code match |
| `AI Grain Grading page.png` | `AiGrainGradingScreen` | Current code match |
| `Farmer Profile page.png` | `ProfileScreen` | Current code match |
| `FPO Dashboard Page.png` | `FpoHomeScreen` | Current code match |

## 3. Current Screen Inventory

| # | Screen | Route or Entry | User | Screenshot in folder |
|---|---|---|---|---|
| 1 | Login and role selection | `/login` | All | Yes |
| 2 | Farmer home dashboard | Farmer tab 1 in `/home` | Farmer | Yes |
| 3 | AI grain grading | `/grain-grading` or Farmer tab 2 | Farmer | Yes |
| 4 | Harvest bag quantity sheet | FAB in AI grain grading | Farmer | No |
| 5 | Farm diagnostics | `/farm-diagnostics` or Farmer tab 3 | Farmer | Yes |
| 6 | Harvest tracker | `/tracker` or Farmer tab 4 | Farmer | No |
| 7 | Update block sheet | FAB in Harvest Tracker | Farmer and FPO | No |
| 8 | Harvest QR page | `/harvest` after grading | Farmer | No |
| 9 | Public verification page | `/verify/:passportId` | Public | No |
| 10 | Profile | Farmer tab 5, FPO More tab | Farmer and FPO | Yes |
| 11 | FPO dashboard | FPO tab 1 in `/home` | FPO | Yes |
| 12 | Farmers list | FPO tab 2 | FPO | No |
| 13 | Add Farmer or Create Farm sheet | Add Member or Add Farmer actions | Farmer and FPO | No |
| 14 | Farmer passport scan | FPO Scan tab | FPO | No |
| 15 | Ledger explorer | FPO Audit tab | FPO | No |
| 16 | My Farm detail page | Code-only alternate inside `FarmersScreen` | Farmer | No |

## 4. Screen by Screen Detail

### 1. Login and Role Selection

- Status: implemented
- Route: `/login`
- Source: `lib/features/auth/login_screen.dart`
- Purpose: entry page for Farmer, FPO, Admin placeholder, and Guest placeholder
- Main UI blocks:
  - centered brand icon tile
  - app title and subtitle
  - "Welcome!" heading
  - four large role cards
  - divider with "or"
  - security reassurance strip
  - scenic field image anchored to lower page background
- Main actions:
  - Farmer Login
  - FPO Login
  - Admin placeholder snackbar
  - Continue as Guest placeholder snackbar
- Notes:
  - Current code combines role selection into a single screen
  - Admin and Guest are visible but not enabled
  - Sign in is session-based, not OTP-based
- Reference image:
  - `![Login](<App UI Images/MilletsNow Welcome role selection Page.png>)`

### 2. Farmer Home Dashboard

- Status: implemented
- Route: Farmer home shell, bottom nav index 0
- Source: `lib/features/home/dashboard_screen.dart`
- Purpose: first landing screen for Farmer users
- Main UI blocks:
  - top bar with menu, brand name, notifications
  - welcome hero card with farmer name and location
  - quick action grid for My Farm, AI Grading, Tracker
  - recent activity list with view buttons
  - weather card
  - active alerts card
  - bottom nav: Home, AI Grade, Farm, Tracker, Profile
- Main actions:
  - floating Farm FAB
  - open farm diagnostics
  - open AI grain grading
  - open harvest tracker
- Notes:
  - Current code uses Kalsubai copy and 3 quick actions
  - Older image includes New Survey and Field Maps, which are not current dashboard actions
- Reference image:
  - `![Farmer Home](<App UI Images/MilletsNow Home Page.png>)`

### 3. AI Grain Grading

- Status: implemented
- Route: `/grain-grading`
- Source: `lib/features/harvest/ai_grain_grading_screen.dart`
- Purpose: upload or preview grain image, show AI quality result, then generate harvest QR
- Main UI blocks:
  - help app bar
  - info banner
  - grain photo card with gallery action and replace or delete state
  - grading result card with circular grade gauge
  - quality parameter tiles
  - AI recommendations list
  - bottom floating CTA for harvest QR generation
- Main actions:
  - add image from gallery
  - remove or replace image
  - open harvest bag quantity sheet
- Data shown:
  - grade `A`
  - score `86 / 100`
  - purity, broken grains, damage, moisture, foreign matter
- Reference image:
  - `![AI Grain Grading](<App UI Images/AI Grain Grading page.png>)`

### 4. Harvest Bag Quantity Sheet

- Status: implemented
- Entry: FAB in AI Grain Grading
- Source: `lib/features/harvest/ai_grain_grading_screen.dart`
- Purpose: collect bag size and bag count before generating the harvest QR
- Main UI blocks:
  - bottom sheet header
  - one bag quantity field in kg
  - quantity of bags field
  - single full-width submit button
- Main actions:
  - validate numeric fields
  - generate harvest QR
- Notes:
  - not present in the image pack
  - this is a current functional screen extension beyond the design PNGs

### 5. Farm Diagnostics

- Status: implemented
- Route: `/farm-diagnostics`
- Source: `lib/features/diagnostics/farm_diagnostics_screen.dart`
- Purpose: show selected farm, polygon heat map, nutrient metrics, and health alerts
- Main UI blocks:
  - app bar with Add Farm and Help
  - My Farms section with farm selector chips
  - map image card with polygon diagnosis overlay
  - 4-tile farm overview
  - diagnostics metric chips:
    - Nitrogen
    - Phosphorus
    - Potassium
    - Moisture
    - NDVI
  - metric summary row with selected value, min, max, std dev
  - health alert cards with confidence tags
  - tip/info callout card
- Main actions:
  - change selected farm
  - switch active metric
  - open alert recommendation dialog
  - add farm
- Notes:
  - the current code follows the `Farm Diagnostics page.png` layout more closely than the legacy `Diagnostics.png`
  - `Diagnostics.png` represents an older upload-based diagnostic flow
- Reference images:
  - `![Farm Diagnostics](<App UI Images/Farm Diagnostics page.png>)`
  - `![Legacy Diagnostics Concept](<App UI Images/Diagnostics.png>)`

### 6. Harvest Tracker

- Status: implemented
- Route: `/tracker`
- Source: `lib/features/traceability/passport_screen.dart`
- Purpose: display crop lifecycle progress and immutable block update history
- Main UI blocks:
  - app bar with Update Block action
  - tracker header card with plot image, farm summary, stage pills
  - farm tracker stage rail for all crop lifecycle stages
  - block update timeline cards
  - floating Update Block FAB
- Main actions:
  - open Update Block sheet
- Data shown:
  - selected plot name
  - current crop stage
  - area, harvest ETA, farmer info
  - chain events with block index and hash
- Notes:
  - no corresponding PNG exists in the folder

### 7. Update Block Sheet

- Status: implemented
- Entry: Harvest Tracker add action
- Source: `lib/features/traceability/add_event_sheet.dart`
- Purpose: append next lifecycle event with optional proof and passport-impact fields
- Main UI blocks:
  - crop stage chip group
  - stage notes field
  - location field
  - evidence label field
  - dynamic field area based on stage:
    - actual yield
    - crop grade
    - disease note
    - farmer rating
  - photo proof card with gallery and camera actions
  - submit button
- Main actions:
  - select stage
  - attach or remove photo
  - mine block and write update
- Notes:
  - this is one of the most important operational modals in the app

### 8. Harvest QR Page

- Status: implemented
- Route: `/harvest`
- Source: `lib/features/harvest/harvest_screen.dart`
- Purpose: show the consumer-facing public harvest QR label and allow preview or download
- Main UI blocks:
  - harvest app bar
  - harvest header with crop summary and grade pill
  - Public Harvest QR card
  - QR action card with download or preview controls
  - detail rows for batch, bag weight, bag count, yield, public scan purpose
- Main actions:
  - go back to AI grain grading
  - download QR label image
  - preview public verification
- Notes:
  - no existing PNG in the folder
  - this page is a current code feature beyond the image pack

### 9. Public Verification Page

- Status: implemented
- Route: `/verify/:passportId`
- Source: `lib/features/traceability/public_verification_screen.dart`
- Purpose: open public harvest verification from the QR payload
- Main UI blocks:
  - simple app bar
  - loading state
  - unavailable or error state card
  - verified passport details card stack via `FarmerPassportCard`
- Main actions:
  - read public passport snapshot
  - show public provenance details
- Notes:
  - no PNG exists in the folder
  - this is a public-facing route, separate from logged-in UI

### 10. Profile

- Status: implemented
- Route: Farmer tab 4 or FPO More tab
- Source: `lib/features/profile/profile_screen.dart`
- Purpose: show identity, verification, QR share card, and account menu
- Main UI blocks:
  - page header with settings icon
  - profile header card with avatar, verified badge, farmer id, location
  - verification card with identity checks
  - farmer-only passport QR area and passport details
  - menu list:
    - My Farm
    - My Crops
    - Support
    - Settings
    - Logout
- Main actions:
  - logout
  - settings placeholder
- Notes:
  - the current code reuses a generated QR for FPO scan-only farmer passport sharing
- Reference image:
  - `![Profile](<App UI Images/Farmer Profile page.png>)`

### 11. FPO Dashboard

- Status: implemented
- Route: FPO home shell, bottom nav index 0
- Source: `lib/features/home/fpo_home_screen.dart`
- Purpose: FPO landing page for member management and traceability activity
- Main UI blocks:
  - FPO Dashboard title row with Add Member button and alert icon
  - FPO profile card
  - Management grid:
    - Members
    - Procurements
    - Products
    - Reports
    - Transactions
    - Alerts
  - Quick Actions grid
  - Recent Activity list
  - Blockchain Verified strip
  - bottom nav: Home, FPO, Scan, Audit, More
- Main actions:
  - add member
  - open procurement flow placeholder
  - send alert placeholder
  - open scan flow
- Notes:
  - `_BatchSummaryList` and `_FarmerBlockchainDetailSheet` also exist in this file but are not currently mounted in the visible page body
- Reference image:
  - `![FPO Dashboard](<App UI Images/FPO Dashboard Page.png>)`

### 12. Farmers List

- Status: implemented
- Route: FPO tab 1
- Source: `lib/features/farmers/farmers_screen.dart`
- Purpose: list all farmer members and their active crop batches
- Main UI blocks:
  - app bar with Add Farmer
  - top summary banner
  - repeating farmer cards with initials, location, land, farming type
  - inline crop batch rows with progress
  - Add Farmer FAB
- Main actions:
  - open Add Farmer sheet
  - tap a crop batch to make it the selected working batch
- Notes:
  - no existing PNG in the folder

### 13. Add Farmer or Create Farm Sheet

- Status: implemented
- Entry: Add Member, Add Farmer, Add Farm, or Create Farm actions
- Source: `lib/features/farmers/add_farmer_sheet.dart`
- Purpose: create a new farmer profile plus starting crop batch
- Main UI blocks:
  - sheet header
  - farmer identity fields
  - farm location and land details
  - Start Crop subsection
  - crop fields, season, plot, seed type, cultivation type, expected yield
  - submit button
- Main actions:
  - create profile and crop
  - auto-write initial block and public passport record
- Notes:
  - for Farmer session this behaves like "Create Farm"
  - for FPO session this behaves like "Add Farmer"

### 14. Farmer Passport Scan

- Status: implemented
- Route: FPO Scan tab
- Source: `lib/features/traceability/farmer_passport_scan_screen.dart`
- Purpose: scan farmer passport QR codes from within the FPO workflow
- Main UI blocks:
  - page header with start or stop scan icon button
  - scanner panel
  - loading spinner
  - error state card
  - ready-to-scan state card
  - result card using `FarmerPassportCard`
  - scan another button
- Main actions:
  - start scan
  - stop scan
  - scan another
- Notes:
  - FPO-only access
  - if the user is not FPO, a locked state card is shown

### 15. Ledger Explorer

- Status: implemented
- Route: FPO Audit tab
- Source: `lib/features/blockchain/ledger_screen.dart`
- Purpose: inspect block integrity, root anchoring, and event chain history
- Main UI blocks:
  - chain validation banner
  - anchor root card
  - blocks list with Reset action
  - individual block cards with timestamps, hashes, nonce, actor
- Main actions:
  - anchor root
  - reset local chain
- Notes:
  - this is the most technical screen in the app
  - no PNG exists in the folder

### 16. My Farm Detail Page

- Status: implemented but not part of the active Farmer bottom nav
- Entry: internal alternate path inside `FarmersScreen`
- Source: `lib/features/farmers/farmers_screen.dart`
- Purpose: show one selected farm summary when `FarmersScreen` is opened for Farmer session
- Main UI blocks:
  - My Farm app bar
  - top info banner
  - single detailed farm card with farmer and crop metadata
  - Create Farm FAB
- Notes:
  - current Farmer shell uses `FarmDiagnosticsScreen` for the Farm tab instead of this page
  - this is effectively a code-only alternate page right now

## 5. Reusable UI Surfaces That Define Multiple Pages

### A. FarmerPassportCard

- Source: `lib/features/traceability/farmer_passport_card.dart`
- Used in:
  - FPO scan result
  - public verification page
- Contains:
  - verification summary
  - farmer section
  - crop section
  - quality section
  - health section
  - ledger section

### B. CropPassportQrCard

- Source: `lib/features/traceability/crop_passport_qr_card.dart`
- Used in:
  - Harvest QR page
- Contains:
  - large QR block
  - crop and farmer summary
  - detailed harvest trace rows

## 6. Gaps Between the PNG Pack and the Current App

- `MilletsNow` branding in PNGs has already shifted to `Kalsubai Farmers` in code.
- The image pack includes a splash screen and phone/OTP login flow, but the current app does not route through those pages.
- The current app adds functional traceability pages that are not present in the PNG folder:
  - Harvest QR page
  - Public verification page
  - Harvest tracker
  - Update block sheet
  - Add Farmer sheet
  - Farmer passport scan
  - Ledger explorer
- The current diagnostics implementation is farm-polygon based, while `Diagnostics.png` shows an older upload-based diagnosis concept.

## 7. Source Files Reviewed

- `lib/core/router/app_router.dart`
- `lib/features/auth/login_screen.dart`
- `lib/features/home/home_shell.dart`
- `lib/features/home/dashboard_screen.dart`
- `lib/features/home/fpo_home_screen.dart`
- `lib/features/harvest/ai_grain_grading_screen.dart`
- `lib/features/harvest/harvest_screen.dart`
- `lib/features/diagnostics/farm_diagnostics_screen.dart`
- `lib/features/traceability/passport_screen.dart`
- `lib/features/traceability/add_event_sheet.dart`
- `lib/features/traceability/public_verification_screen.dart`
- `lib/features/traceability/farmer_passport_scan_screen.dart`
- `lib/features/traceability/farmer_passport_card.dart`
- `lib/features/traceability/crop_passport_qr_card.dart`
- `lib/features/profile/profile_screen.dart`
- `lib/features/farmers/farmers_screen.dart`
- `lib/features/farmers/add_farmer_sheet.dart`
- `lib/features/blockchain/ledger_screen.dart`

