# Kalsubai Farms Reusable Component Library

This document outlines the API specifications, structural tokens, and behavioral rules for Kalsubai Farms' reusable Flutter widget library.

---

## 1. Buttons

### Primary Button (`KalsubaiPrimaryButton`)
*   **Purpose:** Primary call-to-action (e.g. login, verify, scan, place order).
*   **Design Tokens:**
    *   Background: `primaryGreen` (`#0B5D2A` light, `#2D9C59` dark)
    *   Foreground: White (`#FFFFFF`) or Black (`#000000`)
    *   Radius: `radiusSmall` (12dp)
    *   Typography: `Poppins Bold 15px`
    *   Padding: `EdgeInsets.symmetric(horizontal: 24, vertical: 16)`
*   **Feedback:** Press shrink scaling (using `flutter_animate` to shrink to 0.96x scale on tap).
*   **API:**
    ```dart
    const KalsubaiPrimaryButton({
      required String text,
      required VoidCallback onPressed,
      bool isLoading = false,
      IconData? icon,
    });
    ```

---

## 2. Cards

### Metric / Info Card (`KalsubaiCard`)
*   **Purpose:** Base wrapper for all features, weather summaries, and marketplace items.
*   **Design Tokens:**
    *   Background: `surface` (`#FFFFFF` light, `#1A221D` dark)
    *   Border: `Border.all(color: grey.shade200)` (light), `Border.all(color: grey.shade800)` (dark)
    *   Radius: `radiusMedium` (18dp)
    *   Shadow: `AppTheme.getShadow()` (soft primary green ambient shadow)
    *   Padding: `16dp` default internal padding.
*   **API:**
    ```dart
    const KalsubaiCard({
      required Widget child,
      VoidCallback? onTap,
      EdgeInsetsGeometry? padding,
    });
    ```

### Weather Card (`KalsubaiWeatherCard`)
*   **Purpose:** Summarize current weather and rain forecast on the main dashboard.
*   **Design Tokens:**
    *   Accent highlight: `milletGold` (`#CDA434`) for warning indicators
    *   Radius: `radiusMedium` (18dp)

### Marketplace Card (`KalsubaiProductCard`)
*   **Purpose:** Ecommerce display card for crops and milk.
*   **Features:** Product image viewport, price tags with primary color highlighting, organic/verified farmer badges.

---

## 3. Inputs

### Search Bar (`KalsubaiSearchBar`)
*   **Purpose:** Filtering marketplace items and community topics.
*   **Design Tokens:**
    *   Border: `radiusSmall` (12dp) with soft neutral borders.
    *   Icon: Left-aligned outlined magnifying glass icon.
    *   Placeholder: Warm gray hint text.
*   **API:**
    ```dart
    const KalsubaiSearchBar({
      required ValueChanged<String> onChanged,
      String hintText = "Search...",
    });
    ```

---

## 4. Dialogs & Modals

### System Dialog (`KalsubaiDialog`)
*   **Purpose:** Action confirmations, errors, and system warnings.
*   **Design Tokens:**
    *   Radius: `radiusLarge` (24dp)
    *   Background: Light cream/surface, high elevation.
*   **API:**
    ```dart
    static void show({
      required BuildContext context,
      required String title,
      required String content,
      String? confirmText,
      VoidCallback? onConfirm,
    });
    ```

### Bottom Sheet (`KalsubaiBottomSheet`)
*   **Purpose:** Crop remedy detail display, filters selection.
*   **Design Tokens:**
    *   Top Radius: `radiusLarge` (24dp)
    *   Top Indicator: Neutral grab handle.

---

## 5. App Bars

### Custom Navigation App Bar (`KalsubaiAppBar`)
*   **Purpose:** Clean back navigations and branding labels.
*   **Design Tokens:**
    *   Font: `Poppins Bold 20px`
    *   Color: Surface, no elevation shadow. Left aligned logo.
*   **API:**
    ```dart
    PreferredSizeWidget KalsubaiAppBar({
      required String title,
      List<Widget>? actions,
      bool showLeading = true,
    });
    ```

---

## 6. Mascot Views (`KaluMascotView`)

*   **Purpose:** Dynamic rendering of Kalu mascot depending on the app state.
*   **States supported:**
    *   `KaluState.wave` (greeting)
    *   `KaluState.thinking` (processing/loading)
    *   `KaluState.success` (task accomplished)
    *   `KaluState.error` (network or validation issue)
*   **Features:** Floating micro-animations using `Flutter Animate` to make the mascot bob up and down.

---

## 7. Data Visualization (Charts)

### Crop Growth & Price History Charts (`KalsubaiChart`)
*   **Purpose:** Visualizing farm progress and sales values using `fl_chart`.
*   **Design Tokens:**
    *   Line color: `primaryGreen` (`#0B5D2A`)
    *   Grid borders: Soft gray dashed lines.
    *   Background: Tinted surface background.
