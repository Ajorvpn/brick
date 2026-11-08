# Untrusted Input Security Review & Defensive Audit Report

> **DISCLAIMER & SCOPE NOTICE:**
> Per `AI_ROLES/ROADMAP.md` P8-T3 specifications, this document constitutes a
> rigorous internal engineering self-review of all untrusted external input
> surfaces across Brick VPN. It is conducted to verify defensive invariants,
> bounds enforcement, cryptographic sanitization, and denial-of-service
> resilience. This review is **not** a substitute for an external, third-party
> security audit or professional penetration test.

**Date of Review:** 2026-11-07  
**Scope:** Phase 2 Protocol Parsers (`packages/config_parser`), Subscription Network
Fetcher (`SubscriptionFetcher`), and Phase 5 Mobile UI Input Ingestion
(`AddServerScreen`, `QrScanScreen`, `AddSubscriptionScreen`).  
**Verification Suite:** `apps/mobile/test/untrusted_input_security_review_test.dart`

---

## 1. Executive Summary & Security Posture

Brick VPN ingests untrusted external data across three primary threat vectors:
1. **Pasted Configuration Links:** Manual user clipboard paste (`vless://`, `trojan://`, `ss://`, etc.).
2. **Scanned QR Barcodes:** Optical barcode captures via camera stream.
3. **Remote Subscription Documents:** HTTP/HTTPS network fetches parsing multi-profile subscription bodies.

Because these vectors handle arbitrary attacker-controlled strings, every ingress path must enforce four non-negotiable security invariants:
- **Strict Bounds & Resource-Exhaustion Protection:** Length caps, bounded regex evaluation, incremental stream chunk limits, and recursion depth limits.
- **Strict Transport Security (HTTPS-Only):** Cleartext HTTP rejection, TLS certificate validation without user overrides, and redirect downgrade prevention.
- **Zero Secret Echoing:** Sensitive credentials (passwords, UUIDs, private keys, subscription access tokens) must never be reflected in exception strings, error payloads, diagnostic logs, or UI toasts/dialogs.
- **Fail-Closed Malformed Input Handling:** Hostile payloads (null bytes, CRLF injection, invalid percent/base64 encoding, non-numeric parameters, out-of-range ports) must safely map to typed domain errors without crashing or leaking memory.

---

## 2. Per-Parser Audit Matrix

All protocol parsers inherit defensive primitives from `defensive_parser_utils.dart` and `uri_parsing_support.dart`. Each parser was audited against the five standard attack classes:

| Parser / Module | Bounds Check (`maxUriLength = 8 KiB`) | Safe Encoding (Base64 / Percent) | DoS Resistance (Length & Allocations) | Unknown Field Handling | RFC 6066 SNI Sanitization |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **VLESS** (`vless_parser.dart`) | `enforceMaxLength(8192)` | Strict UUID validator | O(1) fast reject on length | Unknown query params discarded | Strips IP literals & trailing dots |
| **VMess** (`vmess_parser.dart`) | `enforceMaxLength(8192)` | Tolerant unpadded Base64 + UTF-8 size cap | Bounded JSON depth (`<= 32`) | Unrecognized keys safely ignored | Strips IP literals & ports from SNI |
| **Trojan** (`trojan_parser.dart`) | `enforceMaxLength(8192)` | Percent-decode with fallback | Port range `1..65535` checked | Extra query parameters ignored | Rejects IP-literal SNIs per RFC 6066 |
| **Shadowsocks** (`shadowsocks_parser.dart`) | `enforceMaxLength(8192)` | Base64 URL-safe & standard normalized | Rejects corrupted method/key | Discards unknown plugin args | Preserves server address / cleans SNI |
| **Hysteria2** (`hysteria2_parser.dart`) | `enforceMaxLength(8192)` | URI-encoded password decode | Mandates `obfs-password` when `obfs` is present | Unrecognized query ignored | SNI defaults to host if not IP |
| **TUIC** (`tuic_parser.dart`) | `enforceMaxLength(8192)` | UUID & token validation | Strict congestion control parsing | Unknown query params ignored | Rejects invalid IP SNIs |
| **WireGuard** (`wireguard_parser.dart`) | `enforceMaxLength(8192)` | 32-byte exact Base64 key enforcement | IP/CIDR address validation | Ignores extraneous fields | N/A (Pure IP endpoints) |
| **AmneziaWG** (`amneziawg_parser.dart`) | `enforceMaxLength(8192)` | 32-byte Base64 key & non-negative integer bounds | Strict numeric conversion (`int.tryParse`) | Unrecognized params ignored | N/A (Pure IP endpoints) |
| **SmartConfigParser** (`smart_config_parser.dart`) | `maxSubscriptionLength (5 MiB)` | Fast format detection without recursion | Depth-limited JSON decode (`<= 32`) | Discards unroutable blocks | Routes to specific parser safely |
| **SubscriptionParser** (`subscription_parser.dart`) | `maxSubscriptionLength (5 MiB)` | Bounded UTF-8 base64 decode | Line-by-line bounded parse with partial-success policy | Malformed lines skipped without aborting valid profiles | Handled per constituent profile |
| **SingBoxOutboundSerializer** (`singbox_serializer.dart`) | Fixed buffer allocation | Safe JSON mapping | Zero string concatenation of raw parameters | Omits empty or invalid blocks | RFC 6066 compliant `server_name` |

