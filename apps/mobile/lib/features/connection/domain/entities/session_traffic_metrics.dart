// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart' show immutable;

/// Immutable snapshot representing traffic metrics for a VPN session.
///
/// Contains cumulative byte counts (session totals) and instantaneous transfer
/// rates (speeds in bytes per second) derived from `TrafficStats` deltas.
///
/// Like `TrafficStats` in `core_domain`, this class intentionally has no
/// `toString` override to prevent connection telemetry from leaking into logs
/// (`SECURITY.md` Section 4).
@immutable
final class SessionTrafficMetrics {
  /// Creates an immutable [SessionTrafficMetrics] instance.
  const SessionTrafficMetrics({
    this.txBytes = 0,
    this.rxBytes = 0,
    this.txBytesPerSec = 0,
    this.rxBytesPerSec = 0,
    this.lastUpdated,
    this.hasError = false,
  });

  /// Default baseline representing a zero/reset session.
  static const SessionTrafficMetrics zero = SessionTrafficMetrics();

  /// Total bytes transmitted during the current session.
  final int txBytes;

  /// Total bytes received during the current session.
  final int rxBytes;

  /// Instantaneous upload throughput in bytes per second.
  /// Always non-negative and finite (free of NaN and Infinity).
  final double txBytesPerSec;

  /// Instantaneous download throughput in bytes per second.
  /// Always non-negative and finite (free of NaN and Infinity).
  final double rxBytesPerSec;

  /// Timestamp of the latest snapshot used to calculate these metrics, if any.
  final DateTime? lastUpdated;

  /// Whether a stream fault occurred while receiving traffic statistics.
  final bool hasError;

  /// Creates a copy of this instance with the given fields replaced.
  SessionTrafficMetrics copyWith({
    int? txBytes,
    int? rxBytes,
    double? txBytesPerSec,
    double? rxBytesPerSec,
    DateTime? lastUpdated,
    bool? hasError,
  }) {
    return SessionTrafficMetrics(
      txBytes: txBytes ?? this.txBytes,
      rxBytes: rxBytes ?? this.rxBytes,
      txBytesPerSec: txBytesPerSec ?? this.txBytesPerSec,
      rxBytesPerSec: rxBytesPerSec ?? this.rxBytesPerSec,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      hasError: hasError ?? this.hasError,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionTrafficMetrics &&
          other.txBytes == txBytes &&
          other.rxBytes == rxBytes &&
          other.txBytesPerSec == txBytesPerSec &&
          other.rxBytesPerSec == rxBytesPerSec &&
          other.lastUpdated == lastUpdated &&
          other.hasError == hasError;

  @override
  int get hashCode => Object.hash(
    txBytes,
    rxBytes,
    txBytesPerSec,
    rxBytesPerSec,
    lastUpdated,
    hasError,
  );
}
