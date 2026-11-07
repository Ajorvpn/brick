// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:mobile/core/logging/log_buffer.dart';
import 'package:mobile/core/logging/log_entry.dart';
import 'package:mobile/core/logging/log_redactor.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
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
  final Set<String> _knownSecrets = <String>{};
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

  /// Registers additional secrets to scrub from all incoming logs.
  void registerKnownSecrets(Iterable<String> secrets) {
    _knownSecrets.addAll(secrets.where((s) => s.trim().length >= 4));
  }

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

    ref.listen<AsyncValue<List<SavedServer>>>(savedServersProvider, (_, next) {
      final servers = next.asData?.value;
      if (servers != null) {
        for (final server in servers) {
          if (server is SavedServerProfile) {
            registerKnownSecrets(
              LogRedactor.extractSecretsFromProfile(server.profile),
            );
          }
        }
      }
    }, fireImmediately: true);

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
    // Immediate ingestion-level redaction across all surfaces
    final safeLine = LogRedactor.redactRawLine(
      log,
      knownSecrets: _knownSecrets,
    );
    final entry = LogEntry.fromRaw(safeLine, knownSecrets: _knownSecrets);

    // 1. Structured parsing and insertion into bounded ring buffer
    _structuredBuffer.add(entry);

    // 2. String buffer with FIFO eviction (O(1))
    if (_buffer.length >= maxBufferSize) {
      _buffer.removeFirst();
    }
    _buffer.addLast(safeLine);

    // 3. Asynchronous file stream
    try {
      _sink?.writeln(safeLine);
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

  /// Ensures all pending sink initialization and writes have flushed to disk.
  Future<void> flushFile() async {
    final op = _pendingSinkOp;
    if (op != null) {
      await op;
    }
    try {
      await _sink?.flush();
    } on Object catch (_) {}
  }

  /// Records a non-sensitive diagnostic log line (e.g. lifecycle,
  /// network change, or auto-reconnect events).
  ///
  /// Safe to call from controllers and providers; automatically stamped with
  /// UTC timestamp and INFO level, adhering to SECURITY.md Section 4 (Zero
  /// Secrets).
  void recordDiagnostic(String message) {
    if (_disposed) return;
    final now = DateTime.now().toUtc();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    final timeStr = '$y-$m-$d $hh:$mm:$ss';
    _handleLogEvent('$timeStr INFO $message');
  }
}

/// Structured log entries from the native VPN engine's bounded buffer.
@Riverpod(keepAlive: true)
List<LogEntry> structuredLogEntries(Ref ref) {
  ref.watch(logManagerProvider);
  return ref.read(logManagerProvider.notifier).structuredEntries;
}
