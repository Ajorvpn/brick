// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:core_domain/core_domain.dart' show Connecting;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:mobile/main.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

/// TrueType (`00 01 00 00`) and OpenType/CFF (`OTTO`) sfnt magic numbers.
const List<List<int>> _sfntMagicNumbers = <List<int>>[
  <int>[0x00, 0x01, 0x00, 0x00],
  <int>[0x4F, 0x54, 0x54, 0x4F],
];

const ValueKey<String> _nextKey = ValueKey<String>('onboarding_next_button');

/// Discovers the repository root by walking up until `pubspec.yaml` and the
/// `apps/` directory are both present, so the font assets can be read from
/// disk no matter which directory `flutter test` was launched from.
Directory _findRepoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync() ||
      !Directory('${dir.path}/apps').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return dir;
}

bool _hasMagicBytes(Uint8List bytes) {
  if (bytes.length < 4) return false;
  return _sfntMagicNumbers.any(
    (magic) =>
        bytes[0] == magic[0] &&
        bytes[1] == magic[1] &&
        bytes[2] == magic[2] &&
        bytes[3] == magic[3],
  );
}

bool _hasWeightAxis(List<FontVariation>? variations, double weight) {
  if (variations == null) return false;
  return variations.any(
    (variation) => variation.axis == 'wght' && variation.value == weight,
  );
}

