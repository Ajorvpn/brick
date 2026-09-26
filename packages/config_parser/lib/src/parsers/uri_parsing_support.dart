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
  try {
    return Uri.decodeComponent(fragment);
  } on ArgumentError {
    return fragment;
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
