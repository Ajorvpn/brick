# Phase 11 — Full UI/UX Design & Implementation: Closeout Report

**Task:** `P11-T7` — Phase 11 Closeout and Definition-of-Done Pass
**Status:** `Ready for Human Review` — automated verification is fully green; the physical-device walkthrough in Section 5 is the remaining gate
**Date:** 2026-11-22
**Template:** `AI_ROLES/DEFINITION_OF_DONE.md`

---

## 1. Executive Summary

Phase 11 replaced the deliberately minimal placeholder UI carried over from the Android MVP
(Phases 0–10) with a complete, coherent design system — **"Obsidian Glass & Brick Ember"** — and
propagated it through every screen, the navigation shell, the typography, the motion language, and
the accessibility layer. No VPN engine, parser, storage or security code was redesigned: every
Phase 0–10 functional invariant was treated as frozen.

| Task | Status | Deliverable | Key files |
|---|---|---|---|
| `P11-T1` | `Completed ✅` (human-approved) | Design-system foundation: tokens, palette, typography scale, Material 3 theme, emblem | `packages/ui_theme/lib/src/{brick_colors,brick_tokens,brick_typography,brick_theme}.dart`, `docs/design/style-guide.md` |
| `P11-T2` | `Ready for Human Review` | Obsidian primitives, 3-tab frosted floating dock, hierarchical country → city → server browser, disclosure sheet, obsidian splash | `packages/ui_theme/lib/src/widgets/brick_glass_card.dart`, `brick_protocol_pill.dart`, `brick_status_dot.dart`, `brick_section_header.dart`; `apps/mobile/lib/core/presentation/widgets/app_shell.dart`; `apps/mobile/lib/features/servers/presentation/screens/servers_screen.dart` |
| `P11-T3` | `Ready for Human Review` | Connection orb + telemetry cards, redesigned live-log console, atmosphere layer | `packages/ui_theme/lib/src/widgets/brick_power_orb.dart`, `brick_telemetry_card.dart`; `apps/mobile/lib/features/connection/presentation/screens/home_screen.dart`; `apps/mobile/lib/features/settings/presentation/screens/live_logs_screen.dart` |
| `P11-T4` | `Ready for Human Review` | 3-card settings screen (Connection / Appearance / Diagnostics), first-run onboarding, onboarding-completed gate | `apps/mobile/lib/features/settings/presentation/screens/settings_screen.dart`; `apps/mobile/lib/features/onboarding/presentation/screens/onboarding_screen.dart`; `apps/mobile/lib/core/router/app_router.dart` |
| `P11-T5` | `Ready for Human Review` | Accessibility pass: real frosted dock, 1.5x/2.0x zero-overflow, WCAG AA contrast hardening, TalkBack semantics audit, SC 2.3.3 reduced motion, bundled OFL-1.1 fonts | `apps/mobile/assets/fonts/*`, `apps/mobile/pubspec.yaml`, `packages/ui_theme/lib/src/widgets/brick_status_dot.dart` |
| `P11-T6` | `Ready for Human Review` | Micro-interactions: `BrickSkeletonBox` skeletons, tactile haptics, atmosphere cross-fade, `AnimatedSize` accordions, `BrickTypography.uiStyle` | `packages/ui_theme/lib/src/widgets/brick_skeleton_box.dart`, `packages/ui_theme/lib/src/widgets/brick_glass_card.dart`, `packages/ui_theme/lib/src/brick_typography.dart`; `apps/mobile/lib/features/connection/presentation/screens/home_screen.dart` |
| `P11-T7` | `Ready for Human Review` | This closeout report, automated design-system contract suite, full monorepo verification | `docs/design/phase11-ui-ux-closeout-report.md`, `apps/mobile/test/phase11_ui_ux_closeout_test.dart` |

**Bottom line:** Phase 11 is complete and fully green — **644/644** `packages/*` tests and
**437/437** `apps/mobile` tests pass, `flutter analyze` is clean in every package, and the
design-system contract is frozen by an automated suite. The only remaining gate is the human
physical-device walkthrough in Section 5: Chunk 7's device leg reported
`ADB_STATUS=no_device_detected`, so no on-device evidence is claimed.

---

## 2. Design System & Engineering Contract Matrix

### 2.1 Palette and WCAG 2.1 AA contrast

