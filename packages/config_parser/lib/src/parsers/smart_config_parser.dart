// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';
import '../subscription/subscription_parser.dart';
import '../subscription/subscription_user_info.dart';
import 'singbox_json_reader.dart';
import 'uri_parser.dart';

/// The custom deep-link scheme the app registers for inbound imports.
///
/// NOTE: the scheme is NOT yet registered in
/// `apps/mobile/android/app/src/main/AndroidManifest.xml` — that is Android
/// wiring and belongs to Phase 3. This parser accepts the shape now so the
/// contract is fixed and testable; until the manifest declares the
/// intent-filter, the OS will not route a `brick://` link here.
const String deepLinkScheme = 'brick';

/// What [parseConfigContent] decided the pasted input actually was.
enum SmartContentType {
  /// One protocol URI (`vless://`, `ss://`, `wireguard://`, ...).
  singleUri,

  /// A newline-separated and/or base64 subscription body.
  subscription,

  /// A raw sing-box outbound JSON object (or an array of them).
  json,

  /// A `brick://import?...` deep link wrapping another payload.
  deepLink,
}

/// The outcome of parsing arbitrary pasted config content.
///
/// One shape covers every input kind so callers (the "add server" flow,
/// clipboard paste, deep links) never have to branch on what the user
/// happened to paste. [warnings] carries non-fatal per-entry failures from a
/// bulk subscription so a single bad line does not discard the good ones.
final class SmartParseResult {
  /// Creates a result.
  const SmartParseResult({
    required this.outbounds,
    required this.detectedType,
    this.userInfo,
    this.warnings = const <ConfigParseError>[],
  });

  /// Everything that parsed successfully, in input order.
  final List<OutboundConfig> outbounds;

  /// Quota/expiry metadata, when the input was a subscription.
  final SubscriptionUserInfo? userInfo;

  /// Non-fatal per-entry errors from a bulk payload.
  final List<ConfigParseError> warnings;

  /// Which branch of the detector handled this input.
  final SmartContentType detectedType;

  /// Number of successfully parsed outbounds.
  int get parsedCount => outbounds.length;

  /// Whether every entry parsed cleanly.
  bool get isComplete => warnings.isEmpty;
}

/// Parses arbitrary pasted config content, whatever its shape.
///
/// Detection order (each step is cheap and rules the previous one out):
/// 1. **Deep link** — `brick://import?url=…` / `?config=…`, recursed into.
/// 2. **Single URI** — anything the protocol router recognises.
/// 3. **Raw JSON** — a `{…}` object or `[…]` array of sing-box outbounds.
/// 4. **Subscription** — newline-separated and/or base64 multi-entry body.
///
/// Never throws: every failure is an `Err`. Nothing from the input is echoed
/// into an error, so a pasted credential cannot reach a log (SECURITY.md §4).
///
/// Recursion into a deep link is bounded (see [_maxDeepLinkDepth]) so a
/// self-referential `brick://import?url=brick://import?url=…` cannot loop.
Result<SmartParseResult, ConfigParseError> parseConfigContent(
  String input, {
  String? userInfoHeaderValue,
  int depth = 0,
}) {
  final lengthCheck = enforceMaxLength(
    input,
    maxLength: maxSubscriptionLength,
    what: 'pasted content',
  );
  if (lengthCheck case Err(:final error)) {
    return Err(error);
  }

  // Strip a UTF-8 BOM if a paste or QR payload included one.
  var text = input.trim();
  if (text.startsWith('﻿')) {
    text = text.substring(1).trim();
  }
  if (text.isEmpty) {
    return Err(InvalidSyntaxError('content', 'empty'));
  }

  // 1. Deep link.
  if (_isDeepLink(text)) {
    if (depth >= _maxDeepLinkDepth) {
      return Err(InvalidSyntaxError('deep link', 'nested too deeply'));
    }
    final inner = _extractDeepLinkPayload(text);
    if (inner == null || inner.trim().isEmpty) {
      return Err(
        MissingRequiredFieldError('url'),
      );
    }
    return parseConfigContent(
      inner,
      userInfoHeaderValue: userInfoHeaderValue,
      depth: depth + 1,
    ).map(
      (parsed) => SmartParseResult(
        outbounds: parsed.outbounds,
        userInfo: parsed.userInfo,
        warnings: parsed.warnings,
        // Report the OUTER shape: the caller handed us a deep link, and
        // that is the most useful thing to tell them.
        detectedType: SmartContentType.deepLink,
      ),
    );
  }

  // 2. Single protocol URI.
  if (text.contains('://') && !_looksMultiEntry(text)) {
    final single = parseUri(text);
    switch (single) {
      case Ok(:final value):
        return Ok(
          SmartParseResult(
            outbounds: <OutboundConfig>[value],
            detectedType: SmartContentType.singleUri,
          ),
        );
      case Err(:final error):
        return Err(error);
    }
  }

  // 3. Raw JSON. A subscription body is never `{`/`[`-prefixed, so this
  // branch is authoritative: its error is the most specific one available
  // and must not be masked by a generic subscription failure.
  if (text.startsWith('{') || text.startsWith('[')) {
    final fromJson = _parseJsonOutbounds(text);
    if (fromJson case Ok(:final value)) {
      return Ok(
        SmartParseResult(
          outbounds: value,
          detectedType: SmartContentType.json,
        ),
      );
    } else if (fromJson case Err(:final error)) {
      return Err(error);
    }
  }

  // 4. Subscription / multi-entry body.
  final subscription = parseSubscription(
    text,
    userInfoHeaderValue: userInfoHeaderValue,
  );
  switch (subscription) {
    case Ok(:final value):
      return Ok(
        SmartParseResult(
          outbounds: value.configs,
          userInfo: value.userInfo,
          warnings: value.errors,
          detectedType: SmartContentType.subscription,
        ),
      );
    case Err(:final error):
      return Err(error);
  }
}

