// SPDX-License-Identifier: GPL-3.0-or-later

import 'composition_types.dart';
import 'protocol_type.dart';

// The polymorphic protocol-configuration hierarchy for every outbound
// sing-box can dial, mirroring the class blueprint in
// COMPETITIVE_RESEARCH.md section 4.
//
// File-level security note: no class in this file overrides `toString`.
// Concrete outbounds carry credentials (UUIDs, passwords, REALITY keys)
// that must never leak into logs through an incidental print, per
// SECURITY.md. Every concrete subclass implements value equality with an
// `identical` fast path and a `toJson()` whose `'type'` entry equals
// `protocol.scheme`.
//
// Sealing note: `OutboundConfig`, `TcpBasedOutbound` and
// `QuicBasedOutbound` are `sealed`, so the set of concrete outbounds is
// closed at compile time and switches over them can be exhaustive.

// Structural equality helpers (same semantics as the private helpers in
// composition_types.dart; duplicated because library-private helpers
// cannot be shared across files).
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

// Hash contribution of the extraParams escape hatch. Structurally equal
// maps built in the same key order produce the same hash, keeping the
// hashCode contract intact for the (discouraged) non-null case.
int? _extraParamsHash(Map<String, dynamic>? extraParams) {
  if (extraParams == null) {
    return null;
  }
  return Object.hashAll([
    for (final entry in extraParams.entries)
      Object.hash(entry.key, entry.value),
  ]);
}

// Merges the extraParams escape hatch into a serialized outbound. Must
// stay null on standard instances; see the base-class contract.
void _addExtraParams(
  Map<String, dynamic> json,
  Map<String, dynamic>? extraParams,
) {
  if (extraParams != null) {
    json.addAll(extraParams);
  }
}

// JSON entries shared by every TCP-family outbound. Null blocks are
// omitted so serialized snapshots stay minimal and deterministic.
void _addTcpFamilyFields(
  Map<String, dynamic> json, {
  required String? network,
  required TlsSettings? tls,
  required TransportSettings? transport,
  required MultiplexSettings? multiplex,
}) {
  if (network != null) {
    json['network'] = network;
  }
  if (tls != null) {
    json['tls'] = tls.toJson();
  }
  if (transport != null) {
    json['transport'] = transport.toJson();
  }
  if (multiplex != null) {
    json['multiplex'] = multiplex.toJson();
  }
}

/// Base of every outbound protocol configuration.
sealed class OutboundConfig {
  const OutboundConfig({
    required this.server,
    required this.serverPort,
    this.extraParams,
  });

  /// Server hostname or IP the outbound dials.
  final String server;

  /// Server port the outbound dials.
  final int serverPort;

  /// Escape hatch for future protocol options before formal typing. Must
  /// stay null on standard instances — enforced at runtime by
  /// `test/extra_params_enforcement_test.dart` — see
  /// COMPETITIVE_RESEARCH.md section 4.1.
  final Map<String, dynamic>? extraParams;

  /// Storage schema version, consumed by Phase 8 secure storage.
  int get schemaVersion => 1;

  /// Which protocol this configuration dials.
  ProtocolType get protocol;

  /// Shared JSON envelope: discriminator plus endpoint fields. Concrete
  /// subclasses extend this fresh map with their own fields; it is never
  /// shared state.
  Map<String, dynamic> outboundJson() => {
    'type': protocol.scheme,
    'server': server,
    'server_port': serverPort,
  };

  /// Deterministic JSON mapping with an explicit `'type'` discriminator.
  Map<String, dynamic> toJson();
}

/// Family of outbounds that dial over TCP and therefore share the optional
/// TLS, V2Ray transport, and multiplex blocks. Sealed: only VLESS, VMess,
/// and Trojan extend it.
sealed class TcpBasedOutbound extends OutboundConfig {
  const TcpBasedOutbound({
    required super.server,
    required super.serverPort,
    this.network,
    this.tls,
    this.transport,
    this.multiplex,
    super.extraParams,
  });

