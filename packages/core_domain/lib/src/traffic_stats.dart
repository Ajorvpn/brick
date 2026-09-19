// SPDX-License-Identifier: GPL-3.0-or-later

/// Why this type exists: every layer that displays or records throughput
/// needs one immutable snapshot shape — bytes sent, bytes received, and the
/// moment the counters were read — so a partially updated reading can never
/// be observed.
///
/// The class is a `const`-constructible value type with value equality so
/// snapshots can be compared, cached, and tested deterministically.
/// There is intentionally no `toString` override: connection telemetry must
/// not leak into system logs via an incidental print, per SECURITY.md.
final class TrafficStats {
  /// Creates one immutable traffic snapshot.
  const TrafficStats({
    required this.txBytes,
    required this.rxBytes,
    required this.timestamp,
  });

  /// Total bytes transmitted through the tunnel at [timestamp].
  final int txBytes;

  /// Total bytes received through the tunnel at [timestamp].
  final int rxBytes;

  /// Moment the counters were read.
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrafficStats &&
          other.txBytes == txBytes &&
          other.rxBytes == rxBytes &&
          other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(txBytes, rxBytes, timestamp);
}
