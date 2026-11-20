// SPDX-License-Identifier: GPL-3.0-or-later

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
  group('Phase 11 Chunk 2A: Obsidian Glass Primitives Test Suite', () {
    testWidgets(
      'Test 1: BrickGlassCard Dark & Light Render, Selected Glow, Press Scale & 48dp Min Touch Target',
      (tester) async {
        for (final isDark in [true, false]) {
          var tapped = false;
          var longPressed = false;
          var isSelected = false;

          await tester.pumpWidget(
            StatefulBuilder(
              builder: (context, setState) {
                return MaterialApp(
                  theme: BrickTheme.light(),
                  darkTheme: BrickTheme.dark(),
                  themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                  home: Scaffold(
                    body: Center(
                      child: BrickGlassCard(
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            tapped = true;
                            isSelected = !isSelected;
                          });
                        },
                        onLongPress: () {
                          setState(() {
                            longPressed = true;
                          });
                        },
                        semanticLabel: 'Server Item Card',
                        child: const Text('Minimal Card Content'),
                      ),
                    ),
                  ),
                );
              },
            ),
          );

          // Verify card rendered and satisfies 48dp minimum touch target
          expect(find.byType(BrickGlassCard), findsOneWidget);
          final initialSize = tester.getSize(find.byType(BrickGlassCard));
          expect(
            initialSize.height,
            greaterThanOrEqualTo(BrickSpacing.minTouchTarget),
            reason: 'Card height must enforce minTouchTarget (48dp)',
          );

          // Verify micro-press feedback: down gesture triggers scale reduction to 0.985
          final gesture = await tester.startGesture(
            tester.getCenter(find.byType(BrickGlassCard)),
          );
          await tester.pump(const Duration(milliseconds: 150));

          final animatedScaleFinder = find.descendant(
            of: find.byType(BrickGlassCard),
            matching: find.byType(AnimatedScale),
          );
          expect(animatedScaleFinder, findsOneWidget);
          final animatedScale = tester.widget<AnimatedScale>(
            animatedScaleFinder,
          );
          expect(
            animatedScale.scale,
            equals(0.985),
            reason: 'Tactile micro-press feedback scales to 0.985 when pressed',
          );

          // Release gesture and verify tap callback
          await gesture.up();
          await tester.pumpAndSettle();
          expect(tapped, isTrue);
          expect(isSelected, isTrue);

          // Verify long press callback
          await tester.longPress(find.byType(BrickGlassCard));
          await tester.pumpAndSettle();
          expect(longPressed, isTrue);

          // Verify Semantics
          final semanticsFinder = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Server Item Card' &&
                widget.properties.selected == true,
          );
          expect(semanticsFinder, findsOneWidget);

          // Verify elevated state render without errors
          await tester.pumpWidget(
            MaterialApp(
              theme: BrickTheme.light(),
              darkTheme: BrickTheme.dark(),
              themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
              home: const Scaffold(
                body: BrickGlassCard(
                  elevated: true,
                  child: Text('Elevated Card'),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'Test 2: BrickProtocolPill Hue Resolution & WCAG AA Contrast Across All 8 Protocols in Dark & Light Modes',
      (tester) async {
        const protocols = <String>[
          'REALITY',
          'VLESS',
          'VMESS',
          'TROJAN',
          'SS',
          'WG',
          'AWG',
          'HY2',
          'TUIC',
        ];

        for (final isDark in [true, false]) {
          final colors = isDark
              ? BrickSemanticColors.dark
              : BrickSemanticColors.light;
          final surface = colors.surface;
          final bgAlpha = isDark ? 0.14 : 0.07;

          for (final proto in protocols) {
            final hue = BrickProtocolPill.resolveHue(
              proto,
              colors: colors,
              isDark: isDark,
            );

            // Compute effective composite background on top of card surface
            final compositeBg = Color.alphaBlend(
              hue.withValues(alpha: bgAlpha),
              surface,
            );
            final ratio = _contrastRatio(hue, compositeBg);

            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  'Protocol $proto in ${isDark ? "Dark" : "Light"} mode must meet WCAG AA contrast (>= 4.5:1), got ${ratio.toStringAsFixed(2)}:1',
            );

            // Mount the widget and verify tabularFigures() on monospace text
            await tester.pumpWidget(
              MaterialApp(
                theme: BrickTheme.light(),
                darkTheme: BrickTheme.dark(),
                themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                home: Scaffold(
                  body: Center(child: BrickProtocolPill(label: proto)),
                ),
              ),
            );

            final textFinder = find.text(proto);
            expect(textFinder, findsOneWidget);
            final textWidget = tester.widget<Text>(textFinder);
            expect(
              textWidget.style?.fontFeatures,
              contains(const FontFeature.tabularFigures()),
              reason: 'BrickProtocolPill must include tabularFigures()',
            );
          }
        }
      },
    );

    testWidgets(
      'Test 3: BrickStatusDot Static, Pulsing & Clean Animation Disposal',
      (tester) async {
        var isPulsing = true;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return MaterialApp(
                theme: BrickTheme.dark(),
                home: Scaffold(
                  body: Center(
                    child: Column(
                      children: [
                        BrickStatusDot(
                          color: const Color(0xFF10B981),
                          size: 10.0,
                          pulsing: isPulsing,
                          semanticLabel: 'Connected Status',
                        ),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              isPulsing = false;
                            });
                          },
                          child: const Text('Stop Pulsing'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );

        // Bounded pump: NEVER call pumpAndSettle on a repeating animation!
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(BrickStatusDot), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Advance further in animation
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);

        // Toggle pulsing to false via didUpdateWidget
        await tester.tap(find.text('Stop Pulsing'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(isPulsing, isFalse);
        expect(tester.takeException(), isNull);

        // Unmount cleanly to verify zero active-ticker leaks on dispose
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Test 4: BrickSectionHeader Render & Tabular Count Pill', (
      tester,
    ) async {
      for (final isDark in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: BrickTheme.light(),
            darkTheme: BrickTheme.dark(),
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360.0,
                  child: BrickSectionHeader(
                    title: 'Servers',
                    icon: Icons.dns_outlined,
                    countLabel: '42',
                    trailing: Text('REFRESH'),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('SERVERS'), findsOneWidget);
        expect(find.text('42'), findsOneWidget);
        expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
        expect(find.text('REFRESH'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
