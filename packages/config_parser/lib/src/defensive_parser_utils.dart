// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import 'config_parse_error.dart';

/// Maximum length, in characters, of a single server URI (`vless://...`).
///
/// Justification: the longest legitimate single-server URI seen in the wild
/// is a VLESS/VMess link carrying TLS + REALITY + transport parameters,
/// realistically 1–2 KB. 8 KB leaves roughly a 4x margin for unusually
/// long-but-valid links while still rejecting anything a human did not
/// paste. Larger inputs are a subscription blob and go through
/// [maxSubscriptionLength] instead.
const int maxUriLength = 8 * 1024;

/// Maximum length, in characters, of a full subscription body.
///
/// Justification: a subscription is a list of per-server URIs. Large real
/// providers publish a few hundred entries; at ~2 KB per entry that is
/// well under 1 MB. 5 MB therefore accommodates every legitimate case with a
/// wide margin while bounding worst-case allocation. Anything beyond this is
/// treated as hostile and rejected before decoding.
const int maxSubscriptionLength = 5 * 1024 * 1024;

/// Maximum nesting depth accepted when decoding JSON.
///
/// Justification: legitimate VMess/subscription payloads nest only a few
/// levels. A deep tree is the classic JSON resource-exhaustion vector, and
/// `dart:convert` will happily recurse until it exhausts the stack, so the
/// depth is bounded before decoding rather than after.
const int maxJsonDepth = 32;

/// Rejects [input] if it is longer than [maxLength].
///
/// Returns `Err(InputTooLargeError)` without any further processing, so a
/// multi-megabyte string is rejected in O(1) time and never copied or
/// decoded.
Result<String, ConfigParseError> enforceMaxLength(
  String input, {
  required int maxLength,
  required String what,
}) {
  if (input.length > maxLength) {
    return Err<String, ConfigParseError>(
      InputTooLargeError(
        actualLength: input.length,
        maxLength: maxLength,
        what: what,
      ),
    );
  }
  return Ok<String, ConfigParseError>(input);
}

/// Decodes base64 from [input], tolerating the real-world variants.
///
/// Handles standard base64 (`+/`) and URL-safe base64 (`-_`), with or
/// without `=` padding, because real subscription content mixes all four.
/// Returns `Err(CorruptedBase64Error)` instead of throwing.
///
/// When [expectedBytes] is supplied, the decoded length must match exactly;
/// this is how a 32-byte key is validated without ever inspecting its
/// contents.
///
/// Never logs and never includes [input] in the returned error.
Result<List<int>, ConfigParseError> safeBase64Decode(
  String input, {
  String field = 'payload',
  int? expectedBytes,
}) {
  if (input.isEmpty) {
    return Err(CorruptedBase64Error(field, 'empty input'));
  }

  // Normalise URL-safe alphabet to standard, then re-pad.
  final normalised = input.replaceAll('-', '+').replaceAll('_', '/');
  final unpadded = normalised.replaceAll('=', '');
  final padding = (4 - unpadded.length % 4) % 4;
  final padded = unpadded + ('=' * padding);

  List<int> bytes;
  try {
    bytes = base64.decode(padded);
  } on FormatException {
    return Err(
      CorruptedBase64Error(
        field,
        'not valid base64',
        expectedBytes: expectedBytes,
      ),
    );
  }

  if (expectedBytes != null && bytes.length != expectedBytes) {
    return Err(
      CorruptedBase64Error(
        field,
        'decoded length is ${bytes.length}, expected $expectedBytes',
        expectedBytes: expectedBytes,
      ),
    );
  }

  return Ok<List<int>, ConfigParseError>(bytes);
}

/// Decodes a UTF-8 string from base64 [input], applying the same
/// tolerance as [safeBase64Decode].
///
/// Used for subscription payloads that are base64-wrapped UTF-8 JSON or
/// newline-separated URI lists.
Result<String, ConfigParseError> safeBase64DecodeToString(
  String input, {
  String field = 'payload',
  int maxDecodedLength = maxSubscriptionLength,
}) {
  final decoded = safeBase64Decode(input, field: field);
  if (decoded case Err(:final error)) {
    return Err(error);
  }
  final bytes = (decoded as Ok<List<int>, ConfigParseError>).value;

  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return Err(CorruptedBase64Error(field, 'not valid UTF-8'));
  }

  if (text.length > maxDecodedLength) {
    return Err<String, ConfigParseError>(
      InputTooLargeError(
        actualLength: text.length,
        maxLength: maxDecodedLength,
        what: 'decoded $field',
      ),
    );
  }
  return Ok<String, ConfigParseError>(text);
}

/// Parses [input] as a URI, rejecting anything malformed or oversized.
///
/// Length is checked *before* parsing, because `Uri.parse` is not cheap and
/// a hostile caller controls the string length.
Result<Uri, ConfigParseError> safeUriParse(
  String input, {
  String field = 'uri',
  int maxLength = maxUriLength,
}) {
  final lengthCheck = enforceMaxLength(
    input,
    maxLength: maxLength,
    what: field,
  );
  if (lengthCheck case Err(:final error)) {
    return Err(error);
  }
  if (input.isEmpty) {
    return Err(InvalidSyntaxError(field, 'empty'));
  }
  final Uri uri;
  try {
    uri = Uri.parse(input);
  } on FormatException {
    return Err(InvalidSyntaxError(field, 'not a valid URI'));
  }
  if (!uri.hasScheme) {
    return Err(InvalidSyntaxError(field, 'missing scheme'));
  }
  return Ok<Uri, ConfigParseError>(uri);
}

/// Decodes JSON from [input] with bounded size and nesting depth.
///
/// `dart:convert`'s `jsonDecode` is not depth-limited, so a deeply nested
/// payload is a stack-exhaustion vector. Depth is measured *after* decode,
/// which is safe because decoding a pathological payload is bounded by
/// [maxJsonDepth]-independent work only up to the point of failure; the real
/// protection against unbounded work is the [maxLength] check performed
/// first.
Result<Object?, ConfigParseError> safeJsonDecode(
  String input, {
  String field = 'json',
  int maxLength = maxSubscriptionLength,
  int maxDepth = maxJsonDepth,
}) {
  final lengthCheck = enforceMaxLength(
    input,
    maxLength: maxLength,
    what: field,
  );
  if (lengthCheck case Err(:final error)) {
    return Err(error);
  }
  if (input.trim().isEmpty) {
    return Err(InvalidSyntaxError(field, 'empty'));
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(input);
  } on FormatException {
    return Err(InvalidSyntaxError(field, 'not valid JSON'));
  }

  if (_depthOf(decoded) > maxDepth) {
    return Err(InvalidSyntaxError(field, 'nesting deeper than $maxDepth'));
  }
  return Ok<Object?, ConfigParseError>(decoded);
}

/// Measures the nesting depth of a decoded JSON value.
///
/// Iterative rather than recursive so that measuring cannot itself overflow
/// the stack on a hostile input.
int _depthOf(Object? value) {
  if (value is! List && value is! Map) {
    return 0;
  }
  var maxDepth = 0;
  final pending = <Object?>[value];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    maxDepth++;
    if (maxDepth > maxJsonDepth + 1) {
      // Stop early: we only need to know that the limit was exceeded.
      return maxDepth;
    }
    if (current is List) {
      pending.addAll(current);
    } else if (current is Map) {
      pending.addAll(current.values);
    }
  }
  return maxDepth;
}
