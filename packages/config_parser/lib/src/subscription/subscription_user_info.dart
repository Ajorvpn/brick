// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';

/// Traffic-quota and expiry metadata a subscription provider returns in the
/// `Subscription-Userinfo` response header.
///
/// Header format (semicolon-separated key=value pairs):
/// `upload=12345; download=67890; total=1000000; expire=1735689600`
///
/// This is a pure immutable value object with value equality. It carries no
/// credential material: the byte counts and an expiry timestamp are not
/// sensitive, and no user password, UUID, or subscription token is ever
/// stored here (SECURITY.md §2).
final class SubscriptionUserInfo {
  /// Creates a usage record. Every field is optional because providers
  /// routinely omit some of them.
  const SubscriptionUserInfo({
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expiresAt,
  });

  /// Bytes uploaded so far in the current period, if reported.
  final int? uploadBytes;

  /// Bytes downloaded so far in the current period, if reported.
  final int? downloadBytes;

  /// Total bytes allowed for the period, if reported.
  final int? totalBytes;

  /// When the quota expires, if an `expire` value was present.
  final DateTime? expiresAt;

  /// Total bytes consumed (upload + download), or null when either is absent.
  int? get usedBytes {
    final up = uploadBytes;
    final down = downloadBytes;
    if (up == null || down == null) {
      return null;
    }
    return up + down;
  }

  /// Fraction of the quota consumed in `[0, 1]`, or null when unknown.
  ///
  /// Returns 0 when the quota is zero or absent rather than dividing by
  /// zero, so a malformed header can never produce NaN or an exception.
  double? get usedFraction {
    final used = usedBytes;
    final total = totalBytes;
    if (used == null || total == null || total <= 0) {
      return null;
    }
    return (used / total).clamp(0.0, 1.0);
  }

  /// Parses a `Subscription-Userinfo` header value.
  ///
  /// Tolerant by design: a provider that reports only some keys still parses,
  /// and unrecognised or malformed pairs are ignored rather than failing the
  /// whole header. Returns `Err` only when [headerValue] carries none of the
  /// recognised keys at all, which means there is nothing to represent.
  ///
  /// The raw header is never echoed into the returned error.
  static Result<SubscriptionUserInfo, ConfigParseError> parse(
    String headerValue,
  ) {
    if (headerValue.trim().isEmpty) {
      return Err(InvalidSyntaxError('Subscription-Userinfo', 'empty'));
    }

    int? upload;
    int? download;
    int? total;
    DateTime? expires;
    var recognised = 0;

    for (final pair in headerValue.split(';')) {
      final trimmed = pair.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final separator = trimmed.indexOf('=');
      if (separator == -1) {
        continue;
      }
      final key = trimmed.substring(0, separator).trim().toLowerCase();
      final value = trimmed.substring(separator + 1).trim();

      switch (key) {
        case 'upload':
          final parsed = int.tryParse(value);
          if (parsed != null && parsed >= 0) {
            upload = parsed;
            recognised++;
          }
        case 'download':
          final parsed = int.tryParse(value);
          if (parsed != null && parsed >= 0) {
            download = parsed;
            recognised++;
          }
        case 'total':
          final parsed = int.tryParse(value);
          if (parsed != null && parsed >= 0) {
            total = parsed;
            recognised++;
          }
        case 'expire':
          final seconds = int.tryParse(value);
          if (seconds != null && seconds > 0) {
            expires = DateTime.fromMillisecondsSinceEpoch(
              seconds * 1000,
              isUtc: true,
            );
            recognised++;
          }
        default:
          // Unknown key (some providers add their own): ignore silently.
          break;
      }
    }

    if (recognised == 0) {
      return Err(
        InvalidSyntaxError('Subscription-Userinfo', 'no recognised keys'),
      );
    }

    return Ok<SubscriptionUserInfo, ConfigParseError>(
      SubscriptionUserInfo(
        uploadBytes: upload,
        downloadBytes: download,
        totalBytes: total,
        expiresAt: expires,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionUserInfo &&
          other.uploadBytes == uploadBytes &&
          other.downloadBytes == downloadBytes &&
          other.totalBytes == totalBytes &&
          other.expiresAt == expiresAt;

  @override
  int get hashCode =>
      Object.hash(uploadBytes, downloadBytes, totalBytes, expiresAt);
}
