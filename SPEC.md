# Spec: Farmer Navigation Update & Detailed Profile

## Objective
Update the farmer application's navigation to focus on information services (Weather, Market, News, Schemes) instead of management tasks (Disease, Farm, History) in the side/bottom navigation bar. Also, implement a more detailed and comprehensive Profile page.

## Success Criteria
- **Navigation Items:** Home, Weather, Market, News, Schemes, and Profile (6 items).
- **Floating Bar:** The bottom navigation bar on mobile is implemented as a floating panel (e.g., using `Padding` and `Container` with decoration) instead of a standard `bottomNavigationBar`.
- **Pages:** 
    - Home: Existing dashboard.
    - Weather, Market, News, Schemes: New placeholder screens.
    - Profile: New detailed profile screen.
- **Side Navigation:** `NavigationRail` for large screens is also updated with the 6 items.

## Tech Stack
- Flutter (Dart)
- GetX (for routing and state management)
- Material 3 (using `NavigationRail` and `NavigationBar`)

## Project Structure
- `lib/screens/farmer_home_screen.dart`: Main entry for farmer home, contains navigation logic.
- `lib/screens/profile_screen.dart` (New): Detailed profile page implementation.
- `lib/widgets/farmer/`: New directory for farmer-specific widgets if needed.

## Code Style
- Use private classes for sub-pages within `FarmerHomeScreen` if they are small, or move to separate files if they become complex.
- Adhere to the existing `AppTheme` and `BrandAssets`.
- Use `LayoutBuilder` for responsive navigation (Side rail for desktop, Bottom bar for mobile).

## Testing Strategy
- Unit tests for navigation index changes.
- Widget tests for the new Profile page to ensure all information is displayed correctly.
- Manual verification of navigation transitions.

## Boundaries
- Always: Use existing theme constants and assets.
- Ask first: Adding new dependencies (e.g., for weather API or charts).
- Never: Remove existing functionality from the dashboard (Disease/Farm/History quick actions must remain functional).

## Open Questions
- Should "Home" be kept in the navigation bar? (Assumed Yes).
- What specific details should be added to the "Detailed Profile Page"? (Assumed: Expanded personal and farm info).
