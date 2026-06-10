# Kalsubai Farms Flutter Enterprise Architecture

This document establishes the architecture, folder structure, state management, and data synchronization patterns for the Kalsubai Farms Flutter application.

---

## 1. Feature-First Clean Architecture

The codebase is structured using a **Feature-First** layout combined with **Clean Architecture** principles. Each business feature resides in its own folder and is split into three layers: `domain`, `data`, and `presentation`.

```
lib/
├── core/                       # Shared modules, theme, routes, network, database
│   ├── theme/                  # Brand themes (theme.dart)
│   ├── router/                 # GoRouter declarations and guards
│   ├── database/               # Drift DB helper and offline tables
│   ├── network/                # Supabase client configurations
│   └── utils/                  # Shared extension methods and date formatters
│
├── features/                   # Feature-specific modules
│   ├── home/
│   │   ├── domain/             # Business models & Repository contracts
│   │   ├── data/               # Models (Freezed) & Repository implementations
│   │   └── presentation/       # Riverpod providers, UI screens and widgets
│   ├── marketplace/
│   ├── diagnosis/
│   ├── weather/
│   ├── community/
│   └── profile/
│
└── app.dart                    # Main App entry scaffold (MaterialApp, router, localizations)
```

### Clean Architecture Layers
1.  **Domain Layer (Independent):** Contains pure business logic. Entities, use-cases, and abstract repository interfaces. It has zero dependencies on external packages, UI, or frameworks.
2.  **Data Layer (Framework Dependent):** Implements repository interfaces. Contains models (using `freezed` for JSON serialization), data sources (Supabase client, local SQLite Drift database), and remote/local synchronization logic.
3.  **Presentation Layer (UI & State):** Contains the screens, widgets, and state management controllers. Business logic in the UI is managed by **Riverpod** providers (e.g. `StateNotifier` or `Notifier` instances).

---

## 2. State Management with Riverpod

We migrate the legacy GetX code to Riverpod. Riverpod provides compile-time safety, testability, and clean dependency injection.

```
       ┌─────────────────────────────────────────────────────┐
       │               RIVERPOD PROVIDER GRAPH               │
       └──────────────────────────┬──────────────────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
  [supabaseClientProvider]   [driftDbProvider]    [connectivityProvider]
         │                        │                        │
         └───────────┬────────────┘                        │
                     ▼                                     │
         [farmRepositoryProvider]                          │
                     │                                     │
                     ▼                                     ▼
         [farmSyncControllerProvider] ◄────────────────────┘
```

### Key Providers
*   `supabaseClientProvider`: Exposes the singleton Supabase client.
*   `appDatabaseProvider`: Exposes the singleton Drift SQLite local database.
*   `authProvider`: Manages session state (unauthenticated, authenticating, authenticated, error).
*   `diagnosisProvider`: Manages image uploading, LeafScan disease analysis status, and treatment caching.
*   `marketplaceProvider`: Manages product listings, filtering, ordering state, and transaction tracking.

---

## 3. Declarative Routing with GoRouter

The application replaces GetX navigation with **GoRouter** to enable type-safe, URL-driven routing, nested navigation rails, and route guards.

*   **Authentication Guard:** If the user is unauthenticated, redirect to `/login`.
*   **Shell Route Structure:** The 5-tab main view is built inside a `StatefulShellRoute` to preserve screen state across tab switches.

### Route Map
*   `/splash` -> Animated Kalsubai splash page
*   `/onboarding` -> Welcome slideshow carousel
*   `/login` -> Phone OTP login
*   `/` (ShellRoute)
    *   `/home` -> Dashboard
    *   `/farm` -> Leaf scanner diagnosis
    *   `/market` -> Agritech marketplace
    *   `/ai` -> Krishi Mitra AI assistant
    *   `/profile` -> Badges & user statistics
*   `/settings` -> App customization, language selector, offline maps

---

## 4. Responsive Framework Breakpoints

To cater to farmers in fields (using phones) and buyers in offices (using tablets/web), the app scales dynamically:

```dart
ResponsiveBreakpoints.builder(
  child: child,
  breakpoints: [
    const Breakpoint(start: 0, end: 450, name: MOBILE),
    const Breakpoint(start: 451, end: 800, name: TABLET),
    const Breakpoint(start: 801, end: 1920, name: DESKTOP),
  ],
)
```
UI layouts dynamically adjust their structure (e.g., using `NavigationRail` on large screens and `FloatingBottomBar` on mobile).

---

## 5. Data Synchronization & Offline Caching (Drift + Supabase)

1.  **Read Strategy:** Always read from local Drift database first for instantaneous loading. Asynchronously fetch from Supabase in the background, update the local database, and trigger a UI refresh.
2.  **Write Strategy:** Queue writes in a local operations table. A background service (using Workmanager) checks connectivity and pushes modifications to Supabase when online.
