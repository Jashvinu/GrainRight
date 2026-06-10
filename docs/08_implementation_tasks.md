# Kalsubai Farms Implementation Roadmap

This document outlines the sequential step-by-step roadmap to implement the Kalsubai Farms platform.

---

### TASK-001: Project Configuration & Pubspec Setup
*   **Objective:** Install required libraries to support clean architecture, state management, animations, and responsive scaling.
*   **Files:**
    *   [pubspec.yaml](file:///C:/Atharva/Millets%20Website/GrainRight/pubspec.yaml)
*   **Dependencies:** None
*   **Estimated Complexity:** Low (1 hour)
*   **Acceptance Criteria:**
    *   Add `flutter_riverpod`, `go_router`, `google_fonts`, `flutter_animate`, `lottie`, and `responsive_framework` to the dependencies list.
    *   Run `flutter pub get` and verify compilation without conflicts.

---

### TASK-002: Base Design Tokens & Core Theme
*   **Objective:** Configure light/dark theme systems using the specific color palettes and font settings of the Mountain Roots design system.
*   **Files:**
    *   [theme.dart](file:///C:/Atharva/Millets%20Website/GrainRight/lib/config/theme.dart)
*   **Dependencies:** TASK-001
*   **Estimated Complexity:** Low (2 hours)
*   **Acceptance Criteria:**
    *   Validate that both `AppTheme.theme` (Light Mode) and `AppTheme.darkTheme` (Dark Mode) compile.
    *   Confirm Google Fonts bindings for Poppins (headings) and Inter (body) load successfully.

---

### TASK-003: Declarative Routing Configuration
*   **Objective:** Transition the application routing structure from GetX to GoRouter. Setup Shell routing for bottom navigation.
*   **Files:**
    *   `lib/core/router/router.dart` [NEW]
    *   [app.dart](file:///C:/Atharva/Millets%20Website/GrainRight/lib/app.dart) [MODIFY]
    *   [main.dart](file:///C:/Atharva/Millets%20Website/GrainRight/lib/main.dart) [MODIFY]
*   **Dependencies:** TASK-002
*   **Estimated Complexity:** Medium (4 hours)
*   **Acceptance Criteria:**
    *   Setup GoRouter with shell routes for Home, Farm, Market, AI, and Profile tabs.
    *   Implement temporary routing placeholders for screens to ensure navigation works correctly.

---

### TASK-004: Reusable Component Library
*   **Objective:** Implement core UI widgets including custom buttons, card wrappers, and the animated Kalu mascot.
*   **Files:**
    *   `lib/components/buttons.dart` [NEW]
    *   `lib/components/cards.dart` [NEW]
    *   `lib/components/mascot.dart` [NEW]
    *   `lib/components/search_bar.dart` [NEW]
*   **Dependencies:** TASK-003
*   **Estimated Complexity:** Medium (4 hours)
*   **Acceptance Criteria:**
    *   `KalsubaiPrimaryButton` behaves with a press scale-down animation.
    *   `KaluMascotView` supports Wave, Thinking, Success, and Error states, animated using `flutter_animate`.

---

### TASK-005: Splash & Onboarding Screens
*   **Objective:** Create the premium animated Sunrise Splash screen and a 3-page Onboarding slide flow.
*   **Files:**
    *   `lib/features/onboarding/presentation/splash_screen.dart` [NEW]
    *   `lib/features/onboarding/presentation/onboarding_screen.dart` [NEW]
*   **Dependencies:** TASK-004
*   **Estimated Complexity:** Medium (3 hours)
*   **Acceptance Criteria:**
    *   On splash startup, a golden sun scale animation plays behind Kalsubai Peak.
    *   Onboarding screen lists the 3 specified agritech slides with responsive layout scaling.

---

### TASK-006: Authentication Screen Migration
*   **Objective:** Migrate the authentication screen to use Riverpod. Set up the OTP input fields.
*   **Files:**
    *   `lib/features/auth/presentation/login_screen.dart` [NEW]
    *   `lib/features/auth/presentation/auth_providers.dart` [NEW]
*   **Dependencies:** TASK-005
*   **Estimated Complexity:** Medium (4 hours)
*   **Acceptance Criteria:**
    *   Verify phone number validation and OTP verification state machine.
    *   Supports changing app language directly from the top menu bar.

---

### TASK-007: Flagship Home Screen
*   **Objective:** Build the flagship home screen dashboard featuring the Mountain Hero banner, quick stats, active crop lists, and daily tasks checklist.
*   **Files:**
    *   `lib/features/home/presentation/home_screen.dart` [NEW]
*   **Dependencies:** TASK-006
*   **Estimated Complexity:** High (6 hours)
*   **Acceptance Criteria:**
    *   Show a beautiful 220px high Kalsubai Mountain header that updates based on the current time of day.
    *   Display the 4 quick stats cards, feature quick links grid, daily checklists, and livestock summaries.

---

### TASK-008: AI Crop Diagnosis & Krishi Mitra Assistant
*   **Objective:** Implement the crop scan upload UI, analysis progress bars, and the leaf disease detection result cards.
*   **Files:**
    *   `lib/features/diagnosis/presentation/diagnosis_screen.dart` [NEW]
    *   `lib/features/diagnosis/presentation/diagnosis_providers.dart` [NEW]
*   **Dependencies:** TASK-007
*   **Estimated Complexity:** High (5 hours)
*   **Acceptance Criteria:**
    *   Allow mock leaf scan image capture or upload.
    *   Show "Kalu Thinking" during mock scanning, returning Leaf Blast rust diagnosis with confidence and organic remedies.

---

### TASK-009: Agritech Marketplace
*   **Objective:** Develop the e-commerce product grids, category filtering horizontal tabs, and order details.
*   **Files:**
    *   `lib/features/marketplace/presentation/marketplace_screen.dart` [NEW]
    *   `lib/features/marketplace/presentation/marketplace_providers.dart` [NEW]
*   **Dependencies:** TASK-008
*   **Estimated Complexity:** High (5 hours)
*   **Acceptance Criteria:**
    *   Show products (Bajra, Jowar, Nachni) with responsive grids.
    *   Add items to cart, submit order, and trigger "Kalu Success" confirmation.

---

### TASK-010: Weather Forecast Screen
*   **Objective:** Implement the hourly and 7-day Sahyadri weather forecast, rain predictions, and agro-meteorological advisories.
*   **Files:**
    *   `lib/features/weather/presentation/weather_screen.dart` [NEW]
*   **Dependencies:** TASK-009
*   **Estimated Complexity:** Medium (4 hours)
*   **Acceptance Criteria:**
    *   Hourly temperature and rainfall progress chart renders correctly.
    *   Weekly forecast rows display high/low bounds with customized icons.

---

### TASK-011: Farmer Community Forum
*   **Objective:** Build the Reddit/WhatsApp inspired community feed, question submissions, and comment threads.
*   **Files:**
    *   `lib/features/community/presentation/community_screen.dart` [NEW]
    *   `lib/features/community/presentation/community_providers.dart` [NEW]
*   **Dependencies:** TASK-010
*   **Estimated Complexity:** High (5 hours)
*   **Acceptance Criteria:**
    *   List posts with filter tags (Millets, Soil, Cattle).
    *   User can like, comment, or write a new post.

---

### TASK-012: Profile & Achievement Badge Screen
*   **Objective:** Design the farmer profile details page highlighting village locations, farm size metrics, and reward badges.
*   **Files:**
    *   `lib/features/profile/presentation/profile_screen.dart` [NEW]
    *   `lib/features/profile/presentation/settings_screen.dart` [NEW]
*   **Dependencies:** TASK-011
*   **Estimated Complexity:** Medium (4 hours)
*   **Acceptance Criteria:**
    *   Show achievements section containing badges (Millet Champion, Water Saver, etc.).
    *   Add settings configuration panel.