| Contract | Enforcement |
|---|---|
| 4-size / 3-weight typography (`w400`, `w500`, `w700` only; no `w600`, no `13sp`) | `BrickTypography` constants; `phase11_ui_ux_closeout_test.dart` Test 4 asserts zero `FontWeight.w600` **and** zero `fontSize: 13` across all six files |
| Every text/accent pair ≥ 4.5:1 (AA), every state accent ≥ 3.0:1 against `surfaceElevated` (SC 1.4.11) | `brick_connection_widgets_test.dart` Test 5 recomputes contrast math |
| Light-mode live-log level pills hardened to `#92400E` (warning, 5.89:1), `#9A3412` (info, 6.04:1), `#B91C1C` (error) | `p11_t5_accessibility_audit_test.dart` |
| `Colors.white` never painted on `brandBrick` fills — `colors.onAccent` instead | `phase11_ui_ux_closeout_test.dart` Test 4: zero `foregroundColor: Colors.white` in all six files, and `colors.onAccent` present in `home_screen.dart`, `settings_screen.dart`, `live_logs_screen.dart` and `onboarding_screen.dart` |
| No `color` + `gradient` in a single `BoxDecoration` | `brick_connection_widgets_test.dart` Tests 2, `brick_micro_interactions_test.dart` Test 2 |

### 2.2 Bundled SIL OFL-1.1 typography (Invariant 37)

| Contract | Value / enforcement |
|---|---|
| Runtime network font fetching | **Zero.** No `google_fonts` dependency; `phase11_ui_ux_closeout_test.dart` Test 2 asserts its absence |
| Assets | `InterVariable.ttf` (879,708 B) + `JetBrainsMono-{Regular,Medium,Bold}.ttf` (25,260 / 25,180 / 25,228 B) = **955,376 B** total |
| Licences in-repo | `OFL-Inter.txt` (4,380 B), `OFL-JetBrainsMono.txt` (4,399 B) |
| Optical weights | `Inter` is one variable file, so every style carries an explicit `FontVariation('wght', 400/500/700)`; `BrickTypography.uiStyle(...)` is the only sanctioned way to build a bespoke `Inter` label |
| Registration | `pubspec.yaml` families are byte-identical to `BrickTypography.primaryFontFamily` (`Inter`) and `monoFontFamily` (`JetBrains Mono`) |

### 2.3 Real frosted glass dock

- `AppShell` uses `Scaffold(extendBody: true)` with **no** opaque background wrapper, so the
  `BackdropFilter` blurs scrolled content instead of a flat canvas.
- Surface and specular sheen are two separate `DecoratedBox` layers (`brick_dock_surface_layer`,
  `brick_dock_sheen_layer`) — `color` and `gradient` never share one decoration.
- The dock contains **zero** `Opacity` widgets and exactly three destinations, each
  `>= BrickSpacing.minTouchTarget` (48dp) — implemented as `minHeight: 52` at `app_shell.dart:227`
  and verified by rendered-size assertions in `app_shell_test.dart` and
  `p11_t5_accessibility_audit_test.dart`.
- Every scrolling surface reserves a dock-aware bottom inset: `HomeScreen`, populated
  `ServersScreen` and `SettingsScreen` use `MediaQuery.paddingOf(context).bottom + BrickSpacing.xl`;
  the empty `ServersScreen` uses `+ BrickSpacing.lg`; `LiveLogsScreen` uses
  `bottomInset + BrickSpacing.section` on its list and plain `bottomInset` on its jump-to-latest FAB.

### 2.4 State truth and perceived performance

| Invariant | Enforcement |
|---|---|
| `VpnEngine` Invariant 1 — zero optimistic state (a tap is a request, never a status) | `p11_t6_micro_interactions_test.dart` Test 2: tap → `engine.startCalls == 1`, orb stays `disconnected`, `'Connected'` never appears |
| `P6-T2` 1 Hz rebuild isolation (ARCHITECTURE §8.2) | Same test: five `TrafficStats` ticks update `ThroughputReadout` to `5.0 KiB` / `10.0 KiB` while the `BrickPowerOrb` widget instance stays identical |
| `BrickSkeletonBox` perceived-performance loading | `p11_t6_micro_interactions_test.dart` Tests 1 and 4 (both shimmer modes, both breakpoints, both themes); `brick_micro_interactions_test.dart` Test 2 |
| Tactile haptics acknowledge gestures only | `mediumImpact` on the orb; `selectionClick` on glass cards, dock branch changes, accordion toggles, settings switches, onboarding completion |
| WCAG 2.1 SC 2.3.3 — every animation honours `MediaQuery.disableAnimationsOf(context)` | `brick_power_orb.dart`, `brick_status_dot.dart`, `brick_skeleton_box.dart`, `brick_glass_card.dart`, plus all screen-level containers; guarded by `phase11_ui_ux_closeout_test.dart` Test 5 |

