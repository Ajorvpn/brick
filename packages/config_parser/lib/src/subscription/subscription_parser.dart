// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../parsers/uri_parser.dart';
import 'subscription_decoder.dart';
import 'subscription_user_info.dart';

/// The outcome of parsing a whole subscription payload.
///
/// This type exists to make fault tolerance explicit: a subscription is
/// untrusted bulk input from a third party, and a single bad line must never
/// discard the good ones. [configs] holds everything that parsed;
/// [errors] records every line that did not, alongside a count of the
/// lines skipped as blank/comment text.
final class SubscriptionParseResult {
  /// Creates a result.
  const SubscriptionParseResult({
    required this.configs,
    required this.errors,
    required this.totalLineCount,
    required this.skippedLineCount,
    this.userInfo,
  });

  /// Every server configuration that parsed successfully, in input order.
  final List<OutboundConfig> configs;

  /// One error per line that failed to parse, in input order.
  ///
  /// These are non-fatal: they explain which entries were dropped without
  /// discarding [configs]. Error objects carry field names and reasons only,
  /// never the offending URI (SECURITY.md §2).
  final List<ConfigParseError> errors;

  /// Total candidate URI lines seen after decoding.
  final int totalLineCount;

  /// Blank/comment lines filtered out before parsing.
  final int skippedLineCount;

  /// Quota/expiry metadata from the `Subscription-Userinfo` header, when the
  /// provider supplied one.
  final SubscriptionUserInfo? userInfo;

  /// Number of servers successfully parsed.
  int get parsedCount => configs.length;

  /// Number of lines that failed to parse.
  int get failedCount => errors.length;

  /// Whether every candidate line parsed.
  bool get isComplete => errors.isEmpty && configs.isNotEmpty;
}

/// Parses a whole subscription payload into per-server configurations.
///
/// Returns `Err` only when the payload as a whole is unusable (empty, or
/// oversized, or contains no URIs at all). Once the payload is decodable,
/// every line is parsed independently: a malformed link is collected into
/// [SubscriptionParseResult.errors] and parsing continues, so one hostile or
/// broken entry cannot discard an otherwise valid subscription.
///
/// [userInfoHeaderValue] is the raw `Subscription-Userinfo` header, when the
/// caller has one. A malformed header is ignored rather than failing the
/// subscription, since the servers themselves are still usable.
Result<SubscriptionParseResult, ConfigParseError> parseSubscription(
  String rawBody, {
  String? userInfoHeaderValue,
}) {
  final decoded = decodeSubscriptionBody(rawBody);
  if (decoded case Err(:final error)) {
    return Err(error);
  }
  final body = (decoded as Ok<DecodedSubscription, ConfigParseError>).value;

  final configs = <OutboundConfig>[];
  final errors = <ConfigParseError>[];

  for (final line in body.lines) {
    final parsed = parseUri(line);
    switch (parsed) {
      case Ok(:final value):
        configs.add(value);
      case Err(:final error):
        // Fault tolerance: record and continue.
        errors.add(error);
    }
  }

  SubscriptionUserInfo? userInfo;
  if (userInfoHeaderValue != null && userInfoHeaderValue.isNotEmpty) {
    final parsedInfo = SubscriptionUserInfo.parse(userInfoHeaderValue);
    if (parsedInfo is Ok) {
      userInfo =
          (parsedInfo as Ok<SubscriptionUserInfo, ConfigParseError>).value;
    }
  }

  if (configs.isEmpty && errors.isEmpty) {
    return Err(UnknownParseError('subscription produced no entries'));
  }

  return Ok<SubscriptionParseResult, ConfigParseError>(
    SubscriptionParseResult(
      configs: configs,
      errors: errors,
      totalLineCount: body.lines.length,
      skippedLineCount: body.skippedLineCount,
      userInfo: userInfo,
    ),
  );
}
