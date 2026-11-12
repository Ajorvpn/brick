# Privacy Policy for Brick VPN

**Effective Date:** November 12, 2026  
**Application Name:** Brick VPN  
**Package Name:** `dev.brickvpn.mobile`  
**License:** GNU General Public License v3.0 or later (GPL-3.0-or-later)  
**Source Code:** [https://github.com/Ajorvpn/brick](https://github.com/Ajorvpn/brick)  
**Contact:** `ajorvpn@gmail.com`

---

## 1. Summary & Zero-Data-Collection Commitment

Brick VPN is committed to user privacy and digital self-determination. We maintain a strict **zero-data-collection** architecture:

- **Zero Tracking & Zero Analytics:** Brick VPN does not embed any analytics SDKs, telemetry frameworks, tracking libraries, crash reporters, or advertising networks.
- **Zero Traffic Logging:** Brick VPN does not operate central proxy infrastructure. The application does not monitor, collect, log, store, or transmit your browsing history, destination IPs, DNS queries, packet payloads, or online activities.
- **Zero Account Requirements:** Brick VPN does not require user registration, email addresses, phone numbers, identity verification, or payment accounts.
- **Zero Sale or Sharing of Data:** Because no personal data is collected, no user information is ever sold, leased, monetized, or shared with third parties, advertisers, or government entities.

Brick VPN functions strictly as a client software application ("Bring Your Own Server"). You connect solely to the servers and subscription endpoints you configure.

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

Brick VPN initiates network connections exclusively in direct response to explicit user actions:

1. **VPN Tunnel Connections:** When you initiate a connection, the embedded Sing-box engine establishes an encrypted tunnel directly to the remote server endpoint specified in your active profile configuration (supporting VLESS with XTLS-Reality, VMess, Trojan, Shadowsocks AEAD, WireGuard, AmneziaWG, Hysteria2, or TUIC).
2. **Subscription Feed Updates:** When you manually refresh or add a subscription feed, the application performs an HTTPS GET request directly to the subscription provider URL you provided to download updated server configurations.
3. **Zero Autonomous Telemetry:** The application makes no background network requests to any Brick VPN servers, third-party analytics services, or external APIs.

---

## 4. Android OS Permissions Explained

Brick VPN declares only the minimum set of permissions necessary to establish and maintain an encrypted VPN tunnel and scan configuration QR codes:

| Android Permission | Declaration Type | Technical Justification & Usage |
| :--- | :--- | :--- |
| `android.permission.BIND_VPN_SERVICE` | System Service Binding | Required to bind to Android's `VpnService` subsystem, establish the local TUN virtual network interface, route device traffic through the encrypted Sing-box engine, and display the system key icon. |
| `android.permission.INTERNET` | Normal Permission | Required to route encrypted packets across network interfaces to user-configured remote proxy endpoints and fetch HTTPS subscription feeds. |
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
- **Delete Subscription Groups:** Deleting a subscription feed cascades immediately, deleting the subscription and all associated child server profiles.
- **Clear Diagnostic Logs:** On the `LiveLogsScreen` (`/logs`), tap the "Clear" button (`logs_clear_button`) to instantly truncate `cache/brick_vpn_live.log` to zero bytes and clear the in-memory log buffer.
- **Complete Application Data Wipe:** In Android OS Settings (`Settings > Apps > Brick VPN > Storage > Clear Data`), clearing storage permanently purges all encrypted configurations, Keystore keys, preferences, and logs from your device.

---

## 6. Open-Source Verification & Contact

Brick VPN is 100% free and open-source software distributed under the GNU General Public License v3.0 or later. Anyone can independently inspect, audit, build, and verify the source code and security invariants:

- **Source Code Repository:** [https://github.com/Ajorvpn/brick](https://github.com/Ajorvpn/brick)
- **Issue Tracker & Security Reports:** [https://github.com/Ajorvpn/brick/issues](https://github.com/Ajorvpn/brick/issues)
- **Direct Contact:** `ajorvpn@gmail.com`

If you have questions, feedback, or security inquiries regarding this Privacy Policy, please contact us via email or open an issue on the public repository.

