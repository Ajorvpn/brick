// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';

/// Reads a sing-box outbound JSON object back into a typed [OutboundConfig].
///
/// This is the inverse of `SingBoxOutboundSerializer`. It exists because a
/// user can paste a raw sing-box outbound (from a config file or a QR code)
/// and the app must understand it, not just emit it.
///
/// Coverage is deliberately bounded to the protocols this package can build
/// a faithful domain object for: shadowsocks, trojan, vmess, vless,
/// hysteria2, tuic, wireguard and amneziawg. Anything else returns
/// [UnsupportedProtocolError] rather than a lossy approximation.
///
/// Field names follow the sing-box documentation verified in P2-T3/P2-T5.
Result<OutboundConfig, ConfigParseError> readSingBoxOutboundJson(
  Map<String, dynamic> json,
) {
  final type = json['type'];
  if (type is! String || type.isEmpty) {
    return Err(InvalidSyntaxError('outbound', 'missing "type"'));
  }

  // Reject an unknown type BEFORE validating shared fields, so the caller
  // gets the accurate reason ("this protocol is not supported") rather than
  // a misleading "missing server_port".
  const supported = {
    'shadowsocks',
    'trojan',
    'vmess',
    'vless',
    'hysteria2',
    'tuic',
    'wireguard',
  };
  if (!supported.contains(type)) {
    return Err(UnsupportedProtocolError(type));
  }

  final server = json['server'];
  if (server is! String || server.isEmpty) {
    return Err(MissingRequiredFieldError('server'));
  }
  final port = json['server_port'];
  if (port is! int) {
    return Err(MissingRequiredFieldError('server_port'));
  }

  return switch (type) {
    'shadowsocks' => _shadowsocks(json, server, port),
    'trojan' => _trojan(json, server, port),
    'vmess' => _vmess(json, server, port),
    'vless' => _vless(json, server, port),
    'hysteria2' => _hysteria2(json, server, port),
    'tuic' => _tuic(json, server, port),
    'wireguard' => _wireguard(json, server, port),
    // Unreachable: `type` is validated against `supported` above.
    _ => Err(UnsupportedProtocolError(type)),
  };
}

Result<OutboundConfig, ConfigParseError> _shadowsocks(
  Map<String, dynamic> json,
  String server,
  int port,
) {
  final method = json['method'];
  final password = json['password'];
  if (method is! String || method.isEmpty) {
    return Err(MissingRequiredFieldError('method'));
  }
  if (password is! String || password.isEmpty) {
    return Err(MissingRequiredFieldError('password'));
  }
  final plugin = json['plugin'];
  final pluginOpts = json['plugin_opts'];
  return Ok<OutboundConfig, ConfigParseError>(
    ShadowsocksOutbound(
      server: server,
      serverPort: port,
      method: method,
      password: password,
      plugin: (plugin is String && plugin.isNotEmpty) ? plugin : null,
      pluginOpts: (pluginOpts is String && pluginOpts.isNotEmpty)
          ? pluginOpts
          : null,
      udpOverTcp: json['udp_over_tcp'] == true,
    ),
  );
}

Result<OutboundConfig, ConfigParseError> _trojan(
  Map<String, dynamic> json,
  String server,
  int port,
) {
  final password = json['password'];
  if (password is! String || password.isEmpty) {
    return Err(MissingRequiredFieldError('password'));
  }
  return Ok<OutboundConfig, ConfigParseError>(
    TrojanOutbound(
      server: server,
      serverPort: port,
      password: password,
      tls: _tls(json),
    ),
  );
}

Result<OutboundConfig, ConfigParseError> _vmess(
  Map<String, dynamic> json,
  String server,
  int port,
) {
  final uuid = json['uuid'];
  if (uuid is! String || uuid.isEmpty) {
    return Err(MissingRequiredFieldError('uuid'));
  }
  final security = json['security'];
  final alterId = json['alter_id'];
  return Ok<OutboundConfig, ConfigParseError>(
    VmessOutbound(
      server: server,
      serverPort: port,
      uuid: uuid,
      security: (security is String && security.isNotEmpty) ? security : 'auto',
      alterId: (alterId is int) ? alterId : 0,
      tls: _tls(json),
    ),
  );
}

