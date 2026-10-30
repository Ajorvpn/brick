// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'log_manager.g.dart';

/// Manages live streaming logs from the native VPN engine.
///
/// CRITICAL ARCHITECTURAL CONSTRAINTS:
/// 1. RAM Protection: Keeps at most [maxBufferSize] (300) lines in memory
///    using a bounded [ListQueue<String>].
/// 2. Asynchronous File Streaming: Streams all lines to a temporary file
///    `brick_vpn_live.log` using [IOSink] with [FileMode.write], which
///    automatically clears past session logs on initialization to protect
///    privacy.
/// 3. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.
@Riverpod(keepAlive: true)
class LogManager extends _$LogManager {
  static const int maxBufferSize = 300;
  static const String logFileName = 'brick_vpn_live.log';

  final ListQueue<String> _buffer = ListQueue<String>(maxBufferSize);
  IOSink? _sink;
  StreamSubscription<String>? _subscription;

  @override
  ListQueue<String> build() {
    final engine = ref.read(vpnEngineProvider);
    unawaited(_subscription?.cancel());
    _subscription = engine.logEvents.listen(_handleLogEvent);

    unawaited(_initSink());

    ref.onDispose(() {
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
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$logFileName');
      // Explicit FileMode.write ensures file truncation across sessions.
      // ignore: avoid_redundant_argument_values
      _sink = file.openWrite(mode: FileMode.write);
      final sink = _sink;
      if (sink != null) {
        _buffer.forEach(sink.writeln);
      }
    } on Object catch (e) {
      debugPrint('LogManager: unable to initialize temp log file: $e');
    }
  }

  void _handleLogEvent(String log) {
    if (_buffer.length >= maxBufferSize) {
      _buffer.removeFirst();
    }
    _buffer.addLast(log);

    try {
      _sink?.writeln(log);
    } on Object catch (_) {}

    state = ListQueue<String>.from(_buffer);
  }
}
