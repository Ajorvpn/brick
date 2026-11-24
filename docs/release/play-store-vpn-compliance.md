# Google Play Store VpnService Policy & Data Safety Compliance

**Document Version:** 1.0  
**Phase:** Phase 10 — Android MVP Release Prep (`P10-T4`)  
**Package Name:** `dev.brickvpn.mobile`  
**License:** GNU General Public License v3.0 or later (GPL-3.0-or-later)  
**Classification:** Google Play Console App Content & Policy Verification  

---

## 1. Google Play VpnService Policy Requirements & Compliance Matrix

### Official Google Play Policy Source References
- **Google Play VpnService Policy:** `https://support.google.com/googleplay/android-developer/answer/12564964` (Device and Network Abuse — VPN Service)
- **Android 14+ Foreground Service (`FOREGROUND_SERVICE_SPECIAL_USE`) Policy:** `https://support.google.com/googleplay/android-developer/answer/13392821` and `https://developer.android.com/about/versions/14/changes/fgs-types-required#special-use`
- **Google Play Data Safety Section Policy:** `https://support.google.com/googleplay/android-developer/answer/10787469`

Google Play Developer Program Policy mandates strict operational, cryptographic, and disclosure requirements for any application declaring and binding to `android.net.VpnService` (`android.permission.BIND_VPN_SERVICE`).

The table below outlines each specific Google Play policy requirement and details Brick VPN's concrete architectural and code implementation verifying compliance:

| Policy Requirement | Google Play Policy Specification | Brick VPN Architectural Compliance | Implementation Files |
|---|---|---|---|
| **Core Functionality** | The app's primary user-facing purpose must be a Virtual Private Network, or enterprise security/parental control. General apps cannot use `VpnService`. | Brick VPN is an open-source privacy and censorship-circumvention VPN client whose sole user-facing functionality is establishing and managing secure VPN tunnels. | `packages/vpn_engine_android/android/src/main/kotlin/dev/brickvpn/harness/vpn/BrickVpnService.kt`, `apps/mobile/lib/features/connection/` |
| **Mandatory Device-to-Endpoint Encryption** | All network traffic routed from the user device to the remote VPN endpoint through the `VpnService` tunnel MUST be cryptographically encrypted. | Every supported protocol encapsulates traffic using robust, authenticated cryptographic primitives (TLS 1.3, AEAD ChaCha20-Poly1305 / AES-256-GCM, Noise Protocol, or QUIC). Unencrypted cleartext transport is architecturally prohibited. | `packages/config_parser/lib/src/serializers/singbox_serializer.dart`, `packages/core_domain/lib/src/outbound_config.dart` |
| **Zero Ad Manipulation & Monetization** | VPN apps must NEVER manipulate, intercept, alter, inject, or redirect advertisements or traffic from other apps for monetization, ad attribution, or affiliate injection. | Open-source GPL-3.0 software with zero ad SDKs, zero ad injection hooks, zero traffic mutation, zero affiliate redirects, and zero data brokerage — a permanent invariant that applies identically to the Free plan and to any future Brick Pro plan. | Monorepo audit (`pubspec.yaml`, `build.gradle.kts`, `AndroidManifest.xml`) |
| **Prominent Disclosure & Consent** | The app must disclose tunnel usage prominently and must request user authorization via the Android system VPN consent dialog before opening a TUN interface. | Uses standard `VpnService.prepare(context)` API. If unapproved, launches Android OS VPN permission request activity. Tunnel is never established without explicit user consent. | `packages/vpn_engine_android/android/src/main/kotlin/dev/brickvpn/harness/vpn/BrickVpnService.kt` |
| **Foreground Service & Persistent Notification** | VPN execution must declare a foreground service with continuous notification so the user is aware when network traffic is being redirected. | Declares `android:foregroundServiceType="specialUse"` with `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE = "vpn"`. Posts a non-dismissible ongoing OS notification via `BrickVpnService` displaying title "Brick VPN" and content "Tunnel active" with tap-to-open intent to return to `HomeScreen` controls. | `packages/vpn_engine_android/android/src/main/AndroidManifest.xml`, `packages/vpn_engine_android/android/src/main/kotlin/dev/brickvpn/harness/vpn/BrickVpnService.kt` |
| **Local Data Privacy & Zero Telemetry by Default** | User network traffic, DNS requests, and browsing activity must never be collected, logged, or monetized by the developer. | Zero analytics SDKs, zero crash tracking clouds, zero remote logging, and diagnostics that are **off by default**. The only optional off-device payload is the 5-key anonymous server-health report (`apps/mobile/lib/core/telemetry/`), sent only after an explicit opt-in. Server profiles are stored encrypted on-device (`enc:v1:`). Logs remain in local memory/cache scrubbed by `LogRedactor`. | `packages/shared_utils/lib/src/redaction.dart`, `apps/mobile/lib/core/logging/log_redactor.dart`, `apps/mobile/lib/features/servers/data/repositories/file_server_profile_repository.dart` |

