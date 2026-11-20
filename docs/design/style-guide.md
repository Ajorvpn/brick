# Brick VPN Design System & Style Guide: "Obsidian Glass & Brick Ember"

## 1. Visual Identity & Design Philosophy

### 1.1 Aesthetic Direction: "Obsidian Glass & Brick Ember"
Brick VPN's visual identity balances cryptographic rigor and modern, tactile consumer craftsmanship. Censorship circumvention tools often fall into one of two extremes: an intimidating, utilitarian terminal interface or a generic, gamified consumer utility. Brick VPN unifies these needs into **Obsidian Glass & Brick Ember**:
- **Dark-First Obsidian Surfaces (`#07090F` / `#111521`):** A deep, ink-like dark background provides high contrast, energy efficiency on OLED panels, and visual depth via elevated surfaces (`#181E2E`) and subtle 8% translucent hairline glass borders (`0x14FFFFFF`).
- **Crafted Ceramic Light Mode (`#F4F6FA` / `#FFFFFF`):** A warm, crisp, non-glare ceramic base tailored for high-ambient-light environments.
- **Brand Brick Ember (`#F97316` Dark / `#C2410C` Light):** Warm, grounded, tactile orange reflecting the physical brick motif. Used as the primary brand accent and the resting idle state of the connection orb.

### 1.2 Trust Psychology & The Peak-End Rule
Connection states represent the primary emotional journey for users operating in restrictive or hostile network environments. The color state progression adheres strictly to security psychology:
1. **Idle / Disconnected (`Brick Ember` `#F97316` / `#C2410C`):** Calm, grounded, non-alarmist. The tool is ready and confident.
2. **Connecting / Reconnecting (`Amber Pulse` `#F59E0B` / `#B45309`):** Active transition. Conveys caution and active cryptographic negotiation without panicking the user.
3. **Connected (`Shield Emerald` `#10B981` / `#047857` with `16% Glow Halo`):** The psychological **Peak** state. Emerald delivers unambiguous reinforcement of privacy, security, and open internet connectivity.
4. **Kill Switch Active & Errors (`Signal Crimson` `#EF4444` / `#DC2626`):** Reserved *strictly* for genuine emergencies, tunnel lockdown, and configuration failure. Crimson is never used decoratively.

---

## 2. Color Palette & 60/30/10 Rule

Every screen follows the **60/30/10 visual balance rule**:
- **60% Dominant Base:** `background` (`#07090F` dark / `#F4F6FA` light)
- **30% Structural Surface:** `surface` & `surfaceElevated` (`#111521` / `#181E2E` dark; `#FFFFFF` / `#EEF2F7` light)
- **10% Intentional Accent:** `brandBrick` or dynamic connection state colors.

### 2.1 Dark Mode Palette ("Obsidian Glass & Brick Ember")

| Semantic Token | Raw Hex / ARGB | Role | WCAG 2.1 AA Contrast Ratio |
|---|---|---|---|
| `background` | `#FF07090F` | 60% App base obsidian background | Base canvas |
| `surface` | `#FF111521` | 30% Card & list tile elevated surface | Surface container |
| `surfaceElevated` | `#FF181E2E` | Modals, bottom sheets, inset elements | Inset / modal surface |
| `glassBorder` | `#14FFFFFF` (~8% White) | Hairline card & container divider borders | Structural divider |
| `textPrimary` | `#FFF8FAFC` | Headings, titles, high-emphasis text | **19.8:1** (on `#07090F`), **18.2:1** (on `#111521`) |
| `textSecondary` | `#FFCBD5E1` | Body copy, subtitles, secondary metadata | **13.5:1** (on `#07090F`), **12.4:1** (on `#111521`) |
| `textMuted` | `#FF8B98B0` | Captions, timestamps, disabled hints | **6.8:1** (on `#07090F`), **6.2:1** (on `#111521`) |
| `brandBrick` | `#FFF97316` | Brick Ember: primary brand accent & idle orb | Brand accent |
| `brandBrickSoft` | `#14F97316` (~8% Ember) | Active tab indicator, pill highlight | Soft accent fill |
| `stateDisconnected` | `#FF64748B` | Slate neutral state indicator | Inactive state |
| `stateConnecting` | `#FFF59E0B` | Amber Pulse: negotiation & handshake | Active state |
| `stateConnected` | `#FF10B981` | Shield Emerald: active tunnel protection | Protected state |
| `stateConnectedGlow` | `#2910B981` (~16% Emerald) | Peak-End connected radial glow halo | Halo effect |
| `stateReconnecting` | `#FFF59E0B` | Amber Pulse: network migration in flight | Migration state |
| `stateDisconnecting` | `#FF94A3B8` | Subtle teardown state indicator | Teardown state |
| `stateError` | `#FFEF4444` | Signal Crimson: errors & exceptions | Error state |
| `killSwitchActive` | `#FFEF4444` | Signal Crimson: full interface lockdown | Lockdown state |
| `tintedShadow` | `#6602040A` | Deep obsidian drop shadow (never flat gray) | Depth elevation |
| `onAccent` | `#FF07090F` | Deep obsidian ink on vibrant accents | High-contrast accent foreground (7.1:1 to 9.1:1) |

