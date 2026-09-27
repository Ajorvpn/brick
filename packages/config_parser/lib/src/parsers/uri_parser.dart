// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import 'hysteria2_parser.dart';
import 'shadowsocks_parser.dart';
import 'trojan_parser.dart';
import 'tuic_parser.dart';
import 'vless_parser.dart';
import 'vmess_parser.dart';

/// Routes [uri] to the parser for its scheme.
///
/// This is the single entry point every caller should use: it inspects the
/// scheme and delegates, so adding a protocol later means adding one branch
/// here rather than changing every call site.
///
/// Returns [UnsupportedSchemeError] for a scheme this package does not
/// handle, and never throws (SECURITY.md §5).
Result<OutboundConfig, ConfigParseError> parseUri(String uri) {
  final lengthCheck = enforceMaxLength(
    uri,
    maxLength: maxUriLength,
    what: 'uri',
  );
  if (lengthCheck case Err(:final error)) {
    return Err(error);
  }

  final separator = uri.indexOf('://');
  if (separator == -1) {
    return Err(InvalidSyntaxError('uri', 'missing scheme separator'));
  }
  final scheme = uri.substring(0, separator).toLowerCase();

  return switch (scheme) {
    'vless' => parseVlessUri(uri),
    'vmess' => parseVmessUri(uri),
    'trojan' => parseTrojanUri(uri),
    'ss' => parseShadowsocksUri(uri),
    'hy2' || 'hysteria2' => parseHysteria2Uri(uri),
    'tuic' => parseTuicUri(uri),
    _ => Err(UnsupportedSchemeError(scheme)),
  };
}

/// The user-visible label for [uri], regardless of protocol.
///
/// Returns an empty string when the link carries no fragment and cannot be
/// parsed, so a caller can fall back to its own default.
String parseUriRemark(String uri) {
  final separator = uri.indexOf('://');
  if (separator == -1) {
    return '';
  }
  final scheme = uri.substring(0, separator).toLowerCase();
  return switch (scheme) {
    'vless' => parseVlessRemark(uri),
    'vmess' => parseVmessRemark(uri),
    'trojan' => parseTrojanRemark(uri),
    'ss' => parseShadowsocksRemark(uri),
    'hy2' || 'hysteria2' => parseHysteria2Remark(uri),
    'tuic' => parseTuicRemark(uri),
    _ => '',
  };
}
