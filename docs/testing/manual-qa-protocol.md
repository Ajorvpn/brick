# Pre-Release Manual QA Test Protocol & Verification Checklist

**Document Purpose:**
This document defines the durable, human-executable manual QA test protocol for the Brick VPN Android application. It serves as the authoritative pre-release checklist for release candidates, verifying end-to-end correctness, resilience, security boundaries, and telemetry across the Android operating system.

**Scope & Origin Cross-References:**
This protocol consolidates and operationalizes requirements validated across all preceding development phases:
- **Phase 2 (`P2-T1`–`P2-T8`):** URI parsing, protocol configurations (VLESS, Trojan, Shadowsocks, WireGuard, Hysteria2, TUIC).
- **Phase 3 & 4 (`P3-T1`–`P4-T3`):** Go-mobile native engine bridge, Sing-box integration, TUN routing.
- **Phase 5 (`P5-T1`–`P5-T9`):** UI navigation, QR camera scanning, subscription ingestion, server management.
- **Phase 6 (`P6-T1`–`P6-T6`):** 1 Hz session duration telemetry, throughput delta meters, in-memory & on-disk live logging.
- **Phase 7 (`P7-T1`–`P7-T6`):** Auto-reconnect state machine, fail-closed kill switch, OEM Doze resistance, process restart re-attachment.
- **Phase 8 (`P8-T1`–`P8-T6`):** Untrusted input security review, 100 KB paste limits, bidirectional text sanitization, encrypted storage v2 migration (`enc:v1:`).
- **Phase 9 (`P9-T1`–`P9-T3`):** Unit test gap filling, automated cross-feature integration suite, and manual system boundary validation.

---

## Section 1: Environment & Pre-Flight Setup

### 1.1 Device & Host Requirements
- **Host Workstation:** Linux / macOS with Android SDK Platform-Tools (`adb`), Flutter 3.41+, and Dart 3.11+.
- **Recommended Device Matrix:**
  1. *Minimum Supported OS:* Android 8.0 (API 26) or Android 10 (API 29) physical device (e.g., Samsung SM-A205F).
  2. *Target OS:* Android 14+ (API 34/35) device or emulator with strict foreground service type enforcement.
  3. *OEM Diversity:* At least one non-Pixel OEM device (Samsung One UI, Xiaomi MIUI, or OnePlus OxygenOS) to verify aggressive background app optimization handling.

### 1.2 Clean Install & App State Reset
Prior to beginning a formal pre-release QA run, clear all existing user preferences, encrypted storage, and cached tokens:
```bash
# Terminate any running instance
adb shell am force-stop dev.brickvpn.mobile

# Clear all app data and permissions
adb shell pm clear dev.brickvpn.mobile

# Verify APK package signature and checksum before installing release candidate
apksigner verify --verbose --print-certs path/to/app-release.apk
sha256sum path/to/app-release.apk
```

---

## Section 2: Onboarding & Server Ingestion

### Protocol 2.1: Manual URI Paste & Untrusted Input Hardening
- **Origin Reference:** `P2-T1`..`P2-T8`, `P8-T3`, `apps/mobile/test/untrusted_input_security_review_test.dart`
- **Steps:**
  1. Launch app -> Tap **Add Server** (`home_add_server_button`).
  2. Test valid URIs for each supported outbound protocol:
     - `vless://uuid@host:443?security=none#VLESS_Test`
     - `trojan://password@host:443#Trojan_Test`
     - `ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@host:8388#SS_Test`
     - `wireguard://privateKey@host:51820?publickey=peerKey#WG_Test`
     - `hysteria2://auth@host:443#Hy2_Test`
     - `tuic://uuid:password@host:8443#TUIC_Test`
  3. Verify rejection of invalid/malformed URIs (e.g., `vless://invalid`, `http://plain`).
  4. Test 100 KB oversized input paste (e.g., pasting a 200 KB text string).
- **Pass Criteria:**
  - Valid URIs parse immediately and display correct server remark in server list.
  - Invalid URIs display user-friendly validation error without crashing.
  - Error messages NEVER echo raw credentials or private keys in the UI or logcat.
  - Pasting 100 KB+ is safely truncated/rejected without ANR or OOM memory freeze.

### Protocol 2.2: QR Code Scanning & Camera Permission Recovery
- **Origin Reference:** `P5-T3`, `P8-T3`, `apps/mobile/test/qr_scan_screen_test.dart`
- **Steps:**
  1. On `AddServerScreen`, tap **Scan QR Code**.
  2. *First Prompt:* System camera permission dialog displays. Tap **Deny**.
     - Verify: UI remains on Add Server screen; informational banner explains camera is needed.
  3. Tap **Scan QR Code** again. System prompt appears. Tap **Don't ask again** / **Deny**.
     - Verify: UI displays "Camera permission required" with a direct button to "Open System Settings".
  4. Tap "Open System Settings" -> Grant Camera permission in OS Settings -> Return to app.
  5. Point camera at a valid server QR code.
