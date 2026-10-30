// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/settings/presentation/screens/live_logs_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  late Directory testTempDir;
  late FakeVpnEngine fakeEngine;

  setUp(() async {
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
      expect(find.text('2026-10-30 INFO Starting tunnel'), findsOneWidget);
      expect(find.text('2026-10-30 INFO Handshake succeeded'), findsOneWidget);
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
  });
}
