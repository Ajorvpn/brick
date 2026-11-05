// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:mobile/features/connection/domain/entities/session_traffic_metrics.dart';

/// Pure calculator that transforms a stream of raw [TrafficStats] snapshots
/// into [SessionTrafficMetrics].
///
/// Invariants enforced:
/// 1. First snapshot of a session: instantaneous transfer rates are clamped to
///    0 to prevent false initial spikes if the native counter starts with
///    accumulated bytes.
/// 2. Subsequent snapshots: transfer rates are computed as
///    `(deltaBytes * 1000) / deltaMs`.
/// 3. Zero duration (`deltaMs <= 0`) or clock skew: clamped to `0 B/s` (never
///    divides by zero).
/// 4. Counter reset (`deltaBytes < 0`): clamped to `0 B/s`.
/// 5. Output rates are strictly non-negative and finite (free of NaN and
///    Infinity).
class SessionTrafficMetricsCalculator {
  TrafficStats? _previous;

  /// Resets the calculator baseline to start a fresh session calculation.
  void reset() {
    _previous = null;
  }

  /// Calculates the next [SessionTrafficMetrics] for [current].
  SessionTrafficMetrics process(TrafficStats current) {
    final previous = _previous;
    _previous = current;

    final tx = current.txBytes < 0 ? 0 : current.txBytes;
    final rx = current.rxBytes < 0 ? 0 : current.rxBytes;

    if (previous == null) {
      // First snapshot: cumulative reflects snapshot, speeds clamped to 0.
      return SessionTrafficMetrics(
        txBytes: tx,
        rxBytes: rx,
        lastUpdated: current.timestamp,
      );
    }

    final deltaMs = current.timestamp
        .difference(previous.timestamp)
        .inMilliseconds;
    final deltaTx = current.txBytes - previous.txBytes;
    final deltaRx = current.rxBytes - previous.rxBytes;

    final double txRate;
    if (deltaMs <= 0 || deltaTx <= 0) {
      txRate = 0;
    } else {
      final calculated = (deltaTx * 1000.0) / deltaMs;
      txRate = (calculated.isNaN || calculated.isInfinite || calculated < 0.0)
          ? 0
          : calculated;
    }

    final double rxRate;
    if (deltaMs <= 0 || deltaRx <= 0) {
      rxRate = 0;
    } else {
      final calculated = (deltaRx * 1000.0) / deltaMs;
      rxRate = (calculated.isNaN || calculated.isInfinite || calculated < 0.0)
          ? 0
          : calculated;
    }

    return SessionTrafficMetrics(
      txBytes: tx,
      rxBytes: rx,
      txBytesPerSec: txRate,
      rxBytesPerSec: rxRate,
      lastUpdated: current.timestamp,
    );
  }
}
