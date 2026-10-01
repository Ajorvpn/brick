// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/router/app_router.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);
  group('appRouterProvider navigation', () {
    testWidgets('default initial location renders HomeScreen', (tester) async {
      await pumpLocalizedApp(
        tester,
        const MyApp(),
        overrides: repositoryOverride(),
      );

      expect(find.byType(HomeScreen), findsOneWidget);
      // HomeScreen shows the AppBar title plus the empty-state message; it
      // does not render `home.label`.
      expect(find.widgetWithText(AppBar, 'Brick VPN'), findsOneWidget);
      expect(find.text('No saved servers yet'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
    });

    testWidgets('navigating to /settings renders SettingsScreen', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        const MyApp(),
        overrides: repositoryOverride(),
      );

      await tester.tap(find.text('Go to Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      // 'Settings' legitimately appears twice (AppBar title + body label),
      // so assert the AppBar title specifically rather than a raw count.
      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('back navigation returns from Settings to Home', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        const MyApp(),
        overrides: repositoryOverride(),
      );

      await tester.tap(find.text('Go to Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
    });
  });

  group('appRouterProvider configuration', () {
    testWidgets('app launches directly into the Home placeholder route', (
      tester,
    ) async {
      // A detached GoRouter has an empty `currentConfiguration.uri` until it
      // is attached to a widget tree, so the initial location is asserted
      // through the rendered output rather than through router internals.
      await pumpLocalizedApp(
        tester,
        const MyApp(),
        overrides: repositoryOverride(),
      );

      expect(find.byType(HomeScreen), findsOneWidget);
    });

    test('provider returns a stable keepAlive singleton', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // A bare `@riverpod` would auto-dispose the router and lose
      // navigation state; keepAlive guarantees one instance per container.
      expect(
        container.read(appRouterProvider),
        same(container.read(appRouterProvider)),
      );
    });
  });
}
