# Kalsubai Farms Avatar & Illustration System

This document specifies the creation rules, file requirements, and detailed generation prompts for Kalsubai Farms avatars, Kalu mascot variants, and standard app illustrations.

---

## 1. Visual Specification Rules

To maintain absolute style consistency, all generated assets must adhere to the following art directions:

*   **Art Style:** Flat vector illustration with soft semi-3D lighting, organic rounded shapes, and clean, uniform outlines (approx. 2pt weight).
*   **Color Palette:** Strictly restricted to the **Mountain Roots** system colors:
    *   Forest Green (`#0B5D2A`), Leaf Green (`#4CAF50`), Millet Gold (`#CDA434`), Earth Brown (`#7A5230`), and Organic Cream (`#FAF7F0`).
*   **Background:** High-resolution transparent background (PNG format, alpha channel enabled).
*   **Resolution:** Minimum `2048 x 2048` pixels for avatars, and `1024 x 1024` pixels for small icons/illustrations.
*   **View Varieties:**
    *   **Avatars:** Full body version, Front facing headshot, 3/4 Profile angle, and a pre-cropped Circle profile version.
    *   **Mascot (Kalu):** Six emotional expressions and stances.

---

## 2. Character & Avatar Roster

### Avatar 1: Smart Farmer (`smart_farmer.png`)
*   **Identity:** Friendly Maharashtrian farmer from the Sahyadri mountains.
*   **Visual Elements:** Traditional white Gandhi cap, green jacket over a crisp white kurta. Smiling, holding a modern smartphone showing agricultural charts.

### Avatar 2: Woman Farmer (`woman_farmer.png`)
*   **Identity:** Progressive female farmer specializing in millet grains.
*   **Visual Elements:** Wearing a beautiful green cotton saree with gold borders. Holding a tablet device showing crop maps, standing next to a healthy, golden Finger Millet (Nachni) crop.

### Avatar 3: Young Agritech Farmer (`agritech_farmer.png`)
*   **Identity:** Tech-savvy young farmer operating agritech systems.
*   **Visual Elements:** Wearing a modern canvas backpack, holding a drone remote controller with antennas. A futuristic agricultural monitoring quadcopter drone visible in the air behind him.

### Avatar 4: Organic Farmer (`organic_farmer.png`)
*   **Identity:** Natural, sustainable agriculture practitioner.
*   **Visual Elements:** Earthy brown clothing, carrying a hand-woven bamboo basket overflowing with freshly harvested organic vegetables (carrots, tomatoes, leafy greens). Standing in front of a bio-diverse field.

### Avatar 5: Dairy Farmer (`dairy_farmer.png`)
*   **Identity:** Sahyadri livestock manager.
*   **Visual Elements:** Wearing a leaf-green field uniform, standing beside a healthy, friendly Gir cow. Holding an aluminum milk container, smiling warmly.

---

## 3. Official Mascot: Kalu

Kalu is a friendly, mountain-themed personified leaf and farmer hybrid representing Kalsubai mountain.

*   **Base Design:** An anthropomorphic friendly farmer character.
*   **Signature Features:** A cap shaped like Kalsubai Peak, a golden Leaf Badge pinned to his vest, and holding a small stalk of Finger Millet in his hand.

### Mascot Stances (`assets/illustrations/kalu_*`)
1.  **Kalu Full (`kalu_full.png`):** Standard standing pose, full-body view, hands on hips, confident smile.
2.  **Kalu Wave (`kalu_wave.png`):** Waving hand in greeting, welcoming farmers on the Onboarding screen.
3.  **Kalu Happy (`kalu_happy.png`):** Jumping or cheering, used for achievements and completed milestones.
4.  **Kalu Thinking (`kalu_thinking.png`):** One hand on chin, thinking, used during loading and data processing states.
5.  **Kalu Success (`kalu_success.png`):** Thumbs-up, smiling broadly, used when a diagnosis completes or order succeeds.
6.  **Kalu Error (`kalu_error.png`):** Holding a magnifying glass, looking puzzled or worried, used for empty states and network errors.

---

## 4. Prompt Engineering Structure

All prompts stored in `assets/prompts/` are structured to guarantee premium results across **Midjourney**, **Gemini**, **GPT DALL-E**, and **Leonardo AI**.

```
[Subject Details] + [Consistent Style Modifiers] + [Color Constraints] + [Output Formatting]
```

### Style Modifiers Applied:
> "Modern flat 2D vector graphic with soft semi-3D gradients, clean outlines, premium organic shapes, minimal background, transparent background, studio lighting, cozy friendly illustration, 8k resolution, inspired by Google, Notion, and Duolingo illustration styles."

### Color Constraints Applied:
> "Color scheme uses forest greens (#0B5D2A), bright leaf green (#4CAF50), warm millet gold (#CDA434), and earth brown. No harsh neon colors. Soft shadows."
