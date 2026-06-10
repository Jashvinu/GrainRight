# Implementation Plan: Farmer Navigation & Profile Update

## Phase 1: Preparation
- [x] Create `SPEC.md` and get approval.
- [ ] Research `AppTheme` for navigation styling.
- [ ] Identify icons for new sections.

## Phase 2: Navigation Structure
- [ ] Update `_destinations` and `_railDestinations` in `lib/screens/farmer_home_screen.dart`.
- [ ] Implement the Floating Bottom Navigation bar in `FarmerHomeScreen`.
- [ ] Update `pages` list with placeholder widgets for new sections.

## Phase 3: New Sections (Placeholders)
- [ ] Implement `WeatherPage` placeholder.
- [ ] Implement `MarketPage` placeholder.
- [ ] Implement `NewsPage` placeholder.
- [ ] Implement `SchemesPage` placeholder.

## Phase 4: Detailed Profile Page
- [ ] Move `_ProfilePage` to `lib/screens/profile_screen.dart` and expand it.
- [ ] Add more detailed farmer and farm information.
- [ ] Add settings and support sections.

## Phase 5: Refinement & Validation
- [ ] Ensure consistent styling across all new sections.
- [ ] Verify navigation on different screen sizes (Responsive check).
- [ ] Run basic widget tests.

# Task Breakdown

- [ ] Task 1: Update navigation destinations and rail in `FarmerHomeScreen.dart`.
  - Acceptance: `_destinations` and `_railDestinations` have 6 items: Home, Weather, Market, News, Schemes, Profile.
  - Verify: Build app and check navigation icons/labels.
  - Files: `lib/screens/farmer_home_screen.dart`

- [ ] Task 2: Implement Floating Bottom Navigation.
  - Acceptance: Bottom navigation is elevated and has margins from screen edges.
  - Verify: Visual check on mobile layout.
  - Files: `lib/screens/farmer_home_screen.dart`

- [ ] Task 3: Create placeholder screens for Weather, Market, News, and Schemes.
  - Acceptance: Each section has a title and basic placeholder content.
  - Verify: Navigate to each section.
  - Files: `lib/screens/farmer_home_screen.dart` (or separate files if needed)

- [ ] Task 4: Implement Detailed Profile Page.
  - Acceptance: Comprehensive profile view with expanded info and better layout.
  - Verify: Check profile section for new details.
  - Files: `lib/screens/profile_screen.dart`, `lib/screens/farmer_home_screen.dart`

- [ ] Task 5: Final Review & Cleanup.
  - Acceptance: All success criteria met, no regressions in Home dashboard.
  - Verify: Manual end-to-end test.
  - Files: All touched files.