---

## 2. Ready-to-Submit Google Play Console VpnService Declaration Form

Below are the exact, copy-paste-ready responses to submit within Google Play Console under **Policy and programs** > **App content** > **VPN Service Declaration**:

### Question 1: Is VPN the core functionality of your app?
**Answer:** `Yes`

### Question 2: Core Purpose & Technical Justification

#### Short Description (Limit 500 characters):
```text
Brick VPN is an open-source privacy and anti-censorship VPN client. Its core and sole purpose is creating a secure local TUN interface via android.net.VpnService and routing device network traffic through user-configured encrypted proxy tunnels (including VLESS, VMess, Trojan, Shadowsocks, WireGuard, AmneziaWG, Hysteria2, and TUIC) to protect user communications and bypass network censorship.
```

#### Detailed Description (For review team):
```text
Brick VPN (dev.brickvpn.mobile) is an open-source (GPL-3.0) mobile VPN application designed to protect user privacy against network surveillance and circumvent arbitrary Internet censorship. The app's primary and sole user-facing feature is establishing an encrypted Virtual Private Network.

To achieve this, the application binds to the Android android.net.VpnService framework (implemented in dev.brickvpn.harness.vpn.BrickVpnService). When the user initiates a connection, the app invokes VpnService.prepare() to obtain system authorization, configures an IP TUN virtual network interface, and passes the resulting file descriptor to the embedded Sing-box core routing engine (libbox/gomobile runtime).

The engine routes outbound device packets into encrypted tunnels connecting to remote servers the user selects — either from the 
app's built-in official free server directory, which is fetched automatically over HTTPS on first entry (with a CDN mirror as 
failover) and cached encrypted on-device with Android Keystore keys, or from servers the user adds personally. The directory is 
a public list of community-contributed endpoints published from the project's open-source collection repository 
(`Ajorvpn/brick-sub-collector`); it is not a paid proxy service, and fetching it sends no account, identifier, or usage data. The 
app supports 8 modern encrypted protocols:
1. VLESS (TLS 1.3 / Reality with Vision/gRPC/WebSocket)
2. VMess (AEAD / TLS transport)
3. Trojan (TLS 1.3 encryption)
4. Shadowsocks (AEAD 2022 / ChaCha20-Poly1305 / AES-256-GCM)
5. WireGuard (Noise Protocol framework, ChaCha20-Poly1305, Curve25519)
6. AmneziaWG (Obfuscated WireGuard with custom junk packet headers)
7. Hysteria2 (QUIC / TLS 1.3 UDP-based congestion transport)
8. TUIC (QUIC v5 / TLS 1.3 multi-stream transport)

The app contains zero background services unrelated to the VPN tunnel and contains zero advertising or analytics SDKs. It makes 
exactly one automatic network request of its own — the plain HTTPS download of that public server list, at most once every 30 
minutes — and never deletes the cached list when the download fails. The Free plan requires no account and no payment details; if an optional Brick Pro subscription is introduced in a future release, Play Store builds would use Google Play Billing exclusively and no browsing or traffic logs would be collected on either plan.
```