/// A deep link is recognised by its scheme alone; the payload is validated
/// after.
bool _isDeepLink(String text) {
  final lower = text.toLowerCase();
  return lower.startsWith('$deepLinkScheme://');
}

/// Extracts the inner payload from `brick://import?url=…` or `?config=…`.
///
/// Returns null when neither parameter is present, so the caller can produce
/// a "missing field" error rather than silently parsing nothing.
String? _extractDeepLinkPayload(String text) {
  final queryStart = text.indexOf('?');
  if (queryStart == -1) {
    return null;
  }
  final query = text.substring(queryStart + 1);
  for (final pair in query.split('&')) {
    if (pair.isEmpty) {
      continue;
    }
    final eq = pair.indexOf('=');
    if (eq == -1) {
      continue;
    }
    final key = _percentDecode(pair.substring(0, eq)).toLowerCase();
    if (key == 'url' || key == 'config') {
      return _percentDecode(pair.substring(eq + 1));
    }
  }
  return null;
}

/// Whether [text] plausibly holds more than one entry.
///
/// A single URI never contains a raw newline, so a newline (or a very long
/// single token with no `://`) is the cheap discriminator. Base64
/// subscription blobs have no `://` at all and fall through to the
/// subscription branch naturally.
bool _looksMultiEntry(String text) {
  if (text.contains('\n')) {
    return true;
  }
  return false;
}

/// Parses a sing-box outbound object, or an array of them.
Result<List<OutboundConfig>, ConfigParseError> _parseJsonOutbounds(
  String text,
) {
  final decoded = safeJsonDecode(
    text,
    field: 'json config',
    maxLength: maxSubscriptionLength,
  );
  if (decoded case Err(:final error)) {
    return Err(error);
  }
  final value = (decoded as Ok<Object?, ConfigParseError>).value;

  if (value is List) {
    return _readOutboundList(value, 'json config');
  }

  if (value is Map) {
    // A full sing-box config wraps its entries in {"outbounds": [...]}.
    final wrapped = value['outbounds'];
    if (wrapped is List) {
      return _readOutboundList(wrapped, 'outbounds');
    }
    final parsed = readSingBoxOutboundJson(value.cast<String, dynamic>());
    if (parsed case Err(:final error)) {
      return Err(error);
    }
    return Ok<List<OutboundConfig>, ConfigParseError>([
      (parsed as Ok<OutboundConfig, ConfigParseError>).value,
    ]);
  }

  return Err(InvalidSyntaxError('json config', 'not an object or array'));
}

/// Reads a decoded JSON list of outbound objects.
Result<List<OutboundConfig>, ConfigParseError> _readOutboundList(
  List<Object?> entries,
  String field,
) {
  if (entries.isEmpty) {
    return Err(InvalidSyntaxError(field, 'empty list'));
  }
  final outbounds = <OutboundConfig>[];
  for (final entry in entries) {
    if (entry is! Map) {
      return Err(InvalidSyntaxError(field, 'entry is not an object'));
    }
    final parsed = readSingBoxOutboundJson(entry.cast<String, dynamic>());
    if (parsed case Err(:final error)) {
      return Err(error);
    }
    outbounds.add((parsed as Ok<OutboundConfig, ConfigParseError>).value);
  }
  return Ok<List<OutboundConfig>, ConfigParseError>(outbounds);
}

const int _maxDeepLinkDepth = 3;

String _percentDecode(String input) {
  try {
    return Uri.decodeComponent(input);
  } on ArgumentError {
    return input;
  }
}
