// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';

import 'localization_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testTempDir;
  late FakeVpnEngine fakeEngine;

  setUp(() async {
    testTempDir = await Directory.systemTemp.createTemp('log_manager_test_');
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
    fakeEngine = FakeVpnEngine();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (testTempDir.existsSync()) {
      await testTempDir.delete(recursive: true);
    }
  });

  test('LogManager starts with empty queue and captures log events', () async {
    final container = ProviderContainer(
      overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
    );
    addTearDown(container.dispose);

    final initialLogs = container.read(logManagerProvider);
    expect(initialLogs, isEmpty);

    fakeEngine
      ..emitLog('test line 1')
      ..emitLog('test line 2');
    await pumpEventQueue();

    final updatedLogs = container.read(logManagerProvider);
    expect(updatedLogs.toList(), ['test line 1', 'test line 2']);
  });

  test(
    'LogManager caps memory buffer at maxBufferSize (300 entries)',
    () async {
      final container = ProviderContainer(
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      )..read(logManagerProvider);
      addTearDown(container.dispose);

      // Emit 350 log lines
      for (var i = 1; i <= 350; i++) {
        fakeEngine.emitLog('log event #$i');
      }
      await pumpEventQueue();

      final logs = container.read(logManagerProvider);
      expect(logs.length, equals(LogManager.maxBufferSize));
      expect(logs.first, equals('log event #51'));
      expect(logs.last, equals('log event #350'));
    },
  );

  test('LogManager streams logs asynchronously to temporary file', () async {
    final container = ProviderContainer(
      overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
    )..read(logManagerProvider);

    // Wait a tick for _initSink to complete
    await pumpEventQueue();

    fakeEngine
      ..emitLog('persisted line 1')
      ..emitLog('persisted line 2');
    await pumpEventQueue();

    // Dispose container to flush and close sink
    container.dispose();
    await pumpEventQueue();

    final logFile = File('${testTempDir.path}/${LogManager.logFileName}');
    expect(logFile.existsSync(), isTrue);

    final content = await logFile.readAsString();
    expect(content, contains('persisted line 1\n'));
    expect(content, contains('persisted line 2\n'));
  });
}
