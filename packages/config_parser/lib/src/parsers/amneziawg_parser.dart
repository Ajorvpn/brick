// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import 'uri_parsing_support.dart';

/// AmneziaWG junk-packet and special-header obfuscation parameters, with the
/// inclusive ranges AmneziaWG itself validates against.
///
/// Names/meaning: `jc` junk-packet count, `jmin`/`jmax` junk-packet size
/// bounds, `s1`/`s2` init-packet junk prefix, and `h1`..`h4` the magic
/// header values.
const Map<String, (int, int)> _obfuscationRanges = {
  'jc': (0, 1280),
  'jmin': (0, 1280),
  'jmax': (0, 1280),
  's1': (0, 1280),
  's2': (0, 1280),
  'h1': (0, 4294967295),
  'h2': (0, 4294967295),
  'h3': (0, 4294967295),
  'h4': (0, 4294967295),
};

/// Parses an `amneziawg://` or `awg://` URI into an [AmneziaWgOutbound].
///
/// Shape: `amneziawg://<private_key>@<host>:<port>?<query>#<remark>`
///
/// The query carries every standard WireGuard parameter plus the nine
/// AmneziaWG obfuscation parameters (`jc`, `jmin`, `jmax`, `s1`, `s2`,
/// `h1`..`h4`), each range-checked.
///
/// Keys are credential material and are never echoed into an error.
Result<OutboundConfig, ConfigParseError> parseAmneziaWgUri(String uri) {
  final parsed = safeUriParse(uri, field: 'amneziawg uri');
  if (parsed case Err(:final error)) {
    return Err(error);
  }
  final value = (parsed as Ok<Uri, ConfigParseError>).value;

  if (value.scheme != 'amneziawg' && value.scheme != 'awg') {
    return Err(UnsupportedSchemeError(value.scheme));
  }

  // A base64 key contains '+', '/' and '=' which corrupt a URI's
  // authority component, so a well-formed link percent-encodes it and
  // `Uri.parse` hands it back decoded. Providers that cannot encode the
  // userinfo put the key in a query parameter instead, so accept both
  // and prefer the explicit query form.
  final keyFromQuery =
      value.queryParameters['private_key'] ??
      value.queryParameters['privatekey'];
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

  // Obfuscation parameters, each range-checked.
  final obfuscation = <String, int>{};
  for (final entry in _obfuscationRanges.entries) {
    final raw = query[entry.key];
    if (raw == null || raw.isEmpty) {
      continue;
    }
    final parsedValue = int.tryParse(raw);
    if (parsedValue == null) {
      return Err(InvalidFieldValueError(entry.key, 'not an integer'));
    }
    final (min, max) = entry.value;
    if (parsedValue < min || parsedValue > max) {
      return Err(
        InvalidFieldValueError(entry.key, 'outside the range $min..$max'),
      );
    }
    obfuscation[entry.key] = parsedValue;
  }

  final mtu = _positiveInt(query['mtu'], 'mtu');
  if (mtu case Err(:final error)) {
    return Err(error);
  }
  final workers = _positiveInt(query['workers'], 'workers');
  if (workers case Err(:final error)) {
    return Err(error);
  }

  final reserved = _parseReserved(query['reserved']);
  if (reserved case Err(:final error)) {
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
    AmneziaWgOutbound(
      server: host,
      serverPort: port,
      privateKey: privateKey,
      peerPublicKey: peerPublicKey,
      localAddresses: localAddresses,
      presharedKey: (preshared != null && preshared.isNotEmpty)
          ? preshared
          : null,
      reserved: (reserved as Ok<List<int>?, ConfigParseError>).value,
      mtu: (mtu as Ok<int?, ConfigParseError>).value,
      workers: (workers as Ok<int?, ConfigParseError>).value,
      dnsServers: dnsServers,
      jc: obfuscation['jc'],
      jmin: obfuscation['jmin'],
      jmax: obfuscation['jmax'],
      s1: obfuscation['s1'],
      s2: obfuscation['s2'],
      h1: obfuscation['h1'],
      h2: obfuscation['h2'],
      h3: obfuscation['h3'],
      h4: obfuscation['h4'],
    ),
  );
}

/// The user-visible label carried in the URI fragment, or `host:port`.
String parseAmneziaWgRemark(String uri) {
  final parsed = safeUriParse(uri, field: 'amneziawg uri');
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

Result<void, ConfigParseError> _validateKey(String field, String key) {
  final decoded = safeBase64Decode(key, field: field, expectedBytes: 32);
  if (decoded case Err(:final error)) {
    return Err<void, ConfigParseError>(error);
  }
  return Ok<void, ConfigParseError>(null);
}

Result<List<int>?, ConfigParseError> _parseReserved(String? raw) {
  if (raw == null || raw.isEmpty) {
    return Ok<List<int>?, ConfigParseError>(null);
  }
  final bytes = <int>[];
  for (final part in raw.split(',').map((e) => e.trim())) {
    if (part.isEmpty) {
      continue;
    }
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) {
      return Err<List<int>?, ConfigParseError>(
        InvalidFieldValueError('reserved', 'not a byte value in 0..255'),
      );
    }
    bytes.add(value);
  }
  return Ok<List<int>?, ConfigParseError>(bytes.isEmpty ? null : bytes);
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
