// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_theme/ui_theme.dart';

/// Minimal harness: real Brick themes inside a real [MaterialApp], so the
/// theme extensions and `MediaQuery` plumbing behave exactly as in the app.
Widget _harness({required Widget child, ThemeMode themeMode = ThemeMode.dark}) {
  return MaterialApp(
    theme: BrickTheme.light(),
    darkTheme: BrickTheme.dark(),
    themeMode: themeMode,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('P11-T6 ui_theme micro-interactions', () {
    test(
      'Test 1: BrickTypography.uiStyle keeps Inter and optical wght variations',
      () {
        final regular = BrickTypography.uiStyle(
          fontSize: BrickTypography.sizeBody,
          fontWeight: FontWeight.w400,
          color: const Color(0xFF000000),
        );
        final medium = BrickTypography.uiStyle(
          fontSize: BrickTypography.sizeLabel,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF000000),
          letterSpacing: 0.8,
        );
        final bold = BrickTypography.uiStyle(
          fontSize: BrickTypography.sizeTitle,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF000000),
          height: 1.3,
        );

        for (final style in <TextStyle>[regular, medium, bold]) {
          expect(style.fontFamily, BrickTypography.primaryFontFamily);
          expect(style.fontFamily, 'Inter');
          expect(
            style.fontFamilyFallback,
            BrickTypography.primaryFontFallbacks,
          );
          expect(style.fontVariations, isNotNull);
        }

        expect(regular.fontVariations, BrickTypography.regularWeight);
        expect(regular.fontVariations, const <FontVariation>[
          FontVariation('wght', 400),
        ]);
        expect(medium.fontVariations, BrickTypography.mediumWeight);
        expect(medium.fontVariations, const <FontVariation>[
          FontVariation('wght', 500),
        ]);
        expect(bold.fontVariations, BrickTypography.boldWeight);
        expect(bold.fontVariations, const <FontVariation>[
          FontVariation('wght', 700),
        ]);

        // Callers' explicit metrics survive the helper.
        expect(medium.letterSpacing, 0.8);
        expect(bold.height, 1.3);
      },
    );

    testWidgets(
      'Test 2: BrickSkeletonBox shimmers, splits decorations and settles '
      'under reduced motion',
      (tester) async {
        for (final mode in <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
          await tester.pumpWidget(
            _harness(
              themeMode: mode,
              child: const BrickSkeletonBox(width: 220, height: 16),
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));

          var sawColor = false;
          var sawGradient = false;
          final decorations = tester.widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(BrickSkeletonBox),
              matching: find.byType(DecoratedBox),
            ),
          );
          for (final box in decorations) {
            final decoration = box.decoration;
            if (decoration is! BoxDecoration) continue;
            expect(
              decoration.color == null || decoration.gradient == null,
              isTrue,
              reason:
                  '`color` and `gradient` must never share one BoxDecoration',
            );
            if (decoration.color != null) sawColor = true;
            if (decoration.gradient != null) sawGradient = true;
          }
          expect(sawColor, isTrue, reason: 'A solid base surface must exist');
          expect(
            sawGradient,
            isTrue,
            reason: 'The sheen must paint as a gradient layer',
          );

          // Decorative only: TalkBack never reads empty shimmer rectangles.
          expect(
            find.descendant(
              of: find.byType(BrickSkeletonBox),
              matching: find.byType(ExcludeSemantics),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }

        // Unmounting mid-shimmer must dispose the ticker cleanly.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Reduced motion: zero active tickers and no sheen layer at all.
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        await tester.pumpWidget(
          _harness(child: const BrickSkeletonBox(width: 220, height: 16)),
        );
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(
          find.byKey(const ValueKey<String>('brick_skeleton_sheen')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('brick_skeleton_base')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Test 3: interactive orb and glass card dispatch haptics, disabled orb '
      'stays silent',
      (tester) async {
        final haptics = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String? ?? '');
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        var orbTaps = 0;
        await tester.pumpWidget(
          _harness(
            child: BrickPowerOrb(
              state: BrickOrbState.disconnected,
              statusLabel: 'Disconnected',
              onTap: () => orbTaps++,
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('brick_orb_core_surface')),
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(orbTaps, 1);
        expect(haptics, contains('HapticFeedbackType.mediumImpact'));

        haptics.clear();
        var cardTaps = 0;
        await tester.pumpWidget(
          _harness(
            child: BrickGlassCard(
              onTap: () => cardTaps++,
              child: const Text('Server'),
            ),
          ),
        );
        await tester.tap(find.text('Server'));
        await tester.pump(const Duration(milliseconds: 200));

        expect(cardTaps, 1);
        expect(haptics, contains('HapticFeedbackType.selectionClick'));

        haptics.clear();
        await tester.pumpWidget(
          _harness(
            child: const BrickPowerOrb(
              state: BrickOrbState.disconnected,
              statusLabel: 'Disconnected',
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('brick_orb_core_surface')),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(haptics, isEmpty);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