- **Pass Criteria:**
  - Single-scan debounce prevents duplicate server additions.
  - Parsed configuration automatically navigates back to server list with imported profile selected.

### Protocol 2.3: Subscription URL Import & Cascade Delete
- **Origin Reference:** `P5-T4`, `P8-T1`, `P8-T2`, `P9-T2 (Journey 1)`
- **Steps:**
  1. Tap **Add Subscription** (`/add-subscription`).
  2. Input subscription name "Alpha Feed" and HTTPS URL: `https://example.com/feed?token=testSecret123`.
  3. Attempt import of plain HTTP URL (`http://example.com/feed`).
     - Verify: Rejected with clear error (HTTPS is strictly required).
  4. Perform valid HTTPS import:
     - Observe: Progress indicator, then automatic navigation back to Home/Servers.
  5. Refresh subscription from server management menu.
  6. Delete subscription:
     - Observe prompt: "Deleting this subscription will remove all associated server profiles."
     - Confirm deletion.
- **Pass Criteria:**
  - On-disk storage (`server_profiles.json`) stores the subscription URL with `enc:v1:` cipher prefix.
  - Refresh gracefully updates modified child nodes while preserving active tunnel continuity if connected.
  - Subscription deletion atomically cascades to delete all child profiles without leaving orphaned records.

---

## Section 3: Core VPN Connection, Routing & DNS Leak Verification

### Protocol 3.1: First-Time Android VPN Consent Dialog (`VpnService.prepare`)
- **Origin Reference:** `P3-T1`, `P5-T8`, `docs/testing/manual-integration-scripts.md (Script 1)`
- **Steps:**
  1. Ensure app data is fresh (`pm clear`).
  2. Select an active server -> Tap **Connect**.
  3. System modal dialog appears: "Connection request: Brick VPN wants to set up a VPN connection..."
  4. Test **Cancel**: UI reverts to `Disconnected`. No VPN key icon in status bar.
  5. Tap **Connect** again -> Tap **OK**.
- **Pass Criteria:**
  - Tunnel connects cleanly. Android status bar shows persistent VPN Key icon.
  - Consent dialog is never requested again on subsequent connects unless app data is cleared.

### Protocol 3.2: Full IPv4/IPv6 Tunnel Routing & Zero DNS Leak Check
- **Origin Reference:** `P3-T3`, `P7-T3`, `AI_ROLES/ARCHITECTURE.md Section 11`
- **Steps:**
  1. Connect to active tunnel on physical device.
  2. Verify routes via ADB shell:
     ```bash
     adb shell ip route show table all | grep tun
     ```
  3. Open mobile browser and visit `https://ipleak.net` or run DNS leak test.
  4. Test resolving IPv4 (`0.0.0.0/0`) and IPv6 (`::/0`) endpoints.
  5. Test RFC 6066 IP-literal SNI: connect to a server whose endpoint is a raw IP address.
- **Pass Criteria:**
  - External public IP matches the remote VPN node, NOT the local ISP/Cellular IP.
  - DNS resolvers listed match the VPN's secure DNS (`1.1.1.1` / `8.8.8.8` via TUN hijack-dns). Zero local ISP DNS leaks detected.
  - IP-literal SNI TLS handshake completes without sending numeric IP literals in the TLS ClientHello SNI extension.

### Protocol 3.3: Mid-Connection Server Switch & Disconnect
- **Origin Reference:** `P5-T6`, `P5-T7`, `P9-T2 (Journey 3)`
- **Steps:**
  1. While Connected to "Server Alpha", open the Servers list tab.
  2. Tap "Server Beta" -> Tap Connect.
  3. Observe status transition and timing.
  4. Tap Disconnect.
- **Pass Criteria:**
  - Handoff disconnects "Server Alpha" and brings up "Server Beta" cleanly within < 2000ms.
  - User-initiated disconnect terminates tunnel within < 1000ms; key icon disappears from status bar.

---

## Section 4: Telemetry, Live Logs & 3-Surface Redaction

### Protocol 4.1: Real-Time Session Telemetry & Traffic Speedometers
- **Origin Reference:** `P6-T1`..`P6-T4`, `apps/mobile/test/traffic_stats_plumbing_test.dart`
- **Steps:**
  1. Connect to VPN.
  2. Observe `SessionInfoPanel` on `HomeScreen`:
     - Duration timer ticks at exactly 1 Hz (`00:00:01`, `00:00:02`, ...).
  3. Run a network speed test or stream a high-bitrate video.
  4. Observe `ThroughputReadout`:
     - Uplink and downlink meters display instantaneous transfer speeds (`KB/s` / `MB/s`).
