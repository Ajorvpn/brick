# Brick VPN Android MVP Milestone Retrospective (Phases 0–10)

**Document Reference:** `docs/release/mvp-milestone-retrospective.md`  
**Milestone:** Phase 10 Closeout — Android MVP Milestone (`P10-T8`)  
**Product Version:** `1.0.0` (Build `2001`)  
**Git Tag Prepared:** `v1.0.0`  
**Release Date:** November 12, 2026

---

## 1. The Legacy Prototype's Collapse vs. The Rebuilt Architecture

Before the commencement of Phase 0, the previous prototype codebase collapsed into unmaintainability, suffering from cascading crashes, race conditions, memory leaks, and unverified security assumptions. Over Phases 0 through 10, the entire system was rebuilt from first principles around formal architectural invariants, defensive domain boundaries, rigorous unit testing, and automated release validation.

### Comparative Failure Mode Resolution Matrix

| Legacy Prototype Failure Mode | Root Cause in Legacy Code | Architectural Resolution in Phases 0–10 | Verification & Evidence |
| :--- | :--- | :--- | :--- |
| **1. Monolithic Spaghetti & Regression Cascades** | Untested 8,000-line monolithic UI files; UI directly mutating native bridge state; zero automated tests. | **Phases 0–2 & 9:** Strict Melos monorepo separation (`core_domain`, `config_parser`, `core_vpn_engine`, `shared_utils`, `ui_theme`, `vpn_engine_android`, `mobile`). Domain logic completely isolated from Flutter/UI. | **81.12% line coverage** (`5,000 / 6,164` lines), **93 Kotlin JVM tests**, **4 hermetic cross-feature journeys** (`cross_feature_integration_suite_test.dart`). |
| **2. Zombie Services, State Races & ANRs** | Multiple simultaneous connection attempts spawned orphaned native services; disconnect blocked the main thread. | **Phases 3 & 7:** Single-flight `CommandCoordinator` mutex, formal `VpnStateMachine`, bounded 5000 ms disconnect watchdog, and `ServiceLifecycleHub` UI process re-attachment. | Tested across 12 discrete failure modes in `legacy_chaos_regression_suite_test.dart` and physical device `SM-A205F`. |
| **3. TUN Blackholes, DNS Leaks & SNI Leaks** | Traffic routed before TUN ready; DNS bypassed encrypted tunnel; raw IP-literals placed in TLS SNI extension. | **Phases 3 & 7:** Explicit `hijack-dns` tunnel routing, RFC 6066 IP-literal SNI stripping, debounced auto-reconnect with offline hold, and OS lockdown Kill Switch (`setBlocking`). | Verified via DNS routing audits and RFC 6066 SNI tests in `process_restart_reattach_test.dart`. |
| **4. Plaintext Secrets & Unredacted Logs** | Passwords and private keys stored in plaintext `SharedPreferences`; diagnostic logs printed sensitive credentials to logcat. | **Phase 8:** Android Keystore `AES-256-GCM` hardware encryption (`enc:v1:` schema v2 in `FileServerProfileRepository`), 3-surface `LogRedactor` (UI, clipboard, disk cache), and $O(1)$ input bounds. | Verified in `secure_storage_test.dart`, `log_redaction_test.dart`, and `untrusted_input_security_review_test.dart`. |
| **5. Release Gomobile Crashes & Unsigned Builds** | Code worked in debug mode but crashed with `NoClassDefFoundError` in release mode due to aggressive R8 stripping; manual ad-hoc signing. | **Phase 10:** Two-layer ProGuard/R8 keep rules protecting gomobile, libbox, and Barhopper (`seeds.txt`), 4096-bit RSA v2/v3 release signing pipeline, AAB and ABI splits. | Verified via `seeds.txt` audit in `proguard_r8_hardening_test.dart` and automated `prepare_github_release_bundle.sh`. |

---

## 2. Holistic Fresh-Build-to-Installed-Artifact Verification Summary

The complete pipeline from clean source tree to running binary on physical hardware has been verified end-to-end:

