// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

/// Severity levels for native VPN engine log events.
enum LogLevel {
  trace,
  debug,
  info,
  warning,
  error,
  fatal;

  /// Returns true if this level is [warning], [error], or [fatal].
  bool get isWarningOrError =>
      this == LogLevel.warning ||
      this == LogLevel.error ||
      this == LogLevel.fatal;

  /// Standard label for display and serialization.
  String get label => name.toUpperCase();
}

/// An immutable structured log entry captured from the VPN engine.
///
/// Designed per Phase 6 / Phase 8 architecture to keep log fields
/// structured (timestamp, level, message, source) rather than flattened
/// into opaque strings, allowing Phase 8 (P8-T2) to inspect and redact
/// sensitive fields cleanly without relying exclusively on regex matching.
///
/// SECURITY NOTE (SECURITY.md Section 4): [toString] is intentionally NOT
/// overridden to prevent accidental leakage of sensitive log lines in
/// crash reports, console traces, or string interpolations.
@immutable
final class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
    required this.raw,
  });

  /// Deterministically parses a raw engine log line into a [LogEntry].
  ///
  /// Supports:
  /// - JSON structured lines: `{"level":"info","time":"...","msg":"..."}`
  /// - sing-box lines: `[INFO] 2026-11-05 12:00:00 router: match rule`
  /// - timezone-prefixed lines: `+0330 2026-11-05 14:30:00 WARN [tun] ...`
  /// - timestamped lines: `2026-11-05 12:00:00.123 [INFO] ...`
  /// - bracketed / prefixed levels: `[WARN] ...`, `ERROR: ...`, `level=info`
  /// - plain lines: falls back to [LogLevel.info] and [fallbackTimestamp].
  factory LogEntry.parseEngineLine(
    String rawLine, {
    DateTime? fallbackTimestamp,
  }) {
    final now = fallbackTimestamp ?? DateTime.now().toUtc();
    final trimmed = rawLine.trim();

    if (trimmed.isEmpty) {
      return LogEntry(
        timestamp: now,
        level: LogLevel.info,
        message: '',
        raw: rawLine,
      );
    }

    // 1. Check for JSON formatted logs
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final levelStr =
              decoded['level'] ??
              decoded['severity'] ??
              decoded['lvl'] ??
              decoded['log_level'];
          final level = _parseLevel(levelStr?.toString());

          final timeVal =
              decoded['time'] ??
              decoded['timestamp'] ??
              decoded['ts'] ??
              decoded['@timestamp'];
          final timestamp = _parseTimestamp(timeVal) ?? now;

          final msg =
              decoded['message'] ??
              decoded['msg'] ??
              decoded['text'] ??
              decoded['error'] ??
              '';
          final source =
              decoded['source'] ??
              decoded['tag'] ??
              decoded['caller'] ??
              decoded['logger'] ??
              decoded['component'];

          return LogEntry(
            timestamp: timestamp,
            level: level,
            message: msg.toString(),
            source: source?.toString(),
            raw: rawLine,
          );
        }
      } on Object catch (_) {
        // Fall through to regex-based text parsing on JSON decode failure
      }
    }

    // 2. Text log parsing with regular expressions
    DateTime? parsedTimestamp;
    LogLevel? parsedLevel;
    String? parsedSource;
    var working = trimmed;

    // A. Parse sing-box leading timezone offset + timestamp:
    // e.g. "+0330 2026-11-05 14:30:00"
    final tzLeadingMatch = RegExp(
      r'^([+-]\d{4})\s+(\d{4}[-/]\d{2}[-/]\d{2})[T ](\d{2}:\d{2}:\d{2}(?:\.\d+)?)\b',
    ).firstMatch(working);
    if (tzLeadingMatch != null) {
      final rawTz = tzLeadingMatch.group(1)!;
      final dateStr = tzLeadingMatch.group(2)!;
      final timeStr = tzLeadingMatch.group(3)!;
      final formattedTz = '${rawTz.substring(0, 3)}:${rawTz.substring(3, 5)}';
      final iso = '${dateStr}T$timeStr$formattedTz';
      final dt = DateTime.tryParse(iso)?.toUtc();
      if (dt != null) {
        parsedTimestamp = dt;
        working = working
            .replaceRange(tzLeadingMatch.start, tzLeadingMatch.end, '')
            .trim();
      }
    } else {
      // Standard timestamp without leading timezone offset:
      final tsMatch = _timestampRegex.firstMatch(working);
      if (tsMatch != null) {
        final tsStr = tsMatch.group(0)!;
        final dt = _parseTimestamp(tsStr);
        if (dt != null) {
          parsedTimestamp = dt;
          working = working.replaceRange(tsMatch.start, tsMatch.end, '').trim();
        }
      }
    }

    // B. Parse log level:
    // Matches [INFO], [WARN], INFO:, level=info, or standalone level words
    final levelMatch = _levelRegex.firstMatch(working);
    if (levelMatch != null) {
      final rawLevel = levelMatch.group(1) ?? levelMatch.group(2);
      parsedLevel = _parseLevel(rawLevel);
      working = working
          .replaceRange(levelMatch.start, levelMatch.end, '')
          .trim();
    }

    // C. Parse source tag: e.g. [inbound/mixed] or router: or [dns]
    final sourceMatch = _sourceRegex.firstMatch(working);
    if (sourceMatch != null) {
      parsedSource = sourceMatch.group(1) ?? sourceMatch.group(2);
      if (sourceMatch.start == 0) {
        working = working
            .replaceRange(sourceMatch.start, sourceMatch.end, '')
            .trim();
      }
    }

    // D. Clean leading colon or dashes if left behind
    working = working.replaceFirst(RegExp(r'^[:\-\s]+'), '').trim();

    return LogEntry(
      timestamp: parsedTimestamp ?? now,
      level: parsedLevel ?? LogLevel.info,
      message: working.isEmpty ? trimmed : working,
      source: parsedSource,
      raw: rawLine,
    );
  }

  /// The timestamp when the log entry occurred.
  final DateTime timestamp;

  /// The severity level of this log entry.
  final LogLevel level;

  /// The clean log message payload without level/timestamp prefixes.
  final String message;

  /// Optional subsystem or component tag (e.g., 'router', 'tun', 'dns').
  final String? source;

  /// The raw, unparsed log line received from the engine.
  final String raw;

  static LogLevel _parseLevel(String? str) {
    if (str == null) return LogLevel.info;
    final upper = str.toUpperCase().trim();
    switch (upper) {
      case 'TRACE':
      case 'TRC':
        return LogLevel.trace;
      case 'DEBUG':
      case 'DBG':
        return LogLevel.debug;
      case 'WARN':
      case 'WARNING':
      case 'WRN':
        return LogLevel.warning;
      case 'ERROR':
      case 'ERR':
        return LogLevel.error;
      case 'FATAL':
      case 'PANIC':
      case 'CRIT':
      case 'CRITICAL':
        return LogLevel.fatal;
      case 'INFO':
      case 'INF':
      default:
        return LogLevel.info;
    }
  }

  static DateTime? _parseTimestamp(dynamic val) {
    if (val == null) return null;
    if (val is int) {
      if (val > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(val, isUtc: true);
      }
      return DateTime.fromMillisecondsSinceEpoch(val * 1000, isUtc: true);
    }
    final str = val.toString().trim();
    final iso = str.contains(' ') ? str.replaceFirst(' ', 'T') : str;
    return DateTime.tryParse(iso)?.toUtc() ?? DateTime.tryParse(str)?.toUtc();
  }

  static final RegExp _timestampRegex = RegExp(
    r'\b\d{4}[-/]\d{2}[-/]\d{2}(?:[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?\b',
  );

  static final RegExp _levelRegex = RegExp(
    r'(?:\[(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL)\]|\b(?:level=)?(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL)\b:?)',
    caseSensitive: false,
  );

  static final RegExp _sourceRegex = RegExp(
    r'(?:^\[([a-zA-Z0-9_\-\/]+)\]|^([a-zA-Z0-9_\-\/]+):)',
  );

  LogEntry copyWith({
    DateTime? timestamp,
    LogLevel? level,
    String? message,
    String? source,
    String? raw,
  }) {
    return LogEntry(
      timestamp: timestamp ?? this.timestamp,
      level: level ?? this.level,
      message: message ?? this.message,
      source: source ?? this.source,
      raw: raw ?? this.raw,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogEntry &&
          runtimeType == other.runtimeType &&
          timestamp == other.timestamp &&
          level == other.level &&
          message == other.message &&
          source == other.source &&
          raw == other.raw;

  @override
  int get hashCode => Object.hash(timestamp, level, message, source, raw);
}
