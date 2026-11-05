// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';

import 'package:mobile/core/logging/log_entry.dart';

/// Bounded in-memory ring buffer of [LogEntry] items.
///
/// Ensures memory growth is strictly bounded by evicting the oldest
/// entries in O(1) time when [maxCapacity] is reached.
class LogBuffer {
  LogBuffer({this.maxCapacity = defaultCapacity})
    : assert(maxCapacity > 0, 'maxCapacity must be positive');

  /// Default ring buffer capacity (300 entries per memory protection limits).
  static const int defaultCapacity = 300;

  /// The maximum number of entries to retain in memory.
  final int maxCapacity;

  final ListQueue<LogEntry> _queue = ListQueue<LogEntry>();

  /// The current number of entries in the buffer.
  int get length => _queue.length;

  /// Whether the buffer has no entries.
  bool get isEmpty => _queue.isEmpty;

  /// Whether the buffer contains at least one entry.
  bool get isNotEmpty => _queue.isNotEmpty;

  /// Oldest entry in the buffer. Throws [StateError] if empty.
  LogEntry get first => _queue.first;

  /// Newest entry in the buffer. Throws [StateError] if empty.
  LogEntry get last => _queue.last;

  /// Adds a new [LogEntry] to the buffer, evicting the oldest entry in O(1)
  /// if the buffer is at capacity.
  void add(LogEntry entry) {
    if (_queue.length >= maxCapacity) {
      _queue.removeFirst();
    }
    _queue.addLast(entry);
  }

  /// Adds multiple [LogEntry] items in sequence.
  void addAll(Iterable<LogEntry> entries) {
    entries.forEach(add);
  }

  /// Empties the buffer.
  void clear() {
    _queue.clear();
  }

  /// Returns an unmodifiable snapshot list of entries (oldest to newest).
  List<LogEntry> toList() => List<LogEntry>.unmodifiable(_queue);

  /// Returns a copy of the underlying [ListQueue].
  ListQueue<LogEntry> toQueue() => ListQueue<LogEntry>.from(_queue);

  /// Iterable over the entries in the buffer.
  Iterable<LogEntry> get entries => _queue;
}
