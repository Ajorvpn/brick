// SPDX-License-Identifier: GPL-3.0-or-later

/// Brick VPN config parser.
///
/// This package is **pure Dart by design** and must never gain a Flutter
/// dependency. Every parser here is a pure function over untrusted text and
/// must be unit-testable with `dart test` alone, with no widget tree and no
/// device. That property is enforced by the Melos test routing in the root
/// `pubspec.yaml`, which lists this package in the `test:dart` allowlist and
/// the `test:flutter` denylist (see P2-T1).
///
/// Cross-cutting security posture (SECURITY.md): all input is untrusted.
/// A subscription URL may point at a malicious or compromised server, so
/// every helper here is bounded (input size, nesting depth) and returns
/// `Result<_, ConfigParseError>` rather than throwing on malformed input.
/// Parsers are pure: no clock, no randomness, no I/O.
library config_parser;

export 'src/config_parse_error.dart';
export 'src/defensive_parser_utils.dart';
export 'src/parsers/amneziawg_parser.dart';
export 'src/parsers/hysteria2_parser.dart';
export 'src/parsers/shadowsocks_parser.dart';
export 'src/parsers/singbox_json_reader.dart';
export 'src/parsers/smart_config_parser.dart';
export 'src/parsers/trojan_parser.dart';
export 'src/parsers/tuic_parser.dart';
export 'src/parsers/uri_parser.dart';
export 'src/parsers/vless_parser.dart';
export 'src/parsers/vmess_parser.dart';
export 'src/parsers/wireguard_parser.dart';
export 'src/serializers/singbox_serializer.dart';
export 'src/subscription/subscription_decoder.dart';
export 'src/subscription/subscription_parser.dart';
export 'src/subscription/subscription_user_info.dart';
export 'src/server_profile_conversion.dart';