Result<OutboundConfig, ConfigParseError> _vless(
  Map<String, dynamic> json,
  String server,
  int port,
) {
  final uuid = json['uuid'];
  if (uuid is! String || uuid.isEmpty) {
    return Err(MissingRequiredFieldError('uuid'));
  }
  final flow = json['flow'];
  final packetEncoding = json['packet_encoding'];
  return Ok<OutboundConfig, ConfigParseError>(
    VlessOutbound(
      server: server,
      serverPort: port,
      uuid: uuid,
      flow: (flow is String && flow.isNotEmpty) ? flow : null,
      packetEncoding: (packetEncoding is String && packetEncoding.isNotEmpty)
          ? packetEncoding
          : null,
      tls: _tls(json),
    ),
  );
}

Result<OutboundConfig, ConfigParseError> _hysteria2(
  Map<String, dynamic> json,
  String server,
  int port,
) {
  final password = json['password'];
  if (password is! String || password.isEmpty) {
    return Err(MissingRequiredFieldError('password'));
  }
  final obfs = json['obfs'];
  final obfsType = (obfs is Map) ? obfs['type'] : null;
  final obfsPassword = (obfs is Map) ? obfs['password'] : null;
  final up = json['up_mbps'];
  final down = json['down_mbps'];
  return Ok<OutboundConfig, ConfigParseError>(
    Hysteria2Outbound(
      server: server,
      serverPort: port,
      password: password,
      upMbps: (up is int) ? up : null,
      downMbps: (down is int) ? down : null,
      obfsType: (obfsType is String && obfsType.isNotEmpty) ? obfsType : null,
      obfsPassword: (obfsPassword is String && obfsPassword.isNotEmpty)
          ? obfsPassword
          : null,
      // Hysteria2/TUIC require a non-null TLS block in the domain model.
      tls:
          _tls(json, defaultEnabled: true, fallbackServerName: server) ??
          TlsSettings(enabled: true, serverName: server),
    ),
  );
}

Result<OutboundConfig, ConfigParseError> _tuic(
  Map<String, dynamic> json,
  String server,
  int port,
) {
  final uuid = json['uuid'];
  final password = json['password'];
  if (uuid is! String || uuid.isEmpty) {
    return Err(MissingRequiredFieldError('uuid'));
  }
  if (password is! String || password.isEmpty) {
    return Err(MissingRequiredFieldError('password'));
  }
  final congestion = json['congestion_control'];
  final udpRelayMode = json['udp_relay_mode'];
  return Ok<OutboundConfig, ConfigParseError>(
    TuicOutbound(
      server: server,
      serverPort: port,
      uuid: uuid,
      password: password,
      congestionControl:
          (congestion is String && congestion.isNotEmpty) ? congestion : 'cubic',
      udpRelayMode: (udpRelayMode is String && udpRelayMode.isNotEmpty)
          ? udpRelayMode
          : null,
      udpOverStream: json['udp_over_stream'] == true,
      zeroRttHandshake: json['zero_rtt_handshake'] == true,
      // Hysteria2/TUIC require a non-null TLS block in the domain model.
      tls:
          _tls(json, defaultEnabled: true, fallbackServerName: server) ??
          TlsSettings(enabled: true, serverName: server),
    ),
  );
}