### 2.2 Light Mode Palette ("Ceramic Light & Brick Ember")

| Semantic Token | Raw Hex / ARGB | Role | WCAG 2.1 AA Contrast Ratio |
|---|---|---|---|
| `background` | `#FFF4F6FA` | 60% App base ceramic background | Base canvas |
| `surface` | `#FFFFFFFF` | 30% Pure crisp card surface | Surface container |
| `surfaceElevated` | `#FFEEF2F7` | Insets, search bars, pill chips | Inset / modal surface |
| `glassBorder` | `#140F172A` (~8% Slate) | Subtle slate card & divider borders | Structural divider |
| `textPrimary` | `#FF0F172A` | Headings, titles, high-emphasis text | **15.4:1** (on `#F4F6FA`), **16.7:1** (on `#FFFFFF`) |
| `textSecondary` | `#FF334155` | Body copy, subtitles, secondary metadata | **9.6:1** (on `#F4F6FA`), **10.4:1** (on `#FFFFFF`) |
| `textMuted` | `#FF475569` | Captions, timestamps, disabled hints | **6.9:1** (on `#F4F6FA`), **7.5:1** (on `#FFFFFF`) |
| `brandBrick` | `#FFC2410C` | Deep Brick Ember for light-mode contrast | **5.18:1** (on `#FFFFFF`), **4.79:1** (on `#F4F6FA`) |
| `brandBrickSoft` | `#14C2410C` (~8% Ember) | Active tab indicator, pill highlight | Soft accent fill |
| `stateDisconnected` | `#FF64748B` | Slate neutral state indicator | Inactive state |
| `stateConnecting` | `#FFB45309` | Deep amber connecting state | **5.02:1** (white on accent) |
| `stateConnected` | `#FF047857` | Deep emerald connected state | **5.48:1** (white on accent) |
| `stateConnectedGlow` | `#24047857` (~14% Emerald) | Connected state highlight halo | Halo effect |
| `stateReconnecting` | `#FFB45309` | Deep amber reconnecting state | **5.02:1** (white on accent) |
| `stateDisconnecting` | `#FF64748B` | Subtle teardown state indicator | Teardown state |
| `stateError` | `#FFDC2626` | Deep crimson error state | **4.54:1** (white on accent) |
| `killSwitchActive` | `#FFDC2626` | Deep crimson kill switch indicator | Lockdown state |
| `tintedShadow` | `#140F172A` | Slate-tinted soft drop shadow | Depth elevation |
| `onAccent` | `#FFFFFFFF` | Crisp white foreground on vibrant accents | High-contrast accent text (>= 4.5:1) |

*Note: Every text color across both dark and light themes surpasses the WCAG 2.1 Level AA threshold of 4.5:1 for standard text.*

---

## 3. Typography & Open-Source Licensing Compliance

To ensure 100% compliance with GPL-3.0-or-later distribution requirements and user privacy (zero tracking / zero remote font downloading at runtime), Brick VPN uses strictly open-source, permissively licensed typefaces with local system fallbacks:

### 3.1 Font Stack & License Audit

| Font Family | Usage | License | GPL-3.0 Compatibility | Fallback Order |
|---|---|---|---|---|
| **Inter** | Primary UI (Headings, Body, Labels, Controls) | SIL Open Font License 1.1 | **Compatible** (OFL-1.1) | `'Roboto', 'sans-serif'` |
| **JetBrains Mono** | Monospace Telemetry, Speedometers, Ping & Diagnostic Logs | SIL Open Font License 1.1 | **Compatible** (OFL-1.1) | `'RobotoMono', 'monospace'` |
| **Roboto / Roboto Mono** | System Fallbacks on Android | Apache License 2.0 | **Compatible** (Apache-2.0) | Standard system sans/mono |
| **Material Symbols / Icons** | System & UI Iconography | Apache License 2.0 | **Compatible** (Apache-2.0) | Bundled Flutter font |

### 3.2 4-Size UI Type Hierarchy

```
Display:  28sp | Weight: 700 (Bold)        | Leading: 1.2  | Used for: Hero headings & main status
Title:    18sp | Weight: 700 (Bold)        | Leading: 1.25 | Used for: Card titles & modal headers
Body:     14sp | Weight: 500/400 (Med/Reg) | Leading: 1.4  | Used for: Primary content, inputs & lists
Label:    12sp | Weight: 500 (Medium)      | Leading: 1.3  | Used for: Captions, tabs & badges
```

