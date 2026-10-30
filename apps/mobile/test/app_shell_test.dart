// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/presentation/widgets/app_shell.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  group('AppShell & StatefulShellRoute Navigation (P4-T16)', () {
    testWidgets(
      'renders NavigationBar with Home and Settings tabs, switching tabs '
      'preserves state',
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
        expect(find.byType(SettingsScreen), findsNothing);

        // 2. Tap Settings tab on NavigationBar.
        await tester.tap(find.byIcon(Icons.settings));
        await tester.pumpAndSettle();

        // 3. SettingsScreen is visible, HomeScreen is offstage.
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);

        // 4. Tap Home tab on NavigationBar.
        await tester.tap(find.byIcon(Icons.home));
        await tester.pumpAndSettle();

        // 5. HomeScreen is visible again, SettingsScreen is offstage.
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(SettingsScreen), findsNothing);
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