### 2.5 Security and privacy preservation (unchanged by Phase 11)

| Guarantee | Where it lives | Phase 11 touch |
|---|---|---|
| Android Keystore AES-256-GCM server-profile storage | `apps/mobile/lib/core/data/…`, `packages/vpn_engine_android` | None (frozen) |
| 3-surface log redaction (UI, file, clipboard) | `packages/shared_utils`, `log_redaction_test.dart` | Log *presentation* restyled only |
| Play-compliant `UpdateServersDisclosureSheet` | `apps/mobile/lib/features/servers/presentation/widgets/` | Restyled, copy preserved |
| `brick.preferences.onboarding_completed` stored at `None` sensitivity | `app_preferences_repository.dart` | Introduced by `P11-T4` |
| GPL-3.0-or-later attribution + privacy policy sheet | `settings_screen.dart` → `showLicensePage(useRootNavigator: true)` | Restyled, contract preserved |
| Zero telemetry / analytics / ad SDKs | manifest, `pubspec.yaml`, Gradle | Untouched; `supply_chain_and_manifest_security_test.dart` still green |

---

## 3. Automated Verification Ledger (measured 2026-11-22, Chunk 7)

Authoritative log: `/home/bellard/Documents/brick log/log1.txt` (Stage 4 verbatim run).

### 3.1 Every `packages/*` suite — PASS

| Package | Analyze | Tests |
|---|---|---|
| `core_domain` | clean | **132 passed** |
| `config_parser` | clean | **398 passed** |
| `core_vpn_engine` | clean | **50 passed** |
| `shared_utils` | clean | **25 passed** |
| `ui_theme` | clean | **19 passed** |
| `vpn_engine_android` | clean | **20 passed** |
| **Total** | **6/6 clean** | **644 passed, 0 failed** |

### 3.2 Entire `apps/mobile/test/` suite — 437 passed, 0 failed

`flutter analyze` in `apps/mobile`: **clean** (0 issues, `ANALYZE(mobile)=0`).

**Totals:** **437 passed, 0 failed** across all 57 test files, run concurrently with
`--concurrency=$(nproc)`. `phase8_e2e_security_journey_test.dart` is green both in isolation and
inside the concurrent whole-tree run.

### 3.3 Remediation record — test-alignment debt, not a product regression

The first closeout run found 30 failing legacy tests (401 passed / 30 failed across the 431
pre-existing mobile tests before adding the 6-test closeout suite, which brings the green total
to 437). Investigation showed they were **stale test expectations**, not product defects, and the
human-confirmed decision was to keep production UI frozen and align the tests instead:

1. **`/add-server` and `/add-subscription` are intentionally without manual buttons.**
   Human-Approved UX Refinement #3 (`ARCHITECTURE.md` Chunk 2C, §13.3): both manual entry buttons
   are intentionally hidden on `HomeScreen` and `ServersScreen` (the subscription strip only
   exposes Refresh and Delete for linked feeds), while both `/add-server` and `/add-subscription`
   routes remain registered and reachable programmatically.
   `servers_screen_test.dart`,
   `add_subscription_screen_test.dart`, `connection_flow_test.dart` and
   `phase5_e2e_journey_test.dart` were already aligned to this pattern; five suites were missed
   during Chunk 3B-3.
2. **`pumpAndSettle()` is not a valid primitive on a stateful home screen.** The orb keeps a
   rotation ticker while transitional and a breathing ticker while connected (P11-T3 design), so
   an animation that never stops can never be "settled" — the harness's trailing
   `pumpAndSettle()` timed out even before a test body ran.

**What changed (test files only; zero production files touched):**