Result<OutboundConfig, ConfigParseError> _wireguard(
  Map<String, dynamic> json,
  String server,
  int port,
) {
  final privateKey = json['private_key'];
  if (privateKey is! String || privateKey.isEmpty) {
    return Err(MissingRequiredFieldError('private_key'));
  }
  final peerPublicKey = json['peer_public_key'];
  if (peerPublicKey is! String || peerPublicKey.isEmpty) {
    return Err(MissingRequiredFieldError('peer_public_key'));
  }
  final localAddress = json['local_address'];
  if (localAddress is! List || localAddress.isEmpty) {
    return Err(MissingRequiredFieldError('local_address'));
  }
  final addresses = localAddress
      .map((e) => e.toString())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
  if (addresses.isEmpty) {
    return Err(InvalidFieldValueError('local_address', 'no usable address'));
  }

  final reserved = json['reserved'];
  List<int>? reservedBytes;
  if (reserved is List) {
    reservedBytes = reserved.map((e) => e is int ? e : 0).toList(growable: false);
  }
  final preShared = json['pre_shared_key'];
  final mtu = json['mtu'];
  final workers = json['workers'];

  // AmneziaWG obfuscation is namespaced by our own serializer (sing-box has
  // no such schema); recover it when present.
  final obfuscation = json['amneziawg_obfuscation'];
  if (obfuscation is Map && obfuscation.isNotEmpty) {
    int? v(String k) {
      final raw = obfuscation[k];
      return raw is int ? raw : null;
    }

    return Ok<OutboundConfig, ConfigParseError>(
      AmneziaWgOutbound(
        server: server,
        serverPort: port,
        privateKey: privateKey,
        peerPublicKey: peerPublicKey,
        localAddresses: addresses,
        presharedKey: (preShared is String && preShared.isNotEmpty)
            ? preShared
            : null,
        reserved: reservedBytes,
        mtu: (mtu is int) ? mtu : null,
        workers: (workers is int) ? workers : null,
        jc: v('jc'),
        jmin: v('jmin'),
        jmax: v('jmax'),
        s1: v('s1'),
        s2: v('s2'),
        h1: v('h1'),
        h2: v('h2'),
        h3: v('h3'),
        h4: v('h4'),
      ),
    );
  }

  return Ok<OutboundConfig, ConfigParseError>(
    WireGuardOutbound(
      server: server,
      serverPort: port,
      privateKey: privateKey,
      peerPublicKey: peerPublicKey,
      localAddresses: addresses,
      presharedKey: (preShared is String && preShared.isNotEmpty)
          ? preShared
          : null,
      reserved: reservedBytes,
      mtu: (mtu is int) ? mtu : null,
      workers: (workers is int) ? workers : null,
    ),
  );
}

/// Reads a sing-box `tls` object, if present.
///
/// `fallbackServerName` is used for QUIC protocols (Hysteria2/TUIC), whose
/// TLS block is mandatory and whose SNI conventionally defaults to the host.
TlsSettings? _tls(
  Map<String, dynamic> json, {
  bool defaultEnabled = false,
  String? fallbackServerName,
}) {
  final tls = json['tls'];
  if (tls is! Map) {
    return defaultEnabled
        ? TlsSettings(enabled: true, serverName: fallbackServerName)
        : null;
  }
  final alpn = tls['alpn'];
  final reality = tls['reality'];
  return TlsSettings(
    enabled: tls['enabled'] == true || defaultEnabled,
    serverName: (tls['server_name'] is String && (tls['server_name'] as String).isNotEmpty)
        ? tls['server_name'] as String
        : fallbackServerName,
    insecure: tls['insecure'] == true,
    alpn: (alpn is List) ? alpn.map((e) => e.toString()).toList() : null,
    utls: (tls['utls'] is Map && (tls['utls'] as Map)['fingerprint'] is String)
        ? UtlsSettings(
            enabled: true,
            fingerprint: (tls['utls'] as Map)['fingerprint'] as String,
          )
        : null,
    reality: (reality is Map &&
            (reality['public_key'] is String) &&
            (reality['short_id'] is String))
        ? RealitySettings(
            enabled: reality['enabled'] != false,
            publicKey: reality['public_key'] as String,
            shortId: reality['short_id'] as String,
          )
        : null,
  );
}
