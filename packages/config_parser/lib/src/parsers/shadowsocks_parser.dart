// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import 'uri_parsing_support.dart';

/// Ciphers sing-box's Shadowsocks outbound accepts in its `method` field.
///
/// Verified against the official sing-box Shadowsocks outbound
/// documentation (<https://sing-box.sagernet.org/configuration/outbound/shadowsocks/>)
/// on 2026-09-27, which lists:
///
/// "Encryption methods: 2022-blake3-aes-128-gcm 2022-blake3-aes-256-gcm
/// 2022-blake3-chacha20-poly1305 none aes-128-gcm aes-192-gcm aes-256-gcm
/// chacha20-ietf-poly1305 xchacha20-ietf-poly1305"
///
/// and, separately:
///
/// "Legacy encryption methods: aes-128-ctr aes-192-ctr aes-256-ctr aes-128-cfb
/// aes-192-cfb aes-256-cfb rc4-md5 chacha20-ietf xchacha20"
///
/// A link naming anything else cannot be dialled by this client, so it is
/// rejected with [UnsupportedCipherError] rather than silently accepted and
/// failing later inside sing-box with an opaque error.
const Set<String> supportedCiphers = {
  // Current AEAD (incl. the 2022-blake3 family).
  '2022-blake3-aes-128-gcm',
  '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305',
  'none',
  'aes-128-gcm',
  'aes-192-gcm',
  'aes-256-gcm',
  'chacha20-ietf-poly1305',
  'xchacha20-ietf-poly1305',
  // Legacy, still accepted by sing-box.
  'aes-128-ctr',
  'aes-192-ctr',
  'aes-256-ctr',
  'aes-128-cfb',
  'aes-192-cfb',
  'aes-256-cfb',
  'rc4-md5',
  'chacha20-ietf',
  'xchacha20',
};

/// Validates [method] against [supportedCiphers].
///
/// Matching is case-insensitive because providers are inconsistent about
/// casing, but the value is otherwise taken verbatim.
Result<String, ConfigParseError> validateCipher(String method) {
  final normalised = method.toLowerCase();
  if (!supportedCiphers.contains(normalised)) {
    return Err(UnsupportedCipherError(normalised));
  }
  return Ok<String, ConfigParseError>(normalised);
}

/// Parses an `ss://` link into a [ShadowsocksOutbound].
///
/// Supports both forms still seen in the wild:
///
///  * **SIP002** — `ss://<base64(method:password)>@host:port#remark`
///    (equivalently `ss://method:password@host:port`, where the userinfo is
///    NOT base64).
///  * **Legacy** — `ss://<base64(method:password@host:port)>#remark`
///
/// Pure and deterministic; the password is never echoed into an error.
Result<OutboundConfig, ConfigParseError> parseShadowsocksUri(String uri) {
  final prefix = 'ss://';
  if (!uri.startsWith(prefix)) {
    final scheme = uri.contains('://') ? uri.split('://').first : '';
    return Err(UnsupportedSchemeError(scheme));
  }

  // Strip the fragment (remark) before doing anything else.
  var body = uri.substring(prefix.length);
  final hashIndex = body.indexOf('#');
  if (hashIndex != -1) {
    body = body.substring(0, hashIndex);
  }
  // Query parameters (plugin=..., etc.) are separated by '?'.
  final queryIndex = body.indexOf('?');
  final query = <String, String>{};
  if (queryIndex != -1) {
    final queryString = body.substring(queryIndex + 1);
    body = body.substring(0, queryIndex);
    for (final pair in queryString.split('&')) {
      if (pair.isEmpty) {
        continue;
      }
      final eq = pair.indexOf('=');
      if (eq == -1) {
        query[percentDecodeOrRaw(pair)] = '';
      } else {
        query[percentDecodeOrRaw(pair.substring(0, eq))] = percentDecodeOrRaw(
          pair.substring(eq + 1),
        );
      }
    }
  }
  if (body.endsWith('/')) {
    body = body.substring(0, body.length - 1);
  }

  final atIndex = body.lastIndexOf('@');
  if (atIndex != -1) {
    return _parseSip002(
      body.substring(0, atIndex),
      body.substring(atIndex + 1),
      query,
    );
  }
  return _parseLegacy(body);
}