### Key Audit Findings & Hardening:
1. **RFC 6066 Compliance:** All TLS-based parsers and the sing-box serializer verify that TLS `server_name` is never populated with an IPv4 or IPv6 address. IPv4/IPv6 endpoints leave `server_name` null, preventing sing-box core TLS handshake panics.
2. **Defensive Base64 Decoding:** `safeBase64Decode` normalizes URL-safe characters (`-`, `_`) to standard (`+`, `/`) and strips trailing `=` before re-padding cleanly. Exact byte length (`expectedBytes: 32`) is asserted for WireGuard and AmneziaWG keys before cryptographic instantiation.
3. **JSON Depth Protection:** `safeJsonDecode` performs an iterative breadth-first depth scan (`_depthOf`) limited to 32 levels, preventing stack overflow attacks via deeply nested JSON structures.

---

## 3. Subscription Network Fetch Security Audit

The subscription fetch path (`SubscriptionFetcher` and `HttpClientTransport`) was audited for network-level transport vulnerabilities:

1. **HTTPS Enforcement:**
   - The initial URI scheme must be `https://`. Plaintext `http://` is rejected immediately with typed `InsecureTransportError('http')`.
   - Disallowed schemes (`file://`, `javascript:`, `data:`, `ftp:`) are rejected during URL syntax validation.
2. **Redirect Security & Downgrade Prevention:**
   - The HTTP transport sets `request.followRedirects = false` and `request.maxRedirects = 0`, forcing all redirect handling into `SubscriptionFetcher`.
   - On every redirect hop (`301`, `302`, `303`, `307`, `308`), `SubscriptionFetcher` resolves `url.resolve(location)` and explicitly re-verifies `_requireHttps(next)`. A redirect from HTTPS to HTTP is instantly aborted with `InsecureTransportError`.
   - Redirect chains are capped at `maxRedirects = 5`. Infinite loops or long chains terminate with `TooManyRedirectsError`.
3. **Memory-DoS & Stream Bounding:**
   - Responses are read through `_readBounded(stream, maxBytes)` with a strict 5 MiB ceiling (`maxSubscriptionLength`).
   - The byte stream is monitored per incoming chunk. As soon as cumulative bytes exceed `maxBytes`, the stream subscription is immediately cancelled (`unawaited(subscription.cancel())`) and aborted with `InputTooLargeError`, preventing memory exhaustion from malicious gigabyte responses.
4. **Timeout Enforcement:**
   - A single cumulative deadline (`defaultFetchTimeout = Duration(seconds: 10)`) covers the entire fetch, including cold DNS resolution, TLS handshake, all redirect hops, and body streaming.
5. **TLS Certificate Policy:**
   - `HttpClientTransport` uses the platform's default trust store. There is no `badCertificateCallback` override anywhere in the repository.

---

## 4. Mobile UI Ingress Audit (`AddServerScreen`, `QrScanScreen`, `AddSubscriptionScreen`)

The presentation and coordinator layers were audited to guarantee that UI components neither weaken parser validations nor leak user credentials:

1. **Zero Secret Echoing Invariant:**
   - Manual Paste: When an invalid URI or malformed port is pasted into `AddServerScreen`, the error returned by `AddServerController.submit` uses safe domain error codes mapped via `ErrorMapper`. The error message presented to the user (via SnackBar or field helper text) never contains the user's password, token, or UUID.
   - QR Scanning: In `QrScanScreen`, scanned payloads with invalid ports or malformed tokens surface a generic error toast via `AppFeedback.showError`. Scanned secrets are never reflected in the widget tree.
   - Subscription Import: If a subscription fetch fails (due to network timeout, HTTP error, or invalid payload), the URL's query parameters and credentials are completely omitted from the error notification.
