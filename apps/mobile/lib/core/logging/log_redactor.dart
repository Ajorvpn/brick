// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:core_domain/core_domain.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:shared_utils/shared_utils.dart';

/// Service performing structured-field, known-secret, and pattern-based
/// log redaction across the application.
///
/// Designed per P8-T2 specification to enforce systematic privacy protection
/// at the ingestion chokepoint before log entries are buffered or stored.
abstract final class LogRedactor {
  static const Set<String> _sensitiveKeys = <String>{
    'uuid',
    'password',
    'passwd',
    'pwd',
    'secret',
    'token',
    'private_key',
    'privatekey',
    'pre_shared_key',
    'presharedkey',
    'public_key',
    'publickey',
    'short_id',
    'shortid',
    'obfs_password',
    'obfspassword',
    'auth',
    'authorization',
    'plugin_opts',
    'pluginopts',
    'uri',
    'url',
  };

  static const Set<String> _hostKeys = <String>{
    'server',
    'server_name',
    'servername',
    'host',
    'endpoint',
    'remote_address',
    'remoteaddress',
    'destination',
  };

  /// Recursively inspects and redacts sensitive fields in a structured
  /// JSON map.
  static Map<String, dynamic> redactJsonMap(
    Map<String, dynamic> map, {
    Iterable<String> knownSecrets = const <String>[],
  }) {
    final result = <String, dynamic>{};

    for (final entry in map.entries) {
      final key = entry.key;
      final lowerKey = key.toLowerCase().replaceAll('_', '');
      final value = entry.value;

      if (_isSensitiveKey(lowerKey)) {
        result[key] = '[REDACTED]';
      } else if (_isHostKey(lowerKey)) {
        if (value is String && _isSafeDiagnosticHost(value)) {
          result[key] = value;
        } else {
          result[key] = '[REDACTED_HOST]';
        }
      } else if (value is Map<String, dynamic>) {
        result[key] = redactJsonMap(value, knownSecrets: knownSecrets);
      } else if (value is Map) {
        result[key] = redactJsonMap(
          Map<String, dynamic>.from(value),
          knownSecrets: knownSecrets,
        );
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return redactJsonMap(item, knownSecrets: knownSecrets);
          } else if (item is Map) {
            return redactJsonMap(
              Map<String, dynamic>.from(item),
              knownSecrets: knownSecrets,
            );
          } else if (item is String) {
            return redact(item, knownSecrets: knownSecrets);
          }
          return item;
        }).toList();
      } else if (value is String) {
        result[key] = redact(value, knownSecrets: knownSecrets);
      } else {
        result[key] = value;
      }
    }

    return result;
  }

  /// Extracts sensitive credentials and server hostnames from a
  /// [ServerProfile].
  static Set<String> extractSecretsFromProfile(ServerProfile profile) {
    final secrets = <String>{};

    // 1. Server hostname or IP
    final server = profile.config.server.trim();
    if (server.isNotEmpty && !_isSafeDiagnosticHost(server)) {
      secrets.add(server);
    }

    // 2. Structured outbound config properties
    final config = profile.config;
    switch (config) {
      case VlessOutbound(:final uuid, :final tls):
        _addNonEmpty(secrets, uuid);
        if (tls?.reality?.publicKey case final pk?) _addNonEmpty(secrets, pk);
        if (tls?.reality?.shortId case final sid?) _addNonEmpty(secrets, sid);
        _extractTransportHeaders(secrets, config.transport);
      case VmessOutbound(:final uuid):
        _addNonEmpty(secrets, uuid);
        _extractTransportHeaders(secrets, config.transport);
      case TrojanOutbound(:final password):
        _addNonEmpty(secrets, password);
        _extractTransportHeaders(secrets, config.transport);
      case ShadowsocksOutbound(:final password, :final pluginOpts):
        _addNonEmpty(secrets, password);
        if (pluginOpts != null) _addNonEmpty(secrets, pluginOpts);
      case Hysteria2Outbound(:final password, :final obfsPassword):
        _addNonEmpty(secrets, password);
        if (obfsPassword != null) _addNonEmpty(secrets, obfsPassword);
      case TuicOutbound(:final uuid, :final password):
        _addNonEmpty(secrets, uuid);
        _addNonEmpty(secrets, password);
      case WireGuardOutbound(:final privateKey, :final presharedKey):
        _addNonEmpty(secrets, privateKey);
        if (presharedKey != null) _addNonEmpty(secrets, presharedKey);
    }

    // 3. Fallback extraction from JSON representation for any custom properties
    try {
      _extractFromJson(config.toJson(), secrets);
    } on Object catch (_) {}

    return secrets;
  }

  /// Extracts sensitive URLs and query parameters from [SubscriptionMetadata].
  static Set<String> extractSecretsFromSubscription(SubscriptionMetadata sub) {
    final secrets = <String>{};
    _addNonEmpty(secrets, sub.url);

    try {
      final uri = Uri.tryParse(sub.url);
      if (uri != null) {
        if (uri.userInfo.isNotEmpty) {
          secrets.add(uri.userInfo);
        }
        for (final val in uri.queryParameters.values) {
          _addNonEmpty(secrets, val);
        }
      }
    } on Object catch (_) {}

    return secrets;
  }

  /// Redacts a raw log line before ingestion into any buffer, sink, or viewer.
  static String redactRawLine(
    String rawLine, {
    Iterable<String> knownSecrets = const <String>[],
  }) {
    if (rawLine.isEmpty) return rawLine;

    final trimmed = rawLine.trim();

    // If line is a JSON object, redact the structured map first
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final redactedMap = redactJsonMap(
            decoded,
            knownSecrets: knownSecrets,
          );
          return jsonEncode(redactedMap);
        }
      } on Object catch (_) {}
    }

    // Standard free-text redaction pass
    return redact(rawLine, knownSecrets: knownSecrets);
  }

  static bool _isSensitiveKey(String lowerKey) {
    return _sensitiveKeys.contains(lowerKey) ||
        lowerKey.endsWith('password') ||
        lowerKey.endsWith('secret') ||
        lowerKey.endsWith('token') ||
        lowerKey.endsWith('key');
  }

  static bool _isHostKey(String lowerKey) {
    return _hostKeys.contains(lowerKey) || lowerKey.endsWith('host');
  }

  static bool _isSafeDiagnosticHost(String host) {
    final clean = host.contains(':') ? host.split(':').first : host;
    if (clean == '127.0.0.1' ||
        clean == '0.0.0.0' ||
        clean == 'localhost' ||
        clean == '::' ||
        clean == '::1') {
      return true;
    }
    if (clean.startsWith('10.111.222.')) {
      return true;
    }
    return false;
  }

  static void _extractTransportHeaders(
    Set<String> secrets,
    TransportSettings? transport,
  ) {
    if (transport is WebSocketTransport && transport.headers != null) {
      for (final val in transport.headers!.values) {
        _addNonEmpty(secrets, val);
      }
    } else if (transport is HttpTransport && transport.headers != null) {
      for (final val in transport.headers!.values) {
        _addNonEmpty(secrets, val);
      }
    }
  }

  static void _extractFromJson(dynamic json, Set<String> secrets) {
    if (json is Map) {
      for (final entry in json.entries) {
        final key = entry.key.toString().toLowerCase().replaceAll('_', '');
        final val = entry.value;
        if (_isSensitiveKey(key) && val is String) {
          _addNonEmpty(secrets, val);
        } else {
          _extractFromJson(val, secrets);
        }
      }
    } else if (json is List) {
      for (final item in json) {
        _extractFromJson(item, secrets);
      }
    }
  }

  static void _addNonEmpty(Set<String> set, String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 4) {
      set.add(trimmed);
    }
  }
}
