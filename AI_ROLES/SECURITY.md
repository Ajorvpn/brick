# SECURITY.md — Brick VPN Security Architecture & Policy

> This document defines the security posture of Brick VPN. It exists 
> because this application is a censorship-circumvention tool that may be 
> used by people in high-risk environments, where a security failure is 
> not merely a bug — it can expose a user to real-world harm. Every rule 
> here is treated as load-bearing, not optional guidance.
>
> This file is referenced by `AGENTS.md` and enforced via 
> `DEFINITION_OF_DONE.md` Section 5. Any task touching networking, 
> storage, parsing, native code, logging, dependencies, or release 
> artifacts must comply with this document.

---

## 1. Threat Model (Summary)

| Threat Actor | Capability | What We Defend Against |
|---|---|---|
| Network-level censor / DPI systems | Can inspect, block, or throttle traffic patterns | Protocol obfuscation is delegated to sing-box (TLS, REALITY, etc.) — this app must not undermine it (e.g., via leaking DNS or metadata outside the tunnel) |
| Malicious/compromised device (device seizure scenario) | Physical or forensic access to the device | Local data must be encrypted at rest; no plaintext server configs, no plaintext logs of sensitive data |
| Malicious subscription/config provider | Supplies a crafted config/subscription URL/QR code | The app must treat all imported config data as **untrusted input** |
| Supply chain attacker | Compromises a dependency or the `libbox` binary distribution | Dependencies and native binaries must be verified, not blindly trusted |
| Malicious GitHub Release tampering | Modifies APK/binary between build and download (since distribution is initially outside Google Play) | Release artifacts must be signed and verifiable |
| Curious/malicious app on the same device | Attempts to read app data or intercept IPC | Platform Channel data must not leak sensitive data to other processes; storage must be sandboxed/encrypted |

We explicitly do **not** attempt to defend against a fully compromised 
operating system (rooted/jailbroken device with an active attacker with 
kernel-level access) — this is outside the realistic scope of an 
application-layer VPN client.

---

## 2. Data Classification

| Data | Sensitivity | Storage Rule |
|---|---|---|
| Server configuration (VLESS/VMess/Trojan/SS/Hysteria2/TUIC URIs, subscription URLs) | **High** — can deanonymize the user or expose the server to blocking if leaked | Encrypted at rest only (Section 3). Never logged (Section 4). |
| Connection state / traffic statistics (bytes transferred, duration) | **Low** — not sensitive on its own | May be kept in memory/local state freely. Not required to persist across restarts unless explicitly designed to. |
| App preferences (theme, language) | **None** | May be stored in plain local storage (e.g., `shared_preferences`). |
| Diagnostic/debug logs | **High** by default, unless explicitly redacted | Must never contain server hostnames/IPs, credentials, or user-identifying data (Section 4). |

---

## 3. Secure Storage Requirements

- All **server configuration data** must be stored using 
  platform-native secure storage:
  - **Android**: Encrypted storage backed by the Android Keystore 
    (e.g., via `flutter_secure_storage` or equivalent, which uses 
    `EncryptedSharedPreferences`/Keystore-backed encryption under the 
    hood) — never raw `SharedPreferences` and never a plain file/JSON on 
    disk.
  - **iOS (future)**: iOS Keychain.
  - **Desktop (future)**: OS-native credential store where available 
    (e.g., libsecret on Linux, Credential Manager on Windows, Keychain 
    on macOS); if unavailable, encrypted at rest with a key protected by 
    OS-level user authentication — this must be explicitly designed, 
    not assumed, before Phase 12.
- The in-memory representation of an active server config may exist in 
  application state (e.g., a Riverpod provider) but must not be trivially 
  dumped via default `toString()` overrides — sensitive fields must 
  implement redacted `toString()` output (see Section 4).
- No server configuration or credential is ever written to:
  - Application logs
  - Crash reports
  - Analytics (there are none — Section 9)
  - Version control (Section 8)
  - Temporary/cache files outside the encrypted storage boundary

---

## 4. Logging & Redaction Policy

- The shared logging utility in `packages/shared_utils` must provide a 
  redaction helper that all logging call sites for domain objects 
  (server configs, subscription content, parsed URIs) are required to 
  use. Direct interpolation of raw config objects into log strings is 
  forbidden.
- Redaction rule of thumb: hostnames/IPs are shown at most partially 
  (e.g., masked) in debug logs, and never in any log output outside a 
  local debug build.