### Question 3: Does your app encrypt all traffic from the device to the VPN tunnel endpoint?
**Answer:** `Yes`

#### Encryption Explanation:
```text
Yes. All network traffic handled by Brick VPN is cryptographically encrypted before leaving the device:
- Protocols using TLS (VLESS, VMess, Trojan) enforce modern TLS 1.3 authenticated ciphersuites (AES-128-GCM, AES-256-GCM, ChaCha20-Poly1305) with server certificate validation or Reality public key authentication.
- UDP-based protocols (WireGuard, AmneziaWG) utilize the Noise IK handshake with Curve25519 Diffie-Hellman, ChaCha20-Poly1305 AEAD, and BLAKE2s hashing.
- QUIC-based protocols (Hysteria2, TUIC) enforce mandatory TLS 1.3 encryption over UDP datagrams with authenticated session negotiation.
- Shadowsocks enforces authenticated AEAD ciphers (AEAD-2022, chacha20-ietf-poly1305, aes-256-gcm).
Cleartext transmission is strictly unsupported.
```

### Question 4: Video Demonstration Walkthrough Script for Google Play Reviewers

For submission in the Play Console URL field (e.g. unlisted YouTube link):

1. **App Launch & Initial State:** Show the main dashboard (`HomeScreen`) displaying "Disconnected" status on the `ConnectionStateBadge`, `SessionInfoPanel`, `ThroughputReadout`, `home_add_server_button` ("Add Server"), `home_add_subscription_button` ("Add Subscription"), and the saved servers list.
2. **Adding Server Configuration:** Tap the "Add Server" button to navigate to `AddServerScreen` (`/add-server`), paste a VPN configuration URI or scan a QR code (`QrScanScreen`), and save the profile. The saved profile appears in the active server card on `HomeScreen`.
3. **OS Permission Request:** Tap the `Connect` button (`FilledButton` on the active server card). The Android OS `VpnService.prepare` consent dialog appears ("Brick VPN wants to set up a VPN connection that allows it to monitor network traffic").
4. **Granting Consent & Tunnel Activation:** Tap "OK". The persistent Android status bar key icon appears, `BrickVpnService` posts its ongoing foreground notification ("Brick VPN" / "Tunnel active"), the `ConnectionStateBadge` reflects "Connected", the live 1 Hz session duration timer increments in `SessionInfoPanel`, and upload/download speeds update in `ThroughputReadout`.
5. **Tunnel Verification:** Open a web browser on the device, navigate to a public IP/DNS leak test page, demonstrating encrypted VPN traffic routing.
6. **Clean Disconnect:** Return to Brick VPN, tap the `Disconnect` button (`home_connect_toggle_button`) on `HomeScreen`. The VPN tunnel shuts down, the key icon disappears, the foreground notification is dismissed, and `ConnectionStateBadge` returns to "Disconnected".

---

## 3. Ready-to-Submit Google Play Console Foreground Service Declaration (`specialUse`)

Google Play requires targetSdk >= 34 apps declaring `FOREGROUND_SERVICE_SPECIAL_USE` to justify why foreground execution is strictly required.

### Declaration Field: Foreground Service Type
**Type:** `specialUse`  
**Manifest Property:** `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE = "vpn"`

