# config_parser

Pure-Dart parsing and serialization for Brick VPN server configurations.

**This package must never gain a Flutter dependency.** Every function here is
pure and deterministic (no clock, no randomness, no I/O) and is unit-tested
with plain `dart test`. That property is enforced by the Melos routing in the
root `pubspec.yaml`: this package is in the `test:dart` allowlist and the
`test:flutter` denylist.

## Security posture (SECURITY.md)

All input is **untrusted** — a subscription may be served by a malicious or
compromised provider. Therefore:

- Nothing here **throws** for malformed input. Every parser returns
  `Result<T, ConfigParseError>`.
- Input is **bounded**: `maxUriLength` (8 KB), `maxSubscriptionLength`
  (5 MB), `maxJsonDepth` (32). Oversized input is rejected *before* decoding.
- Errors **never carry the offending value**. A `ConfigParseError` stores
  only developer-authored metadata (field names, sizes, reasons), so a
  UUID, password, or key cannot reach a log through an error message.
- Base64 decoding tolerates standard and URL-safe alphabets, with or without
  padding, and validates decoded length (e.g. exactly 32 bytes for a key).

## Supported URI formats

| Scheme | Shape | Parser |
|---|---|---|
| `vless://` | `<uuid>@<host>:<port>?<query>#<remark>` | `parseVlessUri` |
| `vmess://` | base64(v2rayN JSON), or a URL-style link | `parseVmessUri` |
| `trojan://` | `<password>@<host>:<port>?<query>#<remark>` | `parseTrojanUri` |
| `ss://` | SIP002 (`base64(method:password)@host:port`) and legacy (fully base64) | `parseShadowsocksUri` |
| any | dispatches on scheme | `parseUri` |

Supported VLESS/VMess query parameters: `type` (tcp/ws/grpc/splithttp/xhttp),
`security` (none/tls/reality), `sni`, `fp`, `path`, `host`, `serviceName`,
`pbk`, `sid`, `spx`, `flow`, `alpn`.

## Sing-Box 1.10+ JSON mapping

`buildSingBoxOutbound(config, {tag})` produces a sing-box outbound object.
Field names follow the **official sing-box documentation**, verified against
<https://sing-box.sagernet.org> (outbound pages plus the shared "V2Ray
Transport" and "TLS" pages) rather than training data.

| Domain | sing-box JSON |
|---|---|
| `VlessOutbound` | `type: "vless"`, `server`, `server_port`, `uuid`, `flow`, `packet_encoding` |
| `VmessOutbound` | `type: "vmess"`, `server`, `server_port`, `uuid`, `security`, `alter_id`, `global_padding`, `authenticated_length` |
| `TrojanOutbound` | `type: "trojan"`, `server`, `server_port`, `password` |
| `ShadowsocksOutbound` | `type: "shadowsocks"`, `server`, `server_port`, `method`, `password`, `plugin`, `plugin_opts`, `udp_over_tcp` |
| `TlsSettings` | `tls: {enabled, server_name, insecure, alpn, min_version, max_version, utls{enabled, fingerprint}, reality{enabled, public_key, short_id, spider_x}}` |
| `WebSocketTransport` | `transport: {type: "ws", path, headers}` |
| `GrpcTransport` | `transport: {type: "grpc", service_name}` |
| `HttpTransport` | `transport: {type: "http", host, path, method, headers}` |
| `HttpUpgradeTransport` | `transport: {type: "httpupgrade", host, path}` |
| `MultiplexSettings` | `multiplex: {enabled, protocol, max_connections, min_streams, max_streams, padding}` |

### Two non-obvious mapping rules

1. **`network` is the L4 network, not the transport.** In sing-box,
   `network` accepts `"tcp"` or `"udp"` (both enabled by default when the key
   is absent). The V2Ray transport belongs in `transport.type`. The
   serializer therefore emits `network` **only** for a genuine L4 value and
   omits it otherwise — emitting `network: "ws"` would be invalid.
2. **The transport is `httpupgrade`, not `splithttp`.** `splithttp` is the
   Xray/v2rayN link spelling; sing-box names the same transport
   `httpupgrade`. The parser accepts both, the serializer emits the
   sing-box spelling.

### Protocol coverage

All six domain protocols are now covered end to end — parser and Sing-Box serializer:

| Protocol | Parser | Serializer |
|---|---|---|
| VLESS | `parseVlessUri` | yes |
| VMess | `parseVmessUri` | yes |
| Trojan | `parseTrojanUri` | yes |
| Shadowsocks | `parseShadowsocksUri` | yes |
| Hysteria2 | `parseHysteria2Uri` | yes (added in P2-T5) |
| TUIC | `parseTuicUri` | yes (added in P2-T5) |
| WireGuard | `parseWireguardUri` (`wireguard://`, `wg://`) | yes (added in P2-T6) |
| AmneziaWG | `parseAmneziaWgUri` (`amneziawg://`, `awg://`) | yes (added in P2-T6) |

`SingBoxOutboundSerializer.tryBuild` therefore succeeds for every `OutboundConfig`
variant; the `UnsupportedProtocolError` path remains as a forward-compatibility guard for a
future protocol, not for any protocol currently in `core_domain`.

### Known limitations

- `disable_sni` is a real sing-box TLS key but has no field on the domain `TlsSettings` type,
  which is frozen. The TUIC parser carries it through `extraParams` and the serializer emits
  it; a proper `disableSni` field should be added upstream.
- Shadowsocks cipher validation covers the 18 values sing-box documents. A future sing-box
  release adding a cipher would need this list updated.
- `Hysteria2` `server_ports` / `hop_interval` and the Hysteria Realm fields are not parsed from
- **sing-box deprecated the WireGuard *outbound* in 1.11.0 and documents its removal in
  1.13.0** (Migration: "Migrate WireGuard outbound to endpoint"). The JSON emitted here is
  correct for the 1.10/1.11 schema this client targets, but that schema is scheduled for
  deletion. When the client moves to sing-box >= 1.13, WireGuard must be modelled as an
  `endpoint`, not an outbound.
- **sing-box has no AmneziaWG support.** Its WireGuard schema documents none of
  `jc`/`jmin`/`jmax`/`s1`/`s2`/`h1`..`h4`, and sing-box rejects unknown top-level keys. The
  parameters are parsed and range-validated into `AmneziaWgOutbound` and preserved on the
  domain object (`obfuscationParams`; `toJson()` namespaces them under
  `amneziawg_obfuscation`) but are deliberately **not** emitted as top-level sing-box keys,
  because doing so would produce a config sing-box refuses to load. Runtime AmneziaWG support
  needs either a patched sing-box or a different outbound construct.
  URIs (no common URI convention exists for them yet).
## API conventions

- Parsers return `Result<OutboundConfig, ConfigParseError>`.
- `OutboundConfig.toServerProfile(...)` wraps a parsed config in a
  `ServerProfile`. `id` and `addedAt` are supplied by the caller because a
  pure parser cannot know them.