- Debug-only, verbose logging (e.g., full native `libbox` stderr output 
  for troubleshooting) is acceptable **only** in local development 
  workflows (e.g., `adb logcat`, local debug log screen) and must never 
  be transmitted off-device automatically.
- No remote log shipping of any kind exists in this application, by 
  design (see Section 9).

---

## 5. Untrusted Input Handling — Config & Subscription Parsing

The `packages/config_parser` package is the primary untrusted-input 
boundary of this application (it processes URIs and subscription 
payloads that may originate from any third party, including malicious 
ones).

Mandatory rules for this package:

- The parser must be a **pure function set** with no network calls, no 
  file I/O, and no side effects — parsing and networking (e.g., fetching 
  a subscription URL) must be strictly separated into different layers, 
  so the parsing logic itself is trivially fuzz-testable in isolation.
- All parsing must be **defensive by default**:
  - Reject malformed input explicitly (return a typed `Failure`, per 
    `CODING_STANDARDS.md` Section 5) rather than throwing unhandled 
    exceptions or silently producing a partially-valid config.
  - Enforce sane upper bounds on input size, nesting depth (for JSON 
    subscription payloads), and number of servers parsed from a single 
    subscription, to prevent resource-exhaustion from a malicious or 
    corrupted subscription source.
  - Never evaluate, execute, or interpret parsed content as code 
    (e.g., no dynamic evaluation of any field).
- Remote rule-sets or auxiliary data referenced by a generated sing-box 
  configuration (e.g., geoip/geosite rule-sets) must be fetched only 
  from sources the user has explicitly configured or that are hardcoded 
  defaults reviewed by the maintainer — never arbitrary URLs embedded in 
  untrusted subscription content without validation.
- QR code scanning (`expo-camera`-equivalent Flutter package) must treat 
  scanned content with the same level of distrust as manually pasted 
  text — no special trust is granted just because it came from a QR 
  code.

---

## 6. Network & DNS Security

- **DNS leak prevention** is a first-class correctness requirement, not 
  an optional hardening step: while the VPN is active, DNS resolution 
  for proxied traffic must occur through the tunnel/sing-box 
  configuration, not through the device's default network DNS.
- The application must expose a clear, verifiable **connection state** 
  (per `ARCHITECTURE.md` Section 3) so the UI never displays 
  "Connected" while the underlying tunnel is not actually passing 
  traffic correctly — a misleading "Connected" state is itself a 
  security issue, since a user may believe they are protected when they 
  are not. This directly targets the predecessor project's Problem 2 
  (TUN up, but no real traffic/DNS resolution).
