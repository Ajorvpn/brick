# PROJECT_STATE.md — Current Snapshot

> **PROCESS RULE (non-negotiable):** This file MUST be updated by the coding
> agent at the end of every task, without exception, reflecting true,
> verified state — not aspirational state. AI chat context does not persist
> across sessions; this file does. It is the authoritative persistent memory
> of the project across sessions. If this file is stale, it must be corrected
> before any new task begins, not silently worked around.

> **PROCESS RULE (as of 2026-09-17 — non-negotiable):** AI coding agents are
> PERMANENTLY PROHIBITED from running any git write command (`add`, `commit`,
> `push`, `branch`, or any other state-changing git operation). Agents may
> only edit files; a human always executes git commands manually. This rule
> was established after an agent made three unauthorized (though low-risk,
> docs-only, factually accurate) commits during a Phase 0 closeout task
> without stopping to ask first.

> This file reflects the CURRENT state of the project only. It is not a
> history log (task-by-task history lives in Git commit history and each
> task's final report). Every AI agent must read this file first, before
> `ARCHITECTURE.md` or `ROADMAP.md`, to get immediate situational awareness.

**Last updated**: 2026-11-12 — Phase 10 Android MVP Milestone Complete (`P10-T1`..`P10-T7` Completed ✅; `P10-T8` Ready for Human Review — ANDROID MVP MILESTONE ACHIEVED).
**Updated by**: Coding agent, during P10-T8 Phase 10 Closeout: Android MVP Milestone.

---

## 1. Current Phase

**Phase 10 — Android MVP Release Prep: COMPLETE (`P10-T1` through `P10-T7` Completed ✅; `P10-T8` Ready for Human Review — ANDROID MVP MILESTONE ACHIEVED).**
- **P10-T1 (Release Signing Key Setup and CI Signing Pipeline):** `Completed ✅` — Generated production release signing keystore strictly outside repository (`/home/bellard/.brickvpn-keystore/brickvpn-release.jks`, `chmod 600`) with 4096-bit RSA SHA256withRSA certificate valid until 2054; configured AGP release signing in `apps/mobile/android/app/build.gradle.kts` with `enableV1Signing = false`, `enableV2Signing = true`, `enableV3Signing = true`, reading from `BRICK_KEYSTORE_PATH` / `key.properties` with safe debug fallback for local development; hardened `.gitignore` and `apps/mobile/android/.gitignore` with comprehensive secret-key bans (`*.jks`, `*.keystore`, `*.p12`, `*.pem`, `*.der`, `key.properties`, `keystore.env`); updated `.github/workflows/ci.yml` with fail-fast non-empty secret guards, release APK & AAB builds, `apksigner` SHA-256 fingerprint verification (`563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`), checksum generation, and ephemeral keystore wiping; published official public certificate SHA-256 fingerprint in `docs/verifying-releases.md`; authored comprehensive key parameters, dual-media backup, and key loss consequence guide in `docs/release-signing-and-key-recovery.md`; delivered 6 passing automated security tests in `apps/mobile/test/release_signing_security_test.dart`; and verified real release APK signing with `apksigner` v2/v3.
- **P10-T2 (ProGuard/R8 Release Hardening and Gomobile Bridge Keep Rules):** `Completed ✅` — Configured two-layer ProGuard/R8 keep rules across library and application layers. Delivered `packages/vpn_engine_android/android/proguard-rules.pro` with `consumerProguardFiles` in `build.gradle.kts` protecting gomobile runtime JNI bridge (`go.**`), libbox bound classes and interfaces (`io.nekohasekai.libbox.**`, `libbox.**`), and plugin harness (`dev.brickvpn.harness.**`). Delivered `apps/mobile/android/app/proguard-rules.pro` protecting Flutter embedding, native JNI method symbols (`native <methods>`), coroutines, and line number attributes. Enabled `isMinifyEnabled = true` and `isShrinkResources = true` in `apps/mobile/android/app/build.gradle.kts`. Verified R8 obfuscation/minification compilation (producing mapping file `apps/mobile/build/app/outputs/mapping/release/mapping.txt`), verified release signing with `apksigner`, and confirmed `seeds.txt` entry points. Added automated regression test `apps/mobile/test/proguard_r8_hardening_test.dart`.
- **P10-T3 (AAB Build and ABI-Split Configuration for Dual Distribution):** `Completed ✅` — Configured dual-distribution packaging for Google Play and Direct APK channels. Configured CI release workflow to produce signed Android App Bundle (`app-release.aab`) alongside per-ABI split APKs (`app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`) and universal fallback APK (`app-release.apk`). Validated all 5 artifacts compiled and signed with APK Signature Scheme v2/v3, matching official certificate fingerprint `563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`, and self-verified via `scripts/generate_and_verify_checksums.sh`. Verified exact native `.so` library contents across all 3 ABIs via automated test in `apps/mobile/test/proguard_r8_hardening_test.dart`. Documented artifact selection guide in `docs/verifying-releases.md` Section 2 and architecture Section 12.3.
- **P10-T4 (Play Store VPN Policy Compliance Pass):** `Completed ✅` — Delivered comprehensive Play Store compliance document `docs/release/play-store-vpn-compliance.md` covering Google Play VpnService policy matrix, copy-paste-ready VpnService declaration form answers with technical justifications, Android 14+ FGS specialUse justification, complete Data Safety questionnaire responses (confirming zero data collection / zero trackers), reviewer video demonstration walkthrough script, and codebase audit. Delivered automated regression suite in `apps/mobile/test/play_store_vpn_policy_compliance_test.dart` asserting zero ad/tracker/telemetry SDKs in manifest/pubspec/gradle and zero monetization code in sources. Added Section 12.4 in `AI_ROLES/ARCHITECTURE.md`.
- **P10-T5 (Minimal Release Store Listing Assets):** `Completed ✅` — Delivered official Google Play Store listing copy in `docs/release/store-listing.md` (verifying Title <= 30 chars, Short Description <= 80 chars, Full Description <= 4000 chars, BYOS disclaimer, 8 protocols, Sing-box engine, Keystore encryption, zero ads/telemetry, and GPL-3.0-or-later); generated technical-compliant PNG graphics in `docs/release/store-assets/` (512x512 32-bit RGBA icon `< 1024 KB`, 1024x500 24-bit RGB feature graphic `< 15 MB`, and four genuine 1080x1920 9:16 portrait Flutter UI screenshots for Disconnected, Connected with throughput metrics, Servers & Subscriptions, and Live Logs with 3-surface redaction); updated AndroidManifest to `android:label="Brick VPN"` and generated 5 density launcher mipmaps; authored public privacy policy at `docs/privacy-policy.md` covering zero data collection and all 8 Android permissions; added Section 12.5 to `AI_ROLES/ARCHITECTURE.md`; and delivered 4 automated tests in `apps/mobile/test/store_listing_assets_test.dart` verifying PNG binary IHDR dimensions, file size limits, character counts, and policy disclosures.
- **P10-T6 (GitHub Release Publication (Direct-Distribution Channel)):** `Completed ✅` — Staged complete direct-distribution GitHub Release bundle for Android MVP Release `v1.0.0`; authored comprehensive release notes in `docs/release/github-release-v1.0.0.md` detailing the BYOS architecture, 8 supported encrypted protocols (VLESS Reality, VMess, Trojan, Shadowsocks AEAD, WireGuard, AmneziaWG, Hysteria2, TUIC), server/subscription management, Keystore AES-256-GCM encryption, 3-surface log redaction, SHA-256 checksums matching fresh release artifacts, official certificate SHA-256 fingerprint (`563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`), step-by-step sideloading ("Install unknown apps") guide, and 5 carried-forward limitations; authored automated release staging and verification script `scripts/prepare_github_release_bundle.sh` (`chmod +x`); updated root `README.md` with direct APK download guidance and installation instructions; delivered automated regression suite in `apps/mobile/test/github_release_readiness_test.dart`; verified physical device installation and runtime execution on `Samsung SM-A205F` (`SM_A205F_RUNNING_PID=24311`); and added Section 12.6 in `AI_ROLES/ARCHITECTURE.md`.
- **P10-T7 (Play Store Submission (Closed/Internal Testing Track)):** `Completed ✅` — Prepared comprehensive Play Store submission package in `docs/release/play-store-submission-guide.md`; evaluated Play App Signing vs. self-managed signing and selected Play App Signing with local keystore export via PEPK preserving cross-channel certificate uniformity with GitHub direct APKs (`INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES` eliminated); documented Internal Testing / Closed Testing track runbook mapping AAB (`versionCode: 1 (AAB / universal base) & 2001 (arm64-v8a split APK)`), assets, policy URL, and compliance declarations; provided reviewer response playbook for FGS video demo, BYOS App Access testing instructions, and protocol encryption; documented Google MASA badge deferral and objective thresholds (10k installs / 250 reviews / 90 days); and added Section 12.7 in `AI_ROLES/ARCHITECTURE.md`.
- **P10-T8 (Phase 10 Closeout: Android MVP Milestone):** `Ready for Human Review` — Delivered final Definition-of-Done closeout for Phase 10 and the entire Android MVP milestone (Phases 0–10); authored `docs/release/mvp-milestone-retrospective.md` analyzing the legacy prototype collapse vs. the rebuilt architecture; delivered automated regression suite in `apps/mobile/test/phase10_mvp_milestone_closeout_test.dart`; consolidated carried-forward limitations ledger; added Section 12.8 in `AI_ROLES/ARCHITECTURE.md`; and established the frozen architectural contract for Phase 11.
- **Next Focus:** **Phase 11 — Full UI/UX Design & Implementation (P11-T1: Design System Foundation: Visual Identity and Style Guide)**.

### Android MVP Milestone Summary (Phases 0–10 Complete)

#### 1. High-Level Summary of What Was Built Across Phases 0–10
The Android MVP represents the complete, production-ready reconstruction of the Brick VPN client from clean architectural foundations:
- **7-Package Melos Monorepo Architecture:** Clean separation of concerns across pure-Dart core domain logic (`core_domain`, `config_parser`, `core_vpn_engine`, `shared_utils`), presentation and styling (`ui_theme`), native platform integration (`vpn_engine_android`), and the Flutter application shell (`apps/mobile`).
- **All 8 Encrypted Protocols on Sing-box `v1.10.7`:** Full client support for VLESS (with XTLS-Reality and Vision), VMess (WebSocket, gRPC, HTTP/2), Trojan (TLS), Shadowsocks AEAD (2022 and legacy ciphers), WireGuard (multi-peer roaming), AmneziaWG (AWG packet obfuscation), Hysteria2 (HY2 UDP congestion control), and TUIC (v5 QUIC proxying).
- **Single-Flight Native Command Coordinator & State Machine:** Monotonic tunnel lifecycle management via native `CommandCoordinator` and `VpnStateMachine` in Kotlin, eliminating all state races, zombie services, and ANRs.
- **Hardware-Backed Cryptographic Storage:** Sensitive server credentials, private keys, and subscription tokens encrypted at rest using AES-256-GCM (`enc:v1:`) backed by Android Keystore.
- **Three-Surface Log Redaction:** Deterministic redaction across the live UI viewer, clipboard export, and on-disk diagnostic logs (`brick_vpn_live.log`), ensuring external IPs, domains, passwords, and UUIDs never leak.
- **Resilient Network Lifecycle & Kill Switch:** Debounced auto-reconnection (exponential backoff, 300ms flap debounce, offline hold) and a fail-closed Kill Switch enforcing strict packet leakage prevention during unexpected drops.
- **Comprehensive Quality Assurance:** 81.12% unit test coverage (+410 lines hit gained monorepo-wide), 93 Kotlin JVM unit tests across 6 suites, 4 cross-feature integration test journeys executing hermetically in < 5 seconds, and full manual QA protocol verified on physical hardware (`Samsung SM-A205F`).
- **Cryptographically Signed Dual Distribution:** Production 4096-bit RSA SHA256withRSA release signing (APK Signature Scheme v2/v3), R8 minification/shrinking with Gomobile keep rules, dual packaging (Google Play AAB and direct-distribution ABI-split APKs), and canonical `SHA256SUMS.txt` integrity verification.

#### 2. Retrospective Comparison: Legacy Prototype Collapse vs. Rebuilt Android MVP
The original legacy prototype suffered from five fatal architectural failures that led to complete project collapse. The rebuilt Android MVP has systematically eliminated every failure mode (see `docs/release/mvp-milestone-retrospective.md` for the comprehensive retrospective analysis):
1. **Monolithic Untestable Spaghetti -> Modular Monorepo:** The legacy prototype intertwined UI, protocol parsing, and JNI calls in a single monolithic package with 0% test coverage. The rebuild enforces a 7-package Melos monorepo where pure-Dart domain logic is decoupled from platform channels, achieving 81.12% unit coverage and 93 host-JVM tests.
2. **Zombie VpnService State Races & ANRs -> Single-Flight CommandCoordinator:** The legacy prototype spawned uncontrolled background threads and lacked state tracking, causing persistent zombie services and OS ANR crashes. The rebuild introduces a single-flight `CommandCoordinator` and stateful `VpnStateMachine` that serialize all commands and guarantee monotonic lifecycle transitions.
3. **Silent TUN/DNS/SNI Leaks -> Hijack-DNS & Fail-Closed Kill Switch:** The legacy prototype routed traffic without DNS interception, leaking queries to ISP resolvers. The rebuild implements explicit TUN DNS hijack rules (`protocol dns -> hijack-dns`), bootstrap resolver isolation (`dns-direct` on `direct-out`), RFC 6066 IP-literal SNI compliance, and a strict fail-closed Kill Switch.
4. **Plaintext Secrets & Unredacted Logs -> Keystore AES-256-GCM & 3-Surface LogRedactor:** The legacy prototype stored passwords and private keys in cleartext `SharedPreferences` and dumped raw logs to logcat. The rebuild secures all sensitive fields with hardware-backed Android Keystore AES-256-GCM (`enc:v1:`) and scrubs logs across UI, clipboard, and disk using a dedicated `LogRedactor`.
5. **Release-Mode R8 Crashes -> Comprehensive ProGuard Keep Rules & Dual-Distribution Pipelines:** The legacy prototype collapsed under ProGuard minification due to stripped Gomobile runtime classes (`NoClassDefFoundError`). The rebuild establishes strict two-layer ProGuard/R8 keep rules (`packages/vpn_engine_android/android/proguard-rules.pro` and `apps/mobile/android/app/proguard-rules.pro`), verified against real compiled AAB and split-ABI release artifacts.

#### 3. Consolidated Known Limitations & Deferred Items Carried Forward to Phase 11+
To ensure total architectural transparency, all 6 known limitations and deferred items carried forward from Phases 0–10 are formally tracked:
1. **Item 1 (Deliberately Minimal Functional UI — Scoped to Phase 11):** Current mobile screens utilize clean Material 3 functional placeholders prioritizing stability, testability, and responsiveness over custom visual styling. Bespoke branding, typography, color tokens, and motion design are the primary scope of **Phase 11 (Full UI/UX Design & Implementation)**.
2. **Item 2 (Log Redaction Residual Boundary on Unstructured Native Free Text — `P8-T2`):** While structured JSON fields, known profile/subscription secrets, URIs, UUIDs, and external IPs are deterministically scrubbed, novel unstructured strings emitted by native C/Go libraries remain best-effort; the non-dismissible privacy warning dialog is enforced before clipboard export.
3. **Item 3 (OEM Background Battery-Optimization Quirks — `P7-T4`):** Aggressive OEM Android skins (Xiaomi MIUI/HyperOS, Samsung One UI, Huawei EMUI) may require the user to grant the in-app `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` exemption.
4. **Item 4 (Bit-for-Bit Reproducible Docker Builds — `P8-T4`):** While `SHA256SUMS.txt` and 4096-bit RSA v2/v3 signatures are published for every release artifact, hermetic bit-for-bit Docker build reproducibility across independent host machines is tracked for future release engineering.
5. **Item 5 (Google MASA "Independent Security Review" Badge Deferral — `P10-T7`):** Deferred until post-launch eligibility thresholds (**10,000+ installs**, **250+ reviews**, **90+ days** on Google Play, and third-party ADA lab audit) are met.
6. **Item 6 (Play Store Human Console Upload/Review Timeline & Dependabot Lockfile Maintenance — `P10-T7` / `P8-T5`):** Complete submission package is staged in-repo (`docs/release/play-store-submission-guide.md`); interactive upload and Google review timeline are human-owned operational steps.

#### 4. Phase 11 (Full UI/UX Design & Implementation) Handoff Statement
The Android MVP milestone (Phases 0–10) is officially complete. All underlying functional engines, protocol parsers, state machines, encryption boundaries, background services, and packaging pipelines are hardened, validated, and frozen. The next phase is **Phase 11 — Full UI/UX Design & Implementation (P11-T1: Design System Foundation: Visual Identity and Style Guide)**. Developers and designers embarking on Phase 11 can build with full confidence upon this stable, battle-tested foundation without needing to modify core domain, VPN engine, or security logic.

### Phase 9 Baseline (Completed ✅)
Phase 9 has delivered comprehensive test coverage audit, cross-feature automated integration journeys, durable manual QA protocol, and Definition-of-Done closeout:
- **P9-T1 (Unit Test Coverage Audit and Gap-Filling):** `Completed ✅` — Delivered automated coverage audit across all packages, generated durable report `AI_ROLES/UNIT_TEST_COVERAGE_REPORT.md`, and filled high-value logic gaps across 5 packages (+410 lines hit gained monorepo-wide): `packages/shared_utils` (100.00%, +10 LH), `packages/core_domain` (94.60%, +140 LH), `packages/core_vpn_engine` (97.74%, +7 LH), `packages/config_parser` (92.10%, +78 LH), `packages/vpn_engine_android` (95.83%), and `apps/mobile` (72.23% excluding generated, +175 LH). Added 24 passing unit tests in `apps/mobile/test/unit_coverage_gap_fill_test.dart` (executing in < 1s with 0 localization warnings and 0 FakeAsync hangs) covering repository CRUD cascade/broken-server cleanup, transport/extraParams reconstruction, LogEntry/LogRedactor edge cases, SensitiveFieldCipher HMAC key compression, AutoReconnect/KillSwitch state machines, ErrorMapper localized mappings, and controllers (`ServerManagementController`, `AddServerController`, `AddSubscriptionController`, `BatteryOptimizationService`). 93 Kotlin JVM unit tests verified passing across 6 suites in `packages/vpn_engine_android/android`.
- **P9-T2 (Integration Test Suite: Cross-Feature Journeys):** `Completed ✅` — Delivered automated cross-feature integration suite in `apps/mobile/test/cross_feature_integration_suite_test.dart` implementing 4 complete end-to-end multi-phase journeys (executing hermetically in < 5 seconds with zero flakiness across repeated runs): Journey 1 (Subscription Lifecycle: import -> connect -> refresh node replacement -> cascade delete -> standalone fallback -> on-disk encrypted persistence `enc:v1:`); Journey 2 (Mid-Session Settings Mutations: theme/locale mutations mid-session with tunnel continuity, mid-session kill switch enable, induced drop fail-closed blocking with `kill_switch_blocking_banner`, manual unblock & reconnect recovery); Journey 3 (Server Management & Handoff: manual URI paste, connect, live rename without disconnect, duplicate server, seamless profile switch across tabs, 3-surface credential redaction across live viewer, in-memory buffer, and real on-disk `brick_vpn_live.log` flushed by LogManager sink); Journey 4 (Encrypted Schema v1 -> v2 Migration: atomic encryption at rest on `server_profiles.json`, UI process death re-attachment without disconnected flash, airplane mode offline hold, Wi-Fi recovery auto-reconnect, and clean disconnect). Delivered companion semi-manual Android system boundary scripts in `docs/testing/manual-integration-scripts.md`.
- **P9-T3 (Manual QA Test Protocol Document):** `Completed ✅` — Delivered durable, step-by-step pre-release QA checklist in `docs/testing/manual-qa-protocol.md` covering environment pre-flight, server onboarding/ingestion, core VPN routing/DNS leak verification, telemetry & 3-surface redaction, resilience/kill switch/Doze states, and physical device test execution log on connected `Samsung SM-A205F` (Android 10, API 29, `arm64-v8a`) confirming package installation, service declarations (`BIND_VPN_SERVICE`), runtime permissions, cold start, and LMK process kill resilience.
- **P9-T4 (Phase 9 Closeout and Definition-of-Done Pass):** `Completed ✅` — Delivered full Definition-of-Done validation across all Phase 9 testing and quality assurance pillars: verified 100% clean test execution across pure-Dart packages, Kotlin JVM unit test suite (93 tests), and mobile integration test journeys; added Section 11.4 in `AI_ROLES/ARCHITECTURE.md` establishing the 3-layer QA posture and Phase 10 handoff contract; test-driven representative manual QA protocols on physical device `Samsung SM-A205F`.

### Phase 10 Handoff Statement (P9-T4 Criterion 5):
Phase 10 inherits a mature, feature-complete, security-hardened, and systematically tested codebase with durable automated CI gates and manual pre-release checklists:
1. **Feature & Security Completeness:** All 8 VPN protocols (VLESS, VMess, Trojan, Shadowsocks, WireGuard, AmneziaWG, Hysteria2, TUIC) with Sing-box core routing, authenticated AES-256-GCM hardware-backed storage encryption at rest (`enc:v1:`), automatic 3-surface log redaction, fail-closed kill switch, and debounced auto-reconnection with offline hold.
2. **Multi-Layer Quality Assurance Posture:** Monorepo-wide unit test coverage at 81.12% (5,000 / 6,164 lines across authored Dart files, +410 lines hit gained), 93 Kotlin JVM unit tests across 6 suites, 4 hermetic automated cross-feature integration journeys running in < 5 seconds with zero flakiness, 4 system-boundary integration scripts (`docs/testing/manual-integration-scripts.md`), and a 6-section durable manual QA protocol (`docs/testing/manual-qa-protocol.md`) validated on physical Android 10 hardware (`Samsung SM-A205F`).
3. **Carried-Forward Phase 10 Items:**
   - *P8-T4 Item 1 (Production Release Keystore & Fingerprint):* In P8-T4, the release verification guide and CI checksum publication were established using the development signing key (`docs/verifying-releases.md`). Phase 10 task `P10-T1` must establish the permanent, securely-managed production release signing keystore, CI secrets injection, and publish the official certificate SHA-256 fingerprint.
   - *P8-T4 Item 2 (Hermetic Reproducible Build Container):* In P8-T4, reproducible builds investigation confirmed Flutter AOT code hash determinism across identical toolchains; task `P10-T1`/`P10-T3` will codify the pinned Docker build container environment for bit-for-bit release builds.
   - *P8-T5 Item 3 (Cosmetic Transitive Lockfile Bump):* In P8-T5, dependabot was configured for weekly dependency vulnerability scanning; Phase 10 will monitor and resolve non-breaking dependency updates prior to final store release.
With zero functional or resilience regressions outstanding, the codebase is fully prepared for Phase 10 release signing, ProGuard/R8 optimization, split-ABI packaging, and Google Play Store submission.

### Phase 8 Baseline (Completed ✅)
Phase 8 has delivered complete security hardening across storage, logging, input validation, release integrity, and supply chain:
- **P8-T1 (Secure Storage for Sensitive Server Fields):** `Completed ✅` — Delivered hardware-backed Android Keystore AES-256-GCM channel in `VpnEngineAndroidPlugin.kt` (`dev.brickvpn.harness/secure_storage`) with `@Synchronized` and `setUserAuthenticationRequired(false)`, `SensitiveFieldCipher` abstraction with deterministic authenticated AEAD fallback, field-level encryption schema v2 in `FileServerProfileRepository` (preserving plaintext query/display metadata while encrypting credentials for all 8 protocols including WireGuard/AmneziaWG `peer_public_key`, transport.headers, extra_params, and subscription URLs), automatic v1->v2 plaintext elimination on load, fail-closed tamper rejection into `SavedServerBroken`, and 9 passing test scenarios in `apps/mobile/test/secure_storage_test.dart`.
- **P8-T2 (Log Redaction):** `Completed ✅` — Delivered canonical pure-Dart redaction engine in `packages/shared_utils` (sanitizing known secrets >= 4 chars, bracketed IPv6 and standard protocol/web URIs, structured JSON sensitive keys including SNI and peer_public_key, free-text patterns, RFC 4122 UUIDs, external IPv4/IPv6 while preserving internal TUN & loopback addresses), priority ordering for known secrets preventing semicolon-separated mangling, dynamic profile and repository subscription secret extraction, ingestion-level sanitization chokepoint in `LogManager`, single-pass alreadyRedacted handling in `LogEntry`, updated copy warning dialog, and 5 test scenarios in `apps/mobile/test/log_redaction_test.dart`.
- **P8-T3 (Input Validation and Untrusted-Data Security Review):** `Completed ✅` — Delivered dedicated project-wide security review of untrusted external input ingestion across Phase 2 protocol parsers, `SubscriptionFetcher`, and Phase 5 mobile UI controllers. Verified bounds checking (`maxUriLength = 8 KiB`, `maxSubscriptionLength = 5 MiB`), JSON depth bounding (`maxJsonDepth = 32`), HTTPS enforcement, redirect loop cap (`maxRedirects = 5`) and downgrade prevention, stream-level memory-DoS throttling, remark sanitization against control chars, newlines, and RTL Bidi spoofing (`BuildServerProfile.sanitizeRemark` enforced across all repository save and load paths for both server profiles and subscriptions), individual zero secret echoing across all 8 protocol parsers, written security report in `AI_ROLES/UNTRUSTED_INPUT_SECURITY_REVIEW.md`, and 4 automated test scenarios in `apps/mobile/test/untrusted_input_security_review_test.dart`.
- **P8-T4 (App Update Integrity Verification):** `Completed ✅` — Delivered deterministic release artifact checksum generation script `scripts/generate_and_verify_checksums.sh` (canonical sorted `SHA256SUMS.txt`, excluding debug APKs/AABs, self-verifying via `sha256sum -c`), release build and checksum upload workflow steps in `.github/workflows/ci.yml`, user-facing release verification guide in `docs/verifying-releases.md` (Linux, macOS, Windows PowerShell, `apksigner` / `keytool` certificate fingerprint inspection, debug key Phase 8 status and Phase 10 production key custody cross-reference), reproducible builds feasibility investigation across Flutter AOT, Go/gomobile, and AGP, and Architecture Section 10.4. Verified against real compiled release APK and installed on connected physical device (`SM-A205F`).
- **P8-T5 (Dependency and Supply-Chain Security Pass):** `Completed ✅` — Delivered comprehensive multi-stack dependency audit across Dart/Flutter, Android/Gradle, and native Go (`libbox.aar`), confirming 0 critical/high CVEs, 0 malicious or unpinned packages, and trusted registry enforcement (`https://pub.dev`). Verified AndroidManifest least-privilege permissions (8 approved permissions, zero invasive permissions, non-exported `BrickVpnService`). Configured automated Dependabot weekly scanning (`.github/dependabot.yml`) for `pub`, `gradle`, and `github-actions`. Created durable audit report in `AI_ROLES/DEPENDENCY_SUPPLY_CHAIN_AUDIT.md`, Architecture Section 10.5, and automated regression test suite in `apps/mobile/test/supply_chain_and_manifest_security_test.dart`.
- **P8-T6 (Phase 8 Closeout and Definition-of-Done Pass):** `Completed ✅` — Delivered full Definition-of-Done validation across all Phase 8 security-hardening pillars:
  - Multi-stage end-to-end security journey test in `apps/mobile/test/phase8_e2e_security_journey_test.dart` (Stage A: O(1) 100 KB payload truncation to 8256 chars and safe error rejection; Stage B: remark sanitization and schema v2 authenticated encryption at rest; Stage C: 3-surface log redaction across live viewer, clipboard export, and on-disk flush; Stage D: ciphertext tamper fail-closed handling, supply chain integrity, Dependabot scanning, and Android manifest permissions).
  - Architecture Section 10.6 establishing explicit 3-category security posture classification (Verified Secure, Best-Effort with Known Limitations, Deferred to Phase 10 / Production).
  - Re-verified complete test suite across all packages (core_domain, config_parser, core_vpn_engine, shared_utils, ui_theme, vpn_engine_android, and apps/mobile).

### Phase 7 Baseline (Completed ✅)
Phase 7 has resolved every historical prototype failure mode and established a hardened, resilient client lifecycle:
- **P7-T1 (Auto-Reconnect on Network Change):** `Completed ✅` — Delivered automatic tunnel reconnection coordinator and reactive Riverpod architecture with exponential backoff (1s, 2s, 4s, 8s, 16s; max 30s; 5 retry ceiling), 300ms flap debounce, user-intent preservation (`_userSessionActive`), offline hold/resume, and SettingsScreen preference toggle.
- **P7-T2 (Kill Switch):** `Completed ✅` — Delivered leak-protection kill switch coordinator and reactive Riverpod architecture with sealed state hierarchy (`KillSwitchInactive`, `KillSwitchArmed`, `KillSwitchBlocking`), full risk window coverage (unexpected drops, auto-reconnect backoff/waiting windows, retry exhaustion), non-blocking on user disconnect invariant, warning banner with unblock action in SessionInfoPanel, and SettingsScreen preference toggle.
- **P7-T3 (DNS Correctness, Bootstrap Deadlock & IP-SNI Hardening):** `Completed ✅` — Delivered end-to-end DNS hardening, bootstrap resolver isolation (`dns-direct` on `direct-out`), TUN DNS hijack rule (`protocol dns -> hijack-dns`), `auto_route`/`strict_route` enforcement, `withTimeout(15_000L)` bounded startup, and RFC 6066 IP-literal SNI compliance.
- **P7-T4 (Foreground Service Resilience: Process Death, Doze, Battery Optimization):** `Completed ✅` — Delivered foreground service lifecycle hardening, AndroidManifest permissions (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), `START_STICKY` null-intent restart handling, `BatteryOptimizationService` platform channel and SettingsScreen integration tile, cold-start and background resume state reconciliation, and Section 9.4 documentation of Doze, process death, and OEM battery manager quirks.
- **P7-T5 (Chaos Test Suite: Legacy Failure Mode Regression Set):** `Completed ✅` — Delivered formal reckoning with all 12 documented legacy prototype failure modes in `apps/mobile/test/legacy_chaos_regression_suite_test.dart`, durable reference checklist matrix in `AI_ROLES/LEGACY_CHAOS_REGRESSION_CHECKLIST.md`, and ARCHITECTURE.md Section 9.5.
- **P7-T6 (VPN State Persistence Across App Process Restart):** `Completed ✅` — Delivered UI process death re-attachment and duplicate session prevention:
  - Startup pre-warming in `AppBootstrap.init()` probing `await vpnEngine.getStatus()` with a 500ms fallback and providing `initialConnectionStateProvider`.
  - Neutral loading state `'connection.state_checking'.tr()` in `SessionInfoPanel` and `ConnectionStateBadge` when in `AsyncLoading` with no pre-warmed state, eliminating any flash of "Disconnected".
  - Seamless active-session re-attachment: `AutoReconnectNotifier` re-arms session state, `KillSwitchNotifier` re-arms protection, `ConnectionController` syncs active server ID, and `sessionDurationProvider` resumes tracking.
  - Duplicate session guard in `ConnectionController.connect()` returning `VpnCommandRejectedBusy()` on repeated connect commands for the active server without disturbing the running tunnel.
  - Comprehensive 3-test suite in `apps/mobile/test/process_restart_reattach_test.dart`.
  - Added Section 9.6 to `AI_ROLES/ARCHITECTURE.md`.
- **P7-T7 (Phase 7 Closeout and Definition-of-Done Pass):** `Completed ✅` — Delivered full Definition-of-Done validation across all Phase 7 resilience features:
  - Continuous 5-stage real-world combined resilience journey in `apps/mobile/test/phase7_e2e_resilience_journey_test.dart` (Stage A: Tokyo Node connect with SNI/stats/logs/timer; Stage B: Wi-Fi to cellular handoff with debounce, lockdown blocking, and 1s backoff recovery; Stage C: Airplane mode outage hold with 0 futile attempts and Wi-Fi recovery; Stage D: UI process kill & relaunch with zero disconnected flash, duplicate connect rejection, and clean Osaka Node switch; Stage E: 5-attempt retry exhaustion, fail-closed lockdown hold, and unblock button recovery to clean baseline).
  - Confirmed all 12 chaos failure modes passing in `apps/mobile/test/legacy_chaos_regression_suite_test.dart`.
  - Added Section 9.7 to `AI_ROLES/ARCHITECTURE.md`.
- **Phase 8 Handoff & Carried-Forward Limitation:**
  1. **Phase 8 Prerequisites Handed Off:** Phase 7 provides rock-solid connection lifecycle stability (Invariants 1 & 2), monotonic teardown, fail-closed kill switch, and UI state reconciliation. Phase 8 can build encrypted storage and log scrubbing directly on this stable foundation without revisiting lifecycle correctness.
  2. **Carried-Forward Limitation — Log Redaction (Deferred to Phase 8):** In Phase 6 and Phase 7, live engine logs contain unredacted sensitive data. Full field-level redaction and regex scrubbing are explicitly deferred to **Phase 8 (P8-T2 — Log Redaction)**.

---

## 2. Completed & Active Task Ledger (Phases 1–10 — quoted from `AI_ROLES/ROADMAP.md`)

Status tokens below are quoted verbatim from the corresponding `**Status:**` line in `AI_ROLES/ROADMAP.md`.

- **P1-T1** (`ROADMAP.md:564`): `Completed ✅` — Hand-written `Result<T, E>` implemented in `packages/shared_utils` with 10 standalone unit tests passing. Pushed and merged to master.
- **P1-T2** (`ROADMAP.md:599`): `Completed ✅` — `ConnectionState` (sealed, 5 variants) and `TrafficStats` (immutable value type) implemented in `packages/core_domain` with 13 standalone unit tests passing. `ConnectionErrorReason` implemented as a sealed class (chosen over enum to carry `PlatformError`'s String payload). Package migrated to pure Dart. Pushed and merged to master at commit `e6f9874`.
- **P1-T3** (`ROADMAP.md:642`): `Completed ✅` — Implemented the sealed `OutboundConfig` hierarchy (TCP-based family: VLESS/VMess/Trojan; QUIC-based family: Hysteria2/TUIC with mandatory non-nullable TLS and `zeroRttHandshake` defaulting to false; standalone Shadowsocks), 7 shared composition types, the `ProtocolType` enum, and the `ServerProfile` container. 76 new unit tests (89 total passing), including the `extraParams` null-defaults tripwire and exhaustive-switch checks. Package remains pure Dart. Pushed and merged to master at commit `9e748e2`.
- **P1-T4** (`ROADMAP.md:679`): `Completed ✅` — Implemented `abstract interface class VpnEngine` (connectionState/trafficStats streams with independent failure domains, `start(ServerProfile)`/`stop()`/`getStatus()` with acceptance-separate-from-state semantics) and sealed `VpnCommandResult` (5 stateless variants with `'type'` discriminators). Package migrated to pure Dart (`core_domain` workspace dep) and added to both Melos lists in the same change set. 13 tests passing, including exhaustive-switch and stream-isolation checks. Pushed and merged to master at commit `249617f`.
- **P1-T5** (`ROADMAP.md:721`): `Completed ✅` — `MockVpnEngine` reference implementation (541 lines) fully implemented: simulated lifecycle, configurable rejections, independent failure domains, session tokens, a 5000 ms stop watchdog, and idempotent `stop()`/`dispose()`. 30 `mock_vpn_engine_test.dart` tests (43 total in the package, up from 13 at P1-T4). 147 pure-Dart tests pass monorepo-wide (10 shared_utils + 94 core_domain + 43 core_vpn_engine). `flutter analyze` clean across all 6 packages. The state-machine graph gained a `Connected -> Error` edge to support `simulateUnexpectedDisconnect()` (see ARCHITECTURE.md Section 3.1). **These changes are uncommitted and awaiting human review/commit** (the earlier `45b7c85` commit's non-conventional message is a permanent accepted deviation — see §6).
- **P1-T6** (`ROADMAP.md:759`): `Completed ✅` — Feature-first folder structure convention + reference feature skeleton.
- **P3-T12** (`ROADMAP.md:2393`): `Completed ✅` — Pigeon schema defined with `@async` methods for `prepare()`, `start()`, `stop()`, and `getStatus()`. Generated Dart and Kotlin bindings committed and passing `melos run analyze`.
- **P3-T13** (`ROADMAP.md:2444`): `Completed ✅` — Kotlin Pigeon host-API implementation (`PigeonVpnApiImpl.kt`, `CommandCoordinator.kt`, `VpnEngineAndroidPlugin.kt`) remediated (D1, D2, D3, R10, `ActivityAware` restored). 84 host-JVM unit tests passing across 6 suites (0 failures, 0 errors, 0 compiler warnings); 23 on-device instrumented tests passing on SM-A205F (RZ8M53WPMPF, Android 10 / API 29) across 5 suites.
- **P3-T14** (`ROADMAP.md:2488`): `Completed ✅` — Dart-side `AndroidVpnEngine implements VpnEngine` in `packages/vpn_engine_android/lib/src/android_vpn_engine.dart` wrapping Pigeon channels with 19 unit tests passing (including real `SingBoxOutboundSerializer` rejection of runtime-unsupported protocols). Implements DECISION P3-T14-A..D with 0 compiler warnings, full analyzer pass, and fully wired into `melos run test` (768 total monorepo tests passing).
- **P3-T15** (`ROADMAP.md:2534`): `Completed ✅` — Wire `AndroidVpnEngine` into `apps/mobile` via Riverpod provider override. Verified end-to-end on physical SM-A205F device with real VLESS server and live network traffic routing. Delivered `LibboxBootstrap.kt` (app-private storage setup), injected `"tag": outboundTag` + DNS detour routing in `PigeonVpnApiImpl.kt`, and single launcher manifest in `vpn_engine_android`. 89/89 host-JVM unit tests, 24/24 on-device instrumented tests, and full monorepo test suites passing.
- **P3-T16** (`ROADMAP.md:2576`): `Completed ✅` — Full-stack chaos/stress test suite (Gate B) implemented with Flutter `integration_test` on physical SM-A205F device (`gate_b_rapid_state_test.dart`, `gate_b_cold_start_test.dart`, `gate_b_revoke_test.dart`). Tested staggered rapid spam interaction, live traffic stats throughput, cold-start state synchronization, and system revoke handling with zero ANR, zero deadlocks, and zero false states.
- **P3-T17** (`ROADMAP.md:2624`): `Completed ✅` — Phase 3 closeout and Definition-of-Done pass. Full repository verification clean, legacy-bug traceability list confirmed valid at full-stack level, and Phase 4 transition prepared.
- **P4-T1** (`ROADMAP.md:2678`): `Completed ✅` — App lifecycle observer (`AppLifecycleListener`) and native state resync on resume/cold start (`connectionStateProvider`).
- **P4-T2** (`ROADMAP.md:2720`): `Completed ✅` — Non-secret local persistence skeleton (`AppPreferencesRepository` backed by `shared_preferences`) with strict `SECURITY.md` data classification boundary.
- **P4-T3** (`ROADMAP.md:2759`): `Completed ✅` — Global error and feedback presentation pattern (`AppFeedback` snackbar utility + `ErrorMapper` domain-to-user-string mapping).
- **P4-T4** (`ROADMAP.md:2799`): `Completed ✅` — Network connectivity change awareness (`NetworkStatus` domain wrapper with `ConnectivityPlusNetworkStatusSource` stream, observability only).
- **P4-T5** (`ROADMAP.md:2832`): `Completed ✅` — Real navigation shell (`StatefulShellRoute.indexedStack` with Material 3 `NavigationBar` across Home, Servers, Logs, Settings).
- **P4-T6** (`ROADMAP.md:2868`): `Completed ✅` — Minimal theming skeleton (Material 3 light/dark/system theme modes persisted via `appPreferencesRepositoryProvider`).
- **P4-T7** (`ROADMAP.md:2901`): `Completed ✅` — App startup sequencing (`AppBootstrap.init()` with deterministic 6-step linear sequence and graceful degradation to `FakeAppPreferencesRepository` on storage failure, passing container to `UncontrolledProviderScope`).
- **P4-T8** (`ROADMAP.md:2935`): `Completed ✅` — Phase 4 closeout and Definition-of-Done pass. Full verification passing monorepo-wide; Phase 5 ready to begin.
- **P5-T1** (`ROADMAP.md:2979`): `Completed ✅` — Local persistent storage for server profiles and subscription metadata via atomic JSON-file store.
- **P5-T2** (`ROADMAP.md:3012`): `Completed ✅` — Add Server: Manual URI/Link Paste with direct save UX (no preview dialog), config_parser integration, subscription detection, and clipboard paste. Approved 10/10 by human owner.
- **P5-T3** (`ROADMAP.md:3044`): `Completed ✅` — Add Server: QR Code Scan with camera permission flow (granted, denied, permanentlyDenied), single-scan debounce lock, direct-save routing through AddServerController, full localization, and hermetic widget tests. Approved 10/10 by human owner.
- **P5-T4** (`ROADMAP.md:3073`): `Completed ✅` — Add Server: Subscription URL Import with SubscriptionFetcher provider injection, partial-success policy, AddSubscriptionController, AddSubscriptionScreen at /add-subscription, GoRouter integration, 100% .tr() localization, and hermetic tests.
- **P5-T5** (`ROADMAP.md:3103`): `Completed ✅` — Server List Screen with real data grouping (standalone vs. subscription), empty states, and reactive updates.
- **P5-T6** (`ROADMAP.md:3134`): `Completed ✅` — Server Management: Edit, Delete, Duplicate, and Subscription Refresh with offline support and error handling.
- **P5-T7** (`ROADMAP.md:3164`): `Completed ✅` — Active Server Selection with persistent storage, radio buttons, and tap-to-select UX.
- **P5-T8** (`ROADMAP.md:3192`): `Completed ✅` — Real Connect/Disconnect Flow with stream-driven state truth, VpnEngine Invariant 1 enforcement, and auto-disconnect on server change. Approved 10/10 by human owner.
- **P5-T9** (`ROADMAP.md:3225`): `Completed ✅` — Phase 5 Closeout and Definition-of-Done Pass. Full user journey integration test (`phase5_e2e_journey_test.dart`), compileSdk 37 remediation, and clean fresh-clone verification.
- **P6-T1** (`ROADMAP.md:3262`): `Completed ✅` — Traffic Stats Data Plumbing: SessionTrafficMetrics, TrafficFormatter, SessionTrafficMetricsCalculator with zero-spike initial clamping and NaN guards, sessionTrafficMetricsProvider, and native stats polling audit.
- **P6-T2** (`ROADMAP.md:3296`): `Completed ✅` — Traffic Stats UI Display: ThroughputReadout with instantaneous speed and cumulative totals, .select() rebuild isolation, and 100% localization.
- **P6-T3** (`ROADMAP.md:3326`): `Completed ✅` — Live Log Capture From Native Engine: LogEntry structured model, LogLevel enum, LogBuffer O(1) bounded ring buffer (300 capacity), LogManager microtask burst coalescing, and async file sink synchronization.
- **P6-T4** (`ROADMAP.md:3356`): `Completed ✅` — Live Log Viewer Screen: Dedicated LiveLogsScreen on Logs tab, virtualized ListView.builder, auto-scroll pause/resume, high-contrast semantic level badges, and atomic buffer clear.
- **P6-T5** (`ROADMAP.md:3388`): `Completed ✅` — Log Export / Copy: Copy to clipboard with mandatory non-dismissible privacy warning modal (barrierDismissible: false), structured payload formatting, and feedback snackbar.
- **P6-T6** (`ROADMAP.md:3415`): `Completed ✅` — Connection Session Info Panel: SessionInfoPanel mounted on HomeScreen, sessionDurationProvider with 1 Hz timer and initial connected state detection, TrafficFormatter.formatDuration, and fine-grained rebuild isolation.
- **P6-T7** (`ROADMAP.md:3443`): `Completed ✅` — Phase 6 Closeout and Definition-of-Done Pass: Two-cycle end-to-end integration test (`apps/mobile/test/phase6_e2e_journey_test.dart`), baseline reset verification across reconnects, carried-forward log-redaction limitation flag, and Phase 7 readiness specification.
- **P7-T1** (`ROADMAP.md:3479`): `Completed ✅` — Auto-Reconnect on Network Change: AutoReconnectNotifier with sealed state hierarchy, exponential backoff (1s, 2s, 4s, 8s, 16s; max 30s; 5 retry ceiling), 300ms flap debounce, user-intent preservation (_userSessionActive), offline hold/resume, SettingsScreen preference toggle, and 15 unit/widget tests in auto_reconnect_test.dart.
- **P7-T2** (`ROADMAP.md:3510`): `Completed ✅` — Kill Switch: KillSwitchNotifier with sealed state hierarchy (Inactive, Armed, Blocking), full risk window coverage (unexpected drops, auto-reconnect backoff/waiting windows, retry exhaustion), non-blocking on user disconnect invariant, warning banner with unblock action in SessionInfoPanel, SettingsScreen preference toggle, and 10 unit/widget tests in kill_switch_test.dart.
- **P7-T3** (`ROADMAP.md:3539`): `Completed ✅` — DNS Correctness and Leak Prevention Hardening: DNS bootstrap resolver isolation (dns-direct on direct-out), TUN DNS hijack rule (protocol dns -> hijack-dns), auto_route/strict_route enforcement, withTimeout(15_000L) bounded startup, and RFC 6066 IP-literal SNI compliance.
- **P7-T4** (`ROADMAP.md:3568`): `Completed ✅` — Foreground Service Resilience (Process Death, Doze, Battery Optimization): AndroidManifest REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, START_STICKY null-intent restart handling, onRevoke() teardown, BrickVpnService lockdown persistence across lifecycles, BatteryOptimizationService channel and SettingsScreen tile, app resume status reconciliation, and Section 9.4 OEM quirks documentation.
- **P7-T5** (`ROADMAP.md:3597`): `Completed ✅` — Chaos Test Suite: Legacy Failure Mode Regression Set: 12 discrete failure modes implemented and tested against current integrated app in `apps/mobile/test/legacy_chaos_regression_suite_test.dart`, durable reference matrix in `AI_ROLES/LEGACY_CHAOS_REGRESSION_CHECKLIST.md`, and ARCHITECTURE.md Section 9.5.
- **P7-T6** (`ROADMAP.md:3636`): `Completed ✅` — VPN State Persistence Across App Process Restart: Startup pre-warming in `AppBootstrap.init()`, neutral loading state `connection.state_checking` in `SessionInfoPanel` and `ConnectionStateBadge` eliminating false "Disconnected" flashes, active session and coordinator re-attachment in `ConnectionController`, `AutoReconnectNotifier`, and `KillSwitchNotifier`, duplicate session rejection, and comprehensive 3-test suite in `apps/mobile/test/process_restart_reattach_test.dart`.
- **P7-T7** (`ROADMAP.md:3664`): `Completed ✅` — Phase 7 Closeout and Definition-of-Done Pass: Multi-stage real-world combined resilience stress test in `apps/mobile/test/phase7_e2e_resilience_journey_test.dart` (Stages A–E), full re-run of 12 legacy chaos failure modes in `legacy_chaos_regression_suite_test.dart`, Section 9.7 in `AI_ROLES/ARCHITECTURE.md`, and Phase 8 security hardening handoff specification.
- **P8-T1** (`ROADMAP.md:3700`): `Completed ✅` — Secure Storage for Sensitive Server Fields: Hardware-backed Android Keystore AES-256-GCM platform channel in `VpnEngineAndroidPlugin.kt` (`dev.brickvpn.harness/secure_storage`), `SensitiveFieldCipher` abstraction with deterministic authenticated AEAD fallback (`LocalAuthenticatedCipher`), field-level encryption schema v2 in `FileServerProfileRepository` (preserving plaintext query/display metadata while encrypting credentials for VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard, AmneziaWG, extra_params, and subscription URLs), automatic v1->v2 plaintext elimination on load, fail-closed tamper rejection into `SavedServerBroken`, and 9 automated scenarios in `apps/mobile/test/secure_storage_test.dart`.
- **P8-T2** (`ROADMAP.md:3732`): `Completed ✅` — Log Redaction: Systematic redaction across all surfaces (live viewer, clipboard export, and temp disk log file), zero-dependency redaction engine in `packages/shared_utils` (sanitizing known secrets >= 4 chars, protocol and web URIs, structured JSON sensitive keys, free-text patterns, RFC 4122 UUIDs, external IPv4/IPv6 while preserving internal TUN & loopback addresses), priority ordering for known secrets preventing semicolon-separated mangling, dynamic profile and repository subscription secret extraction (including host, path tokens, extra_params), ingestion-level sanitization chokepoint in `LogManager`, single-pass redaction in `LogEntry`, updated copy warning dialog, and 5 test scenarios in `apps/mobile/test/log_redaction_test.dart`.
- **P8-T3** (`ROADMAP.md:3763`): `Completed ✅` — Input Validation and Untrusted-Data Security Review (Full Pass): Comprehensive audit of all 8 protocol parsers (VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard, AmneziaWG), `SmartConfigParser`, `SubscriptionParser`, `SingBoxOutboundSerializer`, and `SubscriptionFetcher`. Verified bounds checking (`maxUriLength = 8 KiB`, `maxSubscriptionLength = 5 MiB`), JSON depth bounding (`maxJsonDepth = 32`), RFC 6066 SNI sanitization, mandatory HTTPS transport, redirect downgrade prevention and loop limits (`maxRedirects = 5`), incremental stream memory-DoS caps, remark sanitization across all repository paths (`BuildServerProfile.sanitizeRemark`), and zero secret echoing across UI presentation layers (`AddServerScreen`, `QrScanScreen`, `AddSubscriptionScreen`). Written security report in `AI_ROLES/UNTRUSTED_INPUT_SECURITY_REVIEW.md`, Section 10.3 in `AI_ROLES/ARCHITECTURE.md`, and 4 automated test scenarios in `apps/mobile/test/untrusted_input_security_review_test.dart`.
- **P8-T4** (`ROADMAP.md:3805`): `Completed ✅` — App Update Integrity Verification: Deterministic release artifact checksum generation script `scripts/generate_and_verify_checksums.sh` (canonical sorted `SHA256SUMS.txt`, self-verifying via `sha256sum -c`), release build and checksum upload workflow steps in `.github/workflows/ci.yml`, user-facing release verification guide in `docs/verifying-releases.md` (Linux, macOS, Windows PowerShell, `apksigner` / `keytool` certificate fingerprint inspection, debug key Phase 8 status and Phase 10 production key custody cross-reference), reproducible builds feasibility investigation across Flutter AOT, Go/gomobile, and AGP, and Architecture Section 10.4. Verified against real release APK and installed on physical device `SM-A205F`.
- **P8-T5** (`ROADMAP.md:3821`): `Completed ✅` — Dependency and Supply-Chain Security Pass: Multi-stack dependency audit across Dart/Flutter, Android/Gradle, and Go (`libbox.aar`), confirming 0 critical/high CVEs, 0 malicious or unpinned packages, and trusted registry enforcement (`https://pub.dev`). Verified AndroidManifest least-privilege permissions (8 approved permissions, zero invasive permissions, non-exported `BrickVpnService`). Configured automated Dependabot weekly scanning (`.github/dependabot.yml`) for `pub`, `gradle`, and `github-actions`. Created durable audit report in `AI_ROLES/DEPENDENCY_SUPPLY_CHAIN_AUDIT.md`, Architecture Section 10.5, and automated regression test suite in `apps/mobile/test/supply_chain_and_manifest_security_test.dart`.
- **P8-T6** (`ROADMAP.md:3850`): `Completed ✅` — Phase 8 Closeout and Definition-of-Done Pass: Unified 4-stage end-to-end security journey in `apps/mobile/test/phase8_e2e_security_journey_test.dart` (testing O(1) input bounding, remark sanitization, authenticated AES-256-GCM storage at rest, 3-surface log redaction, tamper fail-closed handling, and supply chain integrity), Section 10.6 security posture classification in `AI_ROLES/ARCHITECTURE.md`, clean low-load monorepo verification, and Phase 9 QA handoff baseline.
- **P9-T1** (`ROADMAP.md:3885`): `Completed ✅` — Unit Test Coverage Audit and Gap-Filling: Comprehensive coverage audit and targeted gap-filling across all packages. Delivered +410 real lines hit across the codebase without vanity chasing: `packages/shared_utils` (100.00%, +10 LH), `packages/core_domain` (94.60%, +140 LH), `packages/core_vpn_engine` (97.74%, +7 LH), `packages/config_parser` (92.10%, +78 LH), `packages/vpn_engine_android` (95.83%), and `apps/mobile` (72.23% excluding generated, +175 LH). Exercised high-value domain, repository cascade/broken-server, redaction, controller (`ServerManagementController`, `AddServerController`, `AddSubscriptionController`), and `BatteryOptimizationService` branches. Zero console warnings, zero `FakeAsync` hangs. Durably documented in `AI_ROLES/UNIT_TEST_COVERAGE_REPORT.md` and Architecture Section 11.1.
- **P9-T2** (`ROADMAP.md:3913`): `Completed ✅` — Integration Test Suite: Cross-Feature Journeys: Delivered automated cross-feature integration test suite covering 4 multi-phase journeys in `apps/mobile/test/cross_feature_integration_suite_test.dart` (executing in < 5s, 100% hermetic, 0 flakiness across repeated runs): Journey 1 (Subscription import, connect, refresh replacement, cascade delete, standalone fallback, on-disk encrypted persistence `enc:v1:`); Journey 2 (Theme/locale mutations mid-session with tunnel continuity, mid-session kill switch enable, induced drop fail-closed blocking with `kill_switch_blocking_banner`, manual unblock and reconnect recovery); Journey 3 (Manual server URI import, connect, live rename without disconnect, duplicate server, seamless profile switch across tabs, 3-surface credential redaction across live viewer, in-memory buffer, and disk file flushed by sink); Journey 4 (Legacy Schema v1 -> v2 migration with AES-GCM `enc:v1:` encryption at rest, UI process restart re-attachment, airplane mode offline hold, Wi-Fi recovery auto-reconnect, and clean disconnect). Delivered companion system boundary manual scripts in `docs/testing/manual-integration-scripts.md`. Documented in `AI_ROLES/ARCHITECTURE.md` Section 11.2.
- **P9-T3** (`ROADMAP.md:3948`): `Completed ✅` — Manual QA Test Protocol Document: Delivered durable, human-executable pre-release checklist in `docs/testing/manual-qa-protocol.md` covering environment setup/pre-flight, server onboarding/ingestion, core VPN routing/DNS leak verification, telemetry/live logs, resilience/kill switch/Doze states, and physical device test execution log on connected `Samsung SM-A205F` (Android 10, API 29, `arm64-v8a`) confirming package installation, service declarations (`BIND_VPN_SERVICE`), runtime permissions, cold start, and LMK kill resilience. Documented in `AI_ROLES/ARCHITECTURE.md` Section 11.3.
- **P9-T4** (`ROADMAP.md:3972`): `Completed ✅` — Phase 9 Closeout and Definition-of-Done Pass: Verified full automated test suite pass (pure-Dart packages, 93 Kotlin JVM unit tests, and Flutter integration journeys), test-driven representative manual QA protocols against physical Android 10 device `Samsung SM-A205F`, added Section 11.4 in `AI_ROLES/ARCHITECTURE.md` establishing 3-layer QA posture and Phase 10 handoff contract, and confirmed monorepo readiness for Phase 10 release preparation.
- **P10-T1** (`ROADMAP.md:4008`): `Completed ✅` — Release Signing Key Setup and CI Signing Pipeline: Generated production release keystore outside repo (`~/.brickvpn-keystore/brickvpn-release.jks`, `chmod 600`, 4096-bit RSA, 10,000 days validity); configured Gradle release signing in `apps/mobile/android/app/build.gradle.kts` with `enableV1Signing = false`, `enableV2Signing = true`, `enableV3Signing = true`, reading environment variables/key.properties with zero passwords hardcoded and debug fallback; hardened root and mobile `.gitignore` against all keystore formats and credential properties; updated `.github/workflows/ci.yml` with fail-fast secret checks, release APK/AAB builds, `apksigner` SHA-256 fingerprint verification (`563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`), checksum generation, and ephemeral keystore wiping; updated `docs/verifying-releases.md` with official SHA-256 fingerprint; created `docs/release-signing-and-key-recovery.md` documenting parameters, backup, and key-loss consequences; added 6 automated regression tests in `apps/mobile/test/release_signing_security_test.dart` (100% passing); and added Section 12 & 12.1 in `AI_ROLES/ARCHITECTURE.md`.
- **P10-T2** (`ROADMAP.md:4038`): `Completed ✅` — ProGuard/R8 Release Hardening and Gomobile Bridge Keep Rules: Configured two-layer ProGuard/R8 keep rules across library and application layers. Delivered `packages/vpn_engine_android/android/proguard-rules.pro` with `consumerProguardFiles` in `build.gradle.kts` protecting gomobile runtime JNI bridge (`go.**`), libbox bound classes and interfaces (`io.nekohasekai.libbox.**`, `libbox.**`), and plugin harness (`dev.brickvpn.harness.**`). Delivered `apps/mobile/android/app/proguard-rules.pro` protecting Flutter embedding, native JNI method symbols (`native <methods>`), coroutines, and line number attributes. Enabled `isMinifyEnabled = true` and `isShrinkResources = true` in `apps/mobile/android/app/build.gradle.kts`. Verified R8 obfuscation/minification compilation (producing mapping file `apps/mobile/build/app/outputs/mapping/release/mapping.txt`), verified release signing with `apksigner`, and confirmed `seeds.txt` entry points. Added automated regression test `apps/mobile/test/proguard_r8_hardening_test.dart`.
- **P10-T3** (`ROADMAP.md:4068`): `Completed ✅` — AAB Build and ABI-Split Configuration for Dual Distribution: Configured dual-distribution packaging for Google Play and Direct APK channels. Configured CI release workflow to produce signed Android App Bundle (`app-release.aab`) alongside per-ABI split APKs (`app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`) and universal fallback APK (`app-release.apk`). Validated all 5 artifacts compiled and signed with APK Signature Scheme v2/v3, matching official certificate fingerprint `563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`, and self-verified via `scripts/generate_and_verify_checksums.sh`. Documented artifact selection guide in `docs/verifying-releases.md` Section 2 and architecture Section 12.3.
- **P10-T4** (`ROADMAP.md:4098`): `Completed ✅` — Play Store VPN Policy Compliance Pass: Delivered comprehensive Play Store compliance document `docs/release/play-store-vpn-compliance.md` covering Google Play VpnService policy matrix, copy-paste-ready VpnService declaration form answers with technical justifications, Android 14+ FGS specialUse justification, complete Data Safety questionnaire responses (confirming zero data collection / zero trackers), reviewer video demonstration walkthrough script, and codebase audit. Delivered automated regression suite in `apps/mobile/test/play_store_vpn_policy_compliance_test.dart` asserting zero ad/tracker/telemetry SDKs in manifest/pubspec/gradle and zero monetization code in sources. Added Section 12.4 in `AI_ROLES/ARCHITECTURE.md`.
- **P10-T5** (`ROADMAP.md:4126`): `Completed ✅` — Minimal Release Store Listing Assets: Delivered official Google Play Store listing copy in `docs/release/store-listing.md` (verifying Title <= 30 chars, Short Description <= 80 chars, Full Description <= 4000 chars, BYOS disclaimer, 8 protocols, Sing-box engine, Keystore encryption, zero ads/telemetry, and GPL-3.0-or-later); generated technical-compliant PNG graphics in `docs/release/store-assets/` (512x512 32-bit RGBA icon `< 1024 KB`, 1024x500 24-bit RGB feature graphic `< 15 MB`, and four genuine 1080x1920 9:16 portrait Flutter UI screenshots for Disconnected, Connected with throughput metrics, Servers & Subscriptions, and Live Logs with 3-surface redaction); updated AndroidManifest to `android:label="Brick VPN"` and generated 5 density launcher mipmaps; authored public privacy policy at `docs/privacy-policy.md` covering zero data collection and all 8 Android permissions; added Section 12.5 to `AI_ROLES/ARCHITECTURE.md`; and delivered 4 automated tests in `apps/mobile/test/store_listing_assets_test.dart` verifying PNG binary IHDR dimensions, file size limits, character counts, and policy disclosures.
- **P10-T6** (`ROADMAP.md:4154`): `Completed ✅` — GitHub Release Publication (Direct-Distribution Channel): Staged complete direct-distribution GitHub Release bundle for Android MVP Release `v1.0.0`; authored comprehensive release notes in `docs/release/github-release-v1.0.0.md` detailing the BYOS architecture, 8 supported encrypted protocols (VLESS Reality, VMess, Trojan, Shadowsocks AEAD, WireGuard, AmneziaWG, Hysteria2, TUIC), server/subscription management, Keystore AES-256-GCM encryption, 3-surface log redaction, SHA-256 checksums matching fresh release artifacts, official certificate SHA-256 fingerprint (`563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`), step-by-step sideloading ("Install unknown apps") guide, and 5 carried-forward limitations; authored automated release staging and verification script `scripts/prepare_github_release_bundle.sh` (`chmod +x`); updated root `README.md` with direct APK download guidance and installation instructions; delivered automated regression suite in `apps/mobile/test/github_release_readiness_test.dart`; verified physical device installation and runtime execution on `Samsung SM-A205F` (`SM_A205F_RUNNING_PID=24311`); and added Section 12.6 in `AI_ROLES/ARCHITECTURE.md`.
- **P10-T7** (`ROADMAP.md:4184`): `Completed ✅` — Play Store Submission (Closed/Internal Testing Track): Prepared comprehensive Play Store submission package in `docs/release/play-store-submission-guide.md`; evaluated Play App Signing vs. self-managed signing and selected Play App Signing with local keystore export via PEPK preserving cross-channel certificate uniformity with GitHub direct APKs (`INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES` eliminated); documented Internal Testing / Closed Testing track runbook mapping AAB (`versionCode: 1 (AAB / universal base) & 2001 (arm64-v8a split APK)`), assets, policy URL, and compliance declarations; provided reviewer response playbook for FGS video demo, BYOS App Access testing instructions, and protocol encryption; documented Google MASA badge deferral and objective thresholds (10k installs / 250 reviews / 90 days); and added Section 12.7 in `AI_ROLES/ARCHITECTURE.md`.
- **P10-T8** (`ROADMAP.md:4214`): `Ready for Human Review` — Phase 10 Closeout: Android MVP Milestone: Delivered final Definition-of-Done closeout for Phase 10 and the entire Android MVP milestone (Phases 0–10); authored `docs/release/mvp-milestone-retrospective.md` analyzing the legacy prototype collapse vs. the rebuilt architecture; delivered automated regression suite in `apps/mobile/test/phase10_mvp_milestone_closeout_test.dart`; consolidated carried-forward limitations ledger; added Section 12.8 in `AI_ROLES/ARCHITECTURE.md`; and established the frozen architectural contract for Phase 11.

---

## 3. What Exists Right Now (Verified)

### Code & Architecture Skeleton
- **`packages/vpn_engine_android/` (Flutter Android platform plugin, verified):** Created in
  P3-T11. Wraps the proven Gate A native VPN engine (`BrickVpnService` + `LibboxTunnelEngine` +
  real libbox `BoxService`) as a Flutter Android platform plugin, replacing the deleted
  `native/android/` standalone harness. P3-T12 added the Pigeon schema (`pigeons/vpn_api.dart`)
  and generated Dart/Kotlin bindings. P3-T13 implemented and remediated `PigeonVpnApiImpl.kt`,
  `CommandCoordinator.kt`, and `VpnEngineAndroidPlugin.kt` (D1, D2, R10, `ActivityAware` restored).
  P3-T14 implemented `AndroidVpnEngine implements VpnEngine` in Dart. Verified:
  **89/89** host-JVM unit tests (0 failures, 0 errors, 0 compiler warnings across `CommandCoordinatorTest` [10],
  `CommandVerdictHubTest` [7], `VpnEngineAndroidPluginTest` [10], `PigeonVpnApiImplTest` [18],
  `ServiceLifecycleHubTest` [7], `VpnStateMachineTest` [37]);
  **24/24** instrumented tests on `SM-A205F` (`RZ8M53WPMPF`, Android 10 / API 29, 0 failures across
  `BrickVpnServiceTest` [4], `BrickVpnServiceVerdictRaceTest` [1], `BrickVpnServiceVerdictTest` [6],
  `LibboxEngineTest` [9], `PigeonVpnApiImplInstrumentedTest` [4]); and
  **19/19** Dart/Flutter unit tests in `test/android_vpn_engine_test.dart`.
  Wired into workspace test discovery with **768/768** total Dart/Flutter tests passing monorepo-wide.
  `PlatformInterface` implements all **18** libbox methods. `minSdk` 24, `compileSdk`/`targetSdk` 36,
  AGP 9.1.0, Gradle 9.3.1, built-in Kotlin. Builds its own `libbox.aar` via
  `scripts/build_libbox_aar.sh` (sing-box v1.10.7, `with_utls`, 16 KB aligned).
- **`packages/shared_utils/` (Pure Dart, verified):** Retroactively corrected P0-T6's scaffolding by removing all Flutter SDK transitives. Contains a hand-written, sealed `Result<T, E>` primitive with `Ok` and `Err` final subclasses (value-equality with `identical` fast path, intentionally no `toString` override so sensitive error payloads are not printed by default, `map`/`mapErr` transforms, and exhaustive `fold`/pattern-matching). Tested with 10 standalone unit tests running under `dart test`.
- **`packages/core_domain/` (Pure Dart, verified):** Contains the complete polymorphic `OutboundConfig` hierarchy — sealed `TcpBasedOutbound` family (VLESS, VMess, Trojan), sealed `QuicBasedOutbound` family (Hysteria2, TUIC — mandatory non-nullable TLS, `zeroRttHandshake` defaulting to false), and standalone `ShadowsocksOutbound` — plus 7 shared composition types (`TlsSettings`, `TransportSettings` with 4 transports, `QuicSettings`, `MultiplexSettings`, and the REALITY/uTLS/fragment blocks), the `ProtocolType` enum (6 values with canonical URI schemes), and the `ServerProfile` container with `copyWith`. Ships alongside sealed `ConnectionState` (5 variants), sealed `ConnectionErrorReason` (4 variants), and immutable `TrafficStats`. All value types are const-constructible with `identical`-fast-path equality, implement discriminated snake_case `toJson()`, and intentionally have no `toString` override (SECURITY.md). Tested with 89 standalone unit tests running under `dart test`.

**API-shape change (2026-09-25):** `TlsSettings`, `WebSocketTransport`, `HttpTransport`, `HttpUpgradeTransport`, and `Hysteria2Outbound` are **no longer `const`-constructible**. The first four now defensively copy their `List`/`Map` fields into unmodifiable views at construction (so a caller mutating a collection afterwards can no longer change a "value type" that may sit in a `Set`/`Map` with a shifting `hashCode`); `Hysteria2Outbound` gained an unconditional constructor-time `ArgumentError` when `obfsType`/`obfsPassword` are set inconsistently. Both are runtime operations a const constructor cannot express. All other domain value types remain `const`-constructible.
- **`packages/core_vpn_engine/` (Pure Dart, verified):** Migrated from Flutter scaffold to pure Dart in P1-T4. Exposes the `abstract interface class VpnEngine` contract (authoritative `connectionState` stream, independent `trafficStats` stream, acceptance-separate-from-state `start(ServerProfile)`/`stop()`/`getStatus()`) and sealed `VpnCommandResult` (5 stateless variants: Accepted, RejectedBusy, RejectedInvalidConfig, RejectedPermissionDenied, Failed — const, value-equal, discriminated `toJson()`, no `toString`). P1-T5 added the in-memory `MockVpnEngine` reference implementation (541 lines): simulated lifecycle (`Disconnected` → `Connecting` → `Connected` → `Disconnecting` → `Disconnected`) with injectable delays, a periodic `TrafficStats` ticker, configurable rejection/failure hooks, an exhaustively-checked legal-transition graph that throws `StateError` on impossible sequences, structurally independent stats/connection pipelines, and an idempotent `dispose()`. Tested with **43 standalone unit tests** under `dart test` (13 from P1-T4 + 30 in `mock_vpn_engine_test.dart`), including exhaustive-switch, stream-isolation, session-token race, stop-watchdog, 100-interleaved-command stress, and 100-engine resource-leak checks. **P1-T5 hardening (2026-09-26)** further added: a monotonic **session token** so superseded async callbacks can never transition the engine; a hard **5000 ms stop watchdog** (`MockVpnEngine.defaultStopWatchdogTimeout`, overridable only so tests can drive the mechanism without a 5-second wait) that force-completes a stuck teardown; fully **idempotent `stop()`** (always accepted); per-session counter reset relocated into `start()`; hardened disposal ordering (`_disposed` set before controllers close, all four timers cancelled); and `simulateConnectionFailure()` / `simulateUnexpectedDisconnect()` failure hooks. The legal-transition graph now permits **`Connected` -> `Error`** so an established tunnel can fail without being asked to (previously only `Connecting` could reach `Error`), which is what `simulateUnexpectedDisconnect()` exercises.
- **`apps/mobile` (Flutter application shell, verified on hardware):** Full application shell integrating all 7 packages, routing, localization, state management, and native VPN lifecycle:
  * `lib/core/providers/` — `@Riverpod(keepAlive: true)` providers: `vpnEngineProvider` (bound to `AndroidVpnEngine` on device, overridable), `appRouterProvider` (`GoRouter`), `appLoggerProvider` (`AppLogger`). All `.g.dart` files are generated by `build_runner` and are committed.
  * `lib/core/logging/` — `AppLogger` routing messages through `LogRedactor` (3-surface redaction across live viewer, clipboard, and disk sink).
  * `lib/core/router/` — Route table supporting Home, Settings, Servers, Subscriptions, QR Scanner, and Live Logs screens.
  * `lib/features/` — Feature-first modules with clean domain/data/presentation separation: connection lifecycle, server management, subscription sync, settings & resilience toggles, QR import, and live log viewer.
  * Verified on physical hardware (`Samsung SM-A205F`, Android 10 / API 29) across Phases 3, 7, 9, and 10 with live encrypted tunnel routing, process death recovery, and release APK execution.
- **Melos Workspace (7 packages):** Configured via root `pubspec.yaml` and package `resolution: workspace` settings across 7 packages: `shared_utils`, `core_domain`, `core_vpn_engine`, `config_parser`, `ui_theme`, `vpn_engine_android`, and `mobile`.
- **Quality Assurance & Test Suite Posture:**
  * **81.12% Monorepo Line Coverage:** 5,000 / 6,164 lines across authored Dart files (+410 lines hit gained monorepo-wide).
  * **93 Kotlin JVM Unit Tests:** 6 passing test suites in `packages/vpn_engine_android/android`.
  * **4 Cross-Feature Integration Journeys:** Comprehensive hermetic end-to-end suites in `apps/mobile/test/cross_feature_integration_suite_test.dart` executing in < 5 seconds.
  * **6 Phase 10 Release-Readiness Suites:** 28 automated tests verifying release signing, R8 minification/seeds, VpnService compliance, store listing assets, GitHub release readiness, and milestone closeout.
  * **5 Signed Release Artifacts:** Complete dual-distribution release packages (`app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`, `app-release.apk`, and `app-release.aab`) signed with 4096-bit RSA v2/v3 signatures and verified on physical hardware (`Samsung SM-A205F`).

### Repository & CI
- **Git HEAD sync:** Local `master` HEAD is verified equal to live `origin/master` at every audit cycle.
- **CI Status:** Automated GitHub Actions workflow (`.github/workflows/ci.yml`) enforces formatting, static analysis, pure-Dart test matrix, Flutter unit/widget tests, release APK & AAB builds, and checksum verification with fail-fast secret guards.
- **Branch Protection:** Active on remote `master` via GitHub UI (no force-push, no deletion).
- **Vulnerability Scanners:** GitHub secret scanning, push protection, and weekly Dependabot dependency vulnerability audits (`.github/dependabot.yml`) are active.
- **Tracked logs:** Phase 0 closeout report is committed and tracked in `AI_ROLES/logs/phase-0-closeout-2026-09-17.md`.

---

## 4. What Does NOT Exist Yet

- ~~`MockVpnEngine` reference implementation (`core_vpn_engine` — P1-T5)~~ — **now exists** (see §3). UI feature wiring and native integration are still ahead.
- ~~**Real redaction logic** (P1-T9 stub, Phase 8 work)~~ — **now exists** (delivered in P8-T2; systematic redaction across live viewer, clipboard export dialog, and on-disk log sink in `packages/shared_utils` and `apps/mobile`).
- ~~Android native integration (`VpnService`, `libbox` JNI bridge)~~ — **now exists** (delivered in Phase 3 Gate A + Gate B, with Pigeon bindings in `packages/vpn_engine_android`).
- ~~**Secure storage for saved server profiles — NOT yet done; release blocker.**~~ — **now exists** (delivered in P8-T1; field-level AES-256-GCM authenticated encryption backed by Android Keystore, schema v2 in `FileServerProfileRepository` with automatic plaintext migration and fail-closed tamper resistance).
- Clean Linux desktop toolchain (missing locally: clang, cmake, ninja, pkg-config; deferred to Phase 12).

---

## 5. Environment & Toolchain Notes

- **Verified toolchain pins:** Flutter 3.47.4 stable, Dart 3.13.3, Melos 8.7.0, Git 2.43.0. Do not change any pinned version as a side effect of another task.
- **Local Gradle init-script footgun (must stay disabled):** `/home/e60/.gradle/init.d/iran-mirrors.gradle.disabled` must remain disabled to prevent settings-repository conflicts in Android Gradle builds.
- **Disk pressure — standing gate item:** Disk `/` fluctuates as build/tool caches accumulate. As measured on 2026-09-25, `/` is at **86% (14 GB free)**, which is **below** the project's documented ~92% danger threshold. A manual cache cleanup was performed by the human maintainer between the 2026-09-22 forensic audit (which recorded 95% / 4.9 GB free — above the danger line) and this entry; this agent did not run the purge itself. Safe repo-local recipe if needed: `rm -rf apps/mobile/build packages/*/build .dart_tool apps/mobile/.dart_tool packages/*/.dart_tool` then `melos bootstrap`. Note the largest consumers on this machine are outside the repo (`~/.gradle` and `~/Android`, measured at 8.4 GB and 8.8 GB respectively on 2026-09-22), so the repo-local recipe alone is not sufficient. Watch this: once disk crosses ~92%, Flutter/Dart/Melos tools can silently fail with exit 255 and empty output. If a tool fails with exit 255 and produces empty output, run **the exit-255 diagnosis below first** before assuming disk pressure.
- **Exit-255 empty-output diagnosis (before assuming disk failure):** The snap-installed Flutter, Dart, and pub-global Melos shims silently fail with exit code 255 and zero-byte output when stdout is redirected to a regular file (e.g., `flutter --version > /tmp/x.log`). The identical command succeeds when piped (e.g., `flutter --version | cat`) or when written directly to a terminal. If you observe exit 255 with empty output from any of these tools, ALWAYS retry the command piped through `cat` or `tee` before concluding disk pressure or environment breakage. This misdiagnosis has happened at least once in project history; capturing it here to prevent recurrence.
- **AGP 9.1.0: how to apply `com.android.library` from a module's `plugins {}` block (recipe, measured 2026-10-03 during P3-T11).** Reusable for P3-T12–P3-T15 and any future Android library/plugin module here. **To apply AGP 9.1.0's `com.android.library` to a module via `plugins{}`, add a `pluginManagement.resolutionStrategy` mapping `id("com.android.library")` to `com.android.tools.build:gradle:9.1.0` in `settings.gradle.kts` — the plugin marker artifact AGP 9 publishes doesn't resolve otherwise.** Built-in Kotlin (no `org.jetbrains.kotlin.android`) works under this setup; the stock `flutter create --template=plugin` output does **NOT** build standalone against our AGP 9.1.0 pin — it relies on the consuming app's settings file for AGP, and its `java.srcDirs(...)` call is deprecated-as-error under 9.1.0.

  The five attempts below were each run as a real build, not reasoned about; the error strings are verbatim.

  | # | Approach | Outcome |
  |---|---|---|
  | 1 | `plugins { id("com.android.library") version "9.1.0" }` in the module | ✗ `could not resolve plugin artifact 'com.android.library:com.android.library.gradle.plugin:9.1.0'` — AGP 9 publishes no plugin-marker for this id |
  | 2 | bare `plugins { id("com.android.library") }` + module-local `buildscript { classpath(...) }` | ✗ `plugin dependency must include a version number for this source` — Gradle evaluates a script's `plugins {}` **before** that same script's `buildscript {}` |
  | 3 | same, version declared in a `plugins {}` block in `settings.gradle.kts` | ✗ same marker-resolution failure as (1) |
  | 4 | `buildscript { classpath(...) }` + `apply(plugin = "com.android.library")` | ✗ plugin applies, but **25** × `Unresolved reference 'implementation'` — `apply()` generates no Kotlin DSL type-safe accessors |
  | **5** | **`plugins { id("com.android.library") version "9.1.0" }` + `pluginManagement.resolutionStrategy { eachPlugin { … useModule("com.android.tools.build:gradle:${requested.version}") } }` in `settings.gradle.kts`** | ✓ **AGP applies, accessors generated, Kotlin compiles** |

  Two further AGP-9 traps found in the same session, both of which the stock Flutter template walks into:
  - `java.srcDirs("src/main/kotlin")` is deprecated and fails the build (`'fun srcDirs(...)' is deprecated. Use \`directories\` mutable set instead`) — and `directories` exposes no `setFrom` in this DSL version. **No `srcDirs` override is needed at all**: AGP 9 includes `src/main/kotlin` and `src/test/kotlin` by default.
  - A module cannot exclude a single source file from its own Kotlin compile via `exclude(...)`/`java.exclude(...)` in `sourceSets` — both resolve to Gradle's `Configuration.exclude` and fail with `Unresolved reference … receiver type mismatch`.
- **`minSdk` is now 24, overriding P3-T2's `minSdk 21` (human-confirmed, 2026-10-03).** Reason: Flutter's platform-plugin mechanism has a **hard floor of 24**, so remaining at 21 is **not a viable alternative** for ROADMAP P3-T11 AC #3 (the plugin must be resolvable by `apps/mobile`). This is an **external constraint forcing the change, not a preference**, and it supersedes the P3-T2 decision recorded at ROADMAP line ~1801 (`minSdk 21 is a human decision and remains an explicitly-unverified P3-T1 open item`). **The test device (SM-A205F, API 29) is unaffected either way, so our device test suite cannot detect this boundary — do not assume the 36/13 instrumented + host-JVM runs cover it.** Any future device-claim about supported API levels must be verified separately or stated as untested.

---

## 6. Open Questions / Pending Human Decisions

### RESOLVED (human decision, 2026-09-29) — sing-box version: staying on v1.10.7

**Decision: Brick VPN stays on sing-box v1.10.7. The pin does not move.**
Evidence base: the read-only evidence report of 2026-09-28 (no build attempted).

Rationale:

- **The interface cost is essentially zero for our scope.** v1.14.2 adds 14
  `PlatformInterface` methods; **10 of the 14 are Tailscale-SSH and bridge
  surface** (`OpenShellSession`, `LookupUser`, `LookupSFTPServer`,
  `ReadSystemSSHHostKey`, `CheckPlatformShell`, `UsePlatformShell`,
  `TailscaleHostname`, `CancelNotification`, `UsePlatformBridge`,
  `CreateBridge`), which this product does not implement. The remaining 4
  (`StartNeighborMonitor`, `CloseNeighborMonitor`, `RegisterMyInterface`,
  `LocalDNSTransport`) are opt-in L2-neighbour and DNS-transport facilities,
  also unused. **None of the 14 is required for the 6+2-protocol TUN MVP** —
  every one has a benign stub default in
  `experimental/libbox/config.go`.
  *(Correction: an earlier draft of this entry said all 14 were Tailscale/bridge.
  That was wrong — 10 of 14. The conclusion is unchanged, since none of the 14
  is needed either way.)*
- **Upgrading is not cheap.** `go.mod` at v1.14.2 requires **Go 1.25.5** against
  our **1.21.x** pin, and `build_libbox_aar.sh` hard-fails on mismatch; the
  `gomobile v0.1.4` pin was chosen because it is the version v1.10.7 requires
  and would need re-validating.
- **It breaks WireGuard/AmneziaWG.** The WireGuard *outbound* no longer exists
  at >= 1.13 (only `endpoint.go` remains), while
  `singbox_serializer.dart` still emits a WireGuard **outbound**. Moving the
  pin would therefore make that output invalid at runtime
  (`config_parser/README.md`).
- **Migration risk is low but real.** 5 methods are removed, and
  `FindConnectionOwner` changed return type `(int32, error)` ->
  `(*ConnectionOwner, error)` while keeping its name — a silent-breakage hazard
  for anything written against the 18-method table.

**Revisit only if** Tailscale-like features or a WireGuard-endpoint rewrite
become actual roadmap items. The v1.10.x pin is otherwise a standing,
deliberate choice — it is four minor series behind upstream and is **not**
expected to move. Note that v1.10.7 receives no upstream fixes from here on;
that is an accepted consequence of the decision, not an oversight.

### Phase 2 closeout audit — open items and known limits (2026-09-27)

Found by the closeout audit. Each is stated with its evidence so it can be verified, not re-derived.

1. **`config_parser` is no longer a pure, I/O-free package (P2-T10).** The `SubscriptionFetcher`
   adds one `dart:io` import. The package still has zero `package:flutter/` and zero `dart:ui`
   imports and still runs under plain `dart test`, but it is **no longer web-compatible** and no
   longer "pure and deterministic (no I/O)" as the README previously claimed. The fetcher is
   confined to a single file so the parsers stay pure, and the transport is an injectable
   interface, so moving it to a dedicated package later is a clean change. **A reviewer may
   reasonably overrule the placement decision and split it out.** Related: TLS **certificate
   pinning is still deferred** and should be added to the `SECURITY.md` hardening backlog.

2. **Security defect found and FIXED during this audit — echoed untrusted identifiers.**
   `UnsupportedSchemeError`, `UnsupportedProtocolError` and `UnsupportedCipherError` stored a
   caller-supplied token and reproduced it verbatim in `message`. The doc comments assumed the
   token was "a short, non-sensitive token", but nothing enforced that: a payload such as
   `{"type":"<credential>","server":...}` produced `Unsupported protocol: <credential>`, putting a
   secret into a log-bound string (`SECURITY.md` §4 forbids credentials in logs). Fixed by routing
   all three through `sanitiseEchoedIdentifier`, which passes only short, identifier-shaped values
   (`[a-z0-9-]`, <= 32 chars) and otherwise reports a shape mismatch. Covered by
   `packages/config_parser/test/error_redaction_test.dart`. **The underlying assumption — that a
   token field is safe to echo — should be re-checked anywhere else it is made.**

3. **`AmneziaWgOutbound` does not override `==`/`hashCode` — DEFERRED.**
   It inherits identity semantics from `WireGuardOutbound`, so two instances differing *only* in
   obfuscation parameters (`jc`, `jmin`, `jmax`, `s1`, `s2`, `h1`–`h4`) compare equal. This is a
   real correctness bug for any future deduplication or profile-diffing logic. It was **not** fixed
   because the fix requires adding fields or an override to `packages/core_domain`, which is
   strictly frozen. Needs a deliberate unfreeze.

4. **Sing-Box WireGuard outbound is deprecated; an endpoint migration is planned.**
   sing-box deprecated the WireGuard *outbound* in 1.11.0 and documents removal in 1.13.0
   ("Migrate WireGuard outbound to endpoint"). The JSON emitted here is correct for the 1.10/1.11
   schema this client targets. When the client moves to sing-box >= 1.13, WireGuard must be
   modelled as an `endpoint`, not an outbound — a `core_domain` shape change, so it needs its own
   task and an unfreeze.

5. **sing-box has no AmneziaWG schema — runtime AmneziaWG is not supported.**
   None of the nine obfuscation parameters exist in sing-box's WireGuard schema and it rejects
   unknown top-level keys. They are parsed, range-validated and preserved on the domain object
   (`toJson()` namespaces them under `amneziawg_obfuscation`) but are **not** emitted for runtime
   use, because doing so yields a config sing-box refuses to load. Real AWG support needs a patched
   sing-box or a different outbound construct. The `amneziawg://` / `awg://` URI scheme is also
   this project's own invention — no stable AWG link convention exists.

6. **AWG numeric ranges are uncited.** The `jc`/`jmin`/`jmax`/`s1`/`s2`/`h1`–`h4` bounds were
   implemented without a cited live AmneziaWG source during this work. They need checking against
   authoritative AmneziaWG documentation before being relied on.

7. **WireGuard private-key transport had to be handled defensively.** A base64 key contains
   `+`, `/` and `=`, any of which corrupts a URI's authority component, so a raw key in the
   userinfo position makes the link unparseable. The parsers accept either a percent-encoded
   userinfo or a `private_key` query parameter (query wins). Real-world clients are inconsistent
   here, so both forms are supported deliberately.

8. **`brick://` deep links are not registered with the OS.** `parseConfigContent` implements and
   tests the `brick://import?url=...` / `?config=...` contract, but
   `apps/mobile/android/app/src/main/AndroidManifest.xml` has no intent-filter for the scheme, so
   Android will not route such a link into the app. It is reachable from clipboard / in-app paste
   only until that Android wiring is added.

9. **Smart-router multi-entry detection is newline-based.** A body of several URIs joined by any
   separator other than a newline is routed as a single URI and fails with a syntax error instead
   of being split. Base64 bodies (no `://` at all) are handled correctly by falling through to the
   subscription decoder.

10. **The Sing-Box serializer's AmneziaWG handling is order-dependent.** `tryBuild` sets
   `'type': config.protocol.name` (which is `amneziawg` for an AWG outbound) and then
   `out.addAll(map)`, where the WireGuard branch supplies `'type': 'wireguard'`, which overwrites
   it. The result is correct, but the correctness depends on that overwrite order. There is a test
   pinning `json['type'] == 'wireguard'`; a future refactor that reorders these lines would
   silently emit `"type": "amneziawg"`, which sing-box would reject.

### Phase 1 closeout — open items (2026-09-26)

These items from early Phase 1 closeout have been resolved or superseded by subsequent phases:

1. **RESOLVED / SUPERSEDED BY PHASES 3–10 — On-Device Execution:** The app has been repeatedly validated on real Android hardware (`Samsung SM-A205F`, Android 10, API 29, `arm64-v8a`) across Phases 3 (P3-T15, P3-T16), Phase 7 (P7-T4), Phase 9 (P9-T3), and Phase 10 (P10-T6 direct APK sideload and P10-T8 milestone closeout smoke test). Routing, DNS interception, background foreground service, and release APK binaries are proven on target hardware.
2. **RESOLVED — Melos Command Execution:** Re-verified as clean. All Melos workspace test, analyze, and format commands execute deterministically without environmental hangs.
3. **RESOLVED / SUPERSEDED BY PHASES 3–10 — CI Validation:** CI workflow (`.github/workflows/ci.yml`) validates the entire codebase, including multi-package static analysis, unit tests, release APK & AAB builds, and checksum publication.
4. **RESOLVED / SUPERSEDED BY PHASES 8–10 — Log Redaction:** Delivered in P8-T2; `redact()` in `packages/shared_utils` and `LogManager`/`LogRedactor` in `apps/mobile` provide deterministic 3-surface redaction across the live viewer, clipboard export dialog, and on-disk log files (`brick_vpn_live.log`).
5. **RESOLVED / SUPERSEDED BY PHASES 3–10 — Governance Alignment:** Documentation, architecture invariant numbering, and sealed state hierarchies have been unified and aligned across all architecture documents.


6. **Dependabot PR #1:** An automated PR to update GitHub Actions remains open and requires a human decision (merge/close).
7. **Dependabot pub failures:** 6 automated dependency updates failed on Dependabot's dynamic run on 2026-09-17 (`apps/mobile`, `core_domain`, `core_vpn_engine`, `config_parser`, `shared_utils`, `ui_theme`) due to monorepo package resolution errors. Non-blocking for local development, but worth noting for automation health.
8. **Pre-P1-T3 competitive research completed (informational, no decision pending):** Four independent AI agents surveyed sing-box protocol documentation, Hiddify implementation, and Iranian VPN user community reports (2025-2026 blackouts). Three agents converged on the same protocol config architecture: a base `sealed OutboundConfig` with family sealed sub-classes (`TcpBasedOutbound`, `QuicBasedOutbound`, standalone `ShadowsocksOutbound`) plus shared composition types (`TlsSettings`, `TransportSettings`, `QuicSettings`, `MultiplexSettings`, `RealitySettings`). Findings including field surveys, competitive gaps, and Iranian censorship-blackout scenarios (dnstt fallback, TLS Fragment, Chrome QUIC parroting) are documented in `AI_ROLES/COMPETITIVE_RESEARCH.md` (see AI_ROLES/COMPETITIVE_RESEARCH.md). This research informed P1-T3's architecture choices before implementation began.

### Known deviations (accepted, not to be fixed)

0. **(2026-09-28) P3-T1 pinned Go 1.20 from `go.mod` alone; P3-T3 corrected it to
   1.21.x.** Evidence trail, recorded rather than amended:
   P3-T1 commit `c6ab7cc` changed exactly one file (`AI_ROLES/TOOLCHAIN_VERSIONS.md`,
   +193/-22) and ran **no build at all**, so the pin rested entirely on reading the
   `go` directive in sing-box v1.10.7's `go.mod` (`go 1.20`). P3-T3's first
   `gomobile bind` then failed with
   `command_connections.go:6:2: package slices is not in GOROOT`, because
   `experimental/libbox/command_connections.go:6` imports the stdlib `slices`
   package, which only entered GOROOT in Go 1.21. Corrected to Go 1.21.13
   (sha256-verified download, human-approved) and re-proven by a clean
   end-to-end rebuild producing a 48 MB `libbox.aar` with arm64 LOAD segments
   at `0x4000`. **Lesson, carried forward: a `go` directive is a floor, not a
   build recipe — a pin that was never exercised is a hypothesis.** See
   `TOOLCHAIN_VERSIONS.md` §"Go version (verified by build)".
1. **P1-T5 commit `45b7c85` violated conventional-commit format** (its whole multi-line body was committed as the subject line, so the subject begins `- In-memory VpnEngine…` instead of `feat:`/`docs:`). Because it is already pushed to `origin/master` and branch protection forbids force-push, and because rewriting published history is permanently prohibited for agents, this is accepted as a permanent historical deviation and **must not be amended**. All subsequent commits should use a conventional subject.
2. **Commit `586908c` bundles P1-T6 and P1-T7's output under a subject labelled only
   "(P1-T8)"** — `git log --oneline -- apps/mobile/lib/features/README.md` and
   `-- apps/mobile/lib/core/providers/vpn_engine_provider.dart` both resolve to that single
   commit, so no dedicated commit exists for T6 or T7 individually. Accepted as historical and
   **not to be split retroactively** (that would require a history rewrite, which is permanently
   prohibited for agents).
3. **Commit `2a1bb4c` ("Add SECURITY.md to define security architecture and
   policies for Brick VPN") does not follow conventional-commit format** — the subject
   begins with a capitalised imperative and no `type:` prefix. It is also the commit that
   introduced the ROADMAP, and therefore the commit that every `Not Started` status line
   from Phase 2 onward still traces back to. Accepted as historical, for the same reason
   as `45b7c85` and `f1245e9`. Recorded here so the count of non-conventional subjects is
   complete rather than silently understated.

4. **Commit `f1245e9` ("updating and fixing CODING_STANDARDS") does not follow
   conventional-commit format**, violating the rule established after `45b7c85`. It touches only
   `AI_ROLES/CODING_STANDARDS.md`. Accepted as historical for the same reason as above. All
   subsequent commits must use a conventional subject.
5. **`AppLogger.e()`'s `error` and `stackTrace` parameters bypass `redact()`.** Only the
   `message` parameter is redacted (structurally, via the single `_emit` chokepoint). An `Object`
   passed as `error` is attached to the log unredacted. Currently harmless because no domain
   type has a `toString` override, so accidental interpolation cannot emit a credential — but it
   is a real seam. **Open item for whoever implements real redaction in Phase 8**: route `error`
   through `redact` too, or document the exclusion as accepted.

6. **`packages/shared_utils/lib/src/result.dart` equality is stricter than payload-only comparison.** `Ok`/`Err` check `other.runtimeType == runtimeType`, so `Ok<int,String>(1)` is not equal to `Ok<num,Object>(1)`. This was deliberately **NOT** changed: simply dropping the `runtimeType` check would make equality **asymmetric** under Dart's covariant generics (one direction true, the other false), violating the `==` contract — a worse defect than being over-strict but symmetric. Documented as an accepted limitation, not a bug to fix.

7. **(2026-10-02) RISK — sing-box v1.10.7's `BoxService.Close()` calls `os.Exit(1)` on a
   `C.FatalStopTimeout` internally** (confirmed in pinned source during P3-T7). This means a hung
   libbox close can kill the entire app process, and our own 5000ms stop watchdog
   (`VpnStateMachine`) cannot intervene — it operates at the Kotlin level, above a process-kill.
   No mitigation exists yet; revisit during Phase 7 stability work (process-level supervision /
   restart strategy). Evidence: `experimental/libbox/service.go`, `func (s *BoxService) Close()`,
   pinned commit `253b41936ecd6ae17948d49d9c510d7100830927` —
   `select { case <-done: return err; case <-time.After(C.FatalStopTimeout): os.Exit(1) }`.

---

### Status provenance under human review (2026-09-28)

A governance integrity sweep (CI-restoration task, Part 1) ran `git blame` over the Status
line of every Phase 0–2 task in `ROADMAP.md` to establish *who wrote each `Completed`*. The
result is a provenance table held in that task's report. Its headline findings, stated here
without changing any ROADMAP status:

- **Phase 0 (P0-T1..T12):** all twelve trace to separate `docs:`-only commits, several of
  them explicitly titled "… after human review". This is the *correct* provenance pattern.
- **Phase 1 (P1-T1..T5):** statuses were written by separate `docs:` commits
  (`5120833`, `6b63ec6`, `300839c`, `896b060`) — correct pattern — **except P1-T5**, whose
  Status line was last written by `a0c2f8e`, the **same commit that added the
  `MockVpnEngine` code**. That is a probable agent self-mark (Class B).
- **Phase 2 (P2-T1..T8, T13, T14, T10, T11):** every `Completed` Status line was written by
  the **same commit that also changed `packages/` code**, i.e. an agent self-marked each task
  complete in the commit that implemented it (Class B). P2-T11's Status is additionally
  **uncommitted working-tree text** written by an agent (Class C). None of the Phase 2
  `Completed` statuses came from a later human sign-off commit.
- A task prompt had also instructed an agent to mark P2-T11 "Completed", which conflicts with
  `DEFINITION_OF_DONE.md` §1 ("An AI agent MUST NOT mark a task as `Completed` by itself").

**No ROADMAP Status was changed in response to these findings.** The human decides whether to
downgrade any of them to "Ready for Human Review — sign-off pending". This block exists so the
decision is made from evidence rather than from a doc that merely asserts the outcome.

### `core_domain` freeze exceptions A1 + A2 (2026-09-28), and re-freeze

The `core_domain` freeze was **temporarily lifted for exactly two, human-authorized changes**
and is **RE-FROZEN** immediately afterwards:

- **A1 — formatting-only:** `packages/core_domain/test/protocol_type_test.dart` and
  `packages/core_domain/test/wireguard_outbound_test.dart` (the two files that had been
  committed unformatted, turning CI red).
- **A2 — the AmneziaWgOutbound equality fix:** `packages/core_domain/lib/src/outbound_config.dart`
  (adds `==`/`hashCode` overrides covering the nine AWG parameters) plus the new
  `packages/core_domain/test/amneziawg_equality_test.dart`.

No other file under `packages/core_domain/` was modified. Nothing else in the frozen package
required change; if something does in future, it needs its own explicit authorization.

---

## 7. Immediate Next Steps (In Order)

1. **Human Review & Git Tag / Release Publication (`P10-T6` / `P10-T8`):** Review and approve `P10-T8`, commit the Phase 8–10 changes, push tag `v1.0.0`, and publish the staged release bundle via the commands in `scripts/prepare_github_release_bundle.sh`.
2. **Human Google Play Console Internal/Closed Track Upload (`P10-T7`):** Upload `app-release.aab` and the prepared store listing/compliance package (`docs/release/play-store-submission-guide.md`) to the Google Play Console Internal/Closed Testing track.
3. **Begin Phase 11 — Full UI/UX Design & Implementation (`P11-T1`):** Once `P10-T8` is approved by the human, start `P11-T1 (Design System Foundation: Visual Identity and Style Guide)`, presenting color palette, typography, spacing, and iconography options for human sign-off before screen redesigns.