void main() {
  setUpAll(initTestLocalization);

  group('Phase 11 Chunk 5B: bundled OFL fonts & WCAG 2.3.3 reduced motion', () {
    test(
      'Test 1: bundled font assets, sfnt magic, pubspec wiring & OFL licenses',
      () {
        final repoRoot = _findRepoRoot();
        final mobileRoot = '${repoRoot.path}/apps/mobile';
        final pubspec = File('$mobileRoot/pubspec.yaml').readAsStringSync();

        // The registered `family:` names must be the exact strings the theme
        // layer asks the engine for; a mismatch silently falls back to Roboto.
        expect(
          pubspec,
          contains('family: ${BrickTypography.primaryFontFamily}'),
          reason: 'pubspec must register BrickTypography.primaryFontFamily',
        );
        expect(
          pubspec,
          contains('family: ${BrickTypography.monoFontFamily}'),
          reason: 'pubspec must register BrickTypography.monoFontFamily',
        );

        // No runtime font fetching: the whole point of bundling is that the
        // network is never consulted for glyphs (Invariant 37).
        expect(
          pubspec.contains('google_fonts'),
          isFalse,
          reason: 'Bundled fonts must not be paired with a network font loader',
        );

        final declared = <String>{};
        final assetPattern = RegExp(r'asset:\s*(assets/fonts/[\w\-.]+\.ttf)');
        for (final match in assetPattern.allMatches(pubspec)) {
          declared.add(match.group(1)!);
        }

        expect(
          declared,
          containsAll(<String>[
            'assets/fonts/InterVariable.ttf',
            'assets/fonts/JetBrainsMono-Regular.ttf',
            'assets/fonts/JetBrainsMono-Medium.ttf',
            'assets/fonts/JetBrainsMono-Bold.ttf',
          ]),
          reason:
              'Every bundled family/weight must be declared in pubspec.yaml',
        );

        var totalBytes = 0;
        for (final relativePath in declared) {
          final file = File('$mobileRoot/$relativePath');
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Declared font asset $relativePath must exist on disk',
          );
          final bytes = file.readAsBytesSync();
          expect(
            _hasMagicBytes(bytes),
            isTrue,
            reason: '$relativePath must be a real TrueType/OpenType container',
          );
          totalBytes += bytes.length;
        }

        // The InterVariable asset alone is allowed up to 1.2 MB; the whole
        // bundle has a 5 MB ceiling so the APK stays lean.
        expect(
          File('$mobileRoot/assets/fonts/InterVariable.ttf').lengthSync(),
          lessThan(1200000),
          reason: 'InterVariable.ttf must stay under 1.2 MB',
        );
        expect(
          totalBytes,
          lessThan(5 * 1024 * 1024),
          reason: 'Total bundled .ttf payload must stay under 5 MB',
        );

        // SIL OFL-1.1 attribution must be auditable in-repo for both families.
        for (final licenseName in const <String>[
          'OFL-Inter.txt',
          'OFL-JetBrainsMono.txt',
        ]) {
          final license = File('$mobileRoot/assets/fonts/$licenseName');
          expect(
            license.existsSync(),
            isTrue,
            reason: '$licenseName must ship beside the fonts',
          );
          final text = license.readAsStringSync();
          expect(text, isNotEmpty);
          expect(
            text,
            contains('SIL OPEN FONT LICENSE Version 1.1'),
            reason: '$licenseName must be the real OFL-1.1 notice',
          );
        }

        // The exact byte total is the only place the bundled payload size is
        // visible during a test run, so printing it is deliberate.
        // ignore: avoid_print
        print(
          'P11_T5_BUNDLED_FONT_BYTES=$totalBytes '
          '(${declared.length} .ttf assets declared)',
        );
      },
    );

    test('Test 2: Inter optical weights & JetBrains Mono tabular figures', () {
      final theme = BrickTypography.textTheme(BrickSemanticColors.dark);

      final styles = <TextStyle?>[
        theme.displayLarge,
        theme.displayMedium,
        theme.displaySmall,
        theme.headlineLarge,
        theme.headlineMedium,
        theme.headlineSmall,
        theme.titleLarge,
        theme.titleMedium,
        theme.titleSmall,
        theme.bodyLarge,
        theme.bodyMedium,
        theme.bodySmall,
        theme.labelLarge,
        theme.labelMedium,
        theme.labelSmall,
      ];

      for (final style in styles) {
        expect(style, isNotNull);
        expect(
          style!.fontFamily,
          BrickTypography.primaryFontFamily,
          reason: 'Every TextTheme style must target the bundled Inter family',
        );
      }

      // InterVariable.ttf is a single variable font: each weight must be
      // selected through the `wght` axis, or the engine fakes the bold.
      expect(_hasWeightAxis(theme.displayLarge!.fontVariations, 700), isTrue);
      expect(_hasWeightAxis(theme.headlineSmall!.fontVariations, 500), isTrue);
      expect(_hasWeightAxis(theme.bodyMedium!.fontVariations, 400), isTrue);
      expect(_hasWeightAxis(theme.labelSmall!.fontVariations, 500), isTrue);

      final monoStyles = <TextStyle>[
        BrickTypography.monoMetricLarge(
          color: BrickSemanticColors.dark.textMuted,
        ),
        BrickTypography.monoMetric(color: BrickSemanticColors.dark.textMuted),
        BrickTypography.monoLog(color: BrickSemanticColors.dark.textMuted),
      ];
      for (final style in monoStyles) {
        expect(style.fontFamily, BrickTypography.monoFontFamily);
        expect(style.fontFamily, 'JetBrains Mono');
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'Telemetry digits must never jitter',
        );
      }
    });

    testWidgets(
      'Test 3: reduced motion settles the full MyApp tree (orb + dock beacon)',
      (tester) async {
        // Mirrors Android's "Remove animations" / "Reduce motion" setting at
        // the platform layer, exactly as the OS reports it to Flutter.
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: <Object>[
            ...repositoryOverride(),
            vpnEngineProvider.overrideWithValue(engine),
            appPreferencesRepositoryProvider.overrideWithValue(
              FakeAppPreferencesRepository(),
            ),
          ],
        );

        // A `Connecting` tunnel normally drives the orb's rotation ticker AND
        // the dock beacon's ripple ticker forever. Under reduced motion the
        // whole tree must therefore settle.
        engine.emit(const Connecting());
        await tester.pumpAndSettle();

        expect(find.byType(BrickPowerOrb), findsOneWidget);
        expect(
          tester.binding.transientCallbackCount,
          0,
          reason: 'No repeating ticker may survive app-wide reduced motion',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Test 4: onboarding jumps pages instantly and keeps semantics clean',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const OnboardingScreen()),
          overrides: <Object>[
            ...repositoryOverride(),
            appPreferencesRepositoryProvider.overrideWithValue(
              FakeAppPreferencesRepository(initialOnboardingCompleted: false),
            ),
          ],
        );

        final semantics = tester.ensureSemantics();

        // Two purely decorative wrappers must be hidden from TalkBack: the
        // 3-dot progress row and the step squircle icon. The mono
        // "Step X of 3" label already speaks the progress information.
        expect(
          find.descendant(
            of: find.byType(OnboardingScreen),
            matching: find.byType(ExcludeSemantics),
          ),
          findsAtLeastNWidgets(2),
        );

        expect(find.text('Step 1 of 3'), findsOneWidget);

        await tester.tap(find.byKey(_nextKey));
        // `jumpToPage` (not `animateToPage`) means the next step is already
        // current after a single frame rather than a 250 ms slide.
        await tester.pump();
        expect(find.text('Step 2 of 3'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        semantics.dispose();
      },
    );
  });
}