### Justification Text for Play Console Reviewers:
```text
Brick VPN requires android:foregroundServiceType="specialUse" with subtype "vpn" for its core service (dev.brickvpn.harness.vpn.BrickVpnService).

Technical Justification:
1. Maintaining the Virtual Network Interface: When an encrypted VPN session is active, the app holds an open TUN file descriptor managed by android.net.VpnService. If the system were to suspend or terminate the process when the user switches to other apps, the TUN interface would immediately collapse, terminating active user connections and causing data loss or network leaks.
2. User Awareness & Control: A foreground service paired with a non-dismissible ongoing notification ("Brick VPN" / "Tunnel active") is required so the user is continuously aware that device network traffic is actively routed through an encrypted tunnel. Tapping the notification immediately returns the user to HomeScreen, where live session duration (SessionInfoPanel), real-time upload/download delta speeds (ThroughputReadout), and an immediate Disconnect toggle button are directly accessible.
3. Compliance with Android 14+ FGS Policies: Since VpnService is the core functionality and requires continuous process execution alongside network event monitoring, foreground service specialUse (vpn) is the standard and necessary mechanism approved under Android 14 requirements.
```

---

## 4. Ready-to-Submit Google Play Console Data Safety Questionnaire

### Google Play Data Collection Definition & Disclosure Scope
Under Google Play's Data Safety definition, "Data Collection" specifically refers to *transmitting user data off the user's device*. Local, on-device data processing and storage do not constitute collection under Google Play's questionnaire guidelines.

The only potential off-device transmission in this app is the **optional, off-by-default** anonymous server-health diagnostics described below. It is declared honestly rather than omitted: answering `No` while a diagnostics path exists would be a Data Safety violation.

### Questionnaire Responses:

1. **Does your app collect or share any of the required user data types?**
   - **Answer:** `Yes` — one category only: **App info and performance > Diagnostics** (optional).
   - *Rationale:* The app collects no personal identifiers, financial data, health data, contacts, photos, audio, files, location, browsing history, in-app search history, installed apps, app activity, device or advertising identifiers. The single declared category covers the anonymous server-health probe report, which the user must explicitly enable (**off by default**) and which is sent only if the build has a collector configured.
   - **Data type:** App info and performance > Diagnostics.
   - **Optional:** Yes — the switch named *Anonymous Server Health Diagnostics* in `Settings > Diagnostics & About` controls it, and it defaults to off.
   - **Not linked to identity:** Yes — the payload has no account, device, advertising or user identifier; `node_hash` is a truncated SHA-256 digest of the server, not of the user.
   - **Not shared with third parties:** Yes — first-party Dart code posts directly to the configured collector; zero third-party analytics/telemetry SDKs are bundled.
   - **Payload allowlist (5 keys):** `node_hash`, `ok`, `latency_ms`, `network_type`, `hour_utc`. Never host, IP, port, UUID, password, private key, remark, SSID/BSSID, IMEI, advertising ID, browsing history, DNS query, destination IP or traffic payload.

2. **Is all user data collected by your app encrypted in transit?**
   - **Answer:** `Yes` — the reporter accepts HTTPS endpoints only: `http`, empty hosts, userinfo and loopback/private/link-local literal addresses are rejected before any byte is written.

3. **Do you provide a way for users to request that their data is deleted?**
   - **Answer:** `Yes (user-controlled)` — turning the switch off stops all diagnostics and wipes the in-memory queue immediately, and the report queue is memory-only (never persisted), so nothing survives a process restart. There is no server-side account to delete because the payload is unlinked to any identity.
   - **In-App Local Data Deletion:** Users have complete control over all on-device data. User-imported server profiles and subscriptions can be deleted directly within the app on `ServersScreen` via the "Delete" action, while diagnostic log entries and the on-disk `brick_vpn_live.log` file can be wiped on `LiveLogsScreen` using the "Clear" button (`logs_clear_button`). Users can also reset all application data at any time via Android System Settings.

4. **Is your app's Data Safety form consistent with on-device local processing?**
   - **Server Profiles:** Stored strictly locally in private internal storage (`/data/user/0/dev.brickvpn.mobile/app_flutter/server_profiles.json`), encrypted using AES-256-GCM with an authenticated HMAC key derived from Android Keystore (`enc:v1:`). Never uploaded to any server.
   - **Diagnostic Logs:** Stored strictly in local memory and temporary circular buffer (`brick_vpn_live.log`). All sensitive credentials (passwords, UUIDs, private keys, subscription tokens) are automatically redacted at ingestion by `LogRedactor`. Logs never leave the device unless manually and deliberately exported by the user.