  /// Explicit network override; null lets sing-box pick its per-transport
  /// default.
  final String? network;

  /// Optional TLS block (mandatory in practice for VLESS+REALITY
  /// deployments, optional for plain VMess/Trojan-over-TLS setups).
  final TlsSettings? tls;

  /// Optional V2Ray transport layered over the TCP stream.
  final TransportSettings? transport;

  /// Optional connection multiplexing block.
  final MultiplexSettings? multiplex;
}

/// VLESS outbound. The only protocol that supports REALITY (through
/// [TlsSettings.reality]).
final class VlessOutbound extends TcpBasedOutbound {
  const VlessOutbound({
    required super.server,
    required super.serverPort,
    required this.uuid,
    this.flow,
    this.packetEncoding,
    super.network,
    super.tls,
    super.transport,
    super.multiplex,
    super.extraParams,
  });

  /// VLESS user UUID — credential material.
  final String uuid;

  /// Optional flow control (e.g. 'xtls-rprx-vision').
  final String? flow;

  /// Optional packet encoding for mux (e.g. 'packetaddr').
  final String? packetEncoding;

  @override
  ProtocolType get protocol => ProtocolType.vless;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VlessOutbound &&
          other.server == server &&
          other.serverPort == serverPort &&
          other.uuid == uuid &&
          other.flow == flow &&
          other.packetEncoding == packetEncoding &&
          other.network == network &&
          other.tls == tls &&
          other.transport == transport &&
          other.multiplex == multiplex &&
          _mapEquals(other.extraParams, extraParams);

  @override
  int get hashCode => Object.hash(
    server,
    serverPort,
    uuid,
    flow,
    packetEncoding,
    network,
    tls,
    transport,
    multiplex,
    _extraParamsHash(extraParams),
  );

  @override
  Map<String, dynamic> toJson() {
    final json = outboundJson();
    json['uuid'] = uuid;
    if (flow != null) {
      json['flow'] = flow;
    }
    if (packetEncoding != null) {
      json['packet_encoding'] = packetEncoding;
    }
    _addTcpFamilyFields(
      json,
      network: network,
      tls: tls,
      transport: transport,
      multiplex: multiplex,
    );
    _addExtraParams(json, extraParams);
    return json;
  }
}

/// VMess outbound.
final class VmessOutbound extends TcpBasedOutbound {
  const VmessOutbound({
    required super.server,
    required super.serverPort,
    required this.uuid,
    this.security = 'auto',
    this.alterId = 0,
    this.globalPadding = false,
    this.authenticatedLength = true,
    this.packetEncoding,
    super.network,
    super.tls,
    super.transport,
    super.multiplex,
    super.extraParams,
  });

  /// VMess user UUID — credential material.
  final String uuid;

  /// VMess cipher ('auto', 'aes-128-gcm', 'chacha20-poly1305', 'none').
  final String security;

  /// Legacy AlterID; modern servers expect 0.
  final int alterId;

  /// Global padding compatibility flag for legacy servers.
  final bool globalPadding;

  /// Authenticated length encoding; resists length-based probing.
  final bool authenticatedLength;

  /// Optional packet encoding for mux.
  final String? packetEncoding;

  @override
  ProtocolType get protocol => ProtocolType.vmess;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmessOutbound &&
          other.server == server &&
          other.serverPort == serverPort &&
          other.uuid == uuid &&
          other.security == security &&
          other.alterId == alterId &&
          other.globalPadding == globalPadding &&
          other.authenticatedLength == authenticatedLength &&
          other.packetEncoding == packetEncoding &&
          other.network == network &&
          other.tls == tls &&
          other.transport == transport &&
          other.multiplex == multiplex &&
          _mapEquals(other.extraParams, extraParams);

  @override
  int get hashCode => Object.hash(
    server,
    serverPort,
    uuid,
    security,
    alterId,
    globalPadding,
    authenticatedLength,
    packetEncoding,
    network,
    tls,
    transport,
    multiplex,
    _extraParamsHash(extraParams),
  );

