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

/// Computes the WCAG 2.1 contrast ratio between two colors.
double _contrastRatio(Color c1, Color c2) {
  final l1 = _relativeLuminance(c1);
  final l2 = _relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _harness({required Widget child, required ThemeMode themeMode}) {
  return MaterialApp(
    theme: BrickTheme.light(),
    darkTheme: BrickTheme.dark(),
    themeMode: themeMode,
    home: Scaffold(body: Center(child: child)),
  );
}

String _statusLabelFor(BrickOrbState state) {
  return switch (state) {
    BrickOrbState.disconnected => 'Disconnected',
    BrickOrbState.connecting => 'Connecting',
    BrickOrbState.connected => 'Connected',
    BrickOrbState.reconnecting => 'Reconnecting',
    BrickOrbState.disconnecting => 'Disconnecting',
    BrickOrbState.error => 'Error',
    BrickOrbState.killSwitch => 'Kill Switch',
  };
}

void main() {
  group('Phase 11 Chunk 3A: BrickPowerOrb & BrickTelemetryCard', () {
    testWidgets(
      'Test 1: All 7 BrickOrbState variants in Dark & Light, bounded tickers, tap callback, state transitions & clean disposal',
      (tester) async {
        for (final themeMode in const [ThemeMode.dark, ThemeMode.light]) {
          for (final state in BrickOrbState.values) {
            var tapCount = 0;

            await tester.pumpWidget(
              _harness(
                themeMode: themeMode,
                child: BrickPowerOrb(
                  state: state,
                  statusLabel: _statusLabelFor(state),
                  actionHint: 'Tap to act',
                  onTap: () => tapCount++,
                ),
              ),
            );

            // Bounded pumps only: several states run repeating tickers.
            await tester.pump(const Duration(milliseconds: 300));

            expect(find.byType(BrickPowerOrb), findsOneWidget);
            expect(find.text(_statusLabelFor(state)), findsOneWidget);
            expect(find.text('Tap to act'), findsOneWidget);
            expect(tester.takeException(), isNull);

            await tester.tap(
              find.descendant(
                of: find.byType(BrickPowerOrb),
                matching: find.byType(InkWell),
              ),
            );
            await tester.pump(const Duration(milliseconds: 200));
            expect(tapCount, 1);

            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
          }
        }

        // Explicit state machine transition: connecting -> connected -> disconnected.
        var liveState = BrickOrbState.connecting;
        late StateSetter setHarnessState;

        await tester.pumpWidget(
          MaterialApp(
            theme: BrickTheme.light(),
            darkTheme: BrickTheme.dark(),
            themeMode: ThemeMode.dark,
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    setHarnessState = setState;
                    return BrickPowerOrb(
                      state: liveState,
                      statusLabel: _statusLabelFor(liveState),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        setHarnessState(() => liveState = BrickOrbState.connected);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Connected'), findsOneWidget);
        expect(find.byIcon(Icons.shield_rounded), findsOneWidget);

        setHarnessState(() => liveState = BrickOrbState.disconnected);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Disconnected'), findsOneWidget);
        expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Unmount: every controller must be disposed with zero ticker leaks.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Test 2: Render integrity — split color/gradient decorations, internal transparency Material, >= 48dp core & typography guard',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            themeMode: ThemeMode.dark,
            child: BrickPowerOrb(
              state: BrickOrbState.connected,
              statusLabel: 'Connected',
              actionHint: 'Tap to disconnect',
              onTap: () {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Solid surface and specular sheen must live in separate DecoratedBox
        // widgets: `color` + `gradient` in one BoxDecoration silently drops color.
        final surfaceFinder = find.byKey(
          const ValueKey<String>('brick_orb_core_surface'),
        );
        expect(surfaceFinder, findsOneWidget);
        final surfaceDecoration =
            tester.widget<DecoratedBox>(surfaceFinder).decoration
                as BoxDecoration;
        expect(surfaceDecoration.color, isNotNull);
        expect(surfaceDecoration.gradient, isNull);

        final sheenFinder = find.byKey(
          const ValueKey<String>('brick_orb_core_sheen'),
        );
        expect(sheenFinder, findsOneWidget);
        final sheenDecoration =
            tester.widget<DecoratedBox>(sheenFinder).decoration
                as BoxDecoration;
        expect(sheenDecoration.gradient, isNotNull);
        expect(sheenDecoration.color, isNull);

        // The InkWell ripple must paint on an internal transparency Material.
        final inkWellFinder = find.descendant(
          of: find.byType(BrickPowerOrb),
          matching: find.byType(InkWell),
        );
        expect(inkWellFinder, findsOneWidget);
        final material = tester
            .element(inkWellFinder)
            .findAncestorWidgetOfExactType<Material>();
        expect(
          material,
          isNotNull,
          reason: 'InkWell needs a Material ancestor',
        );
        expect(
          material!.type,
          MaterialType.transparency,
          reason: 'Ripple must paint on a transparent internal Material',
        );
        // Touch target must clear the 48dp accessibility floor.
        final coreSize = tester.getSize(surfaceFinder);
        expect(coreSize.width, greaterThanOrEqualTo(48.0));
        expect(coreSize.height, greaterThanOrEqualTo(48.0));

        // Typography guard: only w400/w500/w700 and the 4-size scale.
        final texts = tester.widgetList<Text>(
          find.descendant(
            of: find.byType(BrickPowerOrb),
            matching: find.byType(Text),
          ),
        );
        expect(texts, isNotEmpty);
        for (final text in texts) {
          expect(
            text.style?.fontWeight,
            isNot(FontWeight.w600),
            reason: 'w600 is forbidden in the Obsidian Glass hierarchy',
          );
          expect(
            text.style?.fontSize,
            isNot(13.0),
            reason: 'fontSize 13 is outside the 4-size typography scale',
          );
          expect(
            text.style?.fontSize,
            anyOf(
              BrickTypography.sizeDisplay,
              BrickTypography.sizeTitle,
              BrickTypography.sizeBody,
              BrickTypography.sizeLabel,
            ),
          );
        }
      },
    );

    testWidgets(
      'Test 3: BrickTelemetryCard tabular figures & zero overflow in a 2-column 360dp layout (Dark & Light)',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(360.0, 720.0);
        addTearDown(tester.view.reset);

        for (final themeMode in const [ThemeMode.dark, ThemeMode.light]) {
          final colors = themeMode == ThemeMode.dark
              ? BrickSemanticColors.dark
              : BrickSemanticColors.light;
          await tester.pumpWidget(
            MaterialApp(
              theme: BrickTheme.light(),
              darkTheme: BrickTheme.dark(),
              themeMode: themeMode,
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(BrickSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: BrickTelemetryCard(
                          label: 'Download',
                          value: '128.45 MB/s',
                          icon: Icons.arrow_downward_rounded,
                          accentColor: colors.stateConnected,
                        ),
                      ),
                      const SizedBox(width: BrickSpacing.sm),
                      const Expanded(
                        child: BrickTelemetryCard(
                          label: 'Session',
                          value: '14:52:09',
                          prominent: true,
                          sublabel: '↑ 12.4 MB/s · ↓ 98.7 MB/s',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.byType(BrickTelemetryCard), findsNWidgets(2));
          expect(find.text('DOWNLOAD'), findsOneWidget);
          expect(find.text('SESSION'), findsOneWidget);
          expect(tester.takeException(), isNull);

          final metricText = tester.widget<Text>(find.text('128.45 MB/s'));
          expect(
            metricText.style?.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
          expect(metricText.style?.fontSize, BrickTypography.sizeMonoMetric);

          final prominentText = tester.widget<Text>(find.text('14:52:09'));
          expect(
            prominentText.style?.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
          expect(
            prominentText.style?.fontSize,
            BrickTypography.sizeMonoMetricLarge,
          );

          // Time string must fit inside the card without horizontal overflow.
          final cardWidth = tester
              .getSize(find.byType(BrickTelemetryCard).first)
              .width;
          expect(cardWidth, lessThanOrEqualTo(180.0));
        }
      },
    );

    testWidgets(
      'Test 4: Disabled BrickPowerOrb (onTap: null) exposes semantics and never throws on tap',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            themeMode: ThemeMode.light,
            child: const BrickPowerOrb(
              state: BrickOrbState.disconnected,
              statusLabel: 'Disconnected',
              semanticLabel: 'VPN power control',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        final semanticsFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'VPN power control',
        );
        expect(semanticsFinder, findsOneWidget);

        final semantics = tester.widget<Semantics>(semanticsFinder);
        expect(semantics.properties.button, isFalse);
        expect(semantics.properties.enabled, isFalse);

        // Tapping a disabled orb must be inert, not throwing.
        await tester.tap(
          find.byKey(const ValueKey<String>('brick_orb_core_surface')),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.takeException(), isNull);

        // Enabled orb advertises itself as a button.
        await tester.pumpWidget(
          _harness(
            themeMode: ThemeMode.light,
            child: BrickPowerOrb(
              state: BrickOrbState.disconnected,
              statusLabel: 'Disconnected',
              onTap: () {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        final enabledSemantics = tester.widget<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Disconnected' &&
                widget.properties.button == true,
          ),
        );
        expect(enabledSemantics.properties.enabled, isTrue);
      },
    );

    testWidgets(
      'Test 5: Every state accent meets WCAG 2.1 SC 1.4.11 non-text contrast (>= 3.0:1) on surfaceElevated',
      (tester) async {
        for (final isDark in [true, false]) {
          final colors = isDark
              ? BrickSemanticColors.dark
              : BrickSemanticColors.light;
          final accents = <String, Color>{
            'brandBrick': colors.brandBrick,
            'stateConnecting': colors.stateConnecting,
            'stateConnected': colors.stateConnected,
            'stateError': colors.stateError,
            'killSwitchActive': colors.killSwitchActive,
            'stateDisconnecting': colors.stateDisconnecting,
          };

          accents.forEach((name, accent) {
            final ratio = _contrastRatio(accent, colors.surfaceElevated);
            expect(
              ratio,
              greaterThanOrEqualTo(3.0),
              reason:
                  'Accent $name in ${isDark ? "Dark" : "Light"} mode must meet SC 1.4.11 (>= 3.0:1), got ${ratio.toStringAsFixed(2)}:1',
            );
          });
        }

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Test 6: WCAG 2.1 SC 2.3.3 reduced motion halts every repeating ticker',
      (tester) async {
        const colors = BrickSemanticColors.dark;

        Widget tree({required bool disableAnimations}) {
          return MaterialApp(
            theme: BrickTheme.light(),
            darkTheme: BrickTheme.dark(),
            themeMode: ThemeMode.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: disableAnimations),
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const BrickPowerOrb(
                      state: BrickOrbState.connecting,
                      statusLabel: 'Connecting',
                    ),
                    const SizedBox(height: 16),
                    const BrickPowerOrb(
                      state: BrickOrbState.connected,
                      statusLabel: 'Connected',
                    ),
                    const SizedBox(height: 16),
                    BrickStatusDot(
                      color: colors.stateConnecting,
                      pulsing: true,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 1. Reduced motion ON. `connecting` would normally rotate forever,
        // `connected` would breathe forever and the dot would ripple forever.
        // If even one of those tickers survived, this pumpAndSettle would time
        // out instead of returning — so returning is the proof.
        await tester.pumpWidget(tree(disableAnimations: true));
        await tester.pumpAndSettle();
        expect(find.byType(BrickPowerOrb), findsNWidgets(2));
        expect(
          tester.binding.transientCallbackCount,
          0,
          reason: 'No repeating ticker may stay active under reduced motion',
        );
        expect(tester.takeException(), isNull);

        // 2. Toggle OFF: the very same tree animates again, proving the media
        // query value is actually what gates the tickers.
        await tester.pumpWidget(tree(disableAnimations: false));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.binding.transientCallbackCount,
          greaterThan(0),
          reason: 'Motion must resume when reduced motion is disabled',
        );

        // 3. Toggle back ON: everything must stop again, cleanly.
        await tester.pumpWidget(tree(disableAnimations: true));
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);

        // Unmount: zero ticker leaks with controllers disposed.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