---

## 5. Monorepo Codebase Audit Confirmation: Zero Ads, Zero Trackers, Optional Anonymous Diagnostics

An automated and manual static audit was conducted across the monorepo to verify zero ad SDKs, zero tracking, zero billing SDKs, and zero unauthorized permissions:

1. **Manifest Permissions Audit (`AndroidManifest.xml`):**
   - `com.google.android.gms.permission.AD_ID`: **CONFIRMED ABSENT**
   - `android.permission.ACCESS_ADSERVICES_AD_ID`: **CONFIRMED ABSENT**
   - `android.permission.BIND_VPN_SERVICE`: **Present and properly guarded with `android:exported="false"`**
   - `android:foregroundServiceType="specialUse"`: **Present with `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE = "vpn"`**

2. **Dependencies Audit (`pubspec.yaml`, `pubspec.lock`, `build.gradle.kts`):**
   - Advertising SDKs (AdMob, Unity Ads, AppLovin, IronSource): **0 instances found (100% clean)**
   - Analytics & Attribution SDKs (Firebase Analytics, AppsFlyer, Adjust, Mixpanel): **0 instances found (100% clean)**
   - Crash Cloud SDKs (Crashlytics, Sentry, Bugsnag): **0 instances found (100% clean)**

3. **Dart Source Code Audit (`apps/mobile/lib/`):**
   - `AdWidget`, `BannerAd`, `InterstitialAd`: **0 occurrences found**
   - `FirebaseAnalytics`, `AdvertisingIdClient`: **0 occurrences found**
   - Traffic injection, HTTP proxy rewrites, or ad replacement: **0 occurrences found**
   - Third-party analytics/telemetry SDKs: **0 instances**. The only diagnostics code is first-party (`apps/mobile/lib/core/telemetry/server_probe_report.dart`, `server_probe_reporter.dart`): opt-in, off by default, HTTPS-only, rate-limited to one request per minute and 20 reports per batch, and limited to the five-key `node_hash` / `ok` / `latency_ms` / `network_type` / `hour_utc` payload.

4. **Kotlin Platform Source Audit (`packages/vpn_engine_android/`):**
   - VpnService tunnel logic strictly exchanges packets between the virtual TUN interface and Sing-box core routing without packet modification, packet sniffing, or monetization injection.

---

## 6. Monetization, Payments & Dual-Channel Licensing Policy (Free + Future Brick Pro)

This policy replaces every earlier "zero monetization ever" statement with the truthful current-plus-planned posture. The permanent invariants below apply to **all** plans, present and future:

1. **Permanent invariants (Free and Pro):** zero ads, zero ad SDKs, zero third-party trackers or analytics SDKs, zero data brokerage, and zero browsing/destination/DNS/traffic logging.
2. **Current build (Free plan):** no account required, zero billing SDKs bundled, zero payment code, zero checkout URLs, and zero purchase UI. The app is usable immediately after install.
3. **Future optional Brick Pro plan (not yet active):** the only planned account-scoped data is a minimal account identifier and subscription entitlement status, collected solely from users who explicitly choose Pro.
4. **Google Play Payments Policy invariant:** the `play` build flavor MUST use **Google Play Billing exclusively**. No external checkout URL, third-party payment gateway, or out-of-app payment link may ever exist inside a Play-distributed build. Any Pro entry point must appear only once a compliant Billing integration is shipped.
5. **GPL-3.0-or-later licensing invariant:** the client source remains GNU GPL-3.0-or-later, which fully permits commercial Pro subscriptions. Any future proprietary Play Billing integration MUST be isolated behind a build-flavor boundary (`play` vs `direct`/`foss`), so the pure FOSS/direct build compiles with zero proprietary SDKs and stays reproducible from public source.
6. **Disclosure invariant:** the Privacy Policy and the Google Play Data Safety declaration are updated before any Pro plan is activated.

