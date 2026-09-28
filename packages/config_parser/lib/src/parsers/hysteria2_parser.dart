// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import 'uri_parsing_support.dart';

/// Obfuscation types sing-box accepts for Hysteria2 QUIC traffic.
///
/// Verified against the sing-box Hysteria2 outbound schema, which documents
/// `obfs.type` as "one of `salamander` `gecko`".
const Set<String> _supportedObfsTypes = {'salamander', 'gecko'};

/// Parses a `hy2://` or `hysteria2://` URI into a [Hysteria2Outbound].
///
/// Shape: `hy2://<auth>@<host>:<port>?<query>#<remark>`
///
/// Hysteria2 is QUIC-based, so `tls` is mandatory in the domain model and a
/// TLS block is always produced.
///
/// The auth string is credential material: it is percent-decoded but never
/// echoed into an error (SECURITY.md §2).
Result<OutboundConfig, ConfigParseError> parseHysteria2Uri(String uri) {
  final parsed = safeUriParse(uri, field: 'hysteria2 uri');
  if (parsed case Err(:final error)) {
    return Err(error);
  }
  final value = (parsed as Ok<Uri, ConfigParseError>).value;

  // Both spellings are in real use; `hy2` is the short form.
  if (value.scheme != 'hy2' && value.scheme != 'hysteria2') {
    return Err(UnsupportedSchemeError(value.scheme));
  }

  final auth = percentDecodeOrRaw(value.userInfo);
  if (auth.isEmpty) {
    return Err(MissingRequiredFieldError('auth'));
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

  // Obfuscation: both halves must be present and the type must be one
  // sing-box accepts, otherwise sing-box refuses the whole config.
  String? obfsType;
  String? obfsPassword;
  final obfs = query['obfs'];
  final obfsPass = query['obfs-password'];
  if (obfs != null && obfs.isNotEmpty) {
    final normalised = obfs.toLowerCase();
    if (!_supportedObfsTypes.contains(normalised)) {
      return Err(
        InvalidFieldValueError('obfs', 'unsupported obfuscation type'),
      );
    }
    if (obfsPass == null || obfsPass.isEmpty) {
      return Err(MissingRequiredFieldError('obfs-password'));
    }
    obfsType = normalised;
    obfsPassword = obfsPass;
  }

  // Bandwidth: providers spell these several ways.
  final upCheck = _positiveInt(
    query['upmbps'] ?? query['up_mbps'] ?? query['up'],
    'up',
  );
  if (upCheck case Err(:final error)) {
    return Err(error);
  }
  final downCheck = _positiveInt(
    query['downmbps'] ?? query['down_mbps'] ?? query['down'],
    'down',
  );
  if (downCheck case Err(:final error)) {
    return Err(error);
  }

  final sni = query['sni'];
  final alpn = query['alpn'];
  final insecure = _boolParam(query['insecure']);

  return Ok<OutboundConfig, ConfigParseError>(
    Hysteria2Outbound(
      server: host,
      serverPort: port,
      password: auth,
      upMbps: (upCheck as Ok<int?, ConfigParseError>).value,
      downMbps: (downCheck as Ok<int?, ConfigParseError>).value,
      obfsType: obfsType,
      obfsPassword: obfsPassword,
      tls: TlsSettings(
        // Hysteria2 is QUIC-over-TLS; TLS is always on.
        enabled: true,
        serverName: (sni != null && sni.isNotEmpty) ? sni : host,
        insecure: insecure,
        alpn: (alpn != null && alpn.isNotEmpty) ? alpn.split(',') : null,
      ),
    ),
  );
}

/// The user-visible label carried in the URI fragment, or `host:port`.
String parseHysteria2Remark(String uri) {
  final parsed = safeUriParse(uri, field: 'hysteria2 uri');
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

Result<int?, ConfigParseError> _positiveInt(String? raw, String field) {
  if (raw == null || raw.isEmpty) {
    return Ok<int?, ConfigParseError>(null);
  }
  final value = int.tryParse(raw);
  if (value == null || value < 0) {
    return Err<int?, ConfigParseError>(
      InvalidFieldValueError(field, 'not a non-negative integer'),
    );
  }
  return Ok<int?, ConfigParseError>(value);
}

/// Parses the many spellings of a boolean URI parameter.
bool _boolParam(String? raw) {
  if (raw == null || raw.isEmpty) {
    return false;
  }
  final value = raw.toLowerCase();
  return value == '1' || value == 'true';
}
