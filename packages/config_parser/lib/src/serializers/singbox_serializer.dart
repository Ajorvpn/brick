// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';

/// Serializes a typed [OutboundConfig] into a sing-box 1.10+ outbound JSON
/// object.
///
/// ## Source of truth
///
/// Field names and accepted values below were taken from the official
/// sing-box documentation (https://sing-box.sagernet.org), not from training
/// data, per the Phase 2 format-research caveat in `ROADMAP.md`. The
/// verified references are:
///
///  * Outbound VLESS / VMess / Trojan / Shadowsocks pages.
///  * Shared "V2Ray Transport" page (transport `type` values and fields).
///  * Shared "TLS" page (TLS, uTLS and REALITY fields).
///
/// ## Two schema facts worth stating explicitly
///
/// 1. **`network` is NOT the V2Ray transport type.** In sing-box, `network`
///    selects the L4 network (`"tcp"` or `"udp"`); enabling *both* is the
///    default when the key is absent. The V2Ray transport (ws / grpc /
///    httpupgrade) lives under `transport.type`. Emitting
///    `network: "ws"` would be rejected by sing-box, so this serializer
///    only emits `network` when the domain value is a genuine L4 value and
///    otherwise omits the key.
/// 2. **The transport type is `httpupgrade`, not `splithttp`.** `splithttp`
///    is the Xray/v2rayN link spelling; sing-box names the same transport
///    `httpupgrade`. The URI parser accepts both and this serializer emits
///    the sing-box spelling.
class SingBoxOutboundSerializer {
  const SingBoxOutboundSerializer();

  /// Builds the sing-box outbound object for [config].
  ///
  /// Throws [UnsupportedError] for a protocol this serializer does not yet
  /// implement (currently the QUIC-based family, hysteria2 and tuic). Use
  /// [tryBuild] for a non-throwing `Result`-based alternative.
  Map<String, dynamic> build(OutboundConfig config, {String? tag}) {
    final result = tryBuild(config, tag: tag);
    if (result case Err(:final error)) {
      throw UnsupportedError(error.message);
    }
    return (result as Ok<Map<String, dynamic>, ConfigParseError>).value;
  }

  /// Non-throwing variant of [build].
  ///
  /// Returns `Err(UnsupportedProtocolError)` for a protocol that is not
  /// implemented yet, so callers that parse a mixed subscription can skip
  /// the entries they cannot represent instead of crashing.
  Result<Map<String, dynamic>, ConfigParseError> tryBuild(
    OutboundConfig config, {
    String? tag,
  }) {
    final Map<String, dynamic> map;
    switch (config) {
      case VlessOutbound():
        map = _vless(config);
      case VmessOutbound():
        map = _vmess(config);
      case TrojanOutbound():
        map = _trojan(config);
      case ShadowsocksOutbound():
        map = _shadowsocks(config);
      case Hysteria2Outbound():
        map = _hysteria2(config);
      case TuicOutbound():
        map = _tuic(config);
      // AmneziaWgOutbound extends WireGuardOutbound, so the WireGuard
      // pattern below also matches it; that is intentional.
      case WireGuardOutbound():
        map = _wireGuard(config);
    }

    final out = <String, dynamic>{'type': config.protocol.name};
    if (tag != null && tag.isNotEmpty) {
      out['tag'] = tag;
    }
    out.addAll(map);
    return Ok<Map<String, dynamic>, ConfigParseError>(out);
  }

  Map<String, dynamic> _vless(VlessOutbound c) => <String, dynamic>{
    'server': c.server,
    'server_port': c.serverPort,
    'uuid': c.uuid,
    if (c.flow != null) 'flow': c.flow,
    if (c.packetEncoding != null) 'packet_encoding': c.packetEncoding,
    ..._shared(c),
  };

