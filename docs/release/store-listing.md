# Google Play Store Listing Metadata for Brick VPN

This document contains the official Google Play Console store listing metadata, categorization, contact details, and asset inventory for Brick VPN (`dev.brickvpn.mobile`).

---

## 1. Store Listing Copy

### App Title
`Brick VPN`

*(Character count: 9 / 30 limit)*

### Short Description
`Open-source, ad-free VPN client supporting VLESS, Reality, WireGuard, and HY2.`

*(Character count: 78 / 80 limit)*

### Full Description
Brick VPN is a lightweight, high-performance, and privacy-focused Android VPN client engineered for self-hosted proxy and VPN infrastructure. Built on the robust, embedded Sing-box universal proxy core, Brick VPN provides modern censorship-resistant transport protocols with zero telemetry, zero advertisements, and zero tracking.

NOTE: Brick VPN is a client software application ('Bring Your Own Server'). It does NOT bundle, sell, or operate commercial proxy servers. Users must connect to their own self-hosted servers or enter third-party subscription URLs.

---

KEY FEATURES & PROTOCOL SUPPORT

• Advanced Next-Generation Protocols:
  - VLESS with XTLS-Reality and Vision encryption
  - VMess with WebSocket, gRPC, and HTTP/2 transports
  - Trojan with TLS encapsulation
  - Shadowsocks AEAD (2022 and legacy ciphers)
  - WireGuard with multi-peer roaming
  - AmneziaWG (AWG) with packet obfuscation
  - Hysteria2 (HY2) UDP high-speed congestion control
  - TUIC (v5) QUIC-based proxying

• Flexible Server & Subscription Management:
  - Manual Import: Quick-paste standard protocol URIs directly into the app.
  - Optical QR Code Scanner: Fast, on-device QR scanning powered by Google ML Kit.
  - Subscription Feeds: Synchronize HTTPS subscription endpoints with resilient partial-success parsing.
  - Cascade Deletion: Cleanly delete individual profiles or entire subscription groups with one tap.

• Enterprise-Grade Resilience & Security:
  - Fail-Closed Kill Switch: Enforces strict firewall lockdown on Android to prevent unencrypted packet leakage if the VPN tunnel drops.
  - Automatic Smart Reconnect: Resumes connections across Wi-Fi and Cellular network handovers with exponential backoff and offline hold.
  - Robust Foreground Service: Keeps your tunnel active reliably in the background without battery-saver termination.
  - Hardware-Backed Keystore Encryption: Sensitive credentials (passwords, private keys, preshared keys) are encrypted at rest using AES-256-GCM backed by Android Keystore.
  - Three-Surface Log Redaction: Live UI viewer, clipboard export, and on-disk diagnostic logs automatically redact IPs, domain names, passwords, and UUIDs to protect your privacy.

• 100% Free & Open-Source:
  - Licensed under GNU General Public License v3.0 or later (GPL-3.0-or-later).
  - Zero analytics, zero ad SDKs, zero third-party telemetry, and zero user account registration required.

*(Character count: 2411 / 4000 limit)*

---

## 2. Categorization & Contact Information

| Play Console Field | Value |
| :--- | :--- |
| **Application Category** | Tools |
| **Alternative Category** | Communication |
| **Target Audience / Content Rating** | Everyone (PEGI 3 / ESRB Everyone) |
| **Developer Contact Email** | `ajorvpn@gmail.com` |
| **Privacy Policy URL** | `https://github.com/Ajorvpn/brick/blob/master/docs/privacy-policy.md` |
| **Source Code Repository** | `https://github.com/Ajorvpn/brick` |
| **License** | GPL-3.0-or-later |

---

## 3. Store Listing Graphical Asset Inventory

All graphical assets conform to Google Play Console specifications and are version-controlled under `docs/release/store-assets/`:

| Asset File | Format / Bit Depth | Dimensions (W x H) | File Size | Compliance Verification |
| :--- | :--- | :--- | :--- | :--- |
| `docs/release/store-assets/icon-512x512.png` | 32-bit PNG (with alpha) | 512 x 512 px | < 1024 KB | Verified Play Store High-Res Icon specification |
| `docs/release/store-assets/feature-graphic-1024x500.png` | 24-bit RGB PNG | 1024 x 500 px | < 15 MB | Verified Play Store Feature Graphic specification |
| `docs/release/store-assets/screenshots/01_home_disconnected.png` | 32-bit RGBA PNG | 1080 x 1920 px (9:16) | > 5 KB | Verified genuine Flutter UI: HomeScreen Disconnected |
| `docs/release/store-assets/screenshots/02_home_connected.png` | 32-bit RGBA PNG | 1080 x 1920 px (9:16) | > 5 KB | Verified genuine Flutter UI: HomeScreen Connected + Session metrics |
| `docs/release/store-assets/screenshots/03_servers_and_subscriptions.png` | 32-bit RGBA PNG | 1080 x 1920 px (9:16) | > 5 KB | Verified genuine Flutter UI: ServersScreen & Subscription group |
| `docs/release/store-assets/screenshots/04_live_logs_redacted.png` | 32-bit RGBA PNG | 1080 x 1920 px (9:16) | > 5 KB | Verified genuine Flutter UI: LiveLogsScreen with redacted logs |

