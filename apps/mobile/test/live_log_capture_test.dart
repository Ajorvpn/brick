// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/log_buffer.dart';
import 'package:mobile/core/logging/log_entry.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';

/// Test engine providing fine-grained control over log events and errors.
class FakeLogEngine implements VpnEngine {
  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast(sync: true);
  final StreamController<TrafficStats> _statsController =
      StreamController<TrafficStats>.broadcast(sync: true);
  final StreamController<String> _logController =
      StreamController<String>.broadcast(sync: true);

  @override
  Stream<ConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<TrafficStats> get trafficStats => _statsController.stream;

  @override
  Stream<String> get logEvents => _logController.stream;

  void emitLog(String line) => _logController.add(line);

  void emitLogError(Object error) => _logController.addError(error);

  @override
  Future<ConnectionState> getStatus() async => const Disconnected();

  @override
  Future<VpnCommandResult> start(ServerProfile profile) async =>
      const VpnCommandAccepted();

  @override
  Future<VpnCommandResult> stop() async => const VpnCommandAccepted();

  @override
  Future<VpnCommandResult> prepare() async => const VpnCommandAccepted();

  Future<void> dispose() async {
    await _stateController.close();
    await _statsController.close();
    await _logController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testTempDir;
  late FakeLogEngine fakeEngine;

  setUp(() async {
    testTempDir = await Directory.systemTemp.createTemp(
      'live_log_capture_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getTemporaryDirectory') {
              return testTempDir.path;
            }
            return null;
          },
        );
    fakeEngine = FakeLogEngine();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await fakeEngine.dispose();
    if (testTempDir.existsSync()) {
      await testTempDir.delete(recursive: true);
    }
  });

  group('LogEntry & LogLevel Parsing', () {
    final fixedTime = DateTime.utc(2026, 11, 5, 12);

    test('parses ISO8601 timestamped log line with level and source', () {
      const raw =
          '2026-11-05T12:00:00.123Z [INFO] router: '
          'match rule[0] inbound/mixed -> direct';
      final entry = LogEntry.parseEngineLine(raw, fallbackTimestamp: fixedTime);

      expect(entry.level, equals(LogLevel.info));
      expect(
        entry.timestamp,
        equals(DateTime.parse('2026-11-05T12:00:00.123Z')),
      );
      expect(entry.source, equals('router'));
      expect(entry.message, equals('match rule[0] inbound/mixed -> direct'));
      expect(entry.raw, equals(raw));
    });

    test('parses sing-box leading timezone offset and bracketed level', () {
      const raw = '+0000 2026-11-05 14:30:00 WARN [tun] mtu too small';
      final entry = LogEntry.parseEngineLine(raw, fallbackTimestamp: fixedTime);

      expect(entry.level, equals(LogLevel.warning));
      expect(entry.timestamp, equals(DateTime.utc(2026, 11, 5, 14, 30)));
      expect(entry.source, equals('tun'));
      expect(entry.message, equals('mtu too small'));
      expect(entry.raw, equals(raw));
    });

    test(
      'parses sing-box leading timezone offset +0330 and converts to exact UTC',
      () {
        const raw = '+0330 2026-11-05 14:30:00 WARN [tun] mtu too small';
        final entry = LogEntry.parseEngineLine(
          raw,
          fallbackTimestamp: fixedTime,
        );

        expect(entry.level, equals(LogLevel.warning));
        // 14:30:00 with +03:30 offset is exactly 11:00:00 UTC
        expect(entry.timestamp, equals(DateTime.utc(2026, 11, 5, 11)));
        expect(entry.source, equals('tun'));
        expect(entry.message, equals('mtu too small'));
        expect(entry.raw, equals(raw));
      },
    );

    test('parses structured JSON log line', () {
      const raw =
          '{"time":"2026-11-05T15:00:00Z","level":"error",'
          '"msg":"connection refused","tag":"outbound/vless"}';
      final entry = LogEntry.parseEngineLine(raw, fallbackTimestamp: fixedTime);

      expect(entry.level, equals(LogLevel.error));
      expect(entry.timestamp, equals(DateTime.parse('2026-11-05T15:00:00Z')));
      expect(entry.source, equals('outbound/vless'));
      expect(entry.message, equals('connection refused'));
      expect(entry.raw, equals(raw));
    });

    test('parses all LogLevel variants correctly', () {
      expect(
        LogEntry.parseEngineLine(
          '[TRACE] packet dump',
          fallbackTimestamp: fixedTime,
        ).level,
        equals(LogLevel.trace),
      );
      expect(
        LogEntry.parseEngineLine(
          '[DEBUG] payload 64 bytes',
          fallbackTimestamp: fixedTime,
        ).level,
        equals(LogLevel.debug),
      );
      expect(
        LogEntry.parseEngineLine(
          '[INFO] tunnel open',
          fallbackTimestamp: fixedTime,
        ).level,
        equals(LogLevel.info),
      );
      expect(
        LogEntry.parseEngineLine(
          '[WARN] retransmitting',
          fallbackTimestamp: fixedTime,
        ).level,
        equals(LogLevel.warning),
      );
      expect(
        LogEntry.parseEngineLine(
          '[ERROR] handshake failure',
          fallbackTimestamp: fixedTime,
        ).level,
        equals(LogLevel.error),
      );
      expect(
        LogEntry.parseEngineLine(
          '[FATAL] panic at nil pointer',
          fallbackTimestamp: fixedTime,
        ).level,
        equals(LogLevel.fatal),
      );
    });

    test(
      'falls back to LogLevel.info and fallbackTimestamp for plain lines',
      () {
        const raw = 'Starting tunnel backend';
        final entry = LogEntry.parseEngineLine(
          raw,
          fallbackTimestamp: fixedTime,
        );

        expect(entry.level, equals(LogLevel.info));
        expect(entry.timestamp, equals(fixedTime));
        expect(entry.message, equals('Starting tunnel backend'));
        expect(entry.source, isNull);
        expect(entry.raw, equals(raw));
      },
    );

    test('handles empty or whitespace-only lines without throwing', () {
      const raw = '   ';
      final entry = LogEntry.parseEngineLine(raw, fallbackTimestamp: fixedTime);

      expect(entry.level, equals(LogLevel.info));
      expect(entry.timestamp, equals(fixedTime));
      expect(entry.message, isEmpty);
      expect(entry.raw, equals(raw));
    });

    test('value equality, hashCode, and copyWith behave predictably', () {
      final entry1 = LogEntry(
        timestamp: fixedTime,
        level: LogLevel.info,
        message: 'hello',
        source: 'tun',
        raw: 'hello',
      );
      final entry2 = LogEntry(
        timestamp: fixedTime,
        level: LogLevel.info,
        message: 'hello',
        source: 'tun',
        raw: 'hello',
      );
      final entry3 = entry1.copyWith(message: 'world');

      expect(entry1, equals(entry2));
      expect(entry1.hashCode, equals(entry2.hashCode));
      expect(entry1, isNot(equals(entry3)));
      // SECURITY.md Section 4: toString() must not leak unredacted log payload
      expect(entry1.toString(), isNot(contains('hello')));
    });
  });

  group('LogBuffer Memory Bounding & FIFO Eviction', () {
    test('starts empty and retains entries in FIFO order', () {
      final buffer = LogBuffer(maxCapacity: 5);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, equals(0));

      final now = DateTime.now().toUtc();
      for (var i = 1; i <= 3; i++) {
        buffer.add(
          LogEntry(
            timestamp: now,
            level: LogLevel.info,
            message: 'msg #$i',
            raw: 'msg #$i',
          ),
        );
      }

      expect(buffer.length, equals(3));
      expect(buffer.first.message, equals('msg #1'));
      expect(buffer.last.message, equals('msg #3'));
    });

    test(
      '5,000 line stress test: bounds memory growth and maintains FIFO order',
      () {
        final buffer = LogBuffer(maxCapacity: 500);
        final baseTime = DateTime.utc(2026, 11, 5);

        // Artificially high log volume: emit 5,000 log entries
        for (var i = 1; i <= 5000; i++) {
          buffer.add(
            LogEntry(
              timestamp: baseTime.add(Duration(seconds: i)),
              level: LogLevel.info,
              message: 'entry #$i',
              raw: 'entry #$i',
            ),
          );
        }

        // Buffer strictly capped at 500
        expect(buffer.length, equals(500));
        expect(buffer.toList().length, equals(500));

        // Oldest entries (1..4500) were evicted; entries 4501..5000 remain
        expect(buffer.first.message, equals('entry #4501'));
        expect(buffer.last.message, equals('entry #5000'));

        // Order is preserved sequentially
        final snapshot = buffer.toList();
        for (var j = 0; j < 500; j++) {
          expect(snapshot[j].message, equals('entry #${4501 + j}'));
        }
      },
    );

    test('clear() empties all entries', () {
      final buffer = LogBuffer(maxCapacity: 10)
        ..addAll([
          LogEntry(
            timestamp: DateTime.now().toUtc(),
            level: LogLevel.info,
            message: 'one',
            raw: 'one',
          ),
          LogEntry(
            timestamp: DateTime.now().toUtc(),
            level: LogLevel.info,
            message: 'two',
            raw: 'two',
          ),
        ]);
      expect(buffer.length, equals(2));

      buffer.clear();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, equals(0));
    });
  });

  group('LogManager & Provider Integration', () {
    test('Burst Coalescing: 1,000 rapid log lines coalesce into single '
        'microtask UI notification', () async {
      final container = ProviderContainer(
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      );
      addTearDown(container.dispose);

      var notificationCount = 0;
      container
        ..listen<ListQueue<String>>(logManagerProvider, (previous, next) {
          notificationCount++;
        })
        ..read(logManagerProvider);
      expect(notificationCount, equals(0));

      // Rapid burst: emit 1,000 log lines in a tight synchronous loop
      for (var i = 1; i <= 1000; i++) {
        fakeEngine.emitLog('burst line #$i');
      }

      // Before yielding to microtask queue, listeners are NOT spammed
      expect(notificationCount, equals(0));

      // Yield to microtask / event loop
      await pumpEventQueue();

      // Exactly one coalesced state notification fired
      expect(notificationCount, equals(1));

      // String buffer capped at maxBufferSize (300)
      final stringLogs = container.read(logManagerProvider);
      expect(stringLogs.length, equals(LogManager.maxBufferSize));
      expect(stringLogs.first, equals('burst line #701'));
      expect(stringLogs.last, equals('burst line #1000'));

      // Structured buffer capped at maxBufferSize (300) matching string buffer
      final structured = container.read(structuredLogEntriesProvider);
      expect(structured.length, equals(LogManager.maxBufferSize));
      expect(structured.first.message, equals('burst line #701'));
      expect(structured.last.message, equals('burst line #1000'));
    });

    test('Stream Error Resilience: error on engine.logEvents is absorbed '
        'gracefully without crashing', () async {
      final container = ProviderContainer(
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      );
      addTearDown(container.dispose);

      container.read(logManagerProvider);
      await pumpEventQueue();

      // Emit an unexpected platform stream error
      fakeEngine.emitLogError(
        Exception('dev.brickvpn.harness channel interrupted'),
      );
      await pumpEventQueue();

      // Pipeline is resilient: continues receiving subsequent log lines
      fakeEngine.emitLog('recovered line after error');
      await pumpEventQueue();

      final logs = container.read(logManagerProvider);
      expect(logs.last, equals('recovered line after error'));
    });

    test('clear() empties ring buffers and truncates temporary file', () async {
      final container = ProviderContainer(
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      );
      addTearDown(container.dispose);

      container.read(logManagerProvider);
      await pumpEventQueue();

      for (var i = 1; i <= 10; i++) {
        fakeEngine.emitLog('log item #$i');
      }
      await pumpEventQueue();

      expect(container.read(logManagerProvider).length, equals(10));
      expect(container.read(structuredLogEntriesProvider).length, equals(10));

      // Call clear()
      await container.read(logManagerProvider.notifier).clear();
      await pumpEventQueue();

      expect(container.read(logManagerProvider), isEmpty);
      expect(container.read(structuredLogEntriesProvider), isEmpty);

      // Verify temp log file exists and is empty / truncated
      final logFile = File('${testTempDir.path}/${LogManager.logFileName}');
      if (logFile.existsSync()) {
        expect(logFile.readAsStringSync().trim(), isEmpty);
      }
    });

    test(
      'structuredLogEntriesProvider provides typed LogLevel and parsed fields',
      () async {
        final container = ProviderContainer(
          overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
        );
        addTearDown(container.dispose);

        container.read(structuredLogEntriesProvider);
        await pumpEventQueue();

        fakeEngine
          ..emitLog('2026-11-05 10:00:00 INFO [router] default route set')
          ..emitLog('2026-11-05 10:00:01 WARN [dns] fallback server used')
          ..emitLog('2026-11-05 10:00:02 ERROR [tun] write failed');
        await pumpEventQueue();

        final entries = container.read(structuredLogEntriesProvider);
        expect(entries.length, equals(3));

        expect(entries[0].level, equals(LogLevel.info));
        expect(entries[0].source, equals('router'));
        expect(entries[0].message, equals('default route set'));

        expect(entries[1].level, equals(LogLevel.warning));
        expect(entries[1].source, equals('dns'));
        expect(entries[1].message, equals('fallback server used'));

        expect(entries[2].level, equals(LogLevel.error));
        expect(entries[2].source, equals('tun'));
        expect(entries[2].message, equals('write failed'));
      },
    );
  });
}
