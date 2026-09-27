// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart';

/// A decoded subscription body split into candidate server URIs.
final class DecodedSubscription {
  /// Creates a decoded subscription carrying [lines], of which
  /// [skippedLineCount] were blank or comment lines.
  const DecodedSubscription(this.lines, this.skippedLineCount);

  /// The non-empty, non-comment lines that look like server URIs.
  ///
  /// A line is kept if it is non-blank, is not a comment, and contains a
  /// `scheme://` marker. Lines that are none of those (HTML error pages,
  /// stray text) are dropped here so the bulk parser never has to.
  final List<String> lines;

  /// How many lines were dropped as blank or comment lines.
  final int skippedLineCount;
}

/// Decodes a raw subscription payload into candidate server URIs.
///
/// Providers serve subscriptions in two shapes, sometimes both in the wild:
///
///  * **Base64** — the whole body is base64 of the newline-separated URI
///    list. Padded and unpadded base64 are both accepted, as are the
///    URL-safe alphabet and the standard one (see [safeBase64DecodeToString]).
///  * **Plain text** — the body is already newline-separated URIs.
///
/// Detection is content-based rather than flag-based, because a caller
/// cannot know which a given provider uses, and because some providers serve
/// plain text that *looks* base64-ish.
///
/// Security: the payload is size-bounded by [maxSubscriptionLength] before
/// any decoding, and a decoded body is bounded again. Nothing from the
/// payload is echoed into a returned error.
Result<DecodedSubscription, ConfigParseError> decodeSubscriptionBody(
  String rawBody,
) {
  final lengthCheck = enforceMaxLength(
    rawBody,
    maxLength: maxSubscriptionLength,
    what: 'subscription body',
  );
  if (lengthCheck case Err(:final error)) {
    return Err(error);
  }

  var text = rawBody.trim();
  if (text.isEmpty) {
    return Err(InvalidSyntaxError('subscription body', 'empty'));
  }

  // Strip a UTF-8 BOM if the provider emitted one.
  if (text.startsWith('\uFEFF')) {
    text = text.substring(1).trim();
  }

  if (_looksLikeBase64(text)) {
    final decoded = safeBase64DecodeToString(text, field: 'subscription body');
    // A base64-looking string that does not decode is more useful treated
    // as plain text than rejected outright: some providers send plain text
    // whose first line happens to be alphanumeric.
    if (decoded is Ok) {
      text = (decoded as Ok<String, ConfigParseError>).value;
    }
  }

  final lines = <String>[];
  var skipped = 0;
  for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      skipped++;
      continue;
    }
    // Comment styles seen in the wild.
    if (line.startsWith('#') ||
        line.startsWith('//') ||
        line.startsWith(';') ||
        line.startsWith('<!--')) {
      skipped++;
      continue;
    }
    // Must look like a URI we could route.
    if (!line.contains('://')) {
      skipped++;
      continue;
    }
    lines.add(line);
  }

  if (lines.isEmpty) {
    return Err(UnknownParseError('subscription contained no server URIs'));
  }

  return Ok<DecodedSubscription, ConfigParseError>(
    DecodedSubscription(lines, skipped),
  );
}

/// Whether [text] is plausibly a base64 blob.
///
/// Requires the whole body to consist of base64 alphabet characters, a
/// length that is a valid base64 length (mod 4 of 0, 2 or 3 — never 1), and
/// no whitespace. The latter is the key discriminator: a base64 subscription
/// is a single unbroken line, whereas plain text contains `://` and spaces.
bool _looksLikeBase64(String text) {
  if (text.contains(RegExp(r'\s'))) {
    return false;
  }
  if (text.contains('://')) {
    return false;
  }
  if (text.length % 4 == 1) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(text);
}
