// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

const ValueKey<String> _killSwitchTile = ValueKey<String>(
  'settings_kill_switch_tile',
);
const ValueKey<String> _privacyTile = ValueKey<String>(
  'settings_privacy_policy_tile',
);
const ValueKey<String> _licenseTile = ValueKey<String>('settings_license_tile');
const ValueKey<String> _versionTile = ValueKey<String>('settings_version_tile');
const ValueKey<String> _privacyClose = ValueKey<String>(
  'settings_privacy_policy_close_button',
);
const ValueKey<String> _viewLicenses = ValueKey<String>(
  'settings_view_licenses_button',
);

Widget _app({required ThemeMode themeMode}) {
  return Builder(
    builder: (context) => MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      theme: BrickTheme.light(),
      darkTheme: BrickTheme.dark(),
      themeMode: themeMode,
      home: const SettingsScreen(),
    ),
  );
}

Future<FakeAppPreferencesRepository> _pumpSettings(
  WidgetTester tester, {
  ThemeMode themeMode = ThemeMode.dark,
  Size size = const Size(412, 915),
  AssetLoader? assetLoader,
  Locale startLocale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final repo = FakeAppPreferencesRepository();
  await pumpLocalizedApp(
    tester,
    _app(themeMode: themeMode),
    assetLoader: assetLoader,
    overrides: <Object>[
      appPreferencesRepositoryProvider.overrideWithValue(repo),
    ],
    startLocale: startLocale,
  );
  return repo;
}

Map<String, dynamic> _loadTranslations(String languageCode) {
  final direct = File('assets/translations/$languageCode.json');
  final path = direct.existsSync()
      ? direct.path
      : 'apps/mobile/assets/translations/$languageCode.json';
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  setUpAll(initTestLocalization);

  testWidgets(
    'Test 1: three Obsidian sections render and both switches drive their real '
    'preferences with a monospace version badge',
    (tester) async {
      for (final themeMode in const <ThemeMode>[
        ThemeMode.dark,
        ThemeMode.light,
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());

        final repo = await _pumpSettings(tester, themeMode: themeMode);

        expect(
          find.byType(BrickSectionHeader),
          findsNWidgets(3),
          reason: 'Exactly three grouped sections are expected',
        );
        expect(find.text('CONNECTION & RESILIENCE'), findsOneWidget);
        expect(find.text('APPEARANCE & LANGUAGE'), findsOneWidget);
        expect(find.text('DIAGNOSTICS & ABOUT'), findsOneWidget);
        expect(
          find.byType(BrickGlassCard),
          findsNWidgets(3),
          reason: 'Each section is hosted in one glass card',
        );

        final killSwitchSwitch = find.descendant(
          of: find.byKey(_killSwitchTile),
          matching: find.byType(Switch),
        );
        expect(killSwitchSwitch, findsOneWidget);
        expect(repo.isKillSwitchEnabled(), isFalse);
        await tester.tap(killSwitchSwitch);
        await tester.pumpAndSettle();
        expect(repo.isKillSwitchEnabled(), isTrue);

        final autoReconnectSwitch = find.descendant(
          of: find.widgetWithText(SwitchListTile, 'Auto-Reconnect'),
          matching: find.byType(Switch),
        );
        expect(autoReconnectSwitch, findsOneWidget);
        expect(repo.isAutoReconnectEnabled(), isTrue);
        await tester.tap(autoReconnectSwitch);
        await tester.pumpAndSettle();
        expect(repo.isAutoReconnectEnabled(), isFalse);

        await tester.ensureVisible(find.byKey(_versionTile));
        await tester.pumpAndSettle();

        final versionText = tester.widget<Text>(
          find.descendant(
            of: find.byKey(_versionTile),
            matching: find.text('0.4.0'),
          ),
        );
        expect(versionText.style?.fontFamily, BrickTypography.monoFontFamily);
        expect(
          versionText.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
        expect(
          tester.getSize(find.byKey(_versionTile)).height,
          greaterThanOrEqualTo(BrickSpacing.minTouchTarget),
        );

        // A2: no dense rows.
        for (final element in find.byType(ListTile).evaluate()) {
          expect((element.widget as ListTile).dense, isNot(true));
        }
        for (final element in find.byType(SwitchListTile).evaluate()) {
          expect((element.widget as SwitchListTile).dense, isNot(true));
        }

        // A2: 8-point spacing between header/card and 24-point between cards.
        final headers = find.byType(BrickSectionHeader);
        final cards = find.byType(BrickGlassCard);
        final header0 = tester.getRect(headers.at(0));
        final card0 = tester.getRect(cards.at(0));
        final header1 = tester.getRect(headers.at(1));
        expect(card0.top - header0.bottom, greaterThanOrEqualTo(8.0));
        expect(header1.top - card0.bottom, greaterThanOrEqualTo(24.0));

        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Test 2: privacy policy sheet is bottom-aligned on the root navigator and '
    'closes with an onAccent button',
    (tester) async {
      await _pumpSettings(tester, size: const Size(360, 640));

      expect(find.textContaining('collects no personal data'), findsNothing);

      await tester.ensureVisible(find.byKey(_privacyTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_privacyTile));
      await tester.pumpAndSettle();

      expect(find.textContaining('collects no personal data'), findsOneWidget);
      final sheetFinder = find.byKey(
        const ValueKey<String>('settings_privacy_policy_sheet'),
      );
      expect(sheetFinder, findsOneWidget);
      final sheetAlign = tester.widget<Align>(sheetFinder);
      expect(sheetAlign.alignment, Alignment.bottomCenter);
      expect(sheetAlign.heightFactor, 1.0);
      expect(
        find.descendant(of: sheetFinder, matching: find.byType(SafeArea)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheetFinder,
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );

      final closeButton = tester.widget<FilledButton>(
        find.byKey(_privacyClose),
      );
      expect(
        closeButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        BrickSemanticColors.dark.onAccent,
      );
      expect(
        closeButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        isNot(Colors.white),
      );
      expect(
        tester.getSize(find.byKey(_privacyClose)).height,
        greaterThanOrEqualTo(BrickSpacing.minTouchTarget),
      );

      // The disclosure body now also covers the opt-in anonymous diagnostics,
      // so at 360x640 the sheet's close button sits below the fold.
      await tester.ensureVisible(find.byKey(_privacyClose));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_privacyClose));
      await tester.pumpAndSettle();
      expect(find.byKey(_privacyClose), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Test 3: GPL-3.0-or-later attribution is shown and the licenses page opens',
    (tester) async {
      await _pumpSettings(tester);

      await tester.ensureVisible(find.byKey(_licenseTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_licenseTile));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('settings_license_dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('GPL-3.0-or-later'), findsWidgets);
      expect(find.textContaining('0.4.0'), findsWidgets);

      await tester.ensureVisible(find.byKey(_viewLicenses));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_viewLicenses));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(LicensePage), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Test 4: typography guard, EN/FA key parity and responsive render at '
    '360x640 and 412x915',
    (tester) async {
      final en = _loadTranslations('en');
      final fa = _loadTranslations('fa');
      final enSettings = (en['settings'] as Map<String, dynamic>).keys.toSet();
      final faSettings = (fa['settings'] as Map<String, dynamic>).keys.toSet();
      expect(
        enSettings.containsAll(faSettings) &&
            faSettings.containsAll(enSettings),
        isTrue,
        reason:
            'settings.* keys drifted between en.json and fa.json: '
            '${enSettings.difference(faSettings)} / '
            '${faSettings.difference(enSettings)}',
      );

      String? rawKeyLeak(Iterable<Text> texts) {
        for (final text in texts) {
          final data = text.data;
          if (data == null) continue;
          if (data.startsWith('settings.') ||
              data.startsWith('home.') ||
              data.startsWith('logs.')) {
            return data;
          }
        }
        return null;
      }

      for (final size in const <Size>[Size(360, 640), Size(412, 915)]) {
        for (final themeMode in const <ThemeMode>[
          ThemeMode.dark,
          ThemeMode.light,
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());

          await _pumpSettings(tester, themeMode: themeMode, size: size);

          expect(
            tester.takeException(),
            isNull,
            reason:
                'Render exception at ${size.width.toInt()}x'
                '${size.height.toInt()} in $themeMode',
          );

          for (final text in tester.widgetList<Text>(find.byType(Text))) {
            final style = text.style;
            expect(
              style?.fontWeight,
              isNot(FontWeight.w600),
              reason: 'Disallowed FontWeight.w600 in Text("${text.data}")',
            );
            expect(
              style?.fontSize,
              isNot(13),
              reason: 'Disallowed fontSize 13 in Text("${text.data}")',
            );
          }

          expect(
            rawKeyLeak(tester.widgetList<Text>(find.byType(Text))),
            isNull,
            reason: 'A raw localization key leaked in English',
          );
        }
      }

      // Persian render through the real bundled translations.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpSettings(
        tester,
        assetLoader: TestAssetLoader(translations: {'en': en, 'fa': fa}),
        startLocale: const Locale('fa'),
      );

      expect(find.widgetWithText(AppBar, 'تنظیمات'), findsOneWidget);
      expect(find.text('اتصال و پایداری'), findsOneWidget);
      expect(find.text('ظاهر و زبان'), findsOneWidget);
      expect(find.text('تشخیص و درباره'), findsOneWidget);
      expect(find.text('تنظیمات'), findsOneWidget);
      expect(
        rawKeyLeak(tester.widgetList<Text>(find.byType(Text))),
        isNull,
        reason: 'A raw localization key leaked in Persian',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Test 5: theme and language dialogs mark the active choice and update the '
    'preference with 48dp options',
    (tester) async {
      final repo = await _pumpSettings(tester);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('settings_theme_tile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('settings_theme_tile')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      for (final element in find.byType(SimpleDialogOption).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(48.0),
        );
      }

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(repo.getThemeMode(), ThemeMode.dark);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('settings_language_tile')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('settings_language_tile')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      for (final element in find.byType(SimpleDialogOption).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(48.0),
        );
      }
    },
  );
}