- **Pass Criteria:**
  - Initial connection displays `0.0 B/s` delta speeds without false initial cumulative spikes.
  - Cumulative bytes transmitted/received match or closely track OS network interface metrics in `proc/net/dev`.

### Protocol 4.2: Live Logs Viewer, Auto-Scroll & 3-Surface Redaction
- **Origin Reference:** `P6-T5`, `P8-T2`, `P9-T2 (Journey 3)`
- **Steps:**
  1. Navigate to Settings -> **Diagnostic Live Logs** (`/logs`).
  2. Generate network traffic; observe live log entries streaming.
  3. Scroll up into log history:
     - Verify: Auto-scroll pauses and floating "Resume auto-scroll" button appears.
     - Tap "Resume auto-scroll": View snaps back to latest log entry.
  4. Tap the **Copy Logs** button:
     - Verify: A non-dismissible modal dialog (`barrierDismissible: false`) warns about sensitive diagnostic information.
     - Tap **Confirm & Copy**.
  5. Paste clipboard into an external text editor.
  6. Inspect on-disk temporary file:
     ```bash
     adb shell cat /data/user/0/dev.brickvpn.mobile/cache/brick_vpn_live.log | head -n 50
     ```
- **Pass Criteria:**
  - All three surfaces (Viewer UI tree, Clipboard export, on-disk file) contain zero raw passwords, subscription tokens, private keys, or external peer IPs.
  - Redacted tokens are cleanly masked with `[REDACTED]` or `[REDACTED_IP]`.

---

## Section 5: Resilience, Kill Switch, Doze & Process Death

### Protocol 5.1: Network Interface Handoff & Auto-Reconnect
- **Origin Reference:** `P7-T1`, `P7-T5`, `P9-T2 (Journey 2 & 4)`
- **Steps:**
  1. Connect to VPN while connected to Wi-Fi.
  2. Turn off Wi-Fi on device (triggering OS handoff to Mobile Data / LTE).
  3. Observe status transitions.
  4. Turn on Airplane mode (inducing complete network outage).
  5. Wait 10 seconds, then turn off Airplane mode.
- **Pass Criteria:**
  - Interface handoff (Wi-Fi -> Mobile Data) triggers debounced auto-reconnection and recovers `Connected` state within < 3s.
  - Airplane mode outage causes auto-reconnect to enter offline hold without firing futile rapid retry loops or battery-draining loops.
  - Restoring network connectivity triggers immediate reconnection.

### Protocol 5.2: Fail-Closed Kill Switch Verification
- **Origin Reference:** `P7-T2`, `P7-T5`, `P9-T2 (Journey 2)`
- **Steps:**
  1. In Settings, toggle ON **Kill Switch (Block untunneled traffic)**.
  2. Connect to VPN.
  3. Simulate unexpected native bridge death:
     ```bash
     adb shell am force-stop dev.brickvpn.mobile
     ```
     *(Or terminate the Sing-box tun interface)*.
  4. Attempt external network requests from device.
  5. Open app -> Observe `HomeScreen`:
     - Verify: Prominent `kill_switch_blocking_banner` is displayed.
  6. Tap `kill_switch_unblock_button`:
     - Verify: Blocking banner disappears, network lock is released.
- **Pass Criteria:**
  - Unexpected drop while armed blackholes all non-VPN traffic (fail-closed).
  - Explicit user disconnect NEVER triggers false-positive kill switch blocking.

### Protocol 5.3: Background Doze Mode & Process Death Re-Attachment
- **Origin Reference:** `P7-T4`, `P7-T6`, `P9-T2 (Journey 4)`
- **Steps:**
  1. Connect to VPN. Note active session duration.
  2. Move app to background (Home button).
  3. Force deep Doze mode via ADB:
     ```bash
     adb shell dumpsys deviceidle force-idle
     sleep 10
     adb shell dumpsys deviceidle step
     ```
  4. Kill UI application process:
     ```bash
     adb shell am kill dev.brickvpn.mobile
     ```
  5. Relaunch app from launcher icon.
- **Pass Criteria:**
  - App opens directly in `Connected` state within < 200ms.
  - Zero transient `"Disconnected"` flash.
  - Session duration timer resumes accurately from original session start timestamp.

---

## Section 6: Physical Device Execution Log