/// SIP002: userinfo may be base64(`method:password`) or literal
/// `method:password`.
Result<OutboundConfig, ConfigParseError> _parseSip002(
  String userInfo,
  String hostPort,
  Map<String, String> query,
) {
  var methodAndPassword = userInfo;
  final decoded = safeBase64DecodeToString(
    userInfo,
    field: 'ss userinfo',
    maxDecodedLength: maxUriLength,
  );
  if (decoded is Ok) {
    methodAndPassword = (decoded as Ok<String, ConfigParseError>).value;
  }
  // If base64 decoding failed, treat the userinfo as literal
  // `method:password` (valid SIP002).

  final colon = methodAndPassword.indexOf(':');
  if (colon == -1) {
    return Err(InvalidSyntaxError('ss userinfo', 'expected method:password'));
  }
  final method = methodAndPassword.substring(0, colon);
  final password = methodAndPassword.substring(colon + 1);
  if (method.isEmpty) {
    return Err(MissingRequiredFieldError('method'));
  }
  if (password.isEmpty) {
    return Err(MissingRequiredFieldError('password'));
  }

  return _build(method, password, hostPort, query);
}

/// Legacy: the whole `method:password@host:port` blob is base64.
Result<OutboundConfig, ConfigParseError> _parseLegacy(String body) {
  final decoded = safeBase64DecodeToString(body, field: 'ss payload');
  if (decoded case Err(:final error)) {
    return Err(error);
  }
  final text = (decoded as Ok<String, ConfigParseError>).value;

  final at = text.lastIndexOf('@');
  if (at == -1) {
    return Err(InvalidSyntaxError('ss payload', 'missing @ separator'));
  }
  final methodAndPassword = text.substring(0, at);
  final hostPort = text.substring(at + 1);

  final colon = methodAndPassword.indexOf(':');
  if (colon == -1) {
    return Err(InvalidSyntaxError('ss payload', 'expected method:password'));
  }
  final method = methodAndPassword.substring(0, colon);
  final password = methodAndPassword.substring(colon + 1);
  if (method.isEmpty) {
    return Err(MissingRequiredFieldError('method'));
  }
  if (password.isEmpty) {
    return Err(MissingRequiredFieldError('password'));
  }
  return _build(method, password, hostPort, const <String, String>{});
}

Result<OutboundConfig, ConfigParseError> _build(
  String method,
  String password,
  String hostPort,
  Map<String, String> query,
) {
  // Both SIP002 and legacy funnel through here, so one check covers both.
  final cipher = validateCipher(method);
  if (cipher case Err(:final error)) {
    return Err(error);
  }
  final hostResult = _splitHostPort(hostPort);
  if (hostResult case Err(:final error)) {
    return Err(error);
  }
  final (host, port) =
      (hostResult as Ok<(String, int), ConfigParseError>).value;

  final plugin = query['plugin'];
  return Ok<OutboundConfig, ConfigParseError>(
    ShadowsocksOutbound(
      server: host,
      serverPort: port,
      method: (cipher as Ok<String, ConfigParseError>).value,
      password: password,
      plugin: (plugin != null && plugin.isNotEmpty) ? plugin : null,
    ),
  );
}

Result<(String, int), ConfigParseError> _splitHostPort(String hostPort) {
  final colon = hostPort.lastIndexOf(':');
  if (colon == -1) {
    return Err(InvalidSyntaxError('ss endpoint', 'missing port'));
  }
  final host = hostPort.substring(0, colon);
  final portText = hostPort.substring(colon + 1);
  if (host.isEmpty) {
    return Err(MissingRequiredFieldError('server'));
  }
  final hostCheck = validateHost(host, 'server');
  if (hostCheck case Err(:final error)) {
    return Err(error);
  }
  final portCheck = parsePort(portText, 'port');
  if (portCheck case Err(:final error)) {
    return Err(error);
  }
  return Ok<(String, int), ConfigParseError>((
    host,
    (portCheck as Ok<int, ConfigParseError>).value,
  ));
}

/// The user-visible label carried in the URI fragment, or `host:port`.
String parseShadowsocksRemark(String uri) {
  const prefix = 'ss://';
  if (!uri.startsWith(prefix)) {
    return '';
  }
  final hashIndex = uri.indexOf('#');
  if (hashIndex == -1) {
    return '';
  }
  return percentDecodeOrRaw(uri.substring(hashIndex + 1));
}
