// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/presentation/widgets/app_shell.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/logs/presentation/screens/logs_screen.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:mobile/features/settings/presentation/screens/live_logs_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  late Directory testTempDir;

  setUp(() async {
    testTempDir = await Directory.systemTemp.createTemp('app_shell_test_');
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

  group('AppShell 4-tab navigation (P4-T5 remediation)', () {
    testWidgets(
      'renders NavigationBar with all 4 tabs and switches between them',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: repositoryOverride(),
        );

        // 1. Initial location renders AppShell and HomeScreen.
        expect(find.byType(AppShell), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(ServersScreen), findsNothing);
        expect(find.byType(LogsScreen), findsNothing);
        expect(find.byType(SettingsScreen), findsNothing);

        // Verify all 4 navigation destinations exist in the NavigationBar.
        expect(find.byIcon(Icons.home), findsOneWidget);
        expect(find.byIcon(Icons.dns), findsOneWidget);
        expect(find.byIcon(Icons.article_outlined), findsOneWidget);
        expect(find.byIcon(Icons.settings), findsOneWidget);

        // 2. Tap Servers tab (Branch 1).
        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        expect(find.byType(ServersScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Servers'), findsOneWidget);
        expect(find.text('Server list will appear here'), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);

        // 3. Tap Logs tab (Branch 2).
        await tester.tap(find.byIcon(Icons.article_outlined));
        await tester.pumpAndSettle();

        expect(find.byType(LogsScreen), findsOneWidget);
        expect(find.byType(ServersScreen), findsNothing);
        expect(find.byType(HomeScreen), findsNothing);

        // 4. Tap Settings tab (Branch 3).
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.byType(LogsScreen), findsNothing);
        expect(find.byType(HomeScreen), findsNothing);

        // 5. Tap Home tab (Branch 0) to return.
        await tester.tap(find.byIcon(Icons.home));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(SettingsScreen), findsNothing);
      },
    );

    testWidgets(
      'preserves nested navigation state across tabs and resets on re-tap',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: repositoryOverride(),
        );

        // 1. Navigate to Settings tab (Branch 3).
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);

        // 2. Push /settings/logs (LiveLogsScreen) onto Branch 3.
        await tester.tap(find.widgetWithText(ListTile, 'Live Logs'));
        await tester.pumpAndSettle();

        expect(find.byType(LiveLogsScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Live Logs'), findsOneWidget);
        expect(find.byType(SettingsScreen), findsNothing);

        // 3. Switch to Servers tab (Branch 1).
        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        expect(find.byType(ServersScreen), findsOneWidget);
        expect(find.byType(LiveLogsScreen), findsNothing);

        // 4. Switch back to Settings tab (Branch 3).
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        // Nested route is preserved!
        expect(find.byType(LiveLogsScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Live Logs'), findsOneWidget);
        expect(find.byType(ServersScreen), findsNothing);

        // 5. Tap Settings tab a second time while active (initialLocation).
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        // Stack pops back to root of Branch 3 (SettingsScreen).
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
        expect(find.byType(LiveLogsScreen), findsNothing);
      },
    );

    testWidgets(
      'tapping currently active tab calls goBranch with initialLocation: true',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: repositoryOverride(),
        );

        expect(find.byType(HomeScreen), findsOneWidget);

        // Tapping Home while already on Home does not crash or navigate away.
        await tester.tap(find.byIcon(Icons.home));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  });
}