- **Kill Switch** behavior (blocking all non-VPN traffic when the tunnel 
  drops unexpectedly) is a planned MVP-critical feature (tracked in 
  `ROADMAP.md`) and must be implemented at the native platform level 
  (e.g., Android's `VpnService` route configuration), not simulated at 
  the Flutter/Dart layer, since only the native layer can actually 
  enforce it.
- Any bundled default server/rule-set download endpoints must use TLS.

---

## 7. Native Code & Platform Channel Security

- Platform Channel method/event names and payload shapes must be 
  treated as an internal contract, not a public API — no sensitive data 
  should be passed through the channel in a form that would be trivially 
  useful if intercepted by another malicious app via reflection/debugging 
  on a compromised device (defense in depth; the primary boundary is the 
  OS process sandbox, but payload design should still avoid unnecessary 
  sensitive data exposure).
- Native Android code must not write server configuration content to 
  Android system logs (`Log.d`/`Log.i` with sensitive payloads is 
  forbidden in release builds — see `CODING_STANDARDS.md` Section 6 and 
  `DEFINITION_OF_DONE.md` Section 4).
- Any temporary working files written by the native layer (e.g., a 
  generated sing-box JSON config file written to app-private storage for 
  the Go core to consume) must reside in the app's private, sandboxed 
  storage directory (never external/shared storage) and should be 
  deleted or overwritten on each new connection where feasible.

---

## 8. Build & Release Integrity

- **Code signing**: Android release builds must be signed with a 
  maintainer-controlled keystore. The keystore file and its passwords 
  must never be committed to the repository — they are excluded via 
  `.gitignore` and supplied only via local environment variables or 
  CI/CD secrets (GitHub Actions encrypted secrets), never hardcoded.
- **Release artifact verification**: Since initial distribution is via 
  GitHub Releases (outside an app store's own integrity guarantees), 
  every release must publish a checksum (e.g., SHA-256) of the APK 
  alongside the binary, so users can verify the download was not 
  tampered with. This is a mandatory task in the release phase of 
  `ROADMAP.md`.
- **Reproducibility as a goal**: build steps should be scripted (CI 
  workflow) rather than manual, so any maintainer or contributor can 
  verify that a given release artifact corresponds to a specific commit.
- **No secrets in version control**: `.gitignore` must always exclude 
  keystores, `.env` files, local `google-services.json`/equivalent (if 
  ever introduced), and any local machine-specific credentials. This is 
  checked as part of `DEFINITION_OF_DONE.md` Section 5.

---

## 9. Dependency & Supply Chain Security

- The `libbox` binary (compiled from sing-box) must be obtained only 
  from an official, verifiable release source, with its checksum 
  documented in `ARCHITECTURE.md` or a dedicated build documentation 
  file at the time it is integrated — never from an unverified 
  third-party mirror.
- Third-party Dart/Flutter package dependencies must meet the criteria 
  already defined in `CODING_STANDARDS.md` Section 9 (actively 
  maintained, license-compatible, no unnecessary bloat) — from a 
  security lens specifically, prefer packages with a visible security 
  track record and avoid packages with a very small, unaudited 
  maintainer base for security-critical functionality (e.g., secure 
  storage, cryptography).
- Dependency versions should be pinned (not open-ended ranges) for 
  security-critical packages (secure storage, cryptography-adjacent 
  packages) so upgrades are deliberate, reviewed actions rather than 
  silent transitive updates.

---

## 10. Telemetry & Privacy (Restated from `ARCHITECTURE.md`)

- No analytics SDK, crash reporting SDK, or usage-tracking mechanism is 
  included in this application by default, at any phase, without an 
  explicit, separately-approved architecture decision and a clear, 
  user-facing, opt-in disclosure.
- If crash reporting is ever considered in the future, it must be: 
  (a) opt-in, not opt-out; (b) free of any sensitive data listed in 
  Section 2; (c) ideally self-hosted rather than a third-party SaaS 
  provider.

---

## 11. Open Source Security Practices

Since this project is GPL v3 and publicly hosted on GitHub:

- A `SECURITY.md`-style vulnerability disclosure policy must be visible 
  at the repository root (a short public-facing version, distinct from 
  this internal engineering document, though this file can be the 
  internal source of truth it's derived from) once the project goes 
  public, describing how a security researcher should privately report 
  a vulnerability (e.g., a private security contact/email) rather than 
  filing a public GitHub issue for undisclosed vulnerabilities.
- Enable GitHub's automated secret-scanning and dependency 
  vulnerability alerts (Dependabot or equivalent) on the repository as 
  an early Phase 0 infrastructure task.
- Security-relevant code (secure storage wrapper, config parser, native 
  VPN lifecycle code) should be held to a higher review bar than average 
  application code — these areas are explicitly flagged as 
  security-sensitive in `DEFINITION_OF_DONE.md` Section 5.

---

## 12. Explicitly Deferred Security Work (Do Not Assume Solved)

The following are known future security work, intentionally not solved 
yet, and must not be assumed complete when reasoning about the current 
state of the project:

- iOS Keychain integration (Phase 13).
- Desktop OS-native secure credential storage strategy (Phase 12) — the 
  exact mechanism per OS is not yet decided.
- Formal, professional third-party security audit — recommended before 
  the user base grows significantly, not a Phase 0–10 requirement, but 
  noted here so it is not forgotten.
- Reproducible/deterministic build verification tooling beyond basic 
  checksum publishing.
- Premium/subscription backend security model (Phase 14) — deliberately 
  out of scope until that backend's architecture itself is designed.

---

## 13. Relationship to Other Governance Files

- Security checks required at task-completion time live in 
  `DEFINITION_OF_DONE.md` Section 5 and Section 6 (self-review).
- Security-relevant coding rules (redaction utilities, error handling 
  for untrusted input) live in `CODING_STANDARDS.md`.
- The native VPN lifecycle engineering rules that prevent leaked TUN 
  interfaces and misleading connection states live in 
  `ARCHITECTURE.md` Section 3.5, and are treated as security 
  requirements, not merely reliability requirements, per Section 6 of 
  this document.