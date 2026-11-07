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

    test('round-trips active server ID updates', () async {
      final repo = FakeAppPreferencesRepository();
      expect(repo.getActiveServerId(), isNull);

      await repo.setActiveServerId('srv-123');
      expect(repo.getActiveServerId(), equals('srv-123'));

      await repo.setActiveServerId('srv-456');
      expect(repo.getActiveServerId(), equals('srv-456'));

      await repo.setActiveServerId(null);
      expect(repo.getActiveServerId(), isNull);

      await repo.setActiveServerId('');
      expect(repo.getActiveServerId(), isNull);
    });

    test(
      'defaults autoReconnectEnabled to true and round-trips updates',
      () async {
        final repo = FakeAppPreferencesRepository();
        expect(repo.isAutoReconnectEnabled(), isTrue);

        await repo.setAutoReconnectEnabled(enabled: false);
        expect(repo.isAutoReconnectEnabled(), isFalse);

        await repo.setAutoReconnectEnabled(enabled: true);
        expect(repo.isAutoReconnectEnabled(), isTrue);
      },
    );

    test(
      'defaults killSwitchEnabled to false and round-trips updates',
      () async {
        final repo = FakeAppPreferencesRepository();
        expect(repo.isKillSwitchEnabled(), isFalse);

        await repo.setKillSwitchEnabled(enabled: true);
        expect(repo.isKillSwitchEnabled(), isTrue);

        await repo.setKillSwitchEnabled(enabled: false);
        expect(repo.isKillSwitchEnabled(), isFalse);
      },
    );
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

    test('persists active server ID and survives repository restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo1 = SharedPreferencesAppPreferencesRepository(prefs);

      expect(repo1.getActiveServerId(), isNull);

      await repo1.setActiveServerId('srv-999');
      expect(repo1.getActiveServerId(), equals('srv-999'));
      expect(
        prefs.getString(
          SharedPreferencesAppPreferencesRepository.keyActiveServerId,
        ),
        equals('srv-999'),
      );

      // Simulate app restart
      final repo2 = SharedPreferencesAppPreferencesRepository(prefs);
      expect(repo2.getActiveServerId(), equals('srv-999'));

      await repo2.setActiveServerId(null);
      expect(repo2.getActiveServerId(), isNull);
      expect(
        prefs.containsKey(
          SharedPreferencesAppPreferencesRepository.keyActiveServerId,
        ),
        isFalse,
      );
    });

    test(
      'persists auto-reconnect preference and survives repository restart',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final repo1 = SharedPreferencesAppPreferencesRepository(prefs);

        expect(repo1.isAutoReconnectEnabled(), isTrue);

        await repo1.setAutoReconnectEnabled(enabled: false);
        expect(repo1.isAutoReconnectEnabled(), isFalse);
        expect(
          prefs.getBool(
            SharedPreferencesAppPreferencesRepository.keyAutoReconnectEnabled,
          ),
          isFalse,
        );

        final repo2 = SharedPreferencesAppPreferencesRepository(prefs);
        expect(repo2.isAutoReconnectEnabled(), isFalse);
      },
    );

    test(
      'persists kill switch preference and survives repository restart',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final repo1 = SharedPreferencesAppPreferencesRepository(prefs);

        expect(repo1.isKillSwitchEnabled(), isFalse);

        await repo1.setKillSwitchEnabled(enabled: true);
        expect(repo1.isKillSwitchEnabled(), isTrue);
        expect(
          prefs.getBool(
            SharedPreferencesAppPreferencesRepository.keyKillSwitchEnabled,
          ),
          isTrue,
        );

        final repo2 = SharedPreferencesAppPreferencesRepository(prefs);
        expect(repo2.isKillSwitchEnabled(), isTrue);
      },
    );
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

    test(
      'autoReconnectEnabledProvider updates state and persists to repository',
      () async {
        final fakeRepo = FakeAppPreferencesRepository();
        final container = ProviderContainer(
          overrides: [
            appPreferencesRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(autoReconnectEnabledProvider), isTrue);

        await container
            .read(autoReconnectEnabledProvider.notifier)
            .setEnabled(enabled: false);
        expect(container.read(autoReconnectEnabledProvider), isFalse);
        expect(fakeRepo.isAutoReconnectEnabled(), isFalse);
      },
    );

    test(
      'killSwitchEnabledProvider updates state and persists to repository',
      () async {
        final fakeRepo = FakeAppPreferencesRepository();
        final container = ProviderContainer(
          overrides: [
            appPreferencesRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(killSwitchEnabledProvider), isFalse);

        await container
            .read(killSwitchEnabledProvider.notifier)
            .setEnabled(enabled: true);
        expect(container.read(killSwitchEnabledProvider), isTrue);
        expect(fakeRepo.isKillSwitchEnabled(), isTrue);
      },
    );
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

    testWidgets('toggling Auto-Reconnect switch updates provider and repo', (
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

      expect(find.text('Auto-Reconnect'), findsOneWidget);
      final autoReconnectTile = find.widgetWithText(
        SwitchListTile,
        'Auto-Reconnect',
      );
      final switchFinder = find.descendant(
        of: autoReconnectTile,
        matching: find.byType(Switch),
      );
      expect(switchFinder, findsOneWidget);
      expect(fakeRepo.isAutoReconnectEnabled(), isTrue);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(fakeRepo.isAutoReconnectEnabled(), isFalse);
    });

    testWidgets('toggling Kill Switch switch updates provider and repo', (
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

      expect(find.text('Kill Switch'), findsOneWidget);
      final killSwitchTile = find.byKey(
        const ValueKey<String>('settings_kill_switch_tile'),
      );
      expect(killSwitchTile, findsOneWidget);
      final switchFinder = find.descendant(
        of: killSwitchTile,
        matching: find.byType(Switch),
      );
      expect(switchFinder, findsOneWidget);
      expect(fakeRepo.isKillSwitchEnabled(), isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(fakeRepo.isKillSwitchEnabled(), isTrue);
    });
  });
}