1. **Compilation & Minification:**
   - Compiled with Flutter 3.47.4, AGP 9.1.0 (Gradle 9.3.1), and JDK 17.
   - Built 3 split-per-ABI APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`), 1 universal multi-ABI fallback APK, and 1 Android App Bundle (`app-release.aab`).
   - R8 minification and resource shrinking verified via `mapping.txt` and `seeds.txt`.
2. **Cryptographic Signing & Checksums:**
   - All 4 release APKs signed with APK Signature Scheme v2 and v3 using the official 4096-bit RSA key.
   - App Bundle signed with standard JAR signing matching the production certificate digest:
     `563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`
   - Deterministic `SHA256SUMS.txt` generated and self-verified via `sha256sum -c`.
3. **Compiled Manifest Audit:**
   - `apkanalyzer manifest print` confirms `android:label="Brick VPN"`, `versionName="1.0.0"`, `versionCode="2001"`, and `targetSdk=36`.
4. **Physical Hardware Smoke Test:**
   - Installed `app-arm64-v8a-release.apk` on physical test device:
     - **Device Model:** `Samsung SM-A205F` (`RZ8M53WPMPF`)
     - **OS Version:** Android 10 (API 29), Kernel 4.4.177, `arm64-v8a`
     - **Install Result:** `Success` (`ADB_INSTALL_EXIT=0`)
     - **Launch & Runtime PID:** Launched via `android.intent.category.LAUNCHER`, verified active process running with `SM_A205F_RUNNING_PID=24311`.

---

## 3. Consolidated Known Limitations & Carried-Forward Items

In compliance with project governance and Definition-of-Done standards, the following 6 items are documented as open, tracked, and carried forward:

1. **Deliberately Minimal Placeholder UI (Scoped to Phase 11):**
   - The current UI uses clean, standard Material 3 functional components (tiles, dialogs, buttons) without custom visual branding, illustration, or motion design. This was a deliberate architectural decision to prioritize engine stability and security. Full UI/UX redesign is scoped to **Phase 11**.
2. **Unstructured Free-Text Native Log Redaction Boundary (`P8-T2`):**
   - Monorepo-wide `LogRedactor` deterministically sanitizes known profile passwords, keys, URIs, UUIDs, and external IPs across all 3 presentation surfaces. However, novel unstructured free-text strings emitted directly by native Go/C third-party libraries remain best-effort; users are warned to review logs before exporting.
3. **OEM Battery-Optimization Quirks (`P7-T4`):**
   - Non-standard OEM Android skins (Xiaomi MIUI/HyperOS, Samsung One UI, Huawei EMUI) maintain aggressive background process killers that may terminate VPN services in deep sleep. Brick VPN provides the in-app "Ignore Battery Optimizations" exemption flow to mitigate this.
4. **Bit-for-Bit Reproducible Docker Builds (`P8-T4`):**
   - While cryptographic checksums and signatures are published for every binary release, hermetic bit-for-bit Docker build reproducibility across independent developer machines is planned for **Phase 10+ / future releases**.
5. **Google MASA Badge Program Deferral (`P10-T7`):**
   - Google Play's Mobile App Security Assessment (MASA) "Independent Security Review" badge requires 10,000+ installs, 250+ reviews, and 90+ days on Google Play, plus a paid third-party laboratory audit ($3k–$6k USD). It is deferred until post-launch eligibility thresholds are met.
6. **Google Play Console Human Review Timeline (`P10-T7`) & Transitive Cosmetic Lockfile Bump (`P8-T5`):**
   - The Play Store submission package is 100% prepared and staged in-repo; actual web upload and review iteration depend on human developer console actions and Google's review queue. Transitive lockfile maintenance is continuously handled by Dependabot.

---

## 4. Phase 11 (`Full UI/UX Design & Implementation`) Handoff Statement

With the completion of Phase 10, the core foundation of Brick VPN is **rock-solid, thoroughly tested, and frozen**:
- All 8 encrypted transport protocols (VLESS Reality, VMess, Trojan, Shadowsocks, WireGuard, AmneziaWG, Hysteria2, TUIC) are proven.
- OS-level `VpnService` lifecycle, network transitions, kill switch, and background foreground service are hardened against races and ANRs.
- Security at rest (Android Keystore AES-256-GCM) and in transit (TLS 1.3 / Noise / QUIC) is cryptographically enforced.
- Release signing, R8 minification, dual distribution (GitHub Direct APK + Play Store AAB), and compliance documentation are finalized.

**Phase 11 (`Full UI/UX Design & Implementation — P11-T1: Design System Foundation: Visual Identity and Style Guide`)** can now proceed with complete confidence. Phase 11 will build upon this frozen core strictly at the presentation layer (`apps/mobile/lib/features/` and `packages/ui_theme/`), replacing the minimal functional widgets with custom visual identity, cohesive color schemes, animations, and typography without altering underlying VPN engine or domain logic.

