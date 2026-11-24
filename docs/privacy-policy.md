# Privacy Policy for Brick VPN

**Effective Date:** November 23, 2026  
**Application Name:** Brick VPN  
**Package Name:** `dev.brickvpn.mobile`  
**License:** GNU General Public License v3.0 or later (GPL-3.0-or-later)  
**Source Code:** [https://github.com/Ajorvpn/brick](https://github.com/Ajorvpn/brick)  
**Contact:** `ajorvpn@gmail.com`

---

## 1. Summary & Zero-Data-Collection Commitment

Brick VPN is committed to user privacy and digital self-determination. We maintain a strict **zero-data-collection-by-default** architecture:

- **Zero Tracking & Zero Analytics:** Brick VPN does not embed any analytics SDKs, telemetry frameworks, tracking libraries, crash reporters, or advertising networks. The only diagnostics the app can ever send are the anonymous, strictly opt-in server-health reports described in Section 3.1 — off by default, implemented in-app with no third-party SDK.
- **Zero Traffic Logging:** Brick VPN does not operate central proxy infrastructure. The application does not monitor, collect, log, store, or transmit your browsing history, destination IPs, DNS queries, packet payloads, or online activities.
- **No Account for the Free Plan:** Brick VPN's Free plan is usable immediately with no account, registration, email address, phone number, or payment details of any kind. Optional accounts apply solely to the planned, optional `Brick Pro` plan described in Section 6.
- **Zero Sale or Sharing of Data:** Because no personal data is collected, no user information is ever sold, leased, monetized, or shared with third parties, advertisers, or government entities.

Brick VPN is a client software application. It ships with a **built-in official free server directory**, fetched over HTTPS from 
the project's public collection repository (with a CDN mirror as failover) so you can connect immediately after install without 
an account.

The developer does not operate, broker, or resell proxy bandwidth on your behalf: the directory is a list of public 
community-contributed endpoints, and your traffic travels directly between your device and the endpoint you select.

---

## 2. Information Stored Locally on Your Device

All application state is stored strictly on your local device within the application's private sandbox (`/data/user/0/dev.brickvpn.mobile/`):

| Data Type | Storage Location | Security & Encryption Mechanism |
| :--- | :--- | :--- |
| **VPN Server Configurations** | `app_flutter/server_profiles.json` | Sensitive fields (passwords, private keys, preshared keys, UUIDs, `peer_public_key`, `tls.reality.public_key`/`short_id`, `obfs.password`, `plugin_opts`, `transport.headers`, `extra_params`, and subscription URLs) are encrypted at rest using AES-256-GCM (`enc:v1:`) backed by hardware-isolated keys managed by the Android Keystore system. |
| **Application Preferences** | `shared_prefs/FlutterSharedPreferences.xml` | Non-sensitive UI preferences (dark/light theme, selected locale, auto-reconnect toggle, fail-closed kill-switch toggle, selected active profile ID). |
| **Diagnostic Session Logs** | Memory buffer & `cache/brick_vpn_live.log` | Ephemeral bounded ring buffer capped at 1000 lines / 512 KB (`maxLogFileBytes`). All logs are automatically sanitized across 3 surfaces: (1) Live Log Viewer UI (`LiveLogsScreen`), (2) Clipboard Export (`logs_copy_button`), and (3) On-Disk Temp Log File (`cache/brick_vpn_live.log`) by `LogRedactor`, replacing credentials, passwords, private keys, UUIDs, IPv4/IPv6 addresses, and domain names with `[REDACTED]` or `[REDACTED_IP]`. Diagnostic logs never leave your device unless explicitly exported by the user. |

---

## 3. Network Connections Initiated by the App

Brick VPN initiates only the following network connections:

1. **VPN Tunnel Connections:** When you initiate a connection, the embedded Sing-box engine establishes an encrypted tunnel directly to the remote server endpoint specified in your active profile configuration (supporting VLESS with XTLS-Reality, VMess, Trojan, Shadowsocks AEAD, WireGuard, AmneziaWG, Hysteria2, or TUIC).
2. **Built-In Official Server Directory Sync:** On entering the app, and at most once every 30 minutes afterwards, the 
application performs an HTTPS GET request to the official server-directory feed (GitHub raw content, with a jsDelivr mirror as 
failover) to download the current list of free server configurations. Only a plain HTTPS request for a public text file is made: 
no account, identifier, device data, or usage information is sent, and the request is indistinguishable from any other download 
of that public file. The downloaded list is stored encrypted on your device with Android Keystore-backed keys. If every mirror 
fails, the servers already saved on your device are kept exactly as they are — nothing is deleted.
3. **Optional Anonymous Server-Health Diagnostics:** Off by default. No diagnostics request is ever made unless you explicitly enable *Anonymous Server Health Diagnostics* in Settings **and** the build has a collector configured. See Section 3.1 for the exact payload.

The application makes no other background network requests to any Brick VPN servers, third-party analytics services, or external APIs.

### 3.1 Anonymous Server Health Diagnostics (Off by Default)

Brick VPN can help improve directory quality by reporting whether servers in the official directory are reachable. This feature is **disabled by default** and can be switched off again at any time in `Settings > Diagnostics & About > Anonymous Server Health Diagnostics`.

- **What may be sent (only when you opt in):** a strict five-key payload — `node_hash` (the first 16 lowercase hex characters of a SHA-256 digest over `protocol|host|port`, so the server cannot be reversed to its address), `ok` (reachability), `latency_ms` (clamped to 0–30000, `null` on failure), `network_type` (only `wifi`, `cellular` or `other`), and `hour_utc` (a UTC timestamp truncated to the hour).
- **What is never sent:** server hostnames, IP addresses, ports, UUIDs, passwords, private keys, server remarks, subscription URLs, your IP address, SSID/BSSID, IMEI, advertising ID, account identifiers, browsing history, DNS queries, destination IPs, or any traffic payload.
- **Transport:** HTTPS only, to the collector endpoint compiled into the build, with no device or app-fingerprint headers, a 3-second timeout, at most one request per minute, and at most 20 reports per request.
- **Google Play Data Safety:** this optional data is classified as **App info and performance > Diagnostics** — optional, not linked to your identity, not shared with third parties, and encrypted in transit.
- **No third-party SDK:** the reporter is first-party Dart code in `apps/mobile/lib/core/telemetry/`; no analytics or telemetry SDK is bundled.

---

## 4. Android OS Permissions Explained

Brick VPN declares only the minimum set of permissions necessary to establish and maintain an encrypted VPN tunnel and scan configuration QR codes:

| Android Permission | Declaration Type | Technical Justification & Usage |
| :--- | :--- | :--- |
| `android.permission.BIND_VPN_SERVICE` | System Service Binding | Required to bind to Android's `VpnService` subsystem, establish the local TUN virtual network interface, route device traffic through the encrypted Sing-box engine, and display the system key icon. |
| `android.permission.INTERNET` | Normal Permission | Required to route encrypted packets across network interfaces to remote proxy endpoints and to fetch the HTTPS official server directory. |
| `android.permission.ACCESS_NETWORK_STATE` | Normal Permission | Required to detect network availability changes (Wi-Fi to Cellular transitions, interface drops) to trigger automatic reconnection and fail-closed kill-switch protection. |
| `android.permission.FOREGROUND_SERVICE` | Normal Permission | Required by Android 9+ to maintain `BrickVpnService` as an active foreground service so the operating system does not terminate the VPN process while the app is backgrounded. |
| `android.permission.FOREGROUND_SERVICE_SPECIAL_USE` | Play Policy Specific Use | Required by Android 14+ (API 34) for specialized long-running VPN network routing engines running outside standard predefined categories. |
| `android.permission.POST_NOTIFICATIONS` | Runtime Permission | Required by Android 13+ (API 33) to post the persistent foreground status notification (`"Brick VPN"` / `"Tunnel active"`) informing the user of the ongoing VPN session. |
| `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Special Permission | Optional permission allowing the user to exempt Brick VPN from aggressive OEM battery killer daemons, preventing unexpected tunnel drops during deep sleep. |
| `android.permission.CAMERA` | Dangerous / Runtime Permission | Used exclusively on `QrScanScreen` via Google ML Kit / CameraX to optically scan server configuration QR codes. Camera frames are processed strictly in-memory on the device and are never recorded, saved to disk, or transmitted over the network. |

---

## 5. User Data Control & Deletion

You retain full ownership and control over all data stored by Brick VPN:

- **Delete Server Configurations:** In the `ServersScreen` (`/servers`), swipe or tap the "Delete" action on any server profile to immediately remove it from `server_profiles.json` and disk.
- **Clear Diagnostic Logs:** On the `LiveLogsScreen` (`/logs`), tap the "Clear" button (`logs_clear_button`) to instantly truncate `cache/brick_vpn_live.log` to zero bytes and clear the in-memory log buffer.
- **Complete Application Data Wipe:** In Android OS Settings (`Settings > Apps > Brick VPN > Storage > Clear Data`), clearing storage permanently purges all encrypted configurations, Keystore keys, preferences, and logs from your device.

---

## 6. Planned Optional Brick Pro Plan (Not Yet Active)

Brick VPN ships today with a complete Free plan. A future release may offer an **optional** `Brick Pro` subscription for users who want extra Pro features. Until that release exists, this section describes intent only — no account system, entitlement check, or payment flow is present in the current build:

- **Current Free Plan:** zero account required, zero personal data collected, zero payment details requested.
- **Planned Optional Brick Pro Plan:** an account would only ever be created by a user who explicitly chooses Pro, and the only account data planned for storage is a minimal account identifier and subscription entitlement status (whether the Pro subscription is active). No browsing history, DNS queries, destination IPs, or traffic payloads would be collected — on Free or on Pro.
- **Planned Payments:** Google Play Billing would be used exclusively in builds distributed through Google Play; no external checkout URL or third-party payment gateway would be embedded in those builds.
- **Disclosure Before Launch:** this Privacy Policy and the corresponding Google Play Data Safety declaration would be updated, and republished, before any Pro plan is activated.

---

## 7. Open-Source Verification & Contact

Brick VPN is open-source software distributed under the GNU General Public License v3.0 or later. The Free plan is free to use, with no account and no ads. Anyone can independently inspect, audit, build, and verify the source code and security invariants:

- **Source Code Repository:** [https://github.com/Ajorvpn/brick](https://github.com/Ajorvpn/brick)
- **Issue Tracker & Security Reports:** [https://github.com/Ajorvpn/brick/issues](https://github.com/Ajorvpn/brick/issues)
- **Direct Contact:** `ajorvpn@gmail.com`

If you have questions, feedback, or security inquiries regarding this Privacy Policy, please contact us via email or open an issue on the public repository.