  @override
  Map<String, dynamic> toJson() {
    final json = outboundJson();
    json['uuid'] = uuid;
    json['security'] = security;
    json['alter_id'] = alterId;
    json['global_padding'] = globalPadding;
    json['authenticated_length'] = authenticatedLength;
    if (packetEncoding != null) {
      json['packet_encoding'] = packetEncoding;
    }
    _addTcpFamilyFields(
      json,
      network: network,
      tls: tls,
      transport: transport,
      multiplex: multiplex,
    );
    _addExtraParams(json, extraParams);
    return json;
  }
}

/// Trojan outbound.
final class TrojanOutbound extends TcpBasedOutbound {
  const TrojanOutbound({
    required super.server,
    required super.serverPort,
    required this.password,
    super.network,
    super.tls,
    super.transport,
    super.multiplex,
    super.extraParams,
  });

  /// Trojan authentication password — credential material.
  final String password;

  @override
  ProtocolType get protocol => ProtocolType.trojan;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrojanOutbound &&
          other.server == server &&
          other.serverPort == serverPort &&
          other.password == password &&
          other.network == network &&
          other.tls == tls &&
          other.transport == transport &&
          other.multiplex == multiplex &&
          _mapEquals(other.extraParams, extraParams);

  @override
  int get hashCode => Object.hash(
    server,
    serverPort,
    password,
    network,
    tls,
    transport,
    multiplex,
    _extraParamsHash(extraParams),
  );

  @override
  Map<String, dynamic> toJson() {
    final json = outboundJson();
    json['password'] = password;
    _addTcpFamilyFields(
      json,
      network: network,
      tls: tls,
      transport: transport,
      multiplex: multiplex,
    );
    _addExtraParams(json, extraParams);
    return json;
  }
}

/// Shadowsocks outbound. Stands alone in the hierarchy (it neither fits
/// the TCP family's TLS/transport blocks nor the QUIC family's mandatory
/// TLS), mirroring the blueprint in COMPETITIVE_RESEARCH.md section 4.
final class ShadowsocksOutbound extends OutboundConfig {
  const ShadowsocksOutbound({
    required super.server,
    required super.serverPort,
    required this.method,
    required this.password,
    this.network,
    this.plugin,
    this.pluginOpts,
    this.udpOverTcp = false,
    this.multiplex,
    super.extraParams,
  });

  /// AEAD cipher method (e.g. '2022-blake3-aes-128-gcm').
  final String method;

  /// Shadowsocks password — credential material.
  final String password;

  /// Explicit network override; null lets sing-box pick its default.
  final String? network;

  /// Optional SIP003 plugin name (e.g. 'obfs-local').
  final String? plugin;

  /// Optional SIP003 plugin options string.
  final String? pluginOpts;

  /// Whether UDP traffic is relayed over the TCP stream.
  final bool udpOverTcp;

  /// Optional connection multiplexing block.
  final MultiplexSettings? multiplex;

  @override
  ProtocolType get protocol => ProtocolType.shadowsocks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShadowsocksOutbound &&
          other.server == server &&
          other.serverPort == serverPort &&
          other.method == method &&
          other.password == password &&
          other.network == network &&
          other.plugin == plugin &&
          other.pluginOpts == pluginOpts &&
          other.udpOverTcp == udpOverTcp &&
          other.multiplex == multiplex &&
          _mapEquals(other.extraParams, extraParams);

  @override
  int get hashCode => Object.hash(
    server,
    serverPort,
    method,
    password,
    network,
    plugin,
    pluginOpts,
    udpOverTcp,
    multiplex,
    _extraParamsHash(extraParams),
  );

  @override
  Map<String, dynamic> toJson() {
    final json = outboundJson();
    json['method'] = method;
    json['password'] = password;
    if (network != null) {
      json['network'] = network;
    }
    if (plugin != null) {
      json['plugin'] = plugin;
    }
    if (pluginOpts != null) {
      json['plugin_opts'] = pluginOpts;
    }
    json['udp_over_tcp'] = udpOverTcp;
    if (multiplex != null) {
      json['multiplex'] = multiplex!.toJson();
    }
    _addExtraParams(json, extraParams);
    return json;
  }
}

