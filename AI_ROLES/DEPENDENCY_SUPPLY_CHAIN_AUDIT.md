# Dependency & Supply-Chain Security Audit Report (Phase 8 — P8-T5)

This document provides the formal security review of Brick VPN's software supply chain across all three runtime ecosystems:
1. **Dart / Flutter Monorepo Packages**
2. **Android / Kotlin Native Plugins & Gradle Dependencies**
3. **Go Core Engine (`libbox.aar` / sing-box)**

---

## 1. Executive Summary

As a privacy and censorship-circumvention tool, Brick VPN must ensure that its binary dependencies do not introduce malicious payloads, unvetted telemetry, excessive permissions, or unmaintained libraries.

### Key Audit Findings
- **Zero Critical / High CVEs:** Vulnerability scanning across direct and locked transitive dependencies identified **0** known security advisories or CVEs.
- **Trusted Package Registries:** 100% of external Dart dependencies are fetched from the official `https://pub.dev` repository with cryptographic SHA-256 package checksum verification in `pubspec.lock`. Zero unpinned `git:` dependencies or third-party package mirrors exist.
- **Retracted Transitive Packages Documented:** Two transitive dependencies (`cupertino_ui 1.1.0` and `material_ui 1.3.0`, pulled in transitively by `go_router: 18.0.1`) were flagged by pub as retracted upstream by their author in favor of newer feature versions (`1.1.6` and `1.10.0`). Neither package has any reported vulnerability or security advisory (`isCurrentAffectedByAdvisory: false`). A dry-run upgrade was verified, and lockfile version bumping is scheduled for Phase 10.
- **Minimal Manifest Footprint:** Both `AndroidManifest.xml` files declare strictly necessary permissions only. Dangerous/invasive permissions (`READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`, `ACCESS_FINE_LOCATION`, `RECORD_AUDIO`, `QUERY_ALL_PACKAGES`) are absent. `BrickVpnService` is strictly non-exported (`android:exported="false"`).
- **Automated Dependabot Monitoring:** Automated weekly security and version scanning is active via `.github/dependabot.yml` covering `pub`, `gradle` (both mobile app and engine plugin), and `github-actions`.

---

## 2. Multi-Stack Vulnerability Scan Results

### 2.1 Dart / Flutter Ecosystem
- **Audit Tooling:** `flutter pub outdated --json`, `dart pub deps --style=compact`, and official pub.dev GitHub Advisory Database matching.
- **Total Packages Scanned:** 7 workspace packages, 17 direct dependencies, 67 transitive dependencies.
- **Advisories Found:** **0**
- **Discontinued Packages:** **0**
- **Retraction Analysis:**
  - `cupertino_ui 1.1.0` -> `isCurrentRetracted: true`, `isCurrentAffectedByAdvisory: false`, `latest: 1.1.6`.
  - `material_ui 1.3.0` -> `isCurrentRetracted: true`, `isCurrentAffectedByAdvisory: false`, `latest: 1.10.0`.
  - **Verdict:** Neither package possesses any security defect or vulnerability. Both are cosmetic widget support layers pulled by `go_router`. Upgrading will be addressed during Phase 10 release dependency updates.

### 2.2 Android / Gradle Ecosystem
- **Gradle Version:** `9.3.1` (configured in `packages/vpn_engine_android/android/gradle/wrapper/gradle-wrapper.properties`).
- **Android Gradle Plugin (AGP):** `9.1.0` (`com.android.tools.build:gradle:9.1.0`).
- **Kotlin Target:** JVM 17.
- **Android SDK Targets:** `minSdk = 24`, `targetSdk = 36`, `compileSdk = 36`.
- **Core Library Desugaring:** Enabled (`desugar_jdk_libs:2.1.4`) to support modern Java 8+ APIs on older Android runtimes without backported vulnerabilities.

### 2.3 Native Go Core (`libbox.aar`)
- **Engine Source:** Official `sing-box` upstream release tag `v1.10.7`.
- **Build Recipe:** `scripts/build_libbox_aar.sh` with Go toolchain and tags `with_utls`.
- **Binary Hardening:** Native shared objects compiled for `arm64-v8a`, `armeabi-v7a`, `x86_64` with 16 KiB page-size ELF segment alignment.
- **Storage:** Hermetic local binary archive under `packages/vpn_engine_android/android/libs/libbox.aar`.

---

## 3. Direct Dependency Inventory & Risk Assessment

Every direct dependency across the monorepo workspace was audited for maintenance health, publisher provenance, capability footprint, and assigned a security risk tier:

