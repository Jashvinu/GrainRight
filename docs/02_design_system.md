# Kalsubai Farms Design System: "Mountain Roots"

This document establishes the official specifications and design tokens for the Kalsubai Farms platform. All components, screens, and custom elements must strictly conform to these rules to maintain design consistency and a premium brand feel.

---

## 1. Color System

We avoid generic primary/secondary colors. Every color is inspired by the Sahyadri mountains and organic farming roots.

| Token Name | Key / Use Case | Hex Value | Primary UI Usage |
| :--- | :--- | :--- | :--- |
| **Kalsubai Green** | Primary Action / Branding | `#0B5D2A` | Buttons, navigation icons, primary headers, active states. |
| **Leaf Green** | Secondary / Success Status | `#4CAF50` | Crop health indicators, success checkmarks, positive trends. |
| **Millet Gold** | Accent / Premium / Badges | `#CDA434` | Premium listings, achievement stars, reward counts, alert badges. |
| **Earth Brown** | Detail / Brand Illustration | `#7A5230` | Agricultural detailing, secondary text accents, soil health data. |
| **Organic Cream** | Background Base | `#FAF7F0` | Default light scaffold background. **Pure white (`#FFFFFF`) is banned for background screens.** |
| **Charcoal Dark** | Text Primary | `#1E1E1E` | Primary headings, readable text paragraphs. |
| **Warm Gray** | Text Muted / Borders | `#757575` | Subtitles, disabled states, divider lines, form borders. |
| **Card Surface** | Component Base | `#FFFFFF` | Card surfaces, dialog backgrounds, input fields. |

---

## 2. Typography

All typography is rendered using Google Fonts.

*   **Heading Font:** `Poppins` (specifically `Poppins SemiBold` for titles and card headers).
*   **Body Font:** `Inter` (specifically `Inter Medium` or `Inter Regular` for description blocks and table fields).
*   **Marathi Support:** `Noto Sans Devanagari` (matches Poppins for headers and Inter for body text automatically via fallback configuration).

### Hierarchy Specs
*   **Display Large:** Poppins Bold 32px | line-height 40px | letter-spacing -0.5px (Splash logo, hero greetings)
*   **Heading Large:** Poppins SemiBold 24px | line-height 30px | letter-spacing -0.3px (Page headers)
*   **Heading Medium:** Poppins SemiBold 18px | line-height 24px | letter-spacing -0.2px (Card headers, dialog titles)
*   **Body Large:** Inter Medium 16px | line-height 22px | letter-spacing 0.0px (Input text, main descriptions)
*   **Body Medium:** Inter Regular 14px | line-height 20px | letter-spacing 0.0px (Standard card text, details)
*   **Label Small:** Inter SemiBold 12px | line-height 16px | letter-spacing 0.5px (Badges, navigation labels)

---

## 3. Elevation & Shadows

We do not use default Material elevation shadows which tend to look harsh. Instead, we use soft, diffused ambient drop shadows.

*   **Elevation None:** Flat borders. Used for input fields.
*   **Elevation Low (Soft shadow):**
    *   `Offset(0, 4)` | `BlurRadius: 16` | `Color: Color(0x080B5D2A)` (tinted with primary green).
    *   Used for standard cards (Weather, Marketplace cards).
*   **Elevation Medium (Elevated hover):**
    *   `Offset(0, 8)` | `BlurRadius: 24` | `Color: Color(0x0C0B5D2A)`.
    *   Used for floating action buttons, bottom bars, and critical action panels.
*   **Elevation High (Overlay / Dialogs):**
    *   `Offset(0, 16)` | `BlurRadius: 40` | `Color: Color(0x120B5D2A)`.
    *   Used for system modals, bottom sheets, and diagnostics results card.

---

## 4. Radius System

Every container boundary is smooth, giving a modern, friendly feeling. No square corners.

*   **Small (12px):** Buttons, chips, text inputs, small badges.
*   **Medium (18px):** Category cards, marketplace product grid cells, quick actions.
*   **Large (24px):** Flagship dashboard widgets, detail pages headers, dialog overlays.
*   **Extra Large (32px):** Floating bottom navigation bar, user profile headers.

