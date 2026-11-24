// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/settings/presentation/screens/live_logs_screen.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

const ValueKey<String> _copyKey = ValueKey<String>('logs_copy_button');
const ValueKey<String> _clearKey = ValueKey<String>('logs_clear_button');
const ValueKey<String> _dialogKey = ValueKey<String>(
  'logs_privacy_warning_dialog',
);
const ValueKey<String> _cancelKey = ValueKey<String>('logs_copy_cancel_button');
const ValueKey<String> _confirmKey = ValueKey<String>(
  'logs_copy_confirm_button',
);
const ValueKey<String> _jumpKey = ValueKey<String>(
  'logs_jump_to_latest_button',
);

Widget _app({required ThemeMode themeMode}) {
  return Builder(
    builder: (context) => MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      theme: BrickTheme.light(),
      darkTheme: BrickTheme.dark(),
      themeMode: themeMode,
      home: const LiveLogsScreen(),
    ),
  );
}

Future<FakeVpnEngine> _pumpLiveLogs(
  WidgetTester tester, {
  ThemeMode themeMode = ThemeMode.dark,
  Size size = const Size(412, 915),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final engine = FakeVpnEngine();
  addTearDown(engine.dispose);

  await pumpLocalizedApp(
    tester,
    _app(themeMode: themeMode),
    overrides: <Object>[vpnEngineProvider.overrideWithValue(engine)],
  );
  return engine;
}

void main() {
  setUpAll(initTestLocalization);

  testWidgets(
    'Test 1: empty state renders the glass card and both AppBar actions meet '
    'the 48x48dp target in dark and light',
    (tester) async {
      for (final themeMode in const <ThemeMode>[
        ThemeMode.dark,
        ThemeMode.light,
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());

        await _pumpLiveLogs(tester, themeMode: themeMode);

        expect(
          find.byType(BrickGlassCard),
          findsOneWidget,
          reason:
              'Empty state must use the Obsidian glass surface ($themeMode)',
        );
        expect(find.byIcon(Icons.terminal_rounded), findsOneWidget);
        expect(find.text('No log entries yet'), findsOneWidget);
        expect(
          tester.widget<IconButton>(find.byKey(_copyKey)).onPressed,
          isNull,
          reason: 'Copy must stay disabled while the buffer is empty',
        );

        for (final key in const <ValueKey<String>>[_copyKey, _clearKey]) {
          final size = tester.getSize(find.byKey(key));
          expect(
            size.width,
            greaterThanOrEqualTo(BrickSpacing.minTouchTarget),
            reason: '$key width must be >= 48dp',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(BrickSpacing.minTouchTarget),
            reason: '$key height must be >= 48dp',
          );
        }

        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Test 2: structured terminal rows keep the 12sp typography floor, avoid '
    'w600, and use tabular figures throughout',
    (tester) async {
      final engine = await _pumpLiveLogs(tester);

      engine
        ..emitLog('2026-11-05 10:00:00 INFO [tun] Inbound tunnel started')
        ..emitLog('2026-11-05 10:00:01 WARN [dns] High latency detected')
        ..emitLog('2026-11-05 10:00:02 ERROR [router] Handshake failed')
        ..emitLog('2026-11-05 10:00:03 DEBUG [cache] Entry evicted');
      await tester.pumpAndSettle();

      const badges = <List<Object>>[
        <Object>['info', 0],
        <Object>['warning', 1],
        <Object>['error', 2],
        <Object>['debug', 3],
      ];

      for (final badge in badges) {
        final level = badge[0] as String;
        final index = badge[1] as int;
        final badgeFinder = find.byKey(
          ValueKey<String>('log_level_badge_${level}_$index'),
        );
        expect(badgeFinder, findsOneWidget);

        final badgeText = tester.widget<Text>(
          find.descendant(of: badgeFinder, matching: find.byType(Text)),
        );
        expect(
          badgeText.style?.fontSize,
          greaterThanOrEqualTo(12.0),
          reason: '$level badge must use the 12sp floor',
        );
        expect(badgeText.style?.fontWeight, isNot(FontWeight.w600));
        expect(
          badgeText.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }

      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(LiveLogsScreen),
              matching: find.byType(Text),
            ),
          )
          .toList(growable: false);
      expect(texts, isNotEmpty);

      for (final text in texts) {
        final style = text.style;
        final fontSize = style?.fontSize;
        if (fontSize != null) {
          expect(
            fontSize,
            greaterThanOrEqualTo(12.0),
            reason: 'Disallowed fontSize $fontSize in Text("${text.data}")',
          );
          expect(
            const <double>[10, 11, 13],
            isNot(contains(fontSize)),
            reason: 'Off-scale fontSize $fontSize in Text("${text.data}")',
          );
        }
        expect(
          style?.fontWeight,
          isNot(FontWeight.w600),
          reason: 'Disallowed FontWeight.w600 in Text("${text.data}")',
        );
        expect(
          style?.fontFamily,
          isNot('monospace'),
          reason: 'Raw monospace family bypasses BrickTypography.monoLog',
        );
      }

      final monoTexts = texts
          .where((t) => t.style?.fontFamily == BrickTypography.monoFontFamily)
          .toList(growable: false);
      // Badge + timestamp + source per entry (4 entries) plus the AppBar
      // entry-count badge.
      expect(monoTexts.length, greaterThanOrEqualTo(13));
      for (final text in monoTexts) {
        expect(
          text.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'Mono Text("${text.data}") must use tabular figures',
        );
      }

      final selectables = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList(growable: false);
      expect(selectables.length, 4);
      for (final body in selectables) {
        expect(body.style?.fontSize, greaterThanOrEqualTo(12.0));
        expect(body.style?.fontWeight, isNot(FontWeight.w600));
        expect(
          body.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }

      expect(
        find.text('Inbound tunnel started'),
        findsOneWidget,
        reason: 'Row body must keep the parsed message',
      );
      expect(find.text('[tun]'), findsOneWidget);
    },
  );

  testWidgets(
    'Test 3: privacy dialog and jump-to-latest FAB both resolve onAccent on '
    'the brand fill',
    (tester) async {
      final engine = await _pumpLiveLogs(tester);

      engine.emitLog('2026-11-05 10:00:00 INFO Initial log line');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_copyKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_dialogKey), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);

      final confirm = tester.widget<FilledButton>(find.byKey(_confirmKey));
      expect(
        confirm.style?.backgroundColor?.resolve(<WidgetState>{}),
        BrickSemanticColors.dark.brandBrick,
      );
      expect(
        confirm.style?.foregroundColor?.resolve(<WidgetState>{}),
        BrickSemanticColors.dark.onAccent,
      );
      expect(
        confirm.style?.foregroundColor?.resolve(<WidgetState>{}),
        isNot(Colors.white),
      );

      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_dialogKey), findsNothing);

      for (var i = 0; i < 100; i++) {
        engine.emitLog('2026-11-05 10:01:00 INFO Log event $i');
      }
      await tester.pumpAndSettle();

      expect(find.byKey(_jumpKey), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(_jumpKey);
      expect(fabFinder, findsOneWidget);

      final fab = tester.widget<FloatingActionButton>(fabFinder);
      expect(fab.backgroundColor, BrickSemanticColors.dark.brandBrick);
      expect(fab.foregroundColor, BrickSemanticColors.dark.onAccent);
      expect(fab.foregroundColor, isNot(Colors.white));

      await tester.tap(fabFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(_jumpKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Test 4: responsive dark and light render at 360x640 and 412x915 with '
    'zero overflow and zero raw localization keys',
    (tester) async {
      for (final size in const <Size>[Size(360, 640), Size(412, 915)]) {
        for (final themeMode in const <ThemeMode>[
          ThemeMode.dark,
          ThemeMode.light,
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());

          final engine = await _pumpLiveLogs(
            tester,
            themeMode: themeMode,
            size: size,
          );

          engine
            ..emitLog(
              '2026-11-05 10:00:00 INFO '
              '[a_really_long_source_component_name_for_responsive_checks] '
              'The tunnel negotiated a long diagnostic message that must wrap '
              'cleanly inside the virtualized terminal without overflowing the '
              'viewport in either theme mode',
            )
            ..emitLog('2026-11-05 10:00:01 WARN [tun] Short warning line');
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason:
                'Render exception at ${size.width.toInt()}x'
                '${size.height.toInt()} in $themeMode',
          );
          expect(find.byType(LiveLogsScreen), findsOneWidget);
          expect(
            find.text('No log entries yet'),
            findsNothing,
            reason: 'Populated buffer must not show the empty state',
          );

          for (final text in tester.widgetList<Text>(find.byType(Text))) {
            final data = text.data;
            if (data == null) continue;
            expect(
              data.startsWith('logs.') || data.startsWith('settings.'),
              isFalse,
              reason: 'Raw localization key leaked into the UI: $data',
            );
          }
        }
      }
    },
  );
}
