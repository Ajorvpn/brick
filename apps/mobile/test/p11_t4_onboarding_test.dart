// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

const ValueKey<String> _screenKey = ValueKey<String>('onboarding_screen');
const ValueKey<String> _glowKey = ValueKey<String>(
  'onboarding_atmosphere_glow',
);
const ValueKey<String> _skipKey = ValueKey<String>('onboarding_skip_button');
const ValueKey<String> _backKey = ValueKey<String>('onboarding_back_button');
const ValueKey<String> _nextKey = ValueKey<String>('onboarding_next_button');
const ValueKey<String> _finishKey = ValueKey<String>(
  'onboarding_finish_button',
);

/// Boots the real app with a first-run repository (onboarding pending).
Future<FakeAppPreferencesRepository> _pumpFirstRun(
  WidgetTester tester, {
  Size size = const Size(412, 915),
  ThemeMode themeMode = ThemeMode.dark,
  AssetLoader? assetLoader,
  Locale startLocale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final repo = FakeAppPreferencesRepository(
    initialOnboardingCompleted: false,
    initialThemeMode: themeMode,
  );
  await pumpLocalizedApp(
    tester,
    const MyApp(),
    assetLoader: assetLoader,
    overrides: <Object>[
      ...repositoryOverride(),
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

String _loadRawTranslations(String languageCode) {
  final direct = File('assets/translations/$languageCode.json');
  final path = direct.existsSync()
      ? direct.path
      : 'apps/mobile/assets/translations/$languageCode.json';
  return File(path).readAsStringSync();
}

String? _rawOnboardingKeyLeak(Iterable<Text> texts) {
  for (final text in texts) {
    final data = text.data;
    if (data != null && data.startsWith('onboarding.')) {
      return data;
    }
  }
  return null;
}

void main() {
  setUpAll(initTestLocalization);

  test(
    'Test 1: onboarding completion persists in SharedPreferences and survives '
    'repository re-instantiation',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPreferencesAppPreferencesRepository(prefs);

      expect(
        repo.hasCompletedOnboarding(),
        isFalse,
        reason: 'A fresh install must see onboarding once',
      );

      await repo.setOnboardingCompleted(completed: true);
      expect(repo.hasCompletedOnboarding(), isTrue);
      expect(
        prefs.getBool(
          SharedPreferencesAppPreferencesRepository.keyOnboardingCompleted,
        ),
        isTrue,
      );

      // Simulated app restart over the same SharedPreferences instance.
      final restarted = SharedPreferencesAppPreferencesRepository(prefs);
      expect(restarted.hasCompletedOnboarding(), isTrue);
    },
  );

  testWidgets(
    'Test 2: first run redirects / to onboarding and the 3-step walkthrough '
    'completes into HomeScreen',
    (tester) async {
      final repo = await _pumpFirstRun(tester);

      expect(find.byKey(_screenKey), findsOneWidget);
      expect(
        find.byType(HomeScreen),
        findsNothing,
        reason: 'A first-run user must never land on HomeScreen',
      );
      expect(find.text('Private by Design'), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.byKey(_backKey), findsNothing);

      // Step 1 -> 2 -> 3.
      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
      expect(find.text('Your Servers, Your Control'), findsOneWidget);
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.byKey(_backKey), findsOneWidget);

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
      expect(find.text('Android VPN Permission'), findsOneWidget);
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.byKey(_finishKey), findsOneWidget);
      expect(find.byKey(_nextKey), findsNothing);

      // Back 3 -> 2 -> 3.
      await tester.tap(find.byKey(_backKey));
      await tester.pumpAndSettle();
      expect(find.text('Your Servers, Your Control'), findsOneWidget);

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
      expect(find.text('Android VPN Permission'), findsOneWidget);

      expect(repo.hasCompletedOnboarding(), isFalse);
      await tester.tap(find.byKey(_finishKey));
      await tester.pumpAndSettle();

      expect(repo.hasCompletedOnboarding(), isTrue);
      expect(find.byKey(_screenKey), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Test 3: Skip completes onboarding and the router never shows it again',
    (tester) async {
      final repo = await _pumpFirstRun(tester);

      expect(find.byKey(_screenKey), findsOneWidget);
      expect(repo.hasCompletedOnboarding(), isFalse);

      await tester.tap(find.byKey(_skipKey));
      await tester.pumpAndSettle();

      expect(repo.hasCompletedOnboarding(), isTrue);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(_screenKey), findsNothing);

      // A defensive re-entry attempt is redirected back to Home.
      tester.element(find.byType(HomeScreen)).go('/onboarding');
      await tester.pumpAndSettle();

      expect(find.byKey(_screenKey), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Test 4: gradient-only glow, onAccent fills, 48dp touch targets and a '
    'strict typography guard',
    (tester) async {
      await _pumpFirstRun(tester);

      final glow = tester.widget<DecoratedBox>(find.byKey(_glowKey));
      final decoration = glow.decoration as BoxDecoration;
      expect(decoration.gradient, isNotNull);
      expect(
        decoration.color,
        isNull,
        reason: 'color and gradient must never be mixed in one BoxDecoration',
      );

      void expectTouchTarget(Key key) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(48.0));
        expect(size.height, greaterThanOrEqualTo(48.0));
      }

      expectTouchTarget(_skipKey);
      expectTouchTarget(_nextKey);

      final nextButton = tester.widget<FilledButton>(find.byKey(_nextKey));
      expect(
        nextButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        BrickSemanticColors.dark.onAccent,
      );
      expect(
        nextButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        isNot(Colors.white),
      );

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();

      expectTouchTarget(_backKey);
      expectTouchTarget(_finishKey);
      final finishButton = tester.widget<FilledButton>(find.byKey(_finishKey));
      expect(
        finishButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        BrickSemanticColors.dark.onAccent,
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

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Test 5: all 3 steps render without overflow at 360x640 and 412x915 in '
    'dark and light modes',
    (tester) async {
      for (final size in const <Size>[Size(360, 640), Size(412, 915)]) {
        for (final themeMode in const <ThemeMode>[
          ThemeMode.dark,
          ThemeMode.light,
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());

          await _pumpFirstRun(tester, size: size, themeMode: themeMode);

          for (var step = 0; step < 3; step++) {
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'Render exception on step ${step + 1} at '
                  '${size.width.toInt()}x${size.height.toInt()} in $themeMode',
            );
            expect(
              find.text('Step ${step + 1} of 3'),
              findsOneWidget,
              reason:
                  'Wrong step rendered at ${size.width.toInt()}x'
                  '${size.height.toInt()} in $themeMode',
            );
            expect(
              _rawOnboardingKeyLeak(tester.widgetList<Text>(find.byType(Text))),
              isNull,
              reason: 'A raw onboarding.* key leaked',
            );

            if (step < 2) {
              await tester.tap(find.byKey(_nextKey));
              await tester.pumpAndSettle();
            }
          }
        }
      }
    },
  );

  testWidgets('Test 6: EN/FA onboarding key parity, single trailing newline and a Persian '
      'render', (tester) async {
    final en = _loadTranslations('en');
    final fa = _loadTranslations('fa');
    final enOnboarding = en['onboarding'] as Map<String, dynamic>;
    final faOnboarding = fa['onboarding'] as Map<String, dynamic>;

    expect(
      enOnboarding.keys.toSet(),
      equals(faOnboarding.keys.toSet()),
      reason: 'onboarding.* keys drifted between en.json and fa.json',
    );
    expect(enOnboarding, isNotEmpty);

    for (final raw in <String>[
      _loadRawTranslations('en'),
      _loadRawTranslations('fa'),
    ]) {
      expect(raw.endsWith('\n'), isTrue, reason: 'Missing trailing newline');
      expect(
        raw.endsWith('\n\n'),
        isFalse,
        reason: 'Exactly one trailing newline is allowed',
      );
    }

    await _pumpFirstRun(
      tester,
      assetLoader: TestAssetLoader(translations: {'en': en, 'fa': fa}),
      startLocale: const Locale('fa'),
    );

    expect(find.text('حریم خصوصی از پایه'), findsOneWidget);
    expect(find.text('گام 1 از 3'), findsOneWidget);
    expect(find.text('رد کردن'), findsOneWidget);
    expect(find.text('بعدی'), findsOneWidget);
    expect(
      _rawOnboardingKeyLeak(tester.widgetList<Text>(find.byType(Text))),
      isNull,
      reason: 'A raw onboarding.* key leaked in Persian',
    );

    await tester.tap(find.byKey(_nextKey));
    await tester.pumpAndSettle();
    expect(find.text('سرورهای شما، کنترل شما'), findsOneWidget);
    expect(find.text('بازگشت'), findsOneWidget);

    await tester.tap(find.byKey(_nextKey));
    await tester.pumpAndSettle();
    expect(find.text('مجوز VPN اندروید'), findsOneWidget);
    expect(find.text('شروع کنید'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