  Map<String, dynamic> _vmess(VmessOutbound c) => <String, dynamic>{
    'server': c.server,
    'server_port': c.serverPort,
    'uuid': c.uuid,
    'security': c.security,
    'alter_id': c.alterId,
    'global_padding': c.globalPadding,
    'authenticated_length': c.authenticatedLength,
    if (c.packetEncoding != null) 'packet_encoding': c.packetEncoding,
    ..._shared(c),
  };

  Map<String, dynamic> _trojan(TrojanOutbound c) => <String, dynamic>{
    'server': c.server,
    'server_port': c.serverPort,
    'password': c.password,
    ..._shared(c),
  };

  Map<String, dynamic> _shadowsocks(ShadowsocksOutbound c) => <String, dynamic>{
    'server': c.server,
    'server_port': c.serverPort,
    'method': c.method,
    'password': c.password,
    if (c.plugin != null) 'plugin': c.plugin,
    if (c.pluginOpts != null) 'plugin_opts': c.pluginOpts,
    if (c.udpOverTcp) 'udp_over_tcp': c.udpOverTcp,
    ..._network(c.network),
    ..._multiplex(c.multiplex),
  };

  /// Sing-Box `type` for a WireGuard outbound.
  ///
  /// sing-box deprecated the WireGuard *outbound* in 1.11.0 and documents
  /// removal in 1.13.0 (Migration: "Migrate WireGuard outbound to
  /// endpoint"). The JSON below is correct for the 1.10/1.11 schema, which
  /// is the schema this client targets today.
  static const String wireGuardType = 'wireguard';

  Map<String, dynamic> _wireGuard(WireGuardOutbound c) => <String, dynamic>{
    'type': wireGuardType,
    'server': c.server,
    'server_port': c.serverPort,
    // App-level TUN is how a mobile client runs a tunnel; the system
    // interface path requires privileges a phone app does not have.
    'system_interface': false,
    'local_address': c.localAddresses,
    'private_key': c.privateKey,
    'peer_public_key': c.peerPublicKey,
    if (c.presharedKey != null) 'pre_shared_key': c.presharedKey,
    if (c.reserved != null) 'reserved': c.reserved,
    if (c.mtu != null) 'mtu': c.mtu,
    if (c.workers != null) 'workers': c.workers,
  };

  Map<String, dynamic> _hysteria2(Hysteria2Outbound c) => <String, dynamic>{
    'server': c.server,
    'server_port': c.serverPort,
    'password': c.password,
    if (c.upMbps != null) 'up_mbps': c.upMbps,
    if (c.downMbps != null) 'down_mbps': c.downMbps,
    // obfs is only emitted as a complete pair: sing-box requires the
    // password whenever a type is set, and a half-configured obfs block
    // makes it reject the whole outbound.
    if (c.obfsType != null && c.obfsPassword != null)
      'obfs': <String, dynamic>{'type': c.obfsType, 'password': c.obfsPassword},
    ..._tlsWithExtras(c.tls, c.extraParams),
  };

  Map<String, dynamic> _tuic(TuicOutbound c) => <String, dynamic>{
    'server': c.server,
    'server_port': c.serverPort,
    'uuid': c.uuid,
    'password': c.password,
    'congestion_control': c.congestionControl,
    if (c.udpRelayMode != null) 'udp_relay_mode': c.udpRelayMode,
    if (c.udpOverStream) 'udp_over_stream': c.udpOverStream,
    if (c.zeroRttHandshake) 'zero_rtt_handshake': c.zeroRttHandshake,
    ..._tlsWithExtras(c.tls, c.extraParams),
  };

  /// Fields shared by every TCP-based outbound.
  Map<String, dynamic> _shared(TcpBasedOutbound c) => <String, dynamic>{
    ..._network(c.network),
    if (c.tls != null) 'tls': _tls(c.tls!),
    if (c.transport != null) 'transport': _transport(c.transport!),
    ..._multiplex(c.multiplex),
  };