/// Family of outbounds that dial over QUIC/UDP. TLS is mandatory (QUIC
/// always encrypts its handshake), so [tls] is non-nullable here — a
/// compile-time guarantee that no QUIC outbound can be configured without
/// certificate settings. Sealed: only Hysteria2 and TUIC extend it.
sealed class QuicBasedOutbound extends OutboundConfig {
  const QuicBasedOutbound({
    required super.server,
    required super.serverPort,
    required this.tls,
    this.quic,
    super.extraParams,
  });

  /// Mandatory TLS block; QUIC handshakes are always encrypted.
  final TlsSettings tls;

  /// Optional QUIC tuning block.
  final QuicSettings? quic;
}

/// Hysteria2 outbound (QUIC-based).
final class Hysteria2Outbound extends QuicBasedOutbound {
  /// Creates an immutable Hysteria2 outbound.
  ///
  /// Not a `const` constructor: the obfs pairing check below is a runtime
  /// validation, and a const constructor cannot run one.
  Hysteria2Outbound({
    required super.server,
    required super.serverPort,
    required super.tls,
    required this.password,
    this.upMbps,
    this.downMbps,
    this.serverPorts,
    this.obfsType,
    this.obfsPassword,
    this.bbrProfile,
    super.quic,
    super.extraParams,
  }) {
    // Why a real `throw` and not `assert`: Dart strips `assert` entirely
    // from release builds, so a debug-only check would let a half-configured
    // obfs block reach production and be rejected (or silently misread) by
    // sing-box. This is an unconditional, loud failure — the same pattern
    // `MockVpnEngine._transitionTo` uses for its own invariant checks.
    // Emitting `{"obfs": {"type": null, "password": "..."}}` is a config
    // integrity bug that must never reach a Phase 3 sing-box JSON payload.
    if ((obfsType == null) != (obfsPassword == null)) {
      throw ArgumentError(
        'Hysteria2Outbound: obfsType and obfsPassword must both be null or '
        'both be non-null; a partially-set obfs block would serialize to an '
        'invalid sing-box config. Got obfsType=$obfsType, '
        'obfsPassword=${obfsPassword == null ? null : '<redacted>'}.',
      );
    }
  }

  /// Hysteria2 authentication password — credential material.
  final String password;

  /// Optional upload bandwidth cap in Mbps.
  final int? upMbps;

  /// Optional download bandwidth cap in Mbps.
  final int? downMbps;

  /// Optional server port-hopping ranges (e.g. ['20000:30000']).
  final List<String>? serverPorts;

  /// Optional obfuscation type (sing-box supports 'salamander').
  final String? obfsType;

  /// Optional obfuscation password — credential material.
  final String? obfsPassword;

  /// Optional bandwidth/congestion profile label (e.g. 'standard').
  final String? bbrProfile;

  @override
  ProtocolType get protocol => ProtocolType.hysteria2;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hysteria2Outbound &&
          other.server == server &&
          other.serverPort == serverPort &&
          other.password == password &&
          other.upMbps == upMbps &&
          other.downMbps == downMbps &&
          _listEquals(other.serverPorts, serverPorts) &&
          other.obfsType == obfsType &&
          other.obfsPassword == obfsPassword &&
          other.bbrProfile == bbrProfile &&
          other.tls == tls &&
          other.quic == quic &&
          _mapEquals(other.extraParams, extraParams);

  @override
  int get hashCode => Object.hash(
    server,
    serverPort,
    password,
    upMbps,
    downMbps,
    serverPorts == null ? null : Object.hashAll(serverPorts!),
    obfsType,
    obfsPassword,
    bbrProfile,
    tls,
    quic,
    _extraParamsHash(extraParams),
  );

