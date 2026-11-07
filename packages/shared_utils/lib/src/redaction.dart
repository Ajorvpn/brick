// SPDX-License-Identifier: GPL-3.0-or-later

/// Redacts sensitive information from log messages (credentials, keys,
/// URIs, UUIDs, external IP addresses).
///
/// Pure-Dart implementation with zero external dependencies per SECURITY.md
/// Section 4 and P8-T2 specifications.
///
/// Redaction Rules:
/// 1. Known Secrets: literal occurrences of strings in [knownSecrets] with
///    length >= 4 are replaced with `[REDACTED]`.
/// 2. Share-Link & Subscription URIs: proxy/VPN schemes and HTTP(S) URLs are
///    scrubbed to `<scheme>://[REDACTED]`.
/// 3. Structured JSON Keys: sensitive key-value pairs in JSON strings are
///    scrubbed to `"$key":"[REDACTED]"`.
/// 4. Key=Value / Key: Value Free-Text: sensitive parameter assignments in
///    free-text are scrubbed to `$key$sep[REDACTED]`.
/// 5. UUIDs: RFC 4122 UUID strings are scrubbed to `[REDACTED_UUID]`.
/// 6. External IPv4/IPv6: external host endpoints are scrubbed to
///    `[REDACTED_IP]`, preserving local loopback (`127.0.0.1`), unbound
///    (`0.0.0.0`), netmasks (`255.255.255.0`), and internal TUN routing
///    addresses (`10.111.222.*`, `::`, `::1`).
String redact(
  String input, {
  Iterable<String> knownSecrets = const <String>[],
}) {
  if (input.isEmpty) return input;

  var result = input;

  // 1. Share-Link & Subscription URIs
  result = result.replaceAllMapped(_uriRegex, (match) {
    final scheme = match.group(1);
    return '$scheme://[REDACTED]';
  });

  // 2. Structured JSON sensitive keys
  result = result.replaceAllMapped(_jsonKeyRegex, (match) {
    final key = match.group(1);
    final sep = match.group(2) ?? ':';
    return '"$key"$sep"[REDACTED]"';
  });

  // 3. Free-text Key=Value or Key: Value assignments
  result = result.replaceAllMapped(_freeTextRegex, (match) {
    final key = match.group(1);
    final sep = match.group(2) ?? '=';
    return '$key$sep[REDACTED]';
  });

  // 4. UUIDs
  result = result.replaceAllMapped(_uuidRegex, (match) {
    return '[REDACTED_UUID]';
  });

  // 5. Known literal secrets (length >= 4) sorted by descending length
  final secrets =
      knownSecrets.where((s) => s.trim().length >= 4).toSet().toList()
        ..sort((a, b) => b.length.compareTo(a.length));

  for (final secret in secrets) {
    result = result.replaceAll(secret, '[REDACTED]');
  }

  // 6. External IPv4 / IPv6 addresses
  result = result.replaceAllMapped(_ipv4Regex, (match) {
    final candidate = match.group(0)!;
    if (_isValidIpv4(candidate)) {
      if (_isSafeDiagnosticIpv4(candidate)) {
        return candidate;
      }
      return '[REDACTED_IP]';
    }
    return candidate;
  });

  result = result.replaceAllMapped(_ipv6Regex, (match) {
    final candidate = match.group(0)!;
    if (_isValidIpv6(candidate)) {
      if (_isSafeDiagnosticIpv6(candidate)) {
        return candidate;
      }
      return '[REDACTED_IP]';
    }
    return candidate;
  });

  return result;
}

final RegExp _uriRegex = RegExp(
  r'''\b(vless|vmess|trojan|ss|hy2|hysteria2|tuic|wg|wireguard|awg|amneziawg|brick|https?)://[^\s"'()\[\]]+''',
  caseSensitive: false,
);

final RegExp _jsonKeyRegex = RegExp(
  r'''"(uuid|password|passwd|pwd|secret|token|private_key|privateKey|pre_shared_key|presharedKey|public_key|publicKey|short_id|shortId|obfs_password|obfsPassword|auth|authorization|plugin_opts)"(\s*:\s*)"[^"]*"''',
  caseSensitive: false,
);

final RegExp _freeTextRegex = RegExp(
  r'''\b(uuid|password|passwd|pwd|secret|token|private_key|privateKey|pre_shared_key|preshared_key|public_key|short_id|obfs_password|auth|authorization|plugin_opts)(\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;\]\}]+)''',
  caseSensitive: false,
);

final RegExp _uuidRegex = RegExp(
  r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
);

final RegExp _ipv4Regex = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?\b');

final RegExp _ipv6Regex = RegExp(
  r'(?:\[[0-9a-fA-F:]+\](?::\d{1,5})?|\b[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{0,4}){2,7}(?::\d{1,5})?\b)',
);

bool _isValidIpv4(String candidate) {
  final ip = candidate.contains(':') ? candidate.split(':').first : candidate;
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}

bool _isSafeDiagnosticIpv4(String candidate) {
  final ip = candidate.contains(':') ? candidate.split(':').first : candidate;
  if (ip == '127.0.0.1' || ip == '0.0.0.0') return true;
  if (ip == '255.255.255.0' || ip == '255.255.255.255') return true;
  if (ip.startsWith('10.111.222.')) return true;
  return false;
}

bool _isValidIpv6(String candidate) {
  var clean = candidate;
  if (clean.startsWith('[') && clean.contains(']')) {
    clean = clean.substring(1, clean.indexOf(']'));
  }
  // Must contain at least two colons
  final colonCount = ':'.allMatches(clean).length;
  if (colonCount < 2) return false;

  // Timestamps like 12:34:56 have 2 colons, digits only, no '::'
  final hasDoubleColon = clean.contains('::');
  final hasHexLetters = RegExp(r'[a-fA-F]').hasMatch(clean);
  if (!hasDoubleColon && !hasHexLetters && colonCount < 4) {
    return false;
  }

  final parts = clean.split(':');
  if (parts.length > 8) return false;
  for (final part in parts) {
    if (part.length > 4) return false;
  }
  return true;
}

bool _isSafeDiagnosticIpv6(String candidate) {
  var clean = candidate;
  if (clean.startsWith('[') && clean.contains(']')) {
    clean = clean.substring(1, clean.indexOf(']'));
  } else if (clean.contains(':') && !clean.endsWith(':')) {
    final parts = clean.split(':');
    if (parts.length > 2 &&
        int.tryParse(parts.last) != null &&
        !parts.last.contains(RegExp(r'[a-fA-F]'))) {
      clean = parts.sublist(0, parts.length - 1).join(':');
    }
  }
  if (clean == '::' || clean == '::1') return true;
  return false;
}