  /// `network` selects the L4 network in sing-box ("tcp" / "udp"). Anything
  /// else in the domain field is a transport name mis-stored by a URI
  /// parser, and emitting it would be invalid, so it is omitted and sing-box
  /// applies its default (both networks enabled).
  Map<String, dynamic> _network(String? network) {
    if (network == 'tcp' || network == 'udp') {
      return <String, dynamic>{'network': network};
    }
    return const <String, dynamic>{};
  }

  /// Emits the `tls` object, then merges any schema keys a parser parked in
  /// [extraParams] (currently only `disable_sni`, which has no field on the
  /// domain `TlsSettings` type yet).
  Map<String, dynamic> _tlsWithExtras(
    TlsSettings tls,
    Map<String, dynamic>? extraParams,
  ) => <String, dynamic>{
    'tls': <String, dynamic>{
      ..._tls(tls),
      if (extraParams != null) ...extraParams,
    },
  };

  Map<String, dynamic> _tls(TlsSettings tls) => <String, dynamic>{
    'enabled': tls.enabled,
    if (tls.serverName != null) 'server_name': tls.serverName,
    if (tls.insecure) 'insecure': tls.insecure,
    if (tls.alpn != null && tls.alpn!.isNotEmpty) 'alpn': tls.alpn,
    if (tls.minVersion != null) 'min_version': tls.minVersion,
    if (tls.maxVersion != null) 'max_version': tls.maxVersion,
    if (tls.utls != null)
      'utls': <String, dynamic>{
        'enabled': tls.utls!.enabled,
        'fingerprint': tls.utls!.fingerprint,
      },
    if (tls.reality != null)
      'reality': <String, dynamic>{
        'enabled': tls.reality!.enabled,
        'public_key': tls.reality!.publicKey,
        'short_id': tls.reality!.shortId,
        if (tls.reality!.spiderX != null) 'spider_x': tls.reality!.spiderX,
      },
  };

  Map<String, dynamic> _transport(TransportSettings transport) =>
      switch (transport) {
        WebSocketTransport(:final path, :final headers) => <String, dynamic>{
          'type': 'ws',
          'path': path,
          if (headers != null && headers.isNotEmpty) 'headers': headers,
        },
        GrpcTransport(:final serviceName) => <String, dynamic>{
          'type': 'grpc',
          'service_name': serviceName,
        },
        HttpTransport(
          :final host,
          :final path,
          :final method,
          :final headers,
        ) =>
          <String, dynamic>{
            'type': 'http',
            if (host != null && host.isNotEmpty) 'host': host,
            if (path != null) 'path': path,
            if (method != null) 'method': method,
            if (headers != null && headers.isNotEmpty) 'headers': headers,
          },
        // sing-box spells the Xray "splithttp" transport "httpupgrade".
        HttpUpgradeTransport(:final host, :final path) => <String, dynamic>{
          'type': 'httpupgrade',
          if (host != null && host.isNotEmpty) 'host': host,
          if (path != null) 'path': path,
        },
      };

  Map<String, dynamic> _multiplex(MultiplexSettings? mux) {
    if (mux == null || !mux.enabled) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{
      'multiplex': <String, dynamic>{
        'enabled': true,
        if (mux.protocol != null) 'protocol': mux.protocol,
        if (mux.maxConnections != null) 'max_connections': mux.maxConnections,
        if (mux.minStreams != null) 'min_streams': mux.minStreams,
        if (mux.maxStreams != null) 'max_streams': mux.maxStreams,
        if (mux.padding != null) 'padding': mux.padding,
      },
    };
  }
}

/// Builds the sing-box 1.10+ outbound JSON for [config].
///
/// Throws [UnsupportedError] for a protocol with no serializer yet; use
/// [SingBoxOutboundSerializer.tryBuild] for a `Result`-based call site.
Map<String, dynamic> buildSingBoxOutbound(
  OutboundConfig config, {
  String? tag,
}) => const SingBoxOutboundSerializer().build(config, tag: tag);
