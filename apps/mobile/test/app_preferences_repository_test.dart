// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  group('FakeAppPreferencesRepository', () {
    test('defaults to ThemeMode.system and null locale', () {
      final repo = FakeAppPreferencesRepository();
      expect(repo.getThemeMode(), equals(ThemeMode.system));
      expect(repo.getLocale(), isNull);
    });

    test('round-trips ThemeMode updates', () async {
      final repo = FakeAppPreferencesRepository();

      await repo.setThemeMode(ThemeMode.dark);
      expect(repo.getThemeMode(), equals(ThemeMode.dark));

      await repo.setThemeMode(ThemeMode.light);
      expect(repo.getThemeMode(), equals(ThemeMode.light));

      await repo.setThemeMode(ThemeMode.system);
      expect(repo.getThemeMode(), equals(ThemeMode.system));
    });

    test('round-trips Locale updates', () async {
      final repo = FakeAppPreferencesRepository();

      await repo.setLocale(const Locale('de'));
      expect(repo.getLocale(), equals(const Locale('de')));

      await repo.setLocale(const Locale('en'));
      expect(repo.getLocale(), equals(const Locale('en')));

      await repo.setLocale(null);
      expect(repo.getLocale(), isNull);
    });
  });

  group('SharedPreferencesAppPreferencesRepository', () {
    test('persists theme mode and survives repository restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo1 = SharedPreferencesAppPreferencesRepository(prefs);

      expect(repo1.getThemeMode(), equals(ThemeMode.system));

      await repo1.setThemeMode(ThemeMode.dark);
      expect(repo1.getThemeMode(), equals(ThemeMode.dark));
      expect(
        prefs.getString(SharedPreferencesAppPreferencesRepository.keyThemeMode),
        equals('dark'),
      );

      // Simulate app restart by constructing a new repository over the same
      // SharedPreferences instance.
      final repo2 = SharedPreferencesAppPreferencesRepository(prefs);
      expect(repo2.getThemeMode(), equals(ThemeMode.dark));
    });

    test('persists locale and survives repository restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo1 = SharedPreferencesAppPreferencesRepository(prefs);

      expect(repo1.getLocale(), isNull);

      await repo1.setLocale(const Locale('de'));
      expect(repo1.getLocale(), equals(const Locale('de')));
      expect(
        prefs.getString(SharedPreferencesAppPreferencesRepository.keyLocale),
        equals('de'),
      );

      // Simulate app restart
      final repo2 = SharedPreferencesAppPreferencesRepository(prefs);
      expect(repo2.getLocale(), equals(const Locale('de')));

      await repo2.setLocale(null);
      expect(repo2.getLocale(), isNull);
      expect(
        prefs.containsKey(SharedPreferencesAppPreferencesRepository.keyLocale),
        isFalse,
      );
    });
  });

  group('Riverpod Notifiers', () {
    test(
      'themeModeProvider updates state and persists to repository',
      () async {
        final fakeRepo = FakeAppPreferencesRepository();
        final container = ProviderContainer(
          overrides: [
            appPreferencesRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(themeModeProvider), equals(ThemeMode.system));

        await container
            .read(themeModeProvider.notifier)
            .setThemeMode(ThemeMode.dark);
        expect(container.read(themeModeProvider), equals(ThemeMode.dark));
        expect(fakeRepo.getThemeMode(), equals(ThemeMode.dark));
      },
    );

    test('localeProvider updates state and persists to repository', () async {
      final fakeRepo = FakeAppPreferencesRepository();
      final container = ProviderContainer(
        overrides: [
          appPreferencesRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(localeProvider), isNull);

      await container
          .read(localeProvider.notifier)
          .setLocale(const Locale('de'));
      expect(container.read(localeProvider), equals(const Locale('de')));
      expect(fakeRepo.getLocale(), equals(const Locale('de')));
    });
  });

  group('SettingsScreen preference toggles', () {
    testWidgets('changing Theme via dialog updates provider', (tester) async {
      final fakeRepo = FakeAppPreferencesRepository();
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const SettingsScreen()),
        overrides: [
          appPreferencesRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      expect(find.text('System'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'Theme'));
      await tester.pumpAndSettle();

      expect(find.byType(SimpleDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Dark'));
      await tester.pumpAndSettle();

      expect(fakeRepo.getThemeMode(), equals(ThemeMode.dark));
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('changing Language via dialog updates provider', (
      tester,
    ) async {
      final fakeRepo = FakeAppPreferencesRepository();
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const SettingsScreen()),
        overrides: [
          appPreferencesRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      expect(find.text('English'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'Language'));
      await tester.pumpAndSettle();

      expect(find.byType(SimpleDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Deutsch'));
      await tester.pumpAndSettle();

      expect(fakeRepo.getLocale(), equals(const Locale('de')));
    });
  });
}
