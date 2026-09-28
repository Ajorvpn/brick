// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';

/// Shared, protocol-agnostic helpers used by every URI parser in this
/// package.
///
/// Security posture (SECURITY.md): every helper here is pure, never logs,
/// and never places input data into a returned error. Field names and
/// reasons are developer-authored constants only.

/// A canonical UUID (8-4-4-4-12 hex) with no dashes is accepted as well,
/// because subscription providers in the wild emit that form.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Validates that [value] is a canonical UUID.
///
/// Returns a [MissingRequiredFieldError] when empty and an
/// [InvalidFieldValueError] when malformed. The offending value is never
/// echoed back, because a UUID is credential material (SECURITY.md §2).
Result<String, ConfigParseError> validateUuid(String value, String field) {
  if (value.isEmpty) {
    return Err(MissingRequiredFieldError(field));
  }
  if (!_uuidPattern.hasMatch(value)) {
    return Err(
      InvalidFieldValueError(field, 'not a canonical 8-4-4-4-12 UUID'),
    );
  }
  return Ok<String, ConfigParseError>(value);
}

/// Parses a TCP/UDP port and enforces the 1..65535 range.
Result<int, ConfigParseError> parsePort(String value, String field) {
  if (value.isEmpty) {
    return Err(MissingRequiredFieldError(field));
  }
  final port = int.tryParse(value);
  if (port == null) {
    return Err(InvalidFieldValueError(field, 'not a number'));
  }
  if (port < 1 || port > 65535) {
    return Err(InvalidFieldValueError(field, 'outside the range 1..65535'));
  }
  return Ok<int, ConfigParseError>(port);
}

/// Validates a non-empty host / SNI value.
///
/// A bare host must not contain whitespace or a path separator, which would
/// indicate a malformed link rather than a real server name.
Result<String, ConfigParseError> validateHost(String value, String field) {
  if (value.isEmpty) {
    return Err(MissingRequiredFieldError(field));
  }
  if (value.contains(' ') || value.contains('/')) {
    return Err(InvalidFieldValueError(field, 'contains an illegal character'));
  }
  return Ok<String, ConfigParseError>(value);
}

/// Percent-decodes a URI fragment, falling back to the raw value.
String decodeRemark(Uri uri) {
  final fragment = uri.fragment;
  if (fragment.isEmpty) {
    return '';
  }
  return percentDecodeOrRaw(fragment);
}

/// Reads [uri]'s query parameters without ever throwing.
///
/// `Uri.queryParameters` calls `Uri.decodeQueryComponent` on every value, and
/// that throws a `FormatException` for a well-formed percent-escape that is
/// not valid UTF-8 (e.g. `?x=%C3%28`). Parsing an attacker-supplied link must
/// never throw, so every parser reads the query through this helper instead.
///
/// On malformed input the parameters are decoded leniently: values that
/// cannot be decoded are kept as their raw (still-encoded) text rather than
/// aborting the parse, and key/value decoding is otherwise unchanged. A
/// parser that needs a strictly valid value will reject it downstream.
Map<String, String> safeQueryParameters(Uri uri) {
  try {
    return uri.queryParameters;
  } on FormatException {
    // Re-parse leniently, preserving whatever the decoder can handle.
    final out = <String, String>{};
    final query = uri.query;
    if (query.isEmpty) return out;
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final rawKey = eq == -1 ? pair : pair.substring(0, eq);
      final rawValue = eq == -1 ? '' : pair.substring(eq + 1);
      out[percentDecodeOrRaw(rawKey)] = percentDecodeOrRaw(rawValue);
    }
    return out;
  }
}