---

## 5. Spacing System (8pt Base Grid)

All padding, margins, gaps, and sizes are multipliers of 8px.

*   **4px (0.5x):** Micro spacings (text-to-icon gap).
*   **8px (1.0x):** Small padding (padding inside chips, tiny list view items).
*   **12px (1.5x):** Medium spacing (gap between title and description, form field gaps).
*   **16px (2.0x):** Page margins, padding inside standard cards.
*   **24px (3.0x):** Large margins, gaps between major sections.
*   **32px (4.0x):** Bottom sheet safety buffers, profile section gaps.
*   **48px (6.0x) / 64px (8.0x):** Hero banners height metrics, empty states spacing.

---

## 6. Grid & Responsiveness

*   **Mobile Layout:** 4-column layout | 16px outer margin | 12px gutter spacing.
*   **Tablet Layout:** 8-column layout | 24px outer margin | 16px gutter spacing.
*   **Desktop/Web Layout:** 12-column layout | 32px outer margin | 24px gutter spacing | Max content width constrained to `1200px` to maintain premium presentation.

---

## 7. Iconography

We do not use standard filled Material icons.
*   Use outlined icons with a consistent stroke weight of **2.0px**.
*   We use standard Material icons but strictly configure them as `Icons.outlined` and style their size/color to match the system.
*   For navigation, we use custom outlined icons:
    *   **Home:** Custom outlined cottage/farm icon.
    *   **Farm/Diagnosis:** Outlined scan/leaf icon.
    *   **Marketplace:** Outlined shopping-bag icon.
    *   **Krishi Mitra AI:** Custom friendly chat/robot icon.
    *   **Profile:** Outlined user icon.

---

## 8. Motion & Animations

Powered by `flutter_animate` to ensure fluid transitions.

*   **Transitions:**
    *   Page shifts: Horizontal slide-in with fade (300ms duration, `Curves.easeOutCubic`).
    *   Card loading: Soft fade and scale up from bottom (400ms duration, `Curves.decelerate`).
    *   Button feedback: Dynamic press shrink (`transform: Matrix4.identity()..scale(0.95)` on tap).
*   **Mascot animations:**
    *   Kalu Mascot floats gently in empty states (sine wave translation, 3000ms duration).

---

## 9. Dark Theme Rules: "Night Soil"

When switching to dark mode, Kalsubai Farms remains premium and organic. We avoid pure pitch black `#000000`.

| Token Name | Light Value | Dark Value | Dark Mode Usage |
| :--- | :--- | :--- | :--- |
| **Scaffold BG** | `#FAF7F0` | `#111613` | Deep organic forest charcoal. |
| **Surface** | `#FFFFFF` | `#1A221D` | Slightly lighter forest-tinted gray-green. |
| **Primary Green**| `#0B5D2A` | `#2D9C59` | Brightened green for readability. |
| **Secondary Green**| `#4CAF50` | `#66BB6A` | Desaturated green for eye comfort. |
| **Accent Gold** | `#CDA434` | `#DFB847` | Golden warm yellow. |
| **Text Primary** | `#1E1E1E` | `#F0EFEA` | Cream-white. |
| **Text Secondary**| `#757575` | `#A5AFA8` | Pale gray-green. |
| **Shadows** | `0x080B5D2A` | `0x1A000000` | Dimmed ambient shadows. |

---

## 10. Component Rules

1.  **Stateful Feedback:** Every button and card must display an active hover/press state (slight color shift, scale shrink, or shadow reduction).
2.  **Semantic markup:** Interactive components must be wrapped in `Semantics` with appropriate label and trait properties for screen reader access.
3.  **Loading states:** Shimmer effect using primary green tint instead of grey bars (`#FAF7F0` transitioning to `#EFECE5`).
4.  **Error boundaries:** Visual panels containing the Kalu mascot in error mode, explaining the issue in simple Marathi/English.
