// SPDX-License-Identifier: GPL-3.0-or-later

/// Why this file has no `toString` override: an error is very likely to end
/// up interpolated into a log line, a user-facing message, or a crash
/// report. `SECURITY.md` Section 2 classifies server configuration as
/// High-sensitivity data, so an error type in the parsing pipeline must be
/// incapable of carrying a credential into a log by accident. Every variant
/// below therefore stores only structural metadata (field names, sizes,
/// enum-ish reasons) and never the offending value itself.

/// A structured, exhaustive description of why a config could not be parsed.
///
/// Sealed so that a `switch` over it is checked by the analyzer: adding a
/// category later becomes a compile-time error in every consumer rather than
/// a silently unhandled runtime case. This is the `E` in the
/// `Result<ServerProfile, ConfigParseError>` convention (P2-T1
/// acceptance criteria).
///
/// Security: no variant holds the raw input that failed. `detail` fields
/// carry a short, developer-authored explanation; `field` carries a
/// key name like `'PrivateKey'`, never a key value.
sealed class ConfigParseError {
  const ConfigParseError();

  /// A stable, machine-readable category string.
  ///
  /// Safe to log and to branch on. Never includes input data.
  String get code;

  /// A short, safe, human-readable explanation.
  ///
  /// Callers may display this to a user. It MUST NOT be built by
  /// interpolating the offending input.
  String get message;
}

/// The input was syntactically invalid for the expected format.
final class InvalidSyntaxError extends ConfigParseError {
  /// Creates an invalid-syntax error for [field].
  const InvalidSyntaxError(this.field, this.reason);

  /// The field or section that failed to parse, e.g. `'vless uri'`.
  final String field;

  /// A short explanation of the syntax problem.
  final String reason;

  @override
  String get code => 'invalid_syntax';

  @override
  String get message => 'Invalid syntax in $field: $reason';
}

/// A required field was absent.
final class MissingRequiredFieldError extends ConfigParseError {
  /// Creates a missing-field error naming [field].
  const MissingRequiredFieldError(this.field);

  /// The name of the absent field, e.g. `'uuid'`. Never a value.
  final String field;

  @override
  String get code => 'missing_required_field';

  @override
  String get message => 'Missing required field: $field';
}

/// A field was present but its value was not usable.
final class InvalidFieldValueError extends ConfigParseError {
  /// Creates an invalid-value error for [field] explaining [reason].
  const InvalidFieldValueError(this.field, this.reason);

  /// The name of the offending field, e.g. `'port'`. Never a value.
  final String field;

  /// A short explanation, e.g. `'not a number in 1..65535'`.
  final String reason;

  @override
  String get code => 'invalid_field_value';

  @override
  String get message => 'Invalid value for $field: $reason';
}

/// Base64 input could not be decoded, or decoded to an unexpected size.
///
/// Note: this variant deliberately stores only the *expected* size, never
/// the decoded bytes or the input string.
final class CorruptedBase64Error extends ConfigParseError {
  /// Creates a base64 error for [field] with [reason] and [expectedBytes].
  const CorruptedBase64Error(this.field, this.reason, {this.expectedBytes});

  /// The field whose base64 payload was invalid, e.g. `'uuid'`.
  final String field;

  /// A short explanation, e.g. `'not valid base64'`.
  final String reason;

  /// The byte length the payload was required to have, when known.
  final int? expectedBytes;

  @override
  String get code => 'corrupted_base64';

  @override
  String get message => expectedBytes == null
      ? 'Corrupted base64 in $field: $reason'
      : 'Corrupted base64 in $field: $reason (expected $expectedBytes bytes)';
}

/// The URI scheme is not one this package knows how to parse.
final class UnsupportedSchemeError extends ConfigParseError {
  /// Creates an unsupported-scheme error naming [scheme].
  const UnsupportedSchemeError(this.scheme);

  /// The scheme that was not recognised, e.g. `'notavpn'`.
  ///
  /// The scheme is a short, non-sensitive token taken from the URI prefix.
  /// It is stored verbatim, but [message] echoes it only through
  /// [sanitiseEchoedIdentifier], so untrusted input cannot smuggle a
  /// credential into a log-bound string.
  final String scheme;

