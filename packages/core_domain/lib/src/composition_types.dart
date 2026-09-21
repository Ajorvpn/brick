// SPDX-License-Identifier: GPL-3.0-or-later

// Shared, immutable configuration blocks referenced by the outbound
// protocol classes in `outbound_config.dart` (see COMPETITIVE_RESEARCH.md
// section 3 for the field survey these types mirror).
//
// File-level security note: no class in this file overrides `toString`.
// Several of them carry credential-like payloads (REALITY keys,
// obfuscation passwords) that must never reach a log through an
// incidental print, per SECURITY.md. Nullable fields whose value is null
// are omitted from `toJson()` so serialized snapshots stay minimal and
// deterministic.

// Structural equality for nullable lists whose elements have value
// equality. Dart's `List` does not implement structural `==`, so value
// objects that hold lists need this to keep their own equality honest.
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null) {
    return a == null && b == null;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

// Structural equality for nullable maps, one level deep: values are
// compared with `==`, so a value that is itself a mutable collection falls
// back to identity comparison. No field modeled in this library nests
// collections inside collections.
bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null) {
    return a == null && b == null;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) {
      return false;
    }
  }
  return true;
}

/// REALITY handshake settings. Used only by VLESS. Public key and short ID
/// are provisioned per-server; NEVER log them.
final class RealitySettings {
  /// Creates an immutable REALITY settings block.
  const RealitySettings({
    required this.enabled,
    required this.publicKey,
    required this.shortId,
    this.spiderX,
  });

  /// Whether the REALITY extension is active for this outbound.
  final bool enabled;

  /// REALITY server public key — credential-adjacent material.
  final String publicKey;

  /// Short ID token issued together with [publicKey].
  final String shortId;

  /// Optional spider path used during the anti-probing handshake.
  final String? spiderX;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealitySettings &&
          other.enabled == enabled &&
          other.publicKey == publicKey &&
          other.shortId == shortId &&
          other.spiderX == spiderX;

  @override
  int get hashCode => Object.hash(enabled, publicKey, shortId, spiderX);

  /// Deterministic JSON mapping; null optional fields are omitted.
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'public_key': publicKey,
    'short_id': shortId,
    if (spiderX != null) 'spider_x': spiderX,
  };
}

/// uTLS fingerprint simulation. `fingerprint` accepts values like
/// 'chrome', 'firefox', 'safari', 'ios', 'randomized'.
final class UtlsSettings {
  /// Creates an immutable uTLS settings block.
  const UtlsSettings({required this.enabled, required this.fingerprint});

  /// Whether uTLS fingerprint simulation is active.
  final bool enabled;

  /// Browser ClientHello fingerprint to imitate.
  final String fingerprint;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UtlsSettings &&
          other.enabled == enabled &&
          other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(enabled, fingerprint);

  /// Deterministic JSON mapping.
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'fingerprint': fingerprint,
  };
}

/// TLS ClientHello fragmentation to bypass SNI-based DPI filtering.
/// `size` and `sleep` accept sing-box duration strings (e.g. '10-30ms').
final class TlsFragmentSettings {
  /// Creates an immutable fragmentation settings block.
  const TlsFragmentSettings({required this.enabled, this.size, this.sleep});

  /// Whether ClientHello fragmentation is active.
  final bool enabled;

  /// Fragment size range as a sing-box range string.
  final String? size;

  /// Sleep between fragments as a sing-box duration string.
  final String? sleep;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TlsFragmentSettings &&
          other.enabled == enabled &&
          other.size == size &&
          other.sleep == sleep;

  @override
  int get hashCode => Object.hash(enabled, size, sleep);

  /// Deterministic JSON mapping; null optional fields are omitted.
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (size != null) 'size': size,
    if (sleep != null) 'sleep': sleep,
  };
}

/// TLS configuration shared by VLESS, VMess, Trojan, Hysteria2, and TUIC.
///
/// `insecure = true` disables certificate verification and MUST NOT be
/// used in production; it exists so lab profiles can be modeled without a
/// separate type. `serverName` is the SNI value sent in the ClientHello.
final class TlsSettings {
  /// Creates an immutable TLS settings block.
  const TlsSettings({
    required this.enabled,
    this.serverName,
    this.insecure = false,
    this.alpn,
    this.minVersion,
    this.maxVersion,
    this.utls,
    this.reality,
    this.fragment,
  });

  /// Whether TLS negotiation is active for this outbound.
  final bool enabled;

  /// SNI value; null lets the server address double as SNI.
  final String? serverName;

  /// Disables certificate verification. MUST NOT be used in production.
  final bool insecure;

  /// Application-layer protocol negotiation list (e.g. ['h2', 'http/1.1']).
  final List<String>? alpn;

  /// Minimum TLS version string (e.g. '1.2').
  final String? minVersion;