  @override
  Map<String, dynamic> toJson() {
    final json = outboundJson();
    json['password'] = password;
    if (upMbps != null) {
      json['up_mbps'] = upMbps;
    }
    if (downMbps != null) {
      json['down_mbps'] = downMbps;
    }
    if (serverPorts != null) {
      json['server_ports'] = List<String>.of(serverPorts!);
    }
    if (obfsType != null || obfsPassword != null) {
      json['obfs'] = {'type': obfsType, 'password': obfsPassword};
    }
    if (bbrProfile != null) {
      json['bbr_profile'] = bbrProfile;
    }
    json['tls'] = tls.toJson();
    if (quic != null) {
      json['quic'] = quic!.toJson();
    }
    _addExtraParams(json, extraParams);
    return json;
  }
}

/// TUIC outbound (QUIC-based).
final class TuicOutbound extends QuicBasedOutbound {
  const TuicOutbound({
    required super.server,
    required super.serverPort,
    required super.tls,
    required this.uuid,
    required this.password,
    this.congestionControl = 'cubic',
    this.udpRelayMode,
    this.udpOverStream = false,
    this.zeroRttHandshake = false,
    this.heartbeat = const Duration(seconds: 10),
    super.quic,
    super.extraParams,
  });

  /// TUIC user UUID — credential material.
  final String uuid;

  /// TUIC authentication password — credential material.
  final String password;

  /// QUIC congestion controller ('cubic', 'bbr', 'new_renos').
  final String congestionControl;

  /// UDP relay mode ('native' or 'quic'); null keeps the server default.
  final String? udpRelayMode;

  /// Whether UDP is relayed over a QUIC stream (falls back to native).
  final bool udpOverStream;

  /// Enables a 0-RTT handshake. MUST stay false by default: 0-RTT data is
  /// replayable, and a replayed credential-bearing handshake is an active
  /// attack vector (COMPETITIVE_RESEARCH.md section 5).
  final bool zeroRttHandshake;

  /// Keepalive heartbeat interval.
  final Duration? heartbeat;

  @override
  ProtocolType get protocol => ProtocolType.tuic;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TuicOutbound &&
          other.server == server &&
          other.serverPort == serverPort &&
          other.uuid == uuid &&
          other.password == password &&
          other.congestionControl == congestionControl &&
          other.udpRelayMode == udpRelayMode &&
          other.udpOverStream == udpOverStream &&
          other.zeroRttHandshake == zeroRttHandshake &&
          other.heartbeat == heartbeat &&
          other.tls == tls &&
          other.quic == quic &&
          _mapEquals(other.extraParams, extraParams);

  @override
  int get hashCode => Object.hash(
    server,
    serverPort,
    uuid,
    password,
    congestionControl,
    udpRelayMode,
    udpOverStream,
    zeroRttHandshake,
    heartbeat,
    tls,
    quic,
    _extraParamsHash(extraParams),
  );

  @override
  Map<String, dynamic> toJson() {
    final json = outboundJson();
    json['uuid'] = uuid;
    json['password'] = password;
    json['congestion_control'] = congestionControl;
    if (udpRelayMode != null) {
      json['udp_relay_mode'] = udpRelayMode;
    }
    json['udp_over_stream'] = udpOverStream;
    json['zero_rtt_handshake'] = zeroRttHandshake;
    if (heartbeat != null) {
      json['heartbeat'] = heartbeat!.inMicroseconds;
    }
    json['tls'] = tls.toJson();
    if (quic != null) {
      json['quic'] = quic!.toJson();
    }
    _addExtraParams(json, extraParams);
    return json;
  }
}

