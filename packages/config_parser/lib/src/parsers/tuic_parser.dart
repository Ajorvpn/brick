// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import 'uri_parsing_support.dart';

/// Congestion-control algorithms sing-box accepts for TUIC.
///
/// Verified against the sing-box TUIC outbound schema: "One of `cubic`,
/// `new_reno`, `bbr`".
const Set<String> _supportedCongestionControl = {'cubic', 'new_reno', 'bbr'};

/// UDP relay modes sing-box accepts for TUIC.
const Set<String> _supportedUdpRelayMode = {'native', 'quic'};

/// Parses a `tuic://` URI into a [TuicOutbound].
///
/// Shape: `tuic://<uuid>:<password>@<host>:<port>?<query>#<remark>`
///
/// TUIC is QUIC-based, so `tls` is mandatory in the domain model and a TLS
/// block is always produced.
///
/// Both the UUID and the password are credential material: neither is ever
/// echoed into an error (SECURITY.md §2).
Result<OutboundConfig, ConfigParseError> parseTuicUri(String uri) {
  final parsed = safeUriParse(uri, field: 'tuic uri');
  if (parsed case Err(:final error)) {
    return Err(error);
  }
  final value = (parsed as Ok<Uri, ConfigParseError>).value;

  if (value.scheme != 'tuic') {
    return Err(UnsupportedSchemeError(value.scheme));
  }

  // userinfo is `uuid:password`. A TUIC link without the password half is
  // malformed, so the separator must be present.
  final userInfo = value.userInfo;
  if (userInfo.isEmpty) {
    return Err(MissingRequiredFieldError('uuid'));
  }
  final separator = userInfo.indexOf(':');
  if (separator == -1) {
    return Err(InvalidSyntaxError('tuic userinfo', 'expected uuid:password'));
  }
  final uuid = percentDecodeOrRaw(userInfo.substring(0, separator));
  final password = percentDecodeOrRaw(userInfo.substring(separator + 1));

  final uuidCheck = validateUuid(uuid, 'uuid');
  if (uuidCheck case Err(:final error)) {
    return Err(error);
  }
  if (password.isEmpty) {
    return Err(MissingRequiredFieldError('password'));
  }

  final host = value.host;
  if (host.isEmpty) {
    return Err(MissingRequiredFieldError('server'));
  }
  final hostCheck = validateHost(host, 'server');
  if (hostCheck case Err(:final error)) {
    return Err(error);
  }

  if (!value.hasPort) {
    return Err(MissingRequiredFieldError('port'));
  }
  final portCheck = parsePort('${value.port}', 'port');
  if (portCheck case Err(:final error)) {
    return Err(error);
  }
  final port = (portCheck as Ok<int, ConfigParseError>).value;

  final query = safeQueryParameters(value);

  final congestionRaw = query['congestion_control'];
  var congestionControl = 'cubic';
  if (congestionRaw != null && congestionRaw.isNotEmpty) {
    final normalised = congestionRaw.toLowerCase();
    if (!_supportedCongestionControl.contains(normalised)) {
      return Err(
        InvalidFieldValueError('congestion_control', 'unsupported algorithm'),
      );
    }
    congestionControl = normalised;
  }

  final udpRelayRaw = query['udp_relay_mode'];
  String? udpRelayMode;
  if (udpRelayRaw != null && udpRelayRaw.isNotEmpty) {
    final normalised = udpRelayRaw.toLowerCase();
    if (!_supportedUdpRelayMode.contains(normalised)) {
      return Err(
        InvalidFieldValueError('udp_relay_mode', 'unsupported relay mode'),
      );
    }
    udpRelayMode = normalised;
  }

  // sing-box states udp_relay_mode and udp_over_stream conflict, so the
  // legacy flag is only honoured when no explicit relay mode was given.
  final udpOverStream =
      udpRelayMode == null && _boolParam(query['udp_over_stream']);

  final sni = query['sni'];
  final alpn = query['alpn'];
  final disableSni = _boolParam(query['disable_sni']);

  return Ok<OutboundConfig, ConfigParseError>(
    TuicOutbound(
      server: host,
      serverPort: port,
      uuid: uuid,
      password: password,
      congestionControl: congestionControl,
      udpRelayMode: udpRelayMode,
      udpOverStream: udpOverStream,
      zeroRttHandshake: _boolParam(query['zero_rtt_handshake']),
      tls: TlsSettings(
        // TUIC is QUIC-over-TLS; TLS is always on.
        enabled: true,
        serverName: (sni != null && sni.isNotEmpty) ? sni : host,
        alpn: (alpn != null && alpn.isNotEmpty) ? alpn.split(',') : null,
      ),
      // `disable_sni` exists in the sing-box TLS schema but has no field on
      // the domain `TlsSettings` type. `core_domain` is frozen for this task,
      // so the flag is carried through `extraParams` rather than dropped;
      // the serializer emits it when present. A follow-up should add a real
      // `disableSni` field to `TlsSettings`.
      extraParams: disableSni ? <String, dynamic>{'disable_sni': true} : null,
    ),
  );
}

/// The user-visible label carried in the URI fragment, or `host:port`.
String parseTuicRemark(String uri) {
  final parsed = safeUriParse(uri, field: 'tuic uri');
  if (parsed is Err) {
    return '';
  }
  final value = (parsed as Ok<Uri, ConfigParseError>).value;
  final remark = decodeRemark(value);
  if (remark.isNotEmpty) {
    return remark;
  }
  return value.hasPort ? '${value.host}:${value.port}' : value.host;
}

bool _boolParam(String? raw) {
  if (raw == null || raw.isEmpty) {
    return false;
  }
  final value = raw.toLowerCase();
  return value == '1' || value == 'true';
}