  @override
  String get code => 'unsupported_scheme';

  @override
  String get message =>
      'Unsupported scheme: ${sanitiseEchoedIdentifier(scheme)}';
}

/// The protocol family is not implemented.
final class UnsupportedProtocolError extends ConfigParseError {
  /// Creates an unsupported-protocol error naming [protocol].
  const UnsupportedProtocolError(this.protocol);

  /// The protocol that is not yet implemented.
  ///
  /// Stored verbatim, but [message] echoes it only through
  /// [sanitiseEchoedIdentifier] — this value can originate from an untrusted
  /// JSON `type` field, not just a curated token.
  final String protocol;

  @override
  String get code => 'unsupported_protocol';

  @override
  String get message =>
      'Unsupported protocol: ${sanitiseEchoedIdentifier(protocol)}';
}

/// The input exceeded a configured size limit.
///
/// This is a memory-exhaustion guard: `SECURITY.md` requires bounded
/// resource usage for untrusted input, and a hostile subscription could
/// otherwise allocate unbounded memory before any parsing begins.
final class InputTooLargeError extends ConfigParseError {
  /// Creates an oversized-input error.
  const InputTooLargeError({
    required this.actualLength,
    required this.maxLength,
    required this.what,
  });

  /// The length of the rejected input, in bytes or characters.
  final int actualLength;

  /// The limit that was exceeded.
  final int maxLength;

  /// What was being measured, e.g. `'subscription body'`.
  final String what;

  @override
  String get code => 'input_too_large';

  @override
  String get message =>
      '$what is too large: $actualLength exceeds the $maxLength limit';
}

/// A catch-all for a failure that does not fit a more specific category.
final class UnknownParseError extends ConfigParseError {
  /// Creates an unknown-parse error explaining [reason].
  const UnknownParseError(this.reason);

  /// A short, safe explanation of what went wrong.
  final String reason;

  @override
  String get code => 'unknown';

  @override
  String get message => 'Could not parse config: $reason';
}

/// A Shadowsocks cipher/method that sing-box does not support.
///
/// Unlike a password or UUID, a cipher name is **not** secret — it is a
/// public algorithm identifier — so including it in [message] is safe and
/// makes the error user-actionable (the user can pick a different server
/// or cipher). What is deliberately excluded is the password, which
/// accompanies the method in the same URI and must never appear here.
final class UnsupportedCipherError extends ConfigParseError {
  /// Creates an unsupported-cipher error naming [method].
  const UnsupportedCipherError(this.method);

  /// The rejected cipher/method name, verbatim from the link. Public
  /// algorithm identifier, not a credential.
  ///
  /// [message] echoes it through [sanitiseEchoedIdentifier] so a crafted
  /// `method` value cannot smuggle a credential into a log-bound string.
  final String method;

  @override
  String get code => 'unsupported_cipher';

  @override
  String get message =>
      'Unsupported Shadowsocks cipher: ${sanitiseEchoedIdentifier(method)}. '
      'This server may require a '
      'cipher this client does not support.';
}

/// Sanitises a caller-supplied identifier before it is echoed into an error
/// message.
///
/// `UnsupportedSchemeError` and `UnsupportedProtocolError` are handed a token
/// taken straight from untrusted pasted input. The intent is that it is a
/// short, non-sensitive identifier, but nothing enforces that: a hostile or
/// merely malformed payload can put a credential (or an entire base64 key) in
/// the `type` field of a JSON object, and it would then be reproduced verbatim
/// in a message destined for a log or a UI banner.
///
/// This keeps the diagnostic value of a genuine token while removing the leak:
/// only short, identifier-shaped values survive, and anything else is reported
/// as a shape mismatch rather than echoed.
String sanitiseEchoedIdentifier(String raw) {
  const maxLength = 32;
  if (raw.isEmpty) {
    return '(empty)';
  }
  if (raw.length > maxLength) {
    return '(over $maxLength chars)';
  }
  // Allow only what a real scheme/protocol token can contain.
  final isIdentifier = raw.codeUnits.every((c) {
    final isLower = c >= 0x61 && c <= 0x7a; // a-z
    final isDigit = c >= 0x30 && c <= 0x39; // 0-9
    final isHyphen = c == 0x2d; // -
    return isLower || isDigit || isHyphen;
  });
  return isIdentifier ? raw : '(unprintable)';
}

