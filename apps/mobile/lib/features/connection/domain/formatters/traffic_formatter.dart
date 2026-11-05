// SPDX-License-Identifier: GPL-3.0-or-later

/// Zero-dependency formatting utilities for traffic byte counts and rates.
///
/// Formats binary IEC units (1024 basis) deterministically across integer and
/// floating-point values.
abstract final class TrafficFormatter {
  static const List<String> _byteUnits = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  static const List<String> _speedUnits = [
    'B/s',
    'KiB/s',
    'MiB/s',
    'GiB/s',
    'TiB/s',
  ];

  /// Formats [bytes] into a human-readable IEC binary string
  /// (e.g. `0 B`, `1.5 KiB`, `2.0 MiB`, `1.2 GiB`).
  ///
  /// Clamps negative byte values to 0. Displays integers with 0 decimal places
  /// for `B`, and 1 decimal place for `KiB` and above.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024.0 && unit < _byteUnits.length - 1) {
      value /= 1024.0;
      unit++;
    }
    final rendered = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$rendered ${_byteUnits[unit]}';
  }

  /// Formats [bytesPerSec] into a human-readable transfer rate string
  /// (e.g. `0 B/s`, `512 B/s`, `12.4 KiB/s`, `3.5 MiB/s`).
  ///
  /// Clamps negative, NaN, or infinite rates to 0. Displays integers with 0
  /// decimal places for `B/s`, and 1 decimal place for `KiB/s` and above.
  static String formatSpeed(double bytesPerSec) {
    if (bytesPerSec.isNaN || bytesPerSec.isInfinite || bytesPerSec <= 0.0) {
      return '0 B/s';
    }
    var value = bytesPerSec;
    var unit = 0;
    while (value >= 1024.0 && unit < _speedUnits.length - 1) {
      value /= 1024.0;
      unit++;
    }
    final rendered = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$rendered ${_speedUnits[unit]}';
  }

  /// Formats [duration] into standard elapsed time notation `HH:MM:SS`
  /// (e.g. `00:00:00`, `01:05:30`).
  ///
  /// Clamps negative durations to `00:00:00`.
  static String formatDuration(Duration duration) {
    if (duration.isNegative) return '00:00:00';
    final totalSeconds = duration.inSeconds;
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