/// WireGuard outbound.
///
/// IMPORTANT — sing-box lifecycle note (verified 2026-09-27 against
/// <https://sing-box.sagernet.org/configuration/outbound/wireguard/>):
/// the WireGuard *outbound* is marked **"Deprecated in sing-box 1.11.0"**
/// and the docs state it **"will be removed in sing-box 1.13.0"**, with a
/// Migration entry *"Migrate WireGuard outbound to endpoint"* under 1.11.0.
/// The JSON this class serializes to is therefore correct for sing-box
/// 1.10/1.11 but targets a schema scheduled for deletion. See the
/// serializer and the package README for the migration implications.
///
/// Not `const`-constructible: [localAddresses], [reserved] and
/// [dnsServers] are defensively copied into unmodifiable views so a caller
/// mutating a list afterwards cannot change a value object sitting in a
/// `Set`/`Map` with a shifting `hashCode`.
final class WireGuardOutbound extends OutboundConfig {
  /// Creates a WireGuard outbound.
  WireGuardOutbound({
    required super.server,
    required super.serverPort,
    required this.privateKey,
    required this.peerPublicKey,
    required List<String> localAddresses,
    this.presharedKey,
    List<int>? reserved,
    this.mtu,
    this.workers,
    List<String>? dnsServers,
    this.tls,
    super.extraParams,
  }) : localAddresses = List<String>.unmodifiable(localAddresses),
       reserved = reserved == null ? null : List<int>.unmodifiable(reserved),
       dnsServers = dnsServers == null
           ? null
           : List<String>.unmodifiable(dnsServers);

  /// WireGuard private key (base64) — credential material.
  final String privateKey;

  /// Peer's WireGuard public key (base64).
  final String peerPublicKey;

  /// Local interface addresses, e.g. `['10.0.0.2/32']`.
  final List<String> localAddresses;

  /// Optional pre-shared key — credential material.
  final String? presharedKey;

  /// Optional `reserved` field bytes.
  final List<int>? reserved;

  /// Optional MTU override (sing-box defaults to 1408).
  final int? mtu;

  /// Optional worker/thread count.
  final int? workers;

  /// Optional DNS servers the tunnel should use.
  final List<String>? dnsServers;

  /// Present for schema symmetry with the other outbounds. WireGuard is a
  /// raw UDP transport and does not negotiate TLS, so this is normally
  /// `null`; it exists so a caller can express a future TLS-wrapped variant
  /// without another type change.
  final TlsSettings? tls;

  @override
  ProtocolType get protocol => ProtocolType.wireguard;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WireGuardOutbound &&
          other.runtimeType == runtimeType &&
          other.server == server &&
          other.serverPort == serverPort &&
          other.privateKey == privateKey &&
          other.peerPublicKey == peerPublicKey &&
          _listEquals(other.localAddresses, localAddresses) &&
          other.presharedKey == presharedKey &&
          _listEquals(other.reserved, reserved) &&
          other.mtu == mtu &&
          other.workers == workers &&
          _listEquals(other.dnsServers, dnsServers) &&
          other.tls == tls;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    server,
    serverPort,
    privateKey,
    peerPublicKey,
    Object.hashAll(localAddresses),
    presharedKey,
    reserved == null ? null : Object.hashAll(reserved!),
    mtu,
    workers,
    dnsServers == null ? null : Object.hashAll(dnsServers!),
    tls,
  );

  @override
  Map<String, dynamic> toJson() {
    final json = outboundJson();
    json['local_address'] = localAddresses;
    json['private_key'] = privateKey;
    json['peer_public_key'] = peerPublicKey;
    if (presharedKey != null) {
      json['pre_shared_key'] = presharedKey;
    }
    if (reserved != null) {
      json['reserved'] = reserved;
    }
    if (mtu != null) {
      json['mtu'] = mtu;
    }
    if (workers != null) {
      json['workers'] = workers;
    }
    if (dnsServers != null) {
      json['dns_servers'] = dnsServers;
    }
    return json;
  }
}