| Suite | Fix | Result |
|---|---|---|
| `add_server_screen_test.dart` | 8 × `tester.tap(find.text('Add Server'))` → `unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'))` | 8/8 |
| `qr_scan_screen_test.dart` | 6 × same approved route-push pattern | 9/9 |
| `lifecycle_resync_test.dart` | Local `_pumpBoundedHome` mirroring the harness overrides but with bounded `pump()`; `_settleAnimated` for the Connected transitions | 5/5 |
| `process_restart_reattach_test.dart` | Same bounded-pump helper; the legacy `FilledButton` frame-0 assertion re-pointed at the `home_connect_toggle_button` orb toggle | 4/4 |
| `legacy_chaos_regression_suite_test.dart` | Bounded pumps throughout; the `TextButton('Connect')` finder re-pointed at `home_connect_toggle_button` and its disabled-state assertion at `BrickPowerOrb.onTap` being `null` | 12/12 |
| `phase8_e2e_security_journey_test.dart` | No change needed — it passes in isolation **and** under `--concurrency=$(nproc)` once the five hung suites stopped starving the runner | 1/1 |

Every functional, security, redaction and resilience assertion is unchanged; only navigation and
synchronization primitives were realigned.

### 3.4 Live physical device

`adb devices -l` reports an empty device list → `ADB_STATUS=no_device_detected`. No APK build,
install, PID or logcat result is claimed anywhere in this report.

---

## 4. Automated Design-System Contract Suite

`apps/mobile/test/phase11_ui_ux_closeout_test.dart` freezes the Phase 11 contract so later phases
cannot silently regress it:

1. **Deliverables & SPDX integrity** — style guide, this report, onboarding screen and all seven
   `packages/ui_theme` primitives exist, are non-empty, and every `.dart` file starts with
   `// SPDX-License-Identifier: GPL-3.0-or-later`.
2. **Bundled OFL-1.1 fonts & Invariant 37** — `pubspec.yaml` registers `Inter` and `JetBrains Mono`,
   contains no `google_fonts`, and all four `.ttf` files plus both OFL notices exist with valid sfnt
   headers and a total `.ttf` payload under 5 MB.
3. **EN ↔ FA localization parity** — recursive key-path comparison, non-empty leaves, verbatim
   `{placeholder}` parity, exactly one trailing newline in each file, and no `de.json` in the bundle
   (German was retired in Alignment #1B in favour of Persian, which renders right-to-left with
   explicit LTR islands around technical VPN data).
4. **Design-system anti-regression source guard** — across the five redesigned screens plus
   `AppShell`: zero `FontWeight.w600`, zero `Colors.orange`, zero `fontFamily: 'monospace'`, zero
   `fontSize: 13`, zero `foregroundColor: Colors.white`; `colors.onAccent` present in
   `home_screen.dart`, `settings_screen.dart`, `live_logs_screen.dart`, `onboarding_screen.dart`;
   `extendBody: true` present and zero `Opacity(` in `app_shell.dart`; the router gates
   `/onboarding` with `ref.read(onboardingCompletedProvider)`, never `ref.watch`.
5. **Reduced motion & optical typography** — `brick_power_orb.dart`, `brick_status_dot.dart`,
   `brick_skeleton_box.dart` and `brick_glass_card.dart` all read
   `MediaQuery.disableAnimationsOf(context)`; `BrickTypography.uiStyle` attaches `wght` 400/500/700.
6. **Governance consistency** — ARCHITECTURE sections 13.3–13.7 present with no `Section 13.x`
   placeholders; `P11-T1` `Completed ✅`; `P11-T2`–`P11-T6` `Ready for Human Review`; `P11-T7`
   recorded honestly as `Blocked`.

---

## 5. Human Physical-Device Walkthrough & Sign-Off Checklist

Every item below is `[ ]` **Pending Human Sign-Off**. Completing them is what promotes
`P11-T2`–`P11-T7` from `Ready for Human Review` to `Completed ✅`.

### 5.1 Device setup

- [ ] Authorize a physical Android device for USB debugging (`adb devices -l` must list it — Chunk 7
      reported `ADB_STATUS=no_device_detected`).
- [ ] `cd apps/mobile && flutter build apk --debug --target-platform android-arm64 && adb install -r build/app/outputs/flutter-apk/app-debug.apk`
- [ ] Launch and confirm the launcher icon, the Deep Obsidian (`#07090F`) splash screen, and that
      the app boots straight into onboarding on first install (`P11-T2`, `P11-T4`).

### 5.2 Screen-by-screen visual walkthrough

