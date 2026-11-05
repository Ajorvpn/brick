// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:mobile/core/logging/log_buffer.dart';
import 'package:mobile/core/logging/log_entry.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'log_manager.g.dart';

/// Manages live streaming logs from the native VPN engine.
///
/// CRITICAL ARCHITECTURAL CONSTRAINTS:
/// 1. RAM Protection: Keeps at most [maxBufferSize] (300) lines in memory
///    for string consumers and structured entries in a bounded [LogBuffer].
/// 2. Burst Coalescing: Coalesces high-volume bursts per microtask so rapid
///    log streams do not flood the UI thread with hundreds of rebuilds.
/// 3. Stream Resilience: Catches and absorbs errors from engine logEvents
///    gracefully without disrupting the VPN connection or UI.
/// 4. Asynchronous File Streaming: Streams all lines to a temporary file
///    `brick_vpn_live.log` using [IOSink] with default write mode, which
///    automatically clears past session logs on initialization to protect
///    privacy.
/// 5. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.
@Riverpod(keepAlive: true)
class LogManager extends _$LogManager {
  static const int maxBufferSize = 300;
  static const String logFileName = 'brick_vpn_live.log';

  final ListQueue<String> _buffer = ListQueue<String>(maxBufferSize);
  final LogBuffer _structuredBuffer = LogBuffer();
  IOSink? _sink;
  StreamSubscription<String>? _subscription;
  bool _isBatchScheduled = false;
  bool _disposed = false;
  int _sinkGeneration = 0;
  Future<void>? _pendingSinkOp;

  /// Structured entries in the bounded ring buffer (oldest to newest).
  List<LogEntry> get structuredEntries => _structuredBuffer.toList();

  /// Direct queue of structured entries.
  ListQueue<LogEntry> get structuredQueue => _structuredBuffer.toQueue();

  @override
  ListQueue<String> build() {
    _disposed = false;
    final engine = ref.read(vpnEngineProvider);
    unawaited(_subscription?.cancel());
    _subscription = engine.logEvents.listen(
      _handleLogEvent,
      onError: (Object error, StackTrace stackTrace) {
        // Stream error resilience: absorb gracefully without crashing or
        // disrupting tunnel connection. Zero console leakage per SECURITY.md.
      },
      cancelOnError: false,
    );

    unawaited(_initSink());

    ref.onDispose(() {
      _disposed = true;
      _sinkGeneration++;
      _isBatchScheduled = false;
      unawaited(_subscription?.cancel());
      _subscription = null;
      final sink = _sink;
      _sink = null;
      if (sink != null) {
        unawaited(sink.close());
      }
    });

    return ListQueue<String>.from(_buffer);
  }

  Future<void> _initSink() async {
    final currentGen = ++_sinkGeneration;
    final completer = Completer<void>();
    final prevOp = _pendingSinkOp;
    _pendingSinkOp = completer.future;

    try {
      if (prevOp != null) {
        await prevOp;
      }
      if (_disposed || currentGen != _sinkGeneration) return;

      final tempDir = await getTemporaryDirectory();
      if (_disposed || currentGen != _sinkGeneration) return;

      final file = File('${tempDir.path}/$logFileName');
      final sink = file.openWrite();
      if (_disposed || currentGen != _sinkGeneration) {
        unawaited(sink.close());
        return;
      }

      _sink = sink;
      _buffer.forEach(sink.writeln);
    } on Object catch (_) {
      // Silently absorb local file I/O failures to prevent leaking raw errors.
    } finally {
      completer.complete();
    }
  }

  void _handleLogEvent(String log) {
    // 1. Structured parsing and insertion into bounded ring buffer
    final entry = LogEntry.parseEngineLine(log);
    _structuredBuffer.add(entry);

    // 2. String buffer with FIFO eviction (O(1))
    if (_buffer.length >= maxBufferSize) {
      _buffer.removeFirst();
    }
    _buffer.addLast(log);

    // 3. Asynchronous file stream
    try {
      _sink?.writeln(log);
    } on Object catch (_) {}

    // 4. Burst coalescing via microtask
    _scheduleStateUpdate();
  }

  void _scheduleStateUpdate() {
    if (_isBatchScheduled) return;
    _isBatchScheduled = true;
    scheduleMicrotask(() {
      if (_disposed) return;
      _isBatchScheduled = false;
      state = ListQueue<String>.from(_buffer);
    });
  }

  /// Empties the in-memory ring buffers and truncates the temporary log file.
  Future<void> clear() async {
    _buffer.clear();
    _structuredBuffer.clear();
    state = ListQueue<String>.from(_buffer);

    final currentGen = ++_sinkGeneration;
    final completer = Completer<void>();
    final prevOp = _pendingSinkOp;
    _pendingSinkOp = completer.future;

    try {
      if (prevOp != null) {
        await prevOp;
      }
      if (_disposed || currentGen != _sinkGeneration) return;

      final oldSink = _sink;
      _sink = null;
      if (oldSink != null) {
        await oldSink.flush();
        await oldSink.close();
      }
      if (_disposed || currentGen != _sinkGeneration) return;

      final tempDir = await getTemporaryDirectory();
      if (_disposed || currentGen != _sinkGeneration) return;

      final file = File('${tempDir.path}/$logFileName');
      final sink = file.openWrite();
      if (_disposed || currentGen != _sinkGeneration) {
        unawaited(sink.close());
        return;
      }
      _sink = sink;
    } on Object catch (_) {
      // Silently absorb local file I/O failures to prevent leaking raw errors.
    } finally {
      completer.complete();
    }
  }
}

/// Structured log entries from the native VPN engine's bounded buffer.
@Riverpod(keepAlive: true)
List<LogEntry> structuredLogEntries(Ref ref) {
  ref.watch(logManagerProvider);
  return ref.read(logManagerProvider.notifier).structuredEntries;
}