  /// Maximum TLS version string (e.g. '1.3').
  final String? maxVersion;

  /// Optional uTLS fingerprint simulation block.
  final UtlsSettings? utls;

  /// Optional REALITY block (VLESS only).
  final RealitySettings? reality;

  /// Optional ClientHello fragmentation block.
  final TlsFragmentSettings? fragment;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TlsSettings &&
          other.enabled == enabled &&
          other.serverName == serverName &&
          other.insecure == insecure &&
          _listEquals(other.alpn, alpn) &&
          other.minVersion == minVersion &&
          other.maxVersion == maxVersion &&
          other.utls == utls &&
          other.reality == reality &&
          other.fragment == fragment;

  @override
  int get hashCode => Object.hash(
    enabled,
    serverName,
    insecure,
    alpn == null ? null : Object.hashAll(alpn!),
    minVersion,
    maxVersion,
    utls,
    reality,
    fragment,
  );

  /// Deterministic JSON mapping; null optional fields are omitted.
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (serverName != null) 'server_name': serverName,
    'insecure': insecure,
    if (alpn != null) 'alpn': List<String>.of(alpn!),
    if (minVersion != null) 'min_version': minVersion,
    if (maxVersion != null) 'max_version': maxVersion,
    if (utls != null) 'utls': utls!.toJson(),
    if (reality != null) 'reality': reality!.toJson(),
    if (fragment != null) 'fragment': fragment!.toJson(),
  };
}

/// Polymorphic V2Ray-style stream transport layered over the TCP-based
/// protocols (VLESS, VMess, Trojan). Sealed so the Phase 3 JSON generator
/// can switch exhaustively over the four concrete transports.
sealed class TransportSettings {
  const TransportSettings();

  /// sing-box transport discriminator: 'ws', 'grpc', 'http',
  /// 'httpupgrade'.
  String get type;

  /// Deterministic JSON mapping including the `'type'` discriminator.
  Map<String, dynamic> toJson();
}

/// WebSocket transport.
final class WebSocketTransport extends TransportSettings {
  const WebSocketTransport({
    required this.path,
    this.headers,
    this.maxEarlyData,
    this.earlyDataHeaderName,
  });

  /// WebSocket path, e.g. '/ray'.
  final String path;

  /// Optional handshake headers (commonly spoofing `Host`).
  final Map<String, String>? headers;

  /// Maximum early data bytes carried in the upgrade request.
  final int? maxEarlyData;

  /// Header name carrying early data when [maxEarlyData] is set.
  final String? earlyDataHeaderName;

  @override
  String get type => 'ws';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebSocketTransport &&
          other.path == path &&
          _mapEquals(other.headers, headers) &&
          other.maxEarlyData == maxEarlyData &&
          other.earlyDataHeaderName == earlyDataHeaderName;

  @override
  int get hashCode {
    final headersHash = headers == null
        ? null
        : Object.hashAll([
            for (final entry in headers!.entries)
              Object.hash(entry.key, entry.value),
          ]);
    return Object.hash(path, headersHash, maxEarlyData, earlyDataHeaderName);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'path': path,
    if (headers != null) 'headers': Map<String, String>.of(headers!),
    if (maxEarlyData != null) 'max_early_data': maxEarlyData,
    if (earlyDataHeaderName != null)
      'early_data_header_name': earlyDataHeaderName,
  };
}

/// gRPC transport.
final class GrpcTransport extends TransportSettings {
  const GrpcTransport({
    required this.serviceName,
    this.idleTimeout,
    this.pingTimeout,
    this.permitWithoutStream = false,
  });

  /// gRPC service name configured on the server.
  final String serviceName;

  /// Idle connection timeout; null keeps the sing-box default.
  final Duration? idleTimeout;

  /// Keepalive ping interval.
  final Duration? pingTimeout;

  /// Whether the connection may stay alive without active streams.
  final bool permitWithoutStream;

  @override
  String get type => 'grpc';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GrpcTransport &&
          other.serviceName == serviceName &&
          other.idleTimeout == idleTimeout &&
          other.pingTimeout == pingTimeout &&
          other.permitWithoutStream == permitWithoutStream;

  @override
  int get hashCode =>
      Object.hash(serviceName, idleTimeout, pingTimeout, permitWithoutStream);

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'service_name': serviceName,
    if (idleTimeout != null) 'idle_timeout': idleTimeout!.inMicroseconds,
    if (pingTimeout != null) 'ping_timeout': pingTimeout!.inMicroseconds,
    'permit_without_stream': permitWithoutStream,
  };
}

/// Plain HTTP/2 transport.
final class HttpTransport extends TransportSettings {
  const HttpTransport({this.host, this.path, this.method, this.headers});

  /// Optional host list sent in requests.
  final List<String>? host;

  /// Optional request path.
  final String? path;

  /// Optional HTTP method override.
  final String? method;

