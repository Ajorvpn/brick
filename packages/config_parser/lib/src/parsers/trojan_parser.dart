// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import 'uri_parsing_support.dart';

/// Parses a `trojan://` URI into a [TrojanOutbound].
///
/// Shape: `trojan://<password>@<host>:<port>?<query>#<remark>`
///
/// The password is percent-encoded in the wild, so it is decoded before use
/// and never echoed into an error (SECURITY.md §2 — the Trojan password is
/// credential material).
Result<OutboundConfig, ConfigParseError> parseTrojanUri(String uri) {
  final parsed = safeUriParse(uri, field: 'trojan uri');
  if (parsed case Err(:final error)) {
    return Err(error);
  }
  final value = (parsed as Ok<Uri, ConfigParseError>).value;

  if (value.scheme != 'trojan') {
    return Err(UnsupportedSchemeError(value.scheme));
  }

  final rawUserInfo = value.userInfo;
  if (rawUserInfo.isEmpty) {
    return Err(MissingRequiredFieldError('password'));
  }
  final password = _percentDecode(rawUserInfo.split(':').first);
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

  final query = value.queryParameters;
  final transport = buildTransportSettings(query);
  if (transport case Err(:final error)) {
    return Err(error);
  }

  // Trojan is TLS by default in every real deployment: an absent or
  // explicitly 'none' security still yields no TLS block, but a 'tls' value
  // does.
  final security = (query['security'] ?? '').toLowerCase();
  final tlsQuery = <String, String>{
    ...query,
    if (security.isEmpty) 'security': 'tls',
  };

  return Ok<OutboundConfig, ConfigParseError>(
    TrojanOutbound(
      server: host,
      serverPort: port,
      password: password,
      network: _networkFor(query),
      tls: buildTlsSettings(tlsQuery),
      transport: (transport as Ok<TransportSettings?, ConfigParseError>).value,
    ),
  );
}

/// The user-visible label carried in the URI fragment, or `host:port`.
String parseTrojanRemark(String uri) {
  final parsed = safeUriParse(uri, field: 'trojan uri');
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

/// Resolves the sing-box L4 `network` value (see ARCHITECTURE.md Phase 2).
///
/// `network` in sing-box selects the **layer-4** network ("tcp" or "udp") —
/// it is NOT the V2Ray transport. The transport (ws / grpc / httpupgrade)
/// belongs in `transport.type`. Populating `network` with a transport name
/// produces config sing-box rejects.
///
/// Returns null when the link does not pin an L4 network, which is
/// deliberate: per the sing-box schema, omitting `network` enables BOTH
/// tcp and udp. Defaulting to the literal "tcp" here would silently disable
/// UDP for every parsed server.
String? _networkFor(Map<String, String> query) {
  final network = query['network']?.toLowerCase();
  return (network == 'tcp' || network == 'udp') ? network : null;
}

String _percentDecode(String input) {
  try {
    return Uri.decodeComponent(input);
  } on ArgumentError {
    return input;
  }
}