/// AmneziaWG outbound: a WireGuard fork that adds junk-packet and
/// special-header obfuscation parameters.
///
/// sing-box has **no** native AmneziaWG support — its WireGuard outbound
/// schema documents none of `jc`/`jmin`/`jmax`/`s1`/`s2`/`h1`..`h4`
/// (verified 2026-09-27). The parameters are modelled here so a link can be
/// parsed and round-tripped losslessly, and are carried on [extraParams]
/// when serialized rather than being invented into the sing-box outbound
/// schema, where an unknown key would be rejected at config load.
final class AmneziaWgOutbound extends WireGuardOutbound {
  /// Creates an AmneziaWG outbound.
  AmneziaWgOutbound({
    required super.server,
    required super.serverPort,
    required super.privateKey,
    required super.peerPublicKey,
    required super.localAddresses,
    super.presharedKey,
    super.reserved,
    super.mtu,
    super.workers,
    super.dnsServers,
    super.tls,
    super.extraParams,
    this.jc,
    this.jmin,
    this.jmax,
    this.s1,
    this.s2,
    this.h1,
    this.h2,
    this.h3,
    this.h4,
  });

  /// Junk-packet count.
  final int? jc;

  /// Minimum junk-packet size.
  final int? jmin;

  /// Maximum junk-packet size.
  final int? jmax;

  /// Init packet junk prefix length.
  final int? s1;

  /// Init packet junk prefix size.
  final int? s2;

  /// Init packet magic header value (H1).
  final int? h1;

  /// Init packet magic header value (H2).
  final int? h2;

  /// Init packet magic header value (H3).
  final int? h3;

  /// Init packet magic header value (H4).
  final int? h4;

  /// The obfuscation parameters, omitting any that were not set.
  Map<String, int> get obfuscationParams => <String, int>{
    if (jc != null) 'jc': jc!,
    if (jmin != null) 'jmin': jmin!,
    if (jmax != null) 'jmax': jmax!,
    if (s1 != null) 's1': s1!,
    if (s2 != null) 's2': s2!,
    if (h1 != null) 'h1': h1!,
    if (h2 != null) 'h2': h2!,
    if (h3 != null) 'h3': h3!,
    if (h4 != null) 'h4': h4!,
  };

  @override
  ProtocolType get protocol => ProtocolType.amneziawg;

  /// Equality covers the inherited WireGuard fields **and** the nine
  /// AmneziaWG obfuscation parameters.
  ///
  /// Without this override the parent's comparison was silently used, so two
  /// outbounds that differed only in `jc`/`h1`/… compared equal — a real
  /// hazard for any deduplication or profile-diffing logic, and a latent
  /// configuration bug. The parent's `==` is reused rather than restated so
  /// the two definitions cannot drift apart; it already enforces
  /// `runtimeType` symmetry, which is what keeps an `AmneziaWgOutbound` from
  /// ever equalling a plain `WireGuardOutbound` with identical shared fields.
  @override
  bool operator ==(Object other) =>
      super == other &&
      other is AmneziaWgOutbound &&
      other.jc == jc &&
      other.jmin == jmin &&
      other.jmax == jmax &&
      other.s1 == s1 &&
      other.s2 == s2 &&
      other.h1 == h1 &&
      other.h2 == h2 &&
      other.h3 == h3 &&
      other.h4 == h4;

  @override
  int get hashCode =>
      Object.hash(super.hashCode, jc, jmin, jmax, s1, s2, h1, h2, h3, h4);

  @override
  Map<String, dynamic> toJson() {
    final json = outboundJson();
    json['local_address'] = localAddresses;
    json['private_key'] = privateKey;
    json['peer_public_key'] = peerPublicKey;
    if (presharedKey != null) {
      json['pre_shared_key'] = presharedKey;
    }
    if (reserved != null) {
      json['reserved'] = reserved;
    }
    if (mtu != null) {
      json['mtu'] = mtu;
    }
    if (workers != null) {
      json['workers'] = workers;
    }
    if (dnsServers != null) {
      json['dns_servers'] = dnsServers;
    }
    // Obfuscation parameters are deliberately NOT emitted as top-level
    // sing-box keys: the WireGuard outbound schema has no such fields, and
    // sing-box rejects unknown keys. They are namespaced under
    // `amneziawg_obfuscation` so the document round-trips without
    // pretending sing-box understands it.
    final obfuscation = obfuscationParams;
    if (obfuscation.isNotEmpty) {
      json['amneziawg_obfuscation'] = obfuscation;
    }
    return json;
  }
}
