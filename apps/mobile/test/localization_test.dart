// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  group('en.json asset', () {
    test('is valid JSON with the expected top-level keys', () {
      final file = File('assets/translations/en.json');
      expect(file.existsSync(), isTrue);

      final parsed = parseTranslationsJson(file.readAsStringSync());
      expect(
        parsed.keys,
        containsAll(<String>['app_title', 'home', 'settings']),
      );
    });

    test('exactly matches the in-memory map used by widget tests', () {
      // Guards against the test harness drifting from the real asset: the
      // harness duplicates this JSON so tests stay hermetic, and this test
      // is what proves the duplicate is still faithful.
      final file = File('assets/translations/en.json');
      final fromAsset = parseTranslationsJson(file.readAsStringSync());
      expect(fromAsset, equals(testEnglishTranslations()));
    });
  });

  group('.tr() lookup in widgets', () {
    testWidgets('HomeScreen renders translated strings, not keys', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const HomeScreen()),
      );

      expect(find.text('Brick VPN'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Go to Settings'), findsOneWidget);
      // The raw lookup key must never be displayed to a user.
      expect(find.text('home.go_to_settings'), findsNothing);
      expect(find.text('home.title'), findsNothing);
    });

    testWidgets('SettingsScreen renders translated strings, not keys', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const SettingsScreen()),
      );

      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
      expect(find.text('Back to Home'), findsOneWidget);
      expect(find.text('settings.back_to_home'), findsNothing);
    });

    testWidgets("a different locale resolves to that locale's value", (
      tester,
    ) async {
      // Proves `.tr()` performs a real lookup rather than returning the key:
      // the loader serves different text for a different language code.
      final loader = TestAssetLoader(
        translations: {
          'en': testEnglishTranslations(),
          'de': {
            'app_title': 'Ziegel VPN',
            'home': {
              'title': 'Ziegel VPN',
              'label': 'Startseite',
              'go_to_settings': 'Zu den Einstellungen',
            },
            'settings': {
              'title': 'Einstellungen',
              'label': 'Einstellungen',
              'back_to_home': 'Zurück zur Startseite',
            },
          },
        },
      );

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const <Locale>[Locale('en'), Locale('de')],
          path: 'assets/translations',
          startLocale: const Locale('de'),
          fallbackLocale: const Locale('en'),
          saveLocale: false,
          assetLoader: loader,
          child: localizedMaterialApp(home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ziegel VPN'), findsOneWidget);
      expect(find.text('Startseite'), findsOneWidget);
      expect(find.text('Zu den Einstellungen'), findsOneWidget);
    });
  });
}
