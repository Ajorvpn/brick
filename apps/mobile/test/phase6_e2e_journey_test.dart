// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        Disconnected,
        Disconnecting,
        Error,
        PlatformError,
        TrafficStats;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

const String _testVlessUri =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443#Tokyo%20Node';

void main() {
  setUpAll(initTestLocalization);

  late Directory testTempDir;
  String? clipboardText;

  setUp(() async {
    clipboardText = null;
    testTempDir = await Directory.systemTemp.createTemp('phase6_e2e_test_');
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'Clipboard.setData') {
            clipboardText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          } else if (methodCall.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    if (testTempDir.existsSync()) {
      await testTempDir.delete(recursive: true);
    }
  });

  group('Phase 6 Complete End-to-End User Journey (P6-T1 — P6-T7)', () {
    testWidgets('executes the entire Phase 6 lifecycle across two full '
        'connect/disconnect cycles', (tester) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      final fakePrefs = FakeAppPreferencesRepository();
      addTearDown(engine.dispose);

      // Pre-seed an active server profile
      await buildRepository(dataSource).addServer(_testVlessUri);

      // Boot into MyApp shell
      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
        preferencesRepository: fakePrefs,
      );

      // =====================================================================
      // STEP 1: Verify Initial Resting State (Disconnected)
      // =====================================================================
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Server: Tokyo Node (vless)'), findsOneWidget);
      expect(find.text('Tunnel: Disconnected'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);
      expect(find.text('0 B up / 0 B down'), findsOneWidget);
      expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);

      // =====================================================================
      // STEP 2: Cycle 1 — Connect Transition & Duration Timer
      // =====================================================================
      final toggleBtn = find.byKey(
        const ValueKey<String>('home_connect_toggle_button'),
      );
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pump();

      engine.emit(const Connecting());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tunnel: Connecting'), findsOneWidget);

      engine.emit(const Connected());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tunnel: Connected'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);

      // Advance timer 4 seconds
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Duration: 00:00:04'), findsOneWidget);

      // =====================================================================
      // STEP 3: Cycle 1 — Traffic Stats Plumbing & Delta Calculation
      // =====================================================================
      final t0 = DateTime.utc(2026, 11, 5, 12);
      // First snapshot: rate clamped to 0 B/s to prevent initial false spike
      engine.emitStats(
        TrafficStats(txBytes: 1024, rxBytes: 2048, timestamp: t0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1.0 KiB up / 2.0 KiB down'), findsOneWidget);
      expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);

      // Second snapshot 1s later: rates compute to 2.0 KiB/s up, 4.0 KiB/s down
      final t1 = t0.add(const Duration(seconds: 1));
      engine.emitStats(
        TrafficStats(txBytes: 3072, rxBytes: 6144, timestamp: t1),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('3.0 KiB up / 6.0 KiB down'), findsOneWidget);
      expect(find.text('Speed: ↑ 2.0 KiB/s · ↓ 4.0 KiB/s'), findsOneWidget);

      // =====================================================================
      // STEP 4: Cycle 1 — Live Log Capture, Structured View & Export
      // =====================================================================
      // Switch to Logs tab (pump frame + animation duration)
      await tester.tap(find.byIcon(Icons.article_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.widgetWithText(AppBar, 'Logs'), findsOneWidget);

      engine
        ..emitLog('2026-11-05 12:00:00 INFO Initializing tunnel')
        ..emitLog('2026-11-05 12:00:01 WARN [tun] Latency spike')
        ..emitLog('2026-11-05 12:00:02 ERROR [dns] Query timed out');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey<String>('log_level_badge_info_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('log_level_badge_warning_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('log_level_badge_error_2')),
        findsOneWidget,
      );
      expect(find.text('Initializing tunnel'), findsOneWidget);
      expect(find.text('Latency spike'), findsOneWidget);
      expect(find.text('Query timed out'), findsOneWidget);

      // Open non-dismissible privacy warning dialog
      await tester.tap(find.byKey(const ValueKey<String>('logs_copy_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
        findsOneWidget,
      );

      // Barrier tap does not dismiss dialog
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
        findsOneWidget,
      );

      // Confirm copy to clipboard
      await tester.tap(
        find.byKey(const ValueKey<String>('logs_copy_confirm_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
        findsNothing,
      );
      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('Initializing tunnel'));
      expect(clipboardText, contains('Query timed out'));
      expect(find.text('Logs copied to clipboard'), findsOneWidget);

      // Clear logs buffer
      await tester.tap(find.byKey(const ValueKey<String>('logs_clear_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No log entries yet'), findsOneWidget);

      // =====================================================================
      // STEP 5: Cycle 1 — Disconnect Cleanly
      // =====================================================================
      await tester.tap(find.byIcon(Icons.home));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(toggleBtn);
      await tester.pump();
      engine.emit(const Disconnecting());
      await tester.pumpAndSettle();
      expect(find.text('Tunnel: Disconnecting'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);

      engine.emit(const Disconnected());
      await tester.pumpAndSettle();
      expect(find.text('Tunnel: Disconnected'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);
      expect(find.text('0 B up / 0 B down'), findsOneWidget);
      expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);

      // =====================================================================
      // STEP 6: Cycle 2 — Reconnect & Baseline Reset Verification
      // =====================================================================
      await tester.tap(toggleBtn);
      await tester.pump();

      engine.emit(const Connecting());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      engine.emit(const Connected());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tunnel: Connected'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);

      // Cycle 2 Traffic Snapshot 1: proves Cycle 1 baseline was wiped
      final t20 = DateTime.utc(2026, 11, 5, 12, 10);
      engine.emitStats(
        TrafficStats(txBytes: 512, rxBytes: 1024, timestamp: t20),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('512 B up / 1.0 KiB down'), findsOneWidget);
      expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);

      // Cycle 2 Traffic Snapshot 2 (1s later): delta rate computes cleanly
      final t21 = t20.add(const Duration(seconds: 1));
      engine.emitStats(
        TrafficStats(txBytes: 2560, rxBytes: 5120, timestamp: t21),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('2.5 KiB up / 5.0 KiB down'), findsOneWidget);
      expect(find.text('Speed: ↑ 2.0 KiB/s · ↓ 4.0 KiB/s'), findsOneWidget);

      // Cycle 2 Duration Timer: starts fresh from 0, not 00:00:04!
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Duration: 00:00:03'), findsOneWidget);

      // Cycle 2 Live Logs: only shows fresh log line, no Cycle 1 leakage
      await tester.tap(find.byIcon(Icons.article_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.widgetWithText(AppBar, 'Logs'), findsOneWidget);

      engine.emitLog('2026-11-05 12:10:05 INFO Cycle 2 active');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Cycle 2 active'), findsOneWidget);
      expect(find.text('Initializing tunnel'), findsNothing);

      // Return to Home
      await tester.tap(find.byIcon(Icons.home));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // =====================================================================
      // STEP 7: Mid-Session Error State Verification (Acceptance Criterion 3)
      // =====================================================================
      // Deliberately induce an unexpected disconnect error while Connected
      engine.emit(
        const Error(PlatformError('Simulated unexpected disconnect')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Tunnel: Connection error'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);
      expect(find.text('0 B up / 0 B down'), findsOneWidget);
      expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);

      // Clean recovery / teardown to Disconnected by user cancel
      await tester.tap(toggleBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      engine.emit(const Disconnected());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Tunnel: Disconnected'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);
      expect(find.text('0 B up / 0 B down'), findsOneWidget);
      expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);
    });
  });
}