### 3.3 Monospace Telemetry & `tabularFigures()` Rule
In VPN dashboards, real-time metrics update at 1 Hz (e.g. `00:14:32`, `1.42 MB/s`, `42 ms`). Standard variable-width numerals cause horizontal jitter as glyph widths fluctuate.
All monospace telemetry styles (`monoMetricLarge`, `monoMetric`, `monoLog`) enforce:
```dart
fontFeatures: const <FontFeature>[
  FontFeature.tabularFigures(),
]
```
Ensuring all digits occupy uniform horizontal space and eliminate UI vibration.

---

## 4. Spatial Grid, Radius, Elevation & Motion

### 4.1 Strict 8-Point Spatial Grid (`BrickSpacing`)
All padding, margin, and layout dimensions must be cleanly divisible by 4.0 or 8.0:
- `xxs`: 4.0 dp
- `xs`: 8.0 dp
- `sm`: 12.0 dp
- `md`: 16.0 dp (standard screen horizontal margin)
- `lg`: 24.0 dp (standard card padding)
- `xl`: 32.0 dp
- `xxl`: 48.0 dp
- `section`: 64.0 dp
- `hero`: 80.0 dp

### 4.2 Accessibility Touch Targets
Every interactive button, switch, icon button, and list tile must have a minimum bounding touch target of **48.0 x 48.0 dp** (`BrickSpacing.minTouchTarget`), fulfilling WCAG 2.1 Success Criterion 2.5.5.

### 4.3 Corner Radii (`BrickRadius`)
- `xs`: 6.0 dp (chips, small badges)
- `sm`: 8.0 dp (secondary buttons, popovers)
- `md`: 12.0 dp (primary buttons, text input fields)
- `card`: 16.0 dp (standard cards, list containers)
- `cardLarge`: 20.0 dp (featured modal cards)
- `sheet`: 24.0 dp (bottom sheets, dialogs)
- `pill`: 999.0 dp (status pills, active indicator tabs)

### 4.4 Motion & Transitions (`BrickMotion`)
- `fast` (150 ms): Button taps, toggle switches, hover feedback.
- `standard` (250 ms): Sheet reveals, card expansions, tab switches.
- `stateTransition` (350 ms): Connection state color transitions (disconnected -> connecting -> connected).
- `orbPulse` (1800 ms): Ambient breathing animation while connecting.
- `curveStandard`: `Curves.easeOutCubic`
- `curveEmphasized`: `Curves.easeInOutCubicEmphasized`

---

## 5. Iconography & Temporary Geometric Brick Emblem

### 5.1 Iconography
Material Symbols (Outlined style, 24 dp standard bounding box, Apache-2.0) are utilized across all tabs and screens.

### 5.2 Temporary Geometric Brick Emblem (`BrickEmblemPlaceholder`)
Per human architectural decision (2026-11-18), custom high-fidelity brand illustrations and mascot graphics are deferred to a later dedicated pass. Phase 11 uses a clean, vector programmatic mark:
- 3-row staggered masonry shield motif.
- Drawn dynamically via Flutter's `CustomPainter` with rounded rectangular bricks.
- Tinted automatically with `brandBrick` in idle state and `stateConnected` in connected state.
- Drop-in architecture: can be cleanly swapped for vector SVG / asset illustration once finalized.

---

## 6. Architecture & Screen Blueprint Summary (Chunks 2–4)

1. **3-Tab Navigation Shell (Chunk 2 / `P11-T2`):**
   - Bottom navigation bar consolidates to **`Home`**, **`Servers`**, **`Settings`**.
   - `LiveLogsScreen` (`/logs`) relocates into **Settings -> Diagnostic Logs**.
   - Direct action buttons for manual server/subscription entry are hidden from primary navigation while preserving routes (`/add-server`, `/add-subscription`) intact for testing and deep links.
2. **Hierarchical Server Browser (Chunk 2 / `P11-T2`):**
   - Grouping hierarchy: `Country -> City/State -> Server Cards`.
   - Prominent `Update Servers` button providing Hiddify-style opt-in remote feed sync and Play-compliant disclosure.
3. **Core Connection & Live Telemetry (Chunk 3 / `P11-T3`):**
   - 164 dp central connection orb with dynamic ambient glow halo.
   - 1 Hz jitter-free tabular monospace telemetry counters.
4. **Settings & Diagnostic Logs (Chunk 4 / `P11-T4`):**
   - Settings organized into clean 16 dp cards (Connection & Resilience: Auto-Reconnect, Kill Switch, Battery Optimization; Appearance & Language: Theme, Locale; Diagnostics & About: Diagnostic Logs, App Version, GPL-3.0 License, Privacy Policy).
   - High-contrast redacted live log inspection view.