/// A network operation exceeded its deadline.
///
/// `SECURITY.md` requires bounded resource usage on untrusted input, and a
/// network request to a hostile or merely broken provider is unbounded by
/// nature. No URL, host or header value is stored: a subscription URL usually
/// embeds an access token, so it must never reach a log through an error.
final class NetworkTimeoutError extends ConfigParseError {
  /// Creates a timeout error for [operation], which took [timeout].
  const NetworkTimeoutError(this.operation, this.timeout);

  /// A developer-authored label for what timed out, e.g. `'subscription fetch'`.
  final String operation;

  /// The deadline that was exceeded.
  final Duration timeout;

  @override
  String get code => 'network_timeout';

  @override
  String get message => 'Timed out after ${timeout.inSeconds}s: $operation';
}

/// The subscription URL was not HTTPS.
///
/// HTTPS is mandatory with no fallback and no user override
/// (`SECURITY.md` §6). The [scheme] is echoed through
/// [sanitiseEchoedIdentifier]; the host and path are deliberately **not**
/// stored, because a subscription URL typically embeds an access token.
final class InsecureTransportError extends ConfigParseError {
  /// Creates an insecure-transport error for [scheme].
  const InsecureTransportError(this.scheme);

  /// The rejected URL scheme, e.g. `'http'`.
  final String scheme;

  @override
  String get code => 'insecure_transport';

  @override
  String get message =>
      'Subscription URLs must use HTTPS; got '
      '${sanitiseEchoedIdentifier(scheme)}.';
}

/// The server returned a non-success HTTP status.
///
/// Only the numeric [statusCode] is stored. Response bodies from a failing
/// endpoint are untrusted and may echo the request URL (and therefore its
/// token) back at us, so the body is never retained.
final class HttpStatusError extends ConfigParseError {
  /// Creates an HTTP-status error for [statusCode].
  const HttpStatusError(this.statusCode);

  /// The HTTP status code returned, e.g. `403`.
  final int statusCode;

  @override
  String get code => 'http_status';

  @override
  String get message => 'Subscription request failed with HTTP $statusCode';
}

/// The server redirected more times than allowed.
///
/// A redirect chain is an attacker-controlled loop; bounding it is a
/// resource-safety requirement, not a nicety.
final class TooManyRedirectsError extends ConfigParseError {
  /// Creates a redirect-limit error for [limit] hops.
  const TooManyRedirectsError(this.limit);

  /// The maximum number of redirects that was permitted.
  final int limit;

  @override
  String get code => 'too_many_redirects';

  @override
  String get message =>
      'Subscription request exceeded the redirect limit of $limit';
}

/// The transport failed for a reason other than a timeout or a bad status.
///
/// [reason] is a developer-authored category, never a raw exception message:
/// `dart:io` exception strings can embed the host, and therefore the
/// subscription token.
final class NetworkFailureError extends ConfigParseError {
  /// Creates a network-failure error of category [reason].
  const NetworkFailureError(this.reason);

  /// A short, developer-authored category, e.g. `'connection refused'`.
  final String reason;

  @override
  String get code => 'network_failure';

  @override
  String get message => 'Subscription request failed: $reason';
}

/// The fetched bytes were not valid UTF-8.
///
/// The body is not stored and not echoed: a hostile provider controls it.
final class ResponseDecodingError extends ConfigParseError {
  /// Creates a decoding error for [what].
  const ResponseDecodingError(this.what);

  /// What could not be decoded, e.g. `'subscription body'`.
  final String what;

  @override
  String get code => 'response_decoding';

  @override
  String get message => 'Could not decode the $what as UTF-8 text';
}