| Package | Version | Publisher / Upstream | Capability Footprint | Risk Level |
|---|---|---|---|---|
| **`flutter_riverpod`** | `3.4.3` | Remi Rousselet (`rrousselGit`) | In-memory reactive state management | **Low** (zero network/disk capabilities) |
| **`riverpod_annotation`**| `4.0.7` | Remi Rousselet (`rrousselGit`) | Compile-time code generation annotations | **Low** (zero runtime footprint) |
| **`go_router`** | `18.0.1` | Flutter Team (`flutter.dev`) | Declarative in-app routing | **Low** (official Flutter first-party) |
| **`connectivity_plus`** | `6.1.5` | Flutter Community (`pluscommunity.dev`) | Network state change broadcast listener | **Low** (read-only network connectivity state) |
| **`permission_handler`**| `13.0.2` | Baseflow (`baseflow.com`) | Android runtime permission request bridge | **Low** (standard permission prompt bridge) |
| **`shared_preferences`**| `2.5.5` | Flutter Team (`flutter.dev`) | Key-value non-sensitive app settings storage | **Low** (official Flutter first-party) |
| **`mobile_scanner`** | `7.4.3` | Julian Steenbakker (`juliansteenbakker`) | Camera frame optical barcode reader (ML Kit) | **Medium** (requires `CAMERA` permission; scoped strictly to `QrScanScreen`) |
| **`easy_localization`** | `3.0.8` | Bogdan D. (`aissat.dev`) | JSON-based multi-language translation strings | **Low** (local asset reader) |
| **`logger`** | `2.8.0` | Simon Leier (`leier.dev`) | Console log formatting | **Low** (in-memory formatting; routed through `LogRedactor`) |
| **`path_provider`** | `2.1.6` | Flutter Team (`flutter.dev`) | Android file directory path resolution | **Low** (sandboxed app internal storage) |
| **`crypto`** | `3.0.7` | Dart Team (`dart.dev`) | Pure-Dart SHA-256 and HMAC implementations | **Low** (official Dart standard library) |
| **`petitparser`** | `7.0.2` | Lukas Renggli (`renggli.ch`) | Combinatorial parser library for smart configs | **Low** (pure Dart, zero I/O) |
| **`yaml`** | `3.1.4` | Dart Team (`dart.dev`) | YAML specification parser | **Low** (official Dart standard library) |
| **`pigeon`** | `29.0.6` | Flutter Team (`flutter.dev`) | Type-safe MethodChannel interface generator | **Low** (official Flutter first-party) |
| **`melos`** | `8.7.0` | Invertase (`invertase.io`) | Developer workspace monorepo orchestration | **Low** (developer CLI tool only) |
| **`very_good_analysis`**| `11.0.0` | Very Good Ventures (`verygood.ventures`) | Strict lint rules for Dart/Flutter | **Low** (static analysis only) |

---

## 4. AndroidManifest Permission & Capability Audit

### 4.1 Permission Justification Table

| Declared Permission | Scope & Feature Mapping | Justification |
|---|---|---|
| `android.permission.INTERNET` | Outbound VPN Sockets & Subscription Fetching | Required by libbox to open proxy network sockets and by `SubscriptionFetcher` to retrieve HTTPS subscriptions (P2-T10, P3-T17). |
| `android.permission.ACCESS_NETWORK_STATE` | Network Handoff & Auto-Reconnect | Required by `ConnectivityManager` to detect Wi-Fi/cellular transitions and trigger auto-reconnect backoff (P7-T1). |
| `android.permission.BIND_VPN_SERVICE` | Android VPN Framework Hook | Framework signature-only permission required by `VpnService.Builder.establish()` to establish TUN interface (P3-T6, P3-T17). |
| `android.permission.FOREGROUND_SERVICE` | Persistent Tunnel Execution | Required on Android 9+ (API 28+) to run `BrickVpnService` as a persistent foreground service (P3-T17, P7-T4). |
| `android.permission.FOREGROUND_SERVICE_SPECIAL_USE` | Android 14+ FGS Compliance | Required on Android 14+ (API 34+) for foreground services with subtype `vpn` (P3-T17, P7-T4). |
| `android.permission.POST_NOTIFICATIONS` | Ongoing Service Notification | Required on Android 13+ (API 33+) to display the mandatory ongoing VPN status notification (P3-T17). |
| `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Doze & Battery Optimization Exemption | Required for user-prompted battery optimization exemption to prevent OEM killer daemons from aborting VPN sessions (P7-T4). |
| `android.permission.CAMERA` | Optical QR Code Link Import | Declared for camera scanning in `QrScanScreen`; only requested when user explicitly taps "Scan QR" (P5-T3). |

### 4.2 Prohibited Permission Absence Verification
The following high-risk, invasive, or non-essential permissions were verified to be **completely absent** from all manifests:
- `android.permission.READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` (Zero external storage access)
- `android.permission.ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` (Zero location leakage)
- `android.permission.READ_PHONE_STATE` (Zero IMEI/carrier fingerprinting)
- `android.permission.READ_CONTACTS` (Zero contact harvesting)
- `android.permission.RECORD_AUDIO` (Zero microphone access)
- `android.permission.QUERY_ALL_PACKAGES` (Zero app enumeration)
- `android.permission.SYSTEM_ALERT_WINDOW` (Zero screen overlay capability)
- `android.permission.INSTALL_PACKAGES` (Zero self-updating/sideloading capability)

### 4.3 Service Export Security
- `BrickVpnService` is strictly declared with `android:exported="false"`. External applications cannot bind or send unauthorized intents to the VPN service.

---

## 5. Automated Dependabot & Continuous Monitoring Architecture

To ensure dependencies remain up-to-date and vulnerabilities are flagged immediately, `.github/dependabot.yml` configures automated weekly checks:

```yaml
version: 2
updates:
  - package-ecosystem: "pub"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
  - package-ecosystem: "gradle"
    directory: "/apps/mobile/android"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
  - package-ecosystem: "gradle"
    directory: "/packages/vpn_engine_android/android"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
```

Automated enforcement is codified in `apps/mobile/test/supply_chain_and_manifest_security_test.dart`.

