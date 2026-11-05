// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/logs/presentation/screens/logs_screen.dart';
import 'package:mobile/features/settings/presentation/screens/live_logs_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  late Directory testTempDir;
  late FakeVpnEngine fakeEngine;
  String? clipboardText;

  setUp(() async {
    clipboardText = null;
    testTempDir = await Directory.systemTemp.createTemp('live_logs_test_');
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
    fakeEngine = FakeVpnEngine();
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

  group('SettingsScreen and LiveLogsScreen UI', () {
    testWidgets(
      'SettingsScreen displays Language, Theme, and Live Logs tiles',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const SettingsScreen()),
          overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
        );

        expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Language'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Theme'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Live Logs'), findsOneWidget);
      },
    );

    testWidgets('LiveLogsScreen renders empty message when buffer is empty', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const LiveLogsScreen()),
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      );

      expect(find.widgetWithText(AppBar, 'Live Logs'), findsOneWidget);
      expect(find.text('No log entries yet'), findsOneWidget);
    });

    testWidgets('LiveLogsScreen displays emitted log entries', (tester) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const LiveLogsScreen()),
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      );

      expect(find.text('No log entries yet'), findsOneWidget);

      fakeEngine
        ..emitLog('2026-10-30 INFO Starting tunnel')
        ..emitLog('2026-10-30 INFO Handshake succeeded');
      await tester.pumpAndSettle();

      expect(find.text('No log entries yet'), findsNothing);
      expect(find.text('Starting tunnel'), findsOneWidget);
      expect(find.text('Handshake succeeded'), findsOneWidget);
    });

    testWidgets(
      'Settings navigates to /settings/logs when Live Logs tile is tapped',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: [
            repositoryOverride().first,
            vpnEngineProvider.overrideWithValue(fakeEngine),
          ],
        );

        // Navigate to Settings tab
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);

        // Tap Live Logs tile
        await tester.tap(find.widgetWithText(ListTile, 'Live Logs'));
        await tester.pumpAndSettle();

        expect(find.byType(LiveLogsScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Live Logs'), findsOneWidget);
      },
    );

    testWidgets(
      'LiveLogsScreen renders distinct level badges and semantic keys',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const LiveLogsScreen()),
          overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
        );

        fakeEngine
          ..emitLog('2026-11-05 10:00:00 INFO Connection started')
          ..emitLog('2026-11-05 10:00:01 WARN High latency detected')
          ..emitLog('2026-11-05 10:00:02 ERROR Failed handshake');
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('log_entry_tile_0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('log_level_badge_info_0')),
          findsOneWidget,
        );

        expect(
          find.byKey(const ValueKey<String>('log_entry_tile_1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('log_level_badge_warning_1')),
          findsOneWidget,
        );

        expect(
          find.byKey(const ValueKey<String>('log_entry_tile_2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('log_level_badge_error_2')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Auto-scroll pauses on scroll up and resumes on jump button tap',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const LiveLogsScreen()),
          overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
        );

        for (var i = 0; i < 50; i++) {
          final sec = i.toString().padLeft(2, '0');
          fakeEngine.emitLog('2026-11-05 10:00:$sec INFO Log event $i');
        }
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_jump_to_latest_button')),
          findsNothing,
        );

        // Scroll up towards older logs
        await tester.drag(find.byType(ListView), const Offset(0, 500));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_jump_to_latest_button')),
          findsOneWidget,
        );

        // Tap the jump-to-latest button
        await tester.tap(
          find.byKey(const ValueKey<String>('logs_jump_to_latest_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_jump_to_latest_button')),
          findsNothing,
        );
      },
    );

    testWidgets('Clear action button empties UI and underlying buffer', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const LiveLogsScreen()),
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      );

      fakeEngine.emitLog('2026-11-05T10:00:00Z INFO Log event before clear');
      await tester.pumpAndSettle();

      expect(find.text('No log entries yet'), findsNothing);
      expect(find.text('Log event before clear'), findsOneWidget);
      expect(find.text('10:00:00'), findsOneWidget);

      // Tap clear action
      await tester.tap(find.byKey(const ValueKey<String>('logs_clear_button')));
      await tester.pumpAndSettle();

      expect(find.text('No log entries yet'), findsOneWidget);
      expect(find.text('Log event before clear'), findsNothing);
    });

    testWidgets('Viewport virtualization lazily mounts items for 300 entries', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const LiveLogsScreen()),
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      );

      for (var i = 0; i < 300; i++) {
        fakeEngine.emitLog('2026-11-05 10:00:00 INFO Log sequence #$i');
      }
      await tester.pumpAndSettle();

      // Latest item is mounted at the bottom of the viewport
      expect(
        find.byKey(const ValueKey<String>('log_entry_tile_299')),
        findsOneWidget,
      );

      // First item is offscreen and unmounted due to ListView virtualization
      expect(
        find.byKey(const ValueKey<String>('log_entry_tile_0')),
        findsNothing,
      );
    });

    testWidgets('Copy button is disabled when log buffer is empty', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const LiveLogsScreen()),
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      );

      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('logs_copy_button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'Privacy warning dialog is non-dismissible outside barrier, cancel '
      'leaves clipboard untouched',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const LiveLogsScreen()),
          overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
        );

        fakeEngine.emitLog('2026-11-05 10:00:00 INFO Initial log line');
        await tester.pumpAndSettle();

        // Tap copy button to open privacy dialog
        await tester.tap(
          find.byKey(const ValueKey<String>('logs_copy_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
          findsOneWidget,
        );
        expect(find.text('Sensitive Information Warning'), findsOneWidget);

        // Tap outside barrier (dialog must not dismiss)
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
          findsOneWidget,
        );

        // Tap cancel button
        await tester.tap(
          find.byKey(const ValueKey<String>('logs_copy_cancel_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
          findsNothing,
        );
        expect(clipboardText, isNull);
      },
    );

    testWidgets(
      'Confirming privacy warning dialog writes logs to clipboard and shows '
      'feedback',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const LiveLogsScreen()),
          overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
        );

        fakeEngine
          ..emitLog('2026-11-05 10:00:00 INFO Connection started')
          ..emitLog('2026-11-05 10:00:01 WARN [tun] High latency');
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('logs_copy_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
          findsOneWidget,
        );

        // Tap confirm button
        await tester.tap(
          find.byKey(const ValueKey<String>('logs_copy_confirm_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
          findsNothing,
        );
        expect(clipboardText, isNotNull);
        expect(clipboardText, contains('Connection started'));
        expect(clipboardText, contains('High latency'));
        expect(find.text('Logs copied to clipboard'), findsOneWidget);
      },
    );

    testWidgets(
      'Copy action captures logs arriving while privacy warning dialog is open',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const LiveLogsScreen()),
          overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
        );

        fakeEngine.emitLog('2026-11-05 10:00:00 INFO Initial log line');
        await tester.pumpAndSettle();

        // Tap copy button to open privacy dialog
        await tester.tap(
          find.byKey(const ValueKey<String>('logs_copy_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
          findsOneWidget,
        );

        // While dialog is open, a new log arrives
        fakeEngine.emitLog('2026-11-05 10:00:01 INFO Arrived during dialog');
        await tester.pump();

        // Confirm copy
        await tester.tap(
          find.byKey(const ValueKey<String>('logs_copy_confirm_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
          findsNothing,
        );
        expect(clipboardText, isNotNull);
        expect(clipboardText, contains('Initial log line'));
        expect(clipboardText, contains('Arrived during dialog'));
      },
    );

    testWidgets(
      'LogsScreen (/logs tab) renders live log viewer with title Logs and actions',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const LogsScreen()),
          overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
        );

        expect(find.widgetWithText(AppBar, 'Logs'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('logs_copy_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('logs_clear_button')),
          findsOneWidget,
        );
        expect(find.text('No log entries yet'), findsOneWidget);
      },
    );
  });
}