/// Percent-decodes [input], falling back to the raw value on malformed input.
///
/// **This is the single implementation every parser must use.** It used to be
/// duplicated as a private `_percentDecode` in six parser files, each of which
/// caught only `ArgumentError`. That was incomplete: `Uri.decodeComponent`
/// throws **`FormatException`** for a syntactically well-formed escape that
/// decodes to invalid UTF-8 (e.g. `%C3%28`), so inputs like
/// `trojan://%C3%28@host:443` escaped five public parsers as an unhandled
/// `FormatException`, violating the "zero unhandled throws" contract.
///
/// Both exception types are now caught, so this function is **total**: it
/// returns a `String` for every possible input and can never throw.
String percentDecodeOrRaw(String input) {
  try {
    return Uri.decodeComponent(input);
  } on ArgumentError {
    // Malformed escape (e.g. `%`, `%zz`, truncated `%A4`).
    return input;
  } on FormatException {
    // Well-formed escape that is not valid UTF-8 (e.g. `%C3%28`).
    return input;
  }
}

/// Builds the [TlsSettings] block from the shared V2Ray query parameters.
///
/// Returns `null` when TLS is not requested (`security=none` / absent) so
/// the caller can leave `TcpBasedOutbound.tls` unset.
///
/// `pbk`/`sid` are the REALITY parameters; REALITY is only enabled when both
/// are present, because a half-configured REALITY block produces a config
/// that sing-box rejects at runtime.
TlsSettings? buildTlsSettings(Map<String, String> query) {
  final security = (query['security'] ?? '').toLowerCase();
  final sni = query['sni'];
  final alpn = query['alpn'];

  final wantsReality = security == 'reality';
  final wantsTls = security == 'tls' || wantsReality;

  if (!wantsTls) {
    return null;
  }

  final pbk = query['pbk'];
  final sid = query['sid'];
  final spx = query['spx'];

  return TlsSettings(
    enabled: true,
    serverName: (sni != null && sni.isNotEmpty) ? sni : null,
    utls: _buildUtls(query['fp']),
    reality: wantsReality && pbk != null && sid != null
        ? RealitySettings(
            enabled: true,
            publicKey: pbk,
            shortId: sid,
            spiderX: spx,
          )
        : null,
    alpn: (alpn != null && alpn.isNotEmpty) ? alpn.split(',') : null,
  );
}

UtlsSettings? _buildUtls(String? fingerprint) {
  if (fingerprint == null || fingerprint.isEmpty) {
    return null;
  }
  return UtlsSettings(enabled: true, fingerprint: fingerprint);
}

/// Builds the [TransportSettings] block from `type` plus the shared
/// `path` / `host` / `serviceName` parameters.
///
/// Returns `null` for `tcp` (or an absent type), because TCP is the default
/// and sing-box expects no transport object in that case.
Result<TransportSettings?, ConfigParseError> buildTransportSettings(
  Map<String, String> query,
) {
  final type = (query['type'] ?? 'tcp').toLowerCase();
  final path = query['path'];
  final host = query['host'];
  final serviceName = query['serviceName'];

  switch (type) {
    case 'tcp':
      return Ok<TransportSettings?, ConfigParseError>(null);

    case 'ws':
      return Ok<TransportSettings?, ConfigParseError>(
        WebSocketTransport(
          path: (path != null && path.isNotEmpty) ? path : '/',
          headers: (host != null && host.isNotEmpty)
              ? <String, String>{'Host': host}
              : null,
        ),
      );

    case 'grpc':
      if (serviceName == null || serviceName.isEmpty) {
        return Err(MissingRequiredFieldError('serviceName'));
      }
      return Ok<TransportSettings?, ConfigParseError>(
        GrpcTransport(serviceName: serviceName),
      );

    case 'splithttp':
    case 'xhttp':
      return Ok<TransportSettings?, ConfigParseError>(
        HttpUpgradeTransport(
          host: (host != null && host.isNotEmpty) ? host : null,
          path: path,
        ),
      );

    default:
      return Err<TransportSettings?, ConfigParseError>(
        InvalidFieldValueError('type', 'unknown transport type'),
      );
  }
}

/// Reads the `flow` parameter, defaulting to null when absent.
String? readFlow(Map<String, String> query) {
  final flow = query['flow'];
  return (flow != null && flow.isNotEmpty) ? flow : null;
}