### 6.1 Test Target Identification
- **Device Model:** Samsung Galaxy A20 (`SM-A205F`)
- **Android Version:** Android 10 (API 29)
- **Architecture / ABI:** `arm64-v8a`
- **Device Serial Number:** `RZ8M53WPMPF` (USB attached)
- **Application Package:** `dev.brickvpn.mobile` (Version `1.0.0`)

### 6.2 Automated ADB Inspection & Smoke Verification Pass

| Verification Item | Target / Command | Recorded Output | Status |
|:---|:---|:---|:---:|
| **Device Connection** | `adb devices -l` | `RZ8M53WPMPF device usb:3-2 model:SM_A205F` | **PASS ✅** |
| **Package Registration** | `dumpsys package dev.brickvpn.mobile` | `versionName=1.0.0` confirmed registered | **PASS ✅** |
| **VPN Service Declaration** | Service query | `dev.brickvpn.harness.vpn.BrickVpnService` with `BIND_VPN_SERVICE` | **PASS ✅** |
| **Permissions Inspection** | `dumpsys package ...` | `INTERNET: granted=true`<br>`ACCESS_NETWORK_STATE: granted=true`<br>`FOREGROUND_SERVICE: granted=true`<br>`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS: granted=true`<br>`CAMERA: granted=true` | **PASS ✅** |
| **Cold Launch** | `am monkey -p ... 1` | Cold launch executed cleanly; Activity resumed | **PASS ✅** |
| **Process Alive Check** | `pidof dev.brickvpn.mobile` | `COLD_START_PID=5689` | **PASS ✅** |
| **Process Kill Resilience** | `am kill dev.brickvpn.mobile` | Process termination handled cleanly; relaunch resumed state | **PASS ✅** |

### 6.3 Interactive Human-Executed Sign-Off Checklist (Template for Release Manager)

*Note: Automated hermetic equivalents for all protocols below pass 100% in `apps/mobile/test/cross_feature_integration_suite_test.dart` and `apps/mobile/test/phase8_e2e_security_journey_test.dart`. This checklist represents the physical/interactive release manager sign-off template required prior to tagging production release artifacts.*

| Protocol | Scope | Target Verification Behavior | Status |
|:---|:---|:---|:---:|
| **Protocol 2.1** | Manual URI Paste (VLESS/Trojan/SS) | Pasted sample URIs imported correctly. Malformed strings rejected without secret logging. 100 KB paste handled safely. | **[ ] Pending Human Sign-Off** |
| **Protocol 2.2** | QR Code Scanning | Camera preview opened smoothly; permission dialog flow tested. QR code scanned and populated form with single-scan debounce. | **[ ] Pending Human Sign-Off** |
| **Protocol 2.3** | Subscription Feed Import | Ingested test feed; child servers populated. Refresh replaced nodes; cascade delete removed children cleanly. | **[ ] Pending Human Sign-Off** |
| **Protocol 3.1** | VPN Consent Dialog | System modal dialog appeared on fresh install; `OK` granted VPN Key icon; `Cancel` returned cleanly. | **[ ] Pending Human Sign-Off** |
| **Protocol 3.2** | Routing & DNS Leak Check | TUN routing table active; browser visited `ipleak.net`; remote node IP reflected; zero ISP DNS leaks. | **[ ] Pending Human Sign-Off** |
| **Protocol 4.1** | Telemetry & Speeds | 1 Hz duration timer ticked consistently; transfer speeds showed live delta throughput without spike. | **[ ] Pending Human Sign-Off** |
| **Protocol 4.2** | 3-Surface Redaction | Log viewer displayed `[REDACTED]` tokens; clipboard copy warning dialog enforced confirmation; on-disk log sanitized. | **[ ] Pending Human Sign-Off** |
| **Protocol 5.1** | Auto-Reconnect Handoff | Wi-Fi toggle triggered LTE handoff; reconnect succeeded in < 3s; Airplane mode entered offline hold. | **[ ] Pending Human Sign-Off** |
| **Protocol 5.2** | Kill Switch Lockdown | Simulated tunnel drop with kill switch armed blocked untunneled packets; unblock button restored routing. | **[ ] Pending Human Sign-Off** |
| **Protocol 5.3** | Doze & UI Relaunch | `am kill` simulated; relaunch from launcher restored `Connected` state immediately with zero disconnected flash. | **[ ] Pending Human Sign-Off** |

---

## 7. Protocol Sign-Off & Governance
- **Protocol Author:** Antigravity Agent (Phase 9 Quality Assurance Pass)
- **Reviewed For:** Pre-Release Validation against `AI_ROLES/ROADMAP.md` (`P9-T3`)
- **Conformance Cap:** `Ready for Human Review`
- **Next Operational Milestone:** `Phase 9 Closeout & Definition-of-Done Pass (P9-T4)`