- [ ] **`OnboardingScreen`** — three steps (Private by Design / Your Servers, Your Control / Android
      VPN Permission), 3-dot indicator, Skip/Back/Next/Get Started, and the Android
      `VpnService.prepare()` consent dialog on the first Connect (`P11-T4`).
- [ ] **`HomeScreen`** — all seven orb states (disconnected, connecting, connected, reconnecting,
      disconnecting, error, kill-switch), the atmosphere gradient, active-server card, telemetry
      cards, and the loading skeleton while the repository resolves (`P11-T3`, `P11-T6`).
- [ ] **`ServersScreen`** — country → city → server hierarchy, search, accordion expansion, active
      spotlight, subscription strip, broken-server section, `UpdateServersDisclosureSheet`, **and
      the add-server / add-subscription path** (`P11-T2`, Section 3.3).
- [ ] **`LiveLogsScreen`** — monospace entries, level rail, copy/clear 48dp actions, non-dismissible
      privacy dialog, jump-to-latest FAB clearing the dock (`P11-T3`).
- [ ] **`SettingsScreen`** — three cards, theme/language pickers, auto-reconnect and kill-switch
      toggles, battery-optimization row, privacy-policy sheet, `GPL-3.0-or-later` license page (`P11-T4`).
- [ ] **Floating dock** — `BackdropFilter` visibly blurs scrolled content under all three tabs.

### 5.3 Accessibility and motion

- [ ] **TalkBack walkthrough** across all five screens plus the dock: label, role, selected state and
      reading order; confirm the decorative onboarding dots/squircles stay silent and only
      `Step X of 3` is spoken (`P11-T5`).
- [ ] **Large text** at 1.5x and 2.0x system font scale on a 360dp-wide device — zero clipping.
- [ ] **60 fps transition smoothness** with Flutter's performance overlay while switching tabs,
      expanding a country accordion, and moving through connecting → connected (`P11-T6`).
- [ ] **Reduced motion** (Settings → Remove animations): skeletons static, orb arc static, no
      shimmer, no page-slide in onboarding (`P11-T5`).

### 5.4 Phase 9 manual QA regression re-run (`P11-T7`)

- [ ] Re-run the Phase 9 manual QA protocol against the redesigned app (connect / disconnect /
      reconnect, kill switch, auto-reconnect, log redaction, process-restart re-attach, battery
      optimization prompt) and record zero functional regressions.

### 5.5 Separately tracked: post-MVP connectivity (`P10-HF1`)

Not part of Phase 11 sign-off — listed so it is not lost:

- [ ] Rebuild `libbox.aar` against a sing-box `v1.12+` core, flip `enable112Fragmentation` to `true`
      at the engine call site, retest on MCI/Irancell, and (optionally) re-run the Kotlin
      `PigeonVpnApiImplTest` DoH assertions that were never executed.

---

## 6. Phase 12 Handoff

Phase 11 hands Phase 12 (Desktop Support) a **stable, polished Android reference implementation**:
a frozen design system (`packages/ui_theme`), a documented motion and reduced-motion contract, a
bundled-typography policy, a verified accessibility posture, and a 644-test package baseline.

Phase 12 should reuse the *visual and interaction language* — tokens, typography, glass surfaces,
state-truth orb semantics, skeleton loading, haptic-equivalent feedback, WCAG contrast discipline —
while writing its own platform layer: the daemon + authenticated IPC architecture from
`ARCHITECTURE.md` §3.6, not the Android platform-channel plumbing (`vpn_engine_android`,
`VpnService`, Kotlin Pigeon bindings), which stays Android-only.

---

## 7. Self-Review

- **Race conditions:** no production code changed in this chunk; the analysed suites exercise the
  frozen engine and controller layers unchanged.
- **Error paths:** the test-alignment debt found by the first closeout run is documented with the
  exact per-suite counts and the applied fixes (Section 3.3), not summarized away.
- **Resource cleanup:** `BrickSkeletonBox`, the orb and the status dot all stop *and reset* their
  tickers on reduced motion and dispose cleanly (proved by `brick_micro_interactions_test.dart`).
- **Security/privacy:** no secret, keystore, credential or private endpoint appears in this report;
  all identifiers quoted are file paths, class names or hashes.
- **Performance:** the 1 Hz isolation contract is machine-checked (Section 2.4).
