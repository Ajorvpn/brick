// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_theme/ui_theme.dart';

/// Calculates WCAG 2.1 relative luminance for a given [Color].
double _relativeLuminance(Color color) {
  double channelLuminance(int channelValue) {
    final normalized = channelValue / 255.0;
    if (normalized <= 0.04045) {
      return normalized / 12.92;
    } else {
      return math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
    }
  }

  final r = channelLuminance((color.r * 255.0).round().clamp(0, 255));
  final g = channelLuminance((color.g * 255.0).round().clamp(0, 255));
  final b = channelLuminance((color.b * 255.0).round().clamp(0, 255));

  return (0.2126 * r) + (0.7152 * g) + (0.0722 * b);
}

/// Computes the WCAG 2.1 contrast ratio between two colors: (L1 + 0.05) / (L2 + 0.05).
double _contrastRatio(Color c1, Color c2) {
  final l1 = _relativeLuminance(c1);
  final l2 = _relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('P11-T1: Design System Foundation & Accessibility Test Suite', () {
    test(
      'Test 1: WCAG 2.1 AA Contrast Ratio Math — Dark & Light Modes (>= 4.5:1)',
      () {
        final dark = BrickSemanticColors.dark;
        final light = BrickSemanticColors.light;

        // Dark mode text contrast checks against background & surface
        expect(
          _contrastRatio(dark.textPrimary, dark.background),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark textPrimary on background must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(dark.textPrimary, dark.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark textPrimary on surface must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(dark.textSecondary, dark.background),
          greaterThanOrEqualTo(4.5),
          reason:
              'Dark textSecondary on background must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(dark.textSecondary, dark.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark textSecondary on surface must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(dark.textMuted, dark.background),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark textMuted on background must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(dark.textMuted, dark.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark textMuted on surface must pass WCAG AA (>= 4.5:1)',
        );

        // Light mode text contrast checks against background & surface
        expect(
          _contrastRatio(light.textPrimary, light.background),
          greaterThanOrEqualTo(4.5),
          reason:
              'Light textPrimary on background must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.textPrimary, light.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Light textPrimary on surface must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.textSecondary, light.background),
          greaterThanOrEqualTo(4.5),
          reason:
              'Light textSecondary on background must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.textSecondary, light.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Light textSecondary on surface must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.textMuted, light.background),
          greaterThanOrEqualTo(4.5),
          reason: 'Light textMuted on background must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.textMuted, light.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Light textMuted on surface must pass WCAG AA (>= 4.5:1)',
        );

        // Dark onAccent on vibrant accents (buttons, switches, badges)
        expect(
          _contrastRatio(dark.onAccent, dark.brandBrick),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark onAccent on brandBrick must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(dark.onAccent, dark.stateConnected),
          greaterThanOrEqualTo(4.5),
          reason:
              'Dark onAccent on stateConnected must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(dark.onAccent, dark.stateConnecting),
          greaterThanOrEqualTo(4.5),
          reason:
              'Dark onAccent on stateConnecting must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(dark.onAccent, dark.stateError),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark onAccent on stateError must pass WCAG AA (>= 4.5:1)',
        );

        // Light onAccent on vibrant accents (buttons, switches, badges)
        expect(
          _contrastRatio(light.onAccent, light.brandBrick),
          greaterThanOrEqualTo(4.5),
          reason: 'Light onAccent on brandBrick must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.onAccent, light.stateConnected),
          greaterThanOrEqualTo(4.5),
          reason:
              'Light onAccent on stateConnected must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.onAccent, light.stateConnecting),
          greaterThanOrEqualTo(4.5),
          reason:
              'Light onAccent on stateConnecting must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.onAccent, light.stateError),
          greaterThanOrEqualTo(4.5),
          reason: 'Light onAccent on stateError must pass WCAG AA (>= 4.5:1)',
        );

        // brandBrick against background & surface in dark and light modes
        expect(
          _contrastRatio(dark.brandBrick, dark.background),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark brandBrick on background must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(dark.brandBrick, dark.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark brandBrick on surface must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.brandBrick, light.background),
          greaterThanOrEqualTo(4.5),
          reason: 'Light brandBrick on background must pass WCAG AA (>= 4.5:1)',
        );
        expect(
          _contrastRatio(light.brandBrick, light.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Light brandBrick on surface must pass WCAG AA (>= 4.5:1)',
        );
      },
    );

    test('Test 2: BrickSemanticColors ThemeExtension, copyWith, and lerp', () {
      final darkTheme = BrickTheme.dark();
      final lightTheme = BrickTheme.light();

      expect(darkTheme.brightness, equals(Brightness.dark));
      expect(lightTheme.brightness, equals(Brightness.light));

      final darkColors = darkTheme.extension<BrickSemanticColors>();
      final lightColors = lightTheme.extension<BrickSemanticColors>();

      expect(darkColors, isNotNull);
      expect(lightColors, isNotNull);

      // Test copyWith
      const testColor = Color(0xFF123456);
      final modified = darkColors!.copyWith(brandBrick: testColor);
      expect(modified.brandBrick, equals(testColor));
      expect(modified.background, equals(darkColors.background));

      // Test lerp at t = 0.0, 0.5, 1.0
      final lerp0 = darkColors.lerp(lightColors, 0.0);
      expect(lerp0.background, equals(darkColors.background));

      final lerp1 = darkColors.lerp(lightColors, 1.0);
      expect(lerp1.background, equals(lightColors!.background));

      final lerpHalf = darkColors.lerp(lightColors, 0.5);
      expect(
        lerpHalf.background,
        equals(Color.lerp(darkColors.background, lightColors.background, 0.5)),
      );

      // Test lerp with null or incompatible extension
      final lerpSame = darkColors.lerp(null, 0.5);
      expect(lerpSame, equals(darkColors));
    });

    test('Test 3: 8-Point Grid Spacing & Accessibility Touch Targets', () {
      final spatialTokens = <double>[
        BrickSpacing.xxs,
        BrickSpacing.xs,
        BrickSpacing.sm,
        BrickSpacing.md,
        BrickSpacing.lg,
        BrickSpacing.xl,
        BrickSpacing.xxl,
        BrickSpacing.section,
        BrickSpacing.hero,
        BrickSpacing.screenHorizontal,
        BrickSpacing.cardPadding,
        BrickSpacing.cardPaddingCompact,
      ];

      for (final token in spatialTokens) {
        expect(
          token % 4.0,
          equals(0.0),
          reason:
              'Token $token must be divisible by 4.0 in 8-point spatial system',
        );
      }

      // Accessibility touch target requirement
      expect(
        BrickSpacing.minTouchTarget,
        greaterThanOrEqualTo(48.0),
        reason:
            'Interactive elements must satisfy minimum 48x48dp touch target',
      );

      // Ergonomic reading max width constraint
      expect(
        BrickSpacing.maxReadableWidth,
        equals(600.0),
        reason: 'Readable width token must be 600.0',
      );

      // Central Orb size
      expect(
        BrickSpacing.orbDiameter,
        equals(164.0),
        reason: 'Orb diameter must be 164.0',
      );
    });

    test('Test 4: Typography Tabular Figures & GPL-3.0 Style Guide Audit', () {
      // Monospace styles must include tabular figures
      final metricLarge = BrickTypography.monoMetricLarge();
      final metric = BrickTypography.monoMetric();
      final log = BrickTypography.monoLog();

      expect(
        metricLarge.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(metric.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(log.fontFeatures, contains(const FontFeature.tabularFigures()));

      // Strict 4-size / 3-weight typography audit across dark and light themes
      final allowedSizes = <double>{28.0, 18.0, 14.0, 12.0};
      final allowedWeights = <FontWeight>{
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w700,
      };

      for (final theme in [BrickTheme.dark(), BrickTheme.light()]) {
        final styles = [
          theme.textTheme.displayLarge,
          theme.textTheme.displayMedium,
          theme.textTheme.displaySmall,
          theme.textTheme.headlineLarge,
          theme.textTheme.headlineMedium,
          theme.textTheme.headlineSmall,
          theme.textTheme.titleLarge,
          theme.textTheme.titleMedium,
          theme.textTheme.titleSmall,
          theme.textTheme.bodyLarge,
          theme.textTheme.bodyMedium,
          theme.textTheme.bodySmall,
          theme.textTheme.labelLarge,
          theme.textTheme.labelMedium,
          theme.textTheme.labelSmall,
        ];
        for (final style in styles) {
          if (style != null) {
            expect(
              allowedSizes.contains(style.fontSize),
              isTrue,
              reason: 'Font size ${style.fontSize} must be in $allowedSizes',
            );
            expect(
              allowedWeights.contains(style.fontWeight),
              isTrue,
              reason:
                  'Font weight ${style.fontWeight} must be in $allowedWeights',
            );
          }
        }
      }

      // Check style guide existence and content
      final styleGuideFile = File('../../docs/design/style-guide.md');
      final fallbackFile = File('docs/design/style-guide.md');
      final targetFile = styleGuideFile.existsSync()
          ? styleGuideFile
          : fallbackFile;

      expect(
        targetFile.existsSync(),
        isTrue,
        reason: 'docs/design/style-guide.md must exist',
      );
      final content = targetFile.readAsStringSync();

      expect(content.contains('Obsidian Glass & Brick Ember'), isTrue);
      expect(content.contains('SIL Open Font License 1.1'), isTrue);
      expect(content.contains('Apache License 2.0'), isTrue);
      expect(content.contains('GPL-3.0'), isTrue);
      expect(content.contains('tabularFigures()'), isTrue);
      expect(content.contains('8-Point Spatial Grid'), isTrue);
      expect(content.contains('48.0 x 48.0 dp'), isTrue);
      expect(
        content.contains('Split Tunneling'),
        isFalse,
        reason: 'style guide must not claim Split Tunneling',
      );
    });

    testWidgets(
      'Test 5: BrickEmblemPlaceholder Widget Render & Light/Dark Theme Switch Test',
      (tester) async {
        var isDark = true;
        var isConnected = false;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return MaterialApp(
                theme: BrickTheme.light(),
                darkTheme: BrickTheme.dark(),
                themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                home: Scaffold(
                  body: Center(
                    child: Column(
                      children: [
                        BrickEmblemPlaceholder(
                          size: 64.0,
                          isConnected: isConnected,
                        ),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              isDark = !isDark;
                              isConnected = !isConnected;
                            });
                          },
                          child: const Text('Toggle'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );

        // Verify widget rendered in dark mode idle
        expect(find.byType(BrickEmblemPlaceholder), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Toggle to light mode connected
        await tester.tap(find.text('Toggle'));
        await tester.pumpAndSettle();

        expect(find.byType(BrickEmblemPlaceholder), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