  /// Optional request headers.
  final Map<String, String>? headers;

  @override
  String get type => 'http';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpTransport &&
          _listEquals(other.host, host) &&
          other.path == path &&
          other.method == method &&
          _mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(
    host == null ? null : Object.hashAll(host!),
    path,
    method,
    headers == null
        ? null
        : Object.hashAll([
            for (final entry in headers!.entries)
              Object.hash(entry.key, entry.value),
          ]),
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    if (host != null) 'host': List<String>.of(host!),
    if (path != null) 'path': path,
    if (method != null) 'method': method,
    if (headers != null) 'headers': Map<String, String>.of(headers!),
  };
}

/// HTTP upgrade transport.
final class HttpUpgradeTransport extends TransportSettings {
  const HttpUpgradeTransport({this.host, this.path, this.headers});

  /// Optional host header value.
  final String? host;

  /// Optional upgrade path.
  final String? path;

  /// Optional handshake headers.
  final Map<String, String>? headers;

  @override
  String get type => 'httpupgrade';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpUpgradeTransport &&
          other.host == host &&
          other.path == path &&
          _mapEquals(other.headers, headers);

  @override
  int get hashCode {
    final headersHash = headers == null
        ? null
        : Object.hashAll([
            for (final entry in headers!.entries)
              Object.hash(entry.key, entry.value),
          ]);
    return Object.hash(host, path, headersHash);
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    if (host != null) 'host': host,
    if (path != null) 'path': path,
    if (headers != null) 'headers': Map<String, String>.of(headers!),
  };
}

/// QUIC transport tuning parameters shared between Hysteria2 and TUIC.
final class QuicSettings {
  const QuicSettings({
    this.initialPacketSize,
    this.disablePathMtuDiscovery = false,
    this.idleTimeout,
    this.keepAlivePeriod,
  });

  /// Initial QUIC packet size in bytes.
  final int? initialPacketSize;

  /// Disables QUIC path MTU discovery probes.
  final bool disablePathMtuDiscovery;

  /// Idle connection timeout; null keeps the sing-box default.
  final Duration? idleTimeout;

  /// Keepalive period; null keeps the sing-box default.
  final Duration? keepAlivePeriod;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuicSettings &&
          other.initialPacketSize == initialPacketSize &&
          other.disablePathMtuDiscovery == disablePathMtuDiscovery &&
          other.idleTimeout == idleTimeout &&
          other.keepAlivePeriod == keepAlivePeriod;

  @override
  int get hashCode => Object.hash(
    initialPacketSize,
    disablePathMtuDiscovery,
    idleTimeout,
    keepAlivePeriod,
  );

  /// Deterministic JSON mapping; null optional fields are omitted.
  /// Durations are serialized as integer microseconds so the mapping stays
  /// lossless; Phase 3 renders sing-box duration strings.
  Map<String, dynamic> toJson() => {
    if (initialPacketSize != null) 'initial_packet_size': initialPacketSize,
    'disable_path_mtu_discovery': disablePathMtuDiscovery,
    if (idleTimeout != null) 'idle_timeout': idleTimeout!.inMicroseconds,
    if (keepAlivePeriod != null)
      'keep_alive_period': keepAlivePeriod!.inMicroseconds,
  };
}

/// Connection multiplexing (VLESS, VMess, Trojan, Shadowsocks).
/// `protocol` accepts 'smux', 'yamux', 'h2mux'.
final class MultiplexSettings {
  const MultiplexSettings({
    required this.enabled,
    this.protocol,
    this.maxConnections,
    this.minStreams,
    this.maxStreams,
    this.padding,
  });

  /// Whether multiplexing is active for this outbound.
  final bool enabled;

  /// Multiplexing protocol ('smux', 'yamux', 'h2mux').
  final String? protocol;

  /// Maximum simultaneous connections.
  final int? maxConnections;

  /// Minimum multiplexed streams per connection.
  final int? minStreams;

  /// Maximum multiplexed streams per connection.
  final int? maxStreams;

  /// Whether multiplexed streams are padded.
  final bool? padding;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiplexSettings &&
          other.enabled == enabled &&
          other.protocol == protocol &&
          other.maxConnections == maxConnections &&
          other.minStreams == minStreams &&
          other.maxStreams == maxStreams &&
          other.padding == padding;

  @override
  int get hashCode => Object.hash(
    enabled,
    protocol,
    maxConnections,
    minStreams,
    maxStreams,
    padding,
  );

  /// Deterministic JSON mapping; null optional fields are omitted.
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (protocol != null) 'protocol': protocol,
    if (maxConnections != null) 'max_connections': maxConnections,
    if (minStreams != null) 'min_streams': minStreams,
    if (maxStreams != null) 'max_streams': maxStreams,
    if (padding != null) 'padding': padding,
  };
}
