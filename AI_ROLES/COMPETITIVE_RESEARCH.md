# COMPETITIVE RESEARCH & PROTOCOL ARCHITECTURE REFERENCE

**Status:** Living reference document  
**Established:** 2026-09-21 (Pre-P1-T3 Architecture Convergence)  
**Authoritative Context:** Informs `AI_ROLES/ARCHITECTURE.md`, `ROADMAP.md` (P1-T3, Phase 2, Phase 3), and `SECURITY.md`.

---

## 1. Executive Summary & Field Realities (Iran 2025–2026)

Field research across the Iranian circumvention ecosystem (Hiddify, v2rayNG, NapsternetV, sing-box, and server panels like BPB/Nova) alongside network telemetry from the 2025–2026 severe censorship blackouts revealed critical engineering lessons:

1. **Legacy Failure Validation:** Public issue trackers for market-leading clients (e.g., Hiddify) show the exact failure modes Brick VPN's architecture is designed to prevent:
   - *Silent Connection Failures:* VPN reports "Connected" while TUN traffic is dropped or deadlocked (Problem 1 & 2 in Section 1.4 of handoff).
   - *Native Panics:* Unhandled panics in sing-box core (e.g., slice bounds errors in dialer fragmentation during profile latency sorting) crashing the entire application process.
   - *Battery Drain & Deadlocks:* Incomplete stop/teardown cycles leaving orphan background routines.
2. **Blackout Scenario Realities (Severe Censorship Tiers):**
   - During severe national firewall blackouts (such as early 2026), all standard proxy protocols (VLESS, VMess, Trojan, Hysteria2, TUIC) can be actively dropped via DPI or protocol-agnostic port/packet filtering.
   - Fallback mechanisms (e.g., DNS-based tunneling such as `dnstt` over UDP 53, or resilient domain-fronted transports) become the only operational paths.
   - *Architecture Implication:* Protocol configuration MUST be polymorphic and extensible from Day 1 to allow pluggable emergency transports in future phases without breaking core domain models.
3. **Implicit Industry Standards:**
   - **TLS Fragmentation (`fragment`):** Mandatory for bypassing SNI-based DPI blocking on TCP/TLS connections. Supported natively in sing-box's TLS outbound block.
   - **uTLS Fingerprint Simulation:** Simulating browser ClientHello fingerprints (e.g., `chrome`, `firefox`, `safari`) to resist active probing and TLS fingerprint classification.
   - **Cloudflare Warp Chaining:** Chaining outbound traffic through Warp/Warp+ endpoints to obtain clean egress IPs.
   - **Zero-Tolerance DNS Leak Prevention:** Critical flaw in competitor clients where custom DNS in TUN mode fails to capture all queries; verified as a strict security invariant in `SECURITY.md`.

---

## 2. Sing-box Outbound Protocol Matrix (6 Core Protocols)

A comprehensive field and schema survey of the 6 core protocols supported via sing-box core:

| Feature / Dimension | VLESS | VMess | Trojan | Shadowsocks (SIP002/022) | Hysteria2 | TUIC (v5) |
|---|---|---|---|---|---|---|
| **Base Transport** | TCP (default) | TCP (default) | TCP (default) | TCP / UDP raw | QUIC (UDP) | QUIC (UDP) |
| **Primary Auth Field** | `uuid` (UUID) | `uuid` (UUID) | `password` (String) | `password` + `method` | `password` (String) | `uuid` + `password` |
| **TLS Block** | Optional (TLS/REALITY) | Optional (TLS) | Mandatory (`tls.enabled`) | None (handled via plugins) | Mandatory (QUIC-native TLS) | Mandatory (QUIC-native TLS) |
| **V2Ray Transport** | Optional (WS/gRPC/HTTP) | Optional (WS/gRPC/HTTP) | Optional (WS/gRPC/HTTP) | None | None | None |
| **REALITY Support** | Yes (`tls.reality.*`) | Rare / Non-standard | Rare / Non-standard | None | None | None |
| **Multiplex (`smux`/`yamux`)** | Supported | Supported | Supported | Supported | Not Applicable | Not Applicable |
| **QUIC Congestion Control** | None | None | None | None | BBR / Brutal CC | Cubic / BBR / New Reno |
| **Port Hopping** | None | None | None | None | Supported (`server_ports`) | None |
| **Obfuscation (`obfs`)** | None | None | None | Via `obfs-local` plugin | Native (`salamander`, etc.) | None |
| **0-RTT Handshake** | None | None | None | None | None | Supported (Disabled by default) |

---

## 3. Shared Composition Types Architecture

Analysis proves sing-box models outbound configurations through shared polymorphic blocks. The Dart domain model mirrors this composition directly:

### 3.1 `TlsSettings` (Shared across VLESS, VMess, Trojan, Hysteria2, TUIC)
Encapsulates all TLS negotiation parameters:
- `enabled` (bool), `serverName` / SNI (String?), `insecure` (bool - allow untrusted certificates).
- `alpn` (List<String>? - e.g., `["h2", "http/1.1"]` or `["h3"]`).
- `minVersion` / `maxVersion` (String? - e.g., `"1.2"`, `"1.3"`).
- `utls` (Fingerprint settings - `chrome`, `firefox`, `safari`, `ios`, `randomized`).
- `reality` (`RealitySettings`? - public key, short ID, spiderX; primarily for VLESS).
- `fragment` (`TlsFragmentSettings`? - packet fragmentation to bypass SNI DPI filtering).
- `ech` (`EchSettings`? - Encrypted Client Hello parameters).

### 3.2 `TransportSettings` (V2Ray Transport - VLESS, VMess, Trojan)
Polymorphic stream transport layer:
- `WebSocketTransport`: `path`, `headers`, `maxEarlyData`, `earlyDataHeaderName`.
- `GrpcTransport`: `serviceName`, `idleTimeout`, `pingTimeout`, `permitWithoutStream`.
- `HttpTransport`: `host`, `path`, `method`, `headers`.
- `HttpUpgradeTransport`: `host`, `path`, `headers`.

### 3.3 `QuicSettings` (QUIC Parameters - Hysteria2, TUIC)
Direct UDP/QUIC tuning options:
- `initialPacketSize`, `disablePathMtuDiscovery`, `idleTimeout`, `keepAlivePeriod`.

### 3.4 `MultiplexSettings` (Connection Multiplexing - VLESS, VMess, Trojan, Shadowsocks)
- `enabled`, `protocol` (`smux`, `yamux`, `h2mux`), `maxConnections`, `minStreams`, `maxStreams`, `padding`.

---

## 4. Class Hierarchy Blueprint (Pure Dart Domain)

The domain entity architecture in `packages/core_domain` is structured into a clean sealed class hierarchy:

```text
OutboundConfig (sealed base)
├── TcpBasedOutbound (sealed family: server, port, network, TlsSettings?, TransportSettings?, MultiplexSettings?)
│   ├── VlessOutbound (uuid, flow, packetEncoding, TlsSettings with Reality)
│   ├── VmessOutbound (uuid, security, alterId, globalPadding, authenticatedLength)
│   └── TrojanOutbound (password)
├── ShadowsocksOutbound (server, port, method, password, plugin, pluginOpts, udpOverTcp, MultiplexSettings?)
└── QuicBasedOutbound (sealed family: server, port, TlsSettings [mandatory], QuicSettings?)
    ├── Hysteria2Outbound (password, upMbps, downMbps, serverPorts, obfs, bbrProfile)
    └── TuicOutbound (uuid, password, congestionControl, udpRelayMode, zeroRttHandshake)
```

### 4.1 Safety & Extensibility Safeguards

1. **No `toString()` Override:** Sensitive data (UUIDs, passwords, REALITY private/public keys, obfuscation passwords) MUST NEVER be logged or converted to plain strings in system loggers.
2. **Guarded `extraParams`:** An optional `Map<String, dynamic>? extraParams` field exists strictly as an escape hatch for future protocol options before formal typing. Automated unit tests enforce that standard instances keep `extraParams == null` to prevent bypassing type safety.
3. **Deterministic Serialization:** Every class implements `Map<String, dynamic> toJson()` containing an explicit type discriminator tag, ensuring deterministic bidirectional serialization for Phase 8 secure storage.

---

## 5. Security & Privacy Classification

| Protocol | Sensitive Fields (Strictly Redacted / No Plain Logging) | Network Leak Risks (DPI / ISP Visibility) |
|---|---|---|
| VLESS | `uuid`, `reality.publicKey`, `reality.shortId` | Plaintext SNI if ECH disabled; packet size fingerprints |
| VMess | `uuid` | Weak ciphers (none/zero); AlterID timing leaks |
| Trojan | `password` | Plaintext SNI if ECH disabled; invalid certificate MITM |
| Shadowsocks | `password`, `method` | Legacy stream ciphers vulnerable to replay/active probing |
| Hysteria2 | `password`, `obfs.password` | UDP/QUIC packet rate/burst fingerprints |
| TUIC | `uuid`, `password` | Replay attacks if `zeroRttHandshake: true` is enabled |

---

## 6. Forward-Looking Roadmap Guidance

1. **Phase 2 (Config Parser Engine):** Parsers must produce concrete subclasses of `OutboundConfig` with full validation of required fields and safe defaults.
2. **Phase 3 (Android Native / sing-box):** JSON generator must map `OutboundConfig` composition types directly to sing-box outbound structure.
3. **Phase 5 (MVP Features):** Quick Settings Tile integration and automated latency testing (URL-test) are designated high-value UX targets.
4. **Phase 7 & 8 (Security & Resilience):** TLS Fragment, uTLS fingerprint profiles, and strict DNS leak-proof routing must be hardened as primary competitive differentiators.
5. **Future Platform Expansions (Blackout Resilience):** Retain architectural flexibility to introduce emergency transport plugins (e.g., `DnsttOutbound` over UDP port 53) under `OutboundConfig`.