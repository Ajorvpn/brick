# Brick VPN v1.0.0 (Android MVP Release)

**Release Date:** November 12, 2026  
**License:** GNU General Public License v3.0 or later ([GPL-3.0-or-later](https://github.com/Ajorvpn/brick/blob/master/LICENSE))  
**Core Engine:** Sing-box `v1.10.7`  
**Target Platform:** Android (`minSdk 24` / Android 7.0+, `targetSdk 36` / Android 16)

---

## 1. Release Overview & BYOS Architecture Notice

Brick VPN `v1.0.0` is the initial production-ready Android MVP release of Brick VPN — a high-performance, open-source, privacy-focused VPN client designed specifically for censorship circumvention, network resilience, and strict user privacy.

### Bring Your Own Server (BYOS) Model
Brick VPN operates strictly on a **"Bring Your Own Server" (BYOS)** architecture. Brick VPN does **not** provide, operate, broker, or bundle commercial proxy servers, subscriptions, or bandwidth. Users connect using their own self-hosted servers or third-party subscription feeds.
- **Zero Ads:** The app contains zero advertising SDKs, zero banner ads, and zero monetization trackers.
- **Zero Telemetry:** The app contains zero analytics trackers, zero crash log uploaders, and zero telemetry collection.
- **Zero Account Registration:** The app requires no email address, phone number, login, or user account.

---

## 2. What's Included: Complete MVP Feature Summary (Phases 1–10)

### 8 Supported Encrypted Transport Protocols
Powered by the embedded, R8-hardened native Sing-box core engine:
1. **VLESS:** Next-generation lightweight proxy protocol supporting XTLS-Reality, Vision flow, WebSocket, gRPC, HTTP, and HttpUpgrade transports.
2. **VMess:** Standard and authenticated VMess protocol with AEAD encryption.
3. **Trojan:** Encrypted TLS mimicry protocol with ALPN negotiation.
4. **Shadowsocks:** High-speed stream cipher proxy supporting AEAD (AES-128-GCM, AES-256-GCM, ChaCha20-Poly1305) and Shadowsocks 2022 specifications.
5. **WireGuard:** Modern kernel-grade Noise protocol VPN tunnel.
6. **AmneziaWG:** Advanced WireGuard fork incorporating junk-packet obfuscation headers (`Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1`, `H2`, `H3`, `H4`) to circumvent deep packet inspection (DPI).
7. **Hysteria2:** UDP-based proxy protocol built on customized QUIC with Brutal congestion control for lossy and congested network environments.
8. **TUIC v5:** High-performance UDP-based proxy protocol built on QUIC v1 with 0-RTT handshakes.

### Server & Subscription Ingestion
- **Manual URI Ingestion:** Paste standard share links (`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, `tuic://`, `wireguard://`, `amneziawg://`) with an $O(1)$ 8,256-character denial-of-service memory cap.
- **Optical QR Code Scanning:** Fast, privacy-preserving in-memory optical QR scanning via Google ML Kit Barcode Scanning and CameraX (`mobile_scanner`). Frames are processed strictly in RAM and never written to disk or transmitted over the network.
- **HTTPS-Only Subscription Feeds:** Fetch subscription configurations over TLS with redirect-downgrade blocking (HTTP downgrade prevention), 5 MiB stream size capping, resilient partial-success parsing, background refresh, and cascading deletion.

### Resilience & Leak Prevention
- **Fail-Closed OS Kill Switch:** Leverages Android's native `VpnService.Builder.setBlocking(true)` and platform lockdown integration to drop all traffic immediately if the VPN tunnel drops unexpectedly, preventing cleartext packet leaks.
- **Smart Auto-Reconnect:** Seamlessly detects Wi-Fi <-> Cellular handovers with debounced network transition listeners, exponential backoff, and offline hold states.
- **DNS Leak Prevention:** Enforces `hijack-dns` tunnel routing, resolving all queries inside the encrypted tunnel through remote DNS resolvers.
- **SNI Sanitization:** Strict RFC 6066 SNI normalization preventing IP-literal leaks in TLS handshakes.
- **Session Re-Attachment:** Seamlessly re-attaches to existing VPN service sessions across Flutter UI process restarts and configuration changes without interrupting running tunnels.

### Security Hardening & Zero-Leak Privacy Safeguards
- **Hardware-Backed Keystore Encryption:** All sensitive profile fields (passwords, private keys, preshared keys, Reality public keys/short IDs, obfuscation credentials, and subscription URLs) are encrypted at rest with AES-256-GCM (`enc:v1:`) backed by the Android Keystore system.
- **3-Surface Log Redaction:** Monorepo-wide `LogRedactor` sanitizes credentials, URIs, UUIDs, external IPv4/IPv6 addresses, and domain names across (1) Live UI viewer (`LiveLogsScreen`), (2) Clipboard export (`logs_copy_button` with non-dismissible confirmation dialog), and (3) On-disk diagnostic cache (`cache/brick_vpn_live.log` bounded to 1000 lines / 512 KB).
- **ProGuard / R8 Hardening:** All release builds are minified and obfuscated with R8, retaining only required JNI entry points for gomobile, libbox, and ML Kit Barhopper.

---

## 3. Direct-Distribution APK Download Guide & SHA-256 Checksums

### Artifact Selection Guide

| Download Artifact | Architecture / Device Target | File Size | Description |
| :--- | :--- | :--- | :--- |
| `app-arm64-v8a-release.apk` | 64-bit ARM (`arm64-v8a`) | ~47 MB | **Recommended Default:** Modern Android phones & tablets (Android 7.0+). |
| `app-armeabi-v7a-release.apk` | 32-bit ARM (`armeabi-v7a`) | ~42 MB | Legacy 32-bit ARM Android devices. |
| `app-x86_64-release.apk` | 64-bit x86 (`x86_64`) | ~51 MB | Android emulators, ChromeOS, and Chromebooks. |
| `app-release.apk` | Universal Multi-ABI | ~132 MB | Fallback universal APK containing all native architectures. |
| `app-release.aab` | Android App Bundle | ~108 MB | Format for Google Play Store testing tracks. |

### Canonical SHA-256 Checksums (`SHA256SUMS.txt`)
```text
4fb54a334d6444bddf3a145ff6a1fb85428e5547fbc7e67c5005480379eedf86  app-arm64-v8a-release.apk
b1700357bd4a86ac91c77d5f75c76cc1e23f1e281a698766fa1089e5f0728c45  app-armeabi-v7a-release.apk
5d289eb288226471c3b09f489c62dbc91149f717539a8ed12bf5c9ef6bf99e5d  app-release.aab
8a9a695a1f3f522f98444649471ca8e79aae9bb63e0c280a94e65e5180ac0dc5  app-release.apk
57c6982c691305a3d060a8104b77426da5cf49427c8d07cb75dba9d8fccdfd87  app-x86_64-release.apk
```

### Official Production Signing Certificate SHA-256 Fingerprint
All official release packages are signed with APK Signature Scheme v2 and v3 using the Brick VPN release key:
```text
56:3D:AF:71:96:C5:65:AD:43:2B:F5:80:0E:2A:9E:AA:E0:A1:09:18:B0:48:9E:79:65:E6:3D:97:38:27:30:3B
```
*(Lowercase hex without colons: `563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`).*

---

## 4. Step-by-Step Installation & Verification Instructions

### Step 1: Verify Checksums & Digital Signatures
Before installing, verify that your downloaded package matches the official build:
```bash
# Verify file integrity against SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt --ignore-missing

# Verify cryptographic APK Signature Scheme v2/v3 and certificate fingerprint
apksigner verify --print-certs -v app-arm64-v8a-release.apk
```

### Step 2: Enable "Install unknown apps" (Sideloading on Android 8.0+)
Because this is a direct APK download from GitHub (outside Google Play), Android requires granting permission to install unknown apps:
1. Open Android **Settings** > **Apps** (or **Apps & notifications**).
2. Tap **Special app access** > **Install unknown apps**.
3. Select your browser (e.g. Chrome, Firefox) or File Manager app used to download the file.
4. Toggle **"Allow from this source"** to ON.
5. Tap the downloaded APK to install.

*Developer / CLI alternative:*
```bash
adb install -r app-arm64-v8a-release.apk
```

### Step 3: Grant System VPN Permission
1. Open **Brick VPN**.
2. Add your server profile (paste URI, scan QR code, or import subscription URL).
3. Tap **Connect**.
4. When Android displays the system connection request dialog (`"Brick VPN wants to set up a VPN connection that allows it to monitor network traffic"`), tap **OK** / **Accept**. Android will display the key icon in the status bar indicating the secure tunnel is active.

---

## 5. Known Limitations Carried Forward

In accordance with project transparency and governance standards, the following known limitations are documented:
1. **Minimal Functional MVP UI:** The current user interface uses standard Material 3 functional components. Custom visual branding, graphic design polish, and animations are scheduled for **Phase 11**.
2. **Android-Only MVP Scope:** This release targets Android (`minSdk 24` / Android 7.0+). Desktop (Linux, Windows, macOS) and iOS targets are scoped to **Phase 12+**.
3. **Unstructured Free-Text Native Log Redaction Boundary (`P8-T2`):** Structured JSON secrets, known profile passwords/keys, URIs, UUIDs, and external IPs are deterministically redacted. However, novel unstructured formats emitted directly by native C/Go libraries remain best-effort; users should review diagnostic logs before exporting.
4. **OEM Background Killer Quirks (`P7-T4`):** Aggressive OEM battery-optimization daemons (Xiaomi MIUI/HyperOS, Samsung One UI, Huawei EMUI) may terminate background VPN processes during deep sleep. If experiencing unexpected drops, enable the in-app "Ignore Battery Optimizations" exemption.
5. **Reproducible Builds (`P8-T4`):** While SHA-256 checksums and 4096-bit RSA signatures are published for every release, fully hermetic bit-for-bit Docker build reproducibility across independent host machines is planned for **Phase 10+ / future releases**.