2. **Scanner Concurrency Lock:**
   - `QrScanScreen` maintains an atomic `_isProcessing` boolean lock guarding `onDetect`. Once a QR barcode is captured, the camera feed is paused and subsequent camera frames are dropped until processing concludes or an error resets the lock.
3. **Direct Save Invariant:**
   - Both `AddServerScreen` and `QrScanScreen` bypass unnecessary preview dialogs and directly commit validated configurations to `ServerProfileRepository`, ensuring secrets do not linger in ephemeral UI state.
4. **Remark & Name Sanitization (Bidi Spoofing & Control Characters):**
   - Untrusted URI fragment remarks (`#remark`) extracted via `parseUriRemark` are sanitized in `BuildServerProfile.sanitizeRemark` before profile construction.
   - Strips ASCII control characters (`[\x00-\x1F\x7F]`) and CRLF newlines (`\r`, `\n`) to prevent line-break spoofing in UI list views.
   - Strips Unicode bidirectional override characters (`[\u202A-\u202E\u2066-\u2069]`) to eliminate RTL text spoofing attacks against server labels.
   - Collapses consecutive whitespace and clamps display names to a maximum of 128 characters, protecting `ServerTile` and `SessionInfoPanel` against layout disruption and UI overflow.
5. **UI-Layer Denial-of-Service Defense (`LengthLimitingTextInputFormatter`):**
   - The URI input `TextField` in `AddServerScreen` and the URL input `TextField` in `AddSubscriptionScreen` enforce `inputFormatters: [LengthLimitingTextInputFormatter(8256)]` (`maxUriLength + 64`).
   - Caps oversized clipboard paste attacks (e.g., 100 KB - 10 MB payload pastes) in $O(1)$ time at the platform input channel boundary, preventing Flutter's `TextPainter` and text shaping engine from executing CPU-intensive paragraph layout passes on continuous glyph strings (which previously froze the UI thread for up to 60 seconds).
   - The 8,256-character cap exceeds `config_parser`'s `maxUriLength` (8,192 characters) by 64 characters, ensuring payloads slightly exceeding valid boundaries cleanly reach `config_parser` to trigger typed `InputTooLargeError` without UI stutter.

---

## 5. Automated Adversarial Test Verification

The test battery in `apps/mobile/test/untrusted_input_security_review_test.dart` exercises the entire untrusted data pipeline against hostile inputs:

- **Test 1 — Parser Adversarial Battery:**
  - 100 KB oversized URI rejected in `< 50ms` with `InputTooLargeError`.
  - Null bytes in UUID/port/scheme safely rejected.
  - CRLF injection (`\r\n`) in host/port rejected with zero secret echoing.
  - Malformed Base64 across Shadowsocks, VMess, and WireGuard rejected.
  - Out-of-range ports (`0`, `65536`, `-1`) rejected.
  - Half-configured Hysteria2 obfuscation rejected.
  - Non-numeric AmneziaWG obfuscation parameters rejected.
  - Depth-50 JSON resource-exhaustion payload rejected without stack overflow.
  - Self-referential `brick://import` loop rejected.
- **Test 2 — AddServerScreen Manual Paste Security:**
  - 100 KB payload rejected safely without UI freeze.
  - Password embedded in invalid-port URI never echoed in SnackBar or UI tree.
  - CRLF injected URI rejected without crashing.
  - Raw JSON with malicious protocol rejected.
- **Test 3 — QrScanScreen Hostile Barcode Security:**
  - Malformed QR code with sensitive credentials never echoed in UI.
  - Subscription URL scanned in server QR screen rejected safely, unlocking for retry.
  - Corrupt UTF-8 byte stream safely rejected.
- **Test 4 — Subscription Network Security:**
  - Cleartext HTTP rejected immediately.
  - Non-HTTP schemes (`file://`, `javascript:`, `data:`) rejected.
  - HTTPS -> HTTP redirect downgrade rejected with `InsecureTransportError`.
  - Redirect loop terminated at 5 hops with `TooManyRedirectsError`.
  - 6 MB streaming payload aborted incrementally with `InputTooLargeError`.
  - Network transport exception with secret token in URL leaves zero secret traces in UI.

**Result:** 4/4 test suites passed with 100% compliance.

