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
Brick VPN is a lightweight, high-performance, privacy-focused, and fully open-source Android VPN client. It ships a built-in 
official free server directory, synchronized over HTTPS with a CDN mirror as failover, so the app is usable right after install 
with no account, no configuration and no server hunting. Built on the robust, embedded Sing-box universal proxy core, Brick VPN 
provides modern censorship-resistant transport protocols with zero advertisements, zero trackers, and diagnostics that stay off 
unless you turn them on.

NOTE: Brick VPN is open source under GPL-3.0-or-later. On first launch the built-in directory downloads automatically over HTTPS 
from the project's public collection repository, is cached encrypted on your device, and is kept intact whenever the mirrors are 
unreachable. Install, wait a moment for the sync, pick any country, and connect. The developer does not sell or resell proxy 
bandwidth.

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

• Built-In Official Free Server Directory:
  - Synchronizes automatically on launch and at most every 30 minutes over HTTPS, with a CDN mirror as failover.
  - Groups every server by country and city with flags, and searches the whole list instantly.
  - Caches the directory on-device with Android Keystore encryption, and keeps it intact when the mirrors are unreachable.

• Enterprise-Grade Resilience & Security:
  - Fail-Closed Kill Switch: Enforces strict firewall lockdown on Android to prevent unencrypted packet leakage if the VPN tunnel drops.
  - Automatic Smart Reconnect: Resumes connections across Wi-Fi and Cellular network handovers with exponential backoff and offline hold.
  - Robust Foreground Service: Keeps your tunnel active reliably in the background without battery-saver termination.
  - Hardware-Backed Keystore Encryption: Sensitive credentials (passwords, private keys, preshared keys) are encrypted at rest using AES-256-GCM backed by Android Keystore.
  - Three-Surface Log Redaction: Live UI viewer, clipboard export, and on-disk diagnostic logs automatically redact IPs, domain names, passwords, and UUIDs to protect your privacy.

• Free to Start, Optional Pro Later:
  - Free to start with no account required — install, let the built-in directory sync, and connect.
  - An optional Brick Pro plan is planned for future releases for users who want Pro features.
  - Zero ads, zero ad SDKs, zero third-party trackers, and zero browsing/traffic logs on every plan (Free and Pro).
  - Anonymous server-health diagnostics are off by default; if you enable them, only a hashed server ID, reachability, latency, coarse network type, and an hour-bucketed timestamp are ever sent.
  - Licensed under GNU General Public License v3.0 or later (GPL-3.0-or-later), with the complete client source published in the 
spirit of Bring Your Own Server.

*(Character count: 3239 / 4000 limit)*

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

