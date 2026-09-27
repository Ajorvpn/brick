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
- A few errors name a *token* taken from the input (the URI scheme, the JSON
  `type`, the Shadowsocks cipher). Those are echoed through
  `sanitiseEchoedIdentifier`, which passes only short, identifier-shaped
  values (`[a-z0-9-]`, <= 32 chars) and otherwise reports a shape mismatch.
  This matters: a payload like `{"type":"<credential>", ...}` would otherwise
  reproduce the credential in a log-bound message. See
  `test/error_redaction_test.dart`.
- Base64 decoding tolerates standard and URL-safe alphabets, with or without
  padding, and validates decoded length (e.g. exactly 32 bytes for a key).

## Supported URI formats

| Scheme | Shape | Parser |
|---|---|---|
| `vless://` | `<uuid>@<host>:<port>?<query>#<remark>` | `parseVlessUri` |
| `vmess://` | base64(v2rayN JSON), or a URL-style link | `parseVmessUri` |
| `trojan://` | `<password>@<host>:<port>?<query>#<remark>` | `parseTrojanUri` |
| `ss://` | SIP002 (`base64(method:password)@host:port`) and legacy (fully base64) | `parseShadowsocksUri` |
| `hy2://`, `hysteria2://` | `<password>@<host>:<port>?<query>#<remark>` | `parseHysteria2Uri` |
| `tuic://` | `<uuid>:<password>@<host>:<port>?<query>#<remark>` | `parseTuicUri` |
| `wireguard://`, `wg://` | `<private_key>@<host>:<port>?<query>#<remark>` | `parseWireguardUri` |
| `amneziawg://`, `awg://` | same as WireGuard plus the nine obfuscation parameters | `parseAmneziaWgUri` |
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
- **No stable AWG URI convention exists.** The `amneziawg://` / `awg://` scheme is this
  project's own; it follows the WireGuard link shape and is not yet standardised.
## Subscription parsing

`parseSubscription(String body, {String? userInfoHeaderValue})` handles the
two body formats a provider can serve, without any network access:

- a **base64**-encoded blob (standard or URL-safe alphabet, padded or not), or
- a **plain newline-separated** list of server URIs.

It returns `Result<SubscriptionParseResult, ConfigParseError>`, where
`SubscriptionParseResult` carries `configs`, `errors`, `totalLineCount` and
`skippedLineCount`. The parsed `Subscription-Userinfo` header is folded into
`SmartParseResult.userInfo` by `parseConfigContent` (see below).

**Partial success is the point.** A subscription with 40 good entries and 2
malformed ones must not fail as a whole, so per-entry failures land in
`errors` while the good entries are kept. A whole-body `Err` is reserved for
"nothing usable was found at all".

```dart
final result = parseSubscription(
  body,
  userInfoHeaderValue: headers.value('subscription-userinfo'),
);
if (result case Ok(:final value)) {
  for (final outbound in value.configs) {
    /* … */
  }
  for (final failure in value.errors) {
    /* report the bad entry, without echoing its contents */
  }
  // Diagnostics for the subscription as a whole.
  // ignore: avoid_print
  print('${value.configs.length}/${value.totalLineCount} usable, '
      '${value.skippedLineCount} blank/comment lines skipped');
}
```

`SubscriptionUserInfo.parse` reads the `Subscription-Userinfo` header
(`upload=…; download=…; total=…; expire=…`) into `uploadBytes`, `downloadBytes`,
`totalBytes` and `expiresAt`.

> **This package does no networking.** It has no `dart:io`, no `HttpClient` and
> no HTTP dependency, by design — the body must be fetched elsewhere and passed
> in. Fetching a subscription URL is roadmap task P2-T10 and is not started.

## Smart content router (`parseConfigContent`)

`parseConfigContent(String input, {String? userInfoHeaderValue, int depth = 0})`
accepts *whatever the user pasted* and returns one uniform result:

```dart
final result = parseConfigContent(clipboardText);
if (result case Ok(:final value)) {
  for (final outbound in value.outbounds) {
    /* ... */
  }
  if (!value.isComplete) {
    for (final warning in value.warnings) {
      /* per-entry failures */
    }
  }
} else {
  // a typed ConfigParseError; nothing from the input is echoed
}
```

### Detection order

Each step is cheap and rules the previous one out:

1. **Deep link** — `brick://import?url=...` or `?config=...`. The inner payload is
   percent-decoded and re-routed through the same function. The result reports
   `SmartContentType.deepLink` (the *outer* shape), because that is what the
   caller handed us and it is the useful thing to report. Recursion is bounded to
   `_maxDeepLinkDepth` (3), so a self-referential link cannot loop.
2. **Single protocol URI** — anything `parseUri` recognises.
3. **Raw JSON** — a `{...}` object, a `[...]` array, or a full sing-box config with
   an `outbounds` array. This branch is **authoritative**: a subscription body is
   never `{`/`[`-prefixed, so its error is the most specific one available and is
   not masked by a generic subscription failure.
4. **Subscription** — newline-separated and/or base64 multi-entry body, routed
   through `parseSubscription`.

Input is trimmed, a leading UTF-8 BOM is stripped, and `maxSubscriptionLength` is
enforced *before* any parsing so an oversized paste is rejected cheaply.

### `SmartParseResult`

| Field | Type | Meaning |
|---|---|---|
| `outbounds` | `List<OutboundConfig>` | everything that parsed, in input order |
| `userInfo` | `SubscriptionUserInfo?` | quota/expiry metadata, when present |
| `warnings` | `List<ConfigParseError>` | non-fatal per-entry failures from a bulk body |
| `detectedType` | `SmartContentType` | `singleUri` \| `subscription` \| `json` \| `deepLink` |

`parsedCount` and `isComplete` are convenience getters. `warnings` is what makes a
partially-valid subscription salvageable: good entries are kept and the bad ones
are reported, rather than the whole body being discarded.

### Raw JSON reading

`readSingBoxOutboundJson(Map<String, dynamic>)` is the inverse of
`buildSingBoxOutbound`. Coverage is deliberately bounded to what can be rebuilt
losslessly — shadowsocks, trojan, vmess, vless, hysteria2, tuic and wireguard.
Anything else returns `UnsupportedProtocolError` rather than a lossy
approximation. The unknown-type check runs *before* shared-field validation so the
error names the real reason instead of a misleading `server_port`.

An `amneziawg_obfuscation` object (this project's own namespacing, see above) is
recovered back into `AmneziaWgOutbound` when present.

### Security

No input text is ever echoed into an error message or warning, so a pasted private
key, password or UUID cannot reach a log. Deep-link payloads are bounded and
errors are typed. See `test/smart_config_parser_test.dart` for the canary-string
leak tests.

### Known limitations

- **`brick://` is not registered with the OS yet.** This parser fixes and tests the
  contract, but `apps/mobile/android/app/src/main/AndroidManifest.xml` has no
  intent-filter for the scheme, so Android will not route a link here until that is
  added. Registering it is Android wiring and belongs to a later phase — until then
  this path is reachable from clipboard and in-app paste only.
- **Multi-entry detection is newline-based.** A body of several URIs joined by
  something other than a newline will be routed as a single URI and fail with a
  syntax error rather than being split.

## API conventions

- Parsers return `Result<OutboundConfig, ConfigParseError>`.
- `OutboundConfig.toServerProfile(...)` wraps a parsed config in a
  `ServerProfile`. `id` and `addedAt` are supplied by the caller because a
  pure parser cannot know them.
