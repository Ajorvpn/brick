// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import 'uri_parsing_support.dart';

/// Parses a `vless://` URI into a [VlessOutbound].
///
/// Shape: `vless://<uuid>@<host>:<port>?<query>#<remark>`
///
/// Pure and deterministic: no clock, no randomness, no I/O. The remark is
/// parsed for the caller's benefit but is NOT stored on the outbound —
/// `OutboundConfig` has no remark field, so it is surfaced by [parseVlessUri]
/// only through the returned config's server identity. Use
/// `parseVlessRemark` if the label is needed separately.
///
/// Every failure path returns a [ConfigParseError]; this function never
/// throws for malformed input (SECURITY.md §5 untrusted-input handling).
Result<OutboundConfig, ConfigParseError> parseVlessUri(String uri) {
  final parsed = safeUriParse(uri, field: 'vless uri');
  if (parsed case Err(:final error)) {
    return Err(error);
  }
  final value = (parsed as Ok<Uri, ConfigParseError>).value;

  if (value.scheme != 'vless') {
    return Err(UnsupportedSchemeError(value.scheme));
  }

  // The userinfo component carries the UUID.
  final userInfo = value.userInfo;
  if (userInfo.isEmpty) {
    return Err(MissingRequiredFieldError('uuid'));
  }
  // A UUID never contains a password; `uuid:pass@` is a malformed link.
  final uuid = userInfo.split(':').first;
  final uuidCheck = validateUuid(uuid, 'uuid');
  if (uuidCheck case Err(:final error)) {
    return Err(error);
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

  return Ok<OutboundConfig, ConfigParseError>(
    VlessOutbound(
      server: host,
      serverPort: port,
      uuid: uuid,
      flow: readFlow(query),
      network: _networkFor(query),
      tls: buildTlsSettings(query),
      transport: (transport as Ok<TransportSettings?, ConfigParseError>).value,
    ),
  );
}

/// The user-visible label carried in the URI fragment, or a `host:port`
/// fallback when the link has no `#remark`.
String parseVlessRemark(String uri) {
  final parsed = safeUriParse(uri, field: 'vless uri');
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

/// The `network` string sing-box expects, or null to use its own default.
String? _networkFor(Map<String, String> query) {
  final type = query['type'];
  if (type == null || type.isEmpty || type.toLowerCase() == 'tcp') {
    return null;
  }
  return type.toLowerCase();
}
