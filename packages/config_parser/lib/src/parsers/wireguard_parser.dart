// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import 'uri_parsing_support.dart';

/// Parses a `wireguard://` or `wg://` URI into a [WireGuardOutbound].
///
/// Shape: `wireguard://<private_key>@<host>:<port>?<query>#<remark>`
///
/// Both the private key and the optional pre-shared key are credential
/// material: they are parsed but never echoed into an error (SECURITY.md
/// §2). Errors name the *field*, not the value.
///
/// A WireGuard key is 32 bytes, base64-encoded. The length is validated so
/// a truncated or mistyped key fails here rather than at tunnel setup.
Result<OutboundConfig, ConfigParseError> parseWireguardUri(String uri) {
  final parsed = safeUriParse(uri, field: 'wireguard uri');
  if (parsed case Err(:final error)) {
    return Err(error);
  }
  final value = (parsed as Ok<Uri, ConfigParseError>).value;

  if (value.scheme != 'wireguard' && value.scheme != 'wg') {
    return Err(UnsupportedSchemeError(value.scheme));
  }

  // A base64 key contains '+', '/' and '=' which corrupt a URI's
  // authority component, so a well-formed link percent-encodes it and
  // `Uri.parse` hands it back decoded. Providers that cannot encode the
  // userinfo put the key in a query parameter instead, so accept both
  // and prefer the explicit query form.
  final keyFromQuery =
      value.queryParameters['private_key'] ?? value.queryParameters['privatekey'];
  final privateKey = (keyFromQuery ?? _percentDecode(value.userInfo)).trim();
  if (privateKey.isEmpty) {
    return Err(MissingRequiredFieldError('private_key'));
  }
  final keyCheck = _validateKey('private_key', privateKey);
  if (keyCheck case Err(:final error)) {
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

  final peerPublicKey = query['peer_public_key'] ?? query['public_key'];
  if (peerPublicKey == null || peerPublicKey.isEmpty) {
    return Err(MissingRequiredFieldError('peer_public_key'));
  }
  final peerCheck = _validateKey('peer_public_key', peerPublicKey);
  if (peerCheck case Err(:final error)) {
    return Err(error);
  }

  // `ip` / `address` is the local interface address, e.g. "10.0.0.2/32".
  final addressRaw = query['ip'] ?? query['address'];
  if (addressRaw == null || addressRaw.isEmpty) {
    return Err(MissingRequiredFieldError('ip'));
  }
  final localAddresses = addressRaw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
  if (localAddresses.isEmpty) {
    return Err(InvalidFieldValueError('ip', 'no usable address in the list'));
  }

  final preshared = query['preshared_key'] ?? query['pre_shared_key'];
  if (preshared != null && preshared.isNotEmpty) {
    final pskCheck = _validateKey('preshared_key', preshared);
    if (pskCheck case Err(:final error)) {
      return Err(error);
    }
  }

  final reservedCheck = _parseReserved(query['reserved']);
  if (reservedCheck case Err(:final error)) {
    return Err(error);
  }

  final mtu = _positiveInt(query['mtu'], 'mtu');
  if (mtu case Err(:final error)) {
    return Err(error);
  }
  final workers = _positiveInt(query['workers'], 'workers');
  if (workers case Err(:final error)) {
    return Err(error);
  }

  final dns = query['dns'];
  final dnsServers = (dns == null || dns.isEmpty)
      ? null
      : dns
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);

  return Ok<OutboundConfig, ConfigParseError>(
    WireGuardOutbound(
      server: host,
      serverPort: port,
      privateKey: privateKey,
      peerPublicKey: peerPublicKey,
      localAddresses: localAddresses,
      presharedKey: (preshared != null && preshared.isNotEmpty)
          ? preshared
          : null,
      reserved: (reservedCheck as Ok<List<int>?, ConfigParseError>).value,
      mtu: (mtu as Ok<int?, ConfigParseError>).value,
      workers: (workers as Ok<int?, ConfigParseError>).value,
      dnsServers: dnsServers,
    ),
  );
}

/// The user-visible label carried in the URI fragment, or `host:port`.
String parseWireguardRemark(String uri) {
  final parsed = safeUriParse(uri, field: 'wireguard uri');
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

/// Validates that [key] is base64 decoding to exactly 32 bytes.
///
/// A WireGuard key is always 32 bytes; anything else is a truncated or
/// mistyped key. The decoded bytes are discarded, never stored or logged.
Result<void, ConfigParseError> _validateKey(String field, String key) {
  final decoded = safeBase64Decode(key, field: field, expectedBytes: 32);
  if (decoded case Err(:final error)) {
    return Err<void, ConfigParseError>(error);
  }
  return Ok<void, ConfigParseError>(null);
}

/// Parses the `reserved` parameter, a comma-separated list of 0..255 bytes.
Result<List<int>?, ConfigParseError> _parseReserved(String? raw) {
  if (raw == null || raw.isEmpty) {
    return Ok<List<int>?, ConfigParseError>(null);
  }
  final parts = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
  final bytes = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) {
      return Err<List<int>?, ConfigParseError>(
        InvalidFieldValueError('reserved', 'not a byte value in 0..255'),
      );
    }
    bytes.add(value);
  }
  if (bytes.isEmpty) {
    return Err<List<int>?, ConfigParseError>(
      InvalidFieldValueError('reserved', 'empty'),
    );
  }
  return Ok<List<int>?, ConfigParseError>(bytes);
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

String _percentDecode(String input) {
  try {
    return Uri.decodeComponent(input);
  } on ArgumentError {
    return input;
  }
}
