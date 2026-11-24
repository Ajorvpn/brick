// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Disconnecting,
        Error,
        PlatformError;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/widgets/connection_state_badge.dart';
import 'package:mobile/features/connection/presentation/widgets/session_info_panel.dart';
import 'package:mobile/features/connection/presentation/widgets/throughput_readout.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

/// Material app carrying the real Obsidian Glass themes plus the test
/// localization delegates provided by the harness.
Widget _themedApp({required Widget home, required ThemeMode themeMode}) {
  return Builder(
    builder: (context) => MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      theme: BrickTheme.light(),
      darkTheme: BrickTheme.dark(),
      themeMode: themeMode,
      home: Scaffold(body: home),
    ),
  );
}

/// Kill switch notifier forced into the blocking state so the panel's Signal
/// Crimson alert can be asserted without driving a full engine session.
class _BlockingKillSwitchNotifier extends KillSwitchNotifier {
  @override
  KillSwitchState build() => const KillSwitchBlocking(reason: 'test_block');
}

void main() {
  setUpAll(initTestLocalization);

  testWidgets(
    'Test 1: ConnectionStateBadge renders the loading state and all 5 '
    'sealed ConnectionState variants in Dark & Light at 360dp',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      // Loading state: un-emitted stream with no pre-warmed state.
      final loadingEngine = FakeVpnEngine();
      addTearDown(loadingEngine.dispose);

      await pumpConnectionApp(
        tester,
        _themedApp(
          themeMode: ThemeMode.dark,
          home: Center(
            child: ProviderScope(
              overrides: [
                // Keep the provider pending so the badge renders its neutral
                // "Checking..." fallback.
                connectionStateProvider.overrideWith(
                  (ref) => const Stream<ConnectionState>.empty(),
                ),
                initialConnectionStateProvider.overrideWith((ref) => null),
              ],
              child: const ConnectionStateBadge(),
            ),
          ),
        ),
        engine: loadingEngine,
      );
      expect(
        find.byKey(const ValueKey<String>('connection_state_badge')),
        findsOneWidget,
      );
      expect(find.text('Checking...'), findsOneWidget);
      expect(tester.takeException(), isNull);

      for (final themeMode in const [ThemeMode.dark, ThemeMode.light]) {
        // Unmount the previous frame so each mode gets a fresh provider scope.
        await tester.pumpWidget(const SizedBox.shrink());

        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpConnectionApp(
          tester,
          _themedApp(
            themeMode: themeMode,
            home: const Center(child: ConnectionStateBadge()),
          ),
          engine: engine,
        );

        final expected = <ConnectionState, String>{
          const Disconnected(): 'Disconnected',
          const Connecting(): 'Connecting',
          const Connected(): 'Connected',
          const Disconnecting(): 'Disconnecting',
          const Error(PlatformError('bad')): 'Connection error',
        };

        for (final entry in expected.entries) {
          engine.emit(entry.key);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));

          expect(
            find.byKey(const ValueKey<String>('connection_state_badge')),
            findsOneWidget,
          );
          expect(
            find.text(entry.value),
            findsOneWidget,
            reason:
                'Badge must render "${entry.value}" in ${themeMode.name} mode',
          );
          expect(
            find.descendant(
              of: find.byType(ConnectionStateBadge),
              matching: find.byType(BrickStatusDot),
            ),
            findsOneWidget,
            reason: 'Badge must carry exactly one non-pulsing status dot',
          );

          final dot = tester.widget<BrickStatusDot>(
            find.descendant(
              of: find.byType(ConnectionStateBadge),
              matching: find.byType(BrickStatusDot),
            ),
          );
          expect(
            dot.pulsing,
            isFalse,
            reason: 'Dashboard badge must never run a repeating ticker',
          );

          for (final text in tester.widgetList<Text>(
            find.descendant(
              of: find.byType(ConnectionStateBadge),
              matching: find.byType(Text),
            ),
          )) {
            expect(text.style?.fontWeight, isNot(FontWeight.w600));
          }

          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'Test 2: ThroughputReadout renders in a BrickGlassCard with tabular '
    'figures, stats-error fallback and zero overflow at 360dp',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      for (final themeMode in const [ThemeMode.dark, ThemeMode.light]) {
        // Unmount the previous frame so each mode gets a fresh provider scope.
        await tester.pumpWidget(const SizedBox.shrink());

        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpConnectionApp(
          tester,
          _themedApp(
            themeMode: themeMode,
            home: const Padding(
              padding: EdgeInsets.all(BrickSpacing.md),
              child: Center(child: ThroughputReadout()),
            ),
          ),
          engine: engine,
        );

        engine.emit(const Connected());
        await tester.pumpAndSettle();

        expect(find.byType(BrickGlassCard), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('throughput_readout')),
          findsOneWidget,
        );

        final speedText = tester.widget<Text>(
          find.byKey(const ValueKey<String>('throughput_speed_readout')),
        );
        expect(
          speedText.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'Instantaneous speed must use tabular figures',
        );

        final totalsText = tester.widget<Text>(
          find.byKey(const ValueKey<String>('throughput_readout')),
        );
        expect(
          totalsText.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'Cumulative totals must use tabular figures',
        );
        expect(totalsText.style?.fontWeight, FontWeight.w500);
        expect(tester.takeException(), isNull);

        // Stats error surfaces the localized fallback without throwing.
        engine.emitStatsError(Exception('stats pipeline failure'));
        await tester.pumpAndSettle();

        expect(find.text('Traffic data unavailable'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('throughput_readout')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('throughput_speed_readout')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Test 3: SessionInfoPanel renders in a BrickGlassCard with tabular '
    'duration, zero w600 and a 48dp Signal Crimson kill-switch action',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);

      for (final themeMode in const [ThemeMode.dark, ThemeMode.light]) {
        // Unmount the previous frame so each mode gets a fresh provider scope.
        await tester.pumpWidget(const SizedBox.shrink());

        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpConnectionApp(
          tester,
          _themedApp(
            themeMode: themeMode,
            home: const Padding(
              padding: EdgeInsets.all(BrickSpacing.md),
              child: Center(child: SessionInfoPanel()),
            ),
          ),
          engine: engine,
        );

        expect(find.byType(BrickGlassCard), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('session_info_panel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('session_server_text')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('session_status_text')),
          findsOneWidget,
        );

        final durationText = tester.widget<Text>(
          find.byKey(const ValueKey<String>('session_duration_text')),
        );
        expect(
          durationText.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'Session duration must use tabular figures',
        );

        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(SessionInfoPanel),
            matching: find.byType(Text),
          ),
        )) {
          expect(text.style?.fontWeight, isNot(FontWeight.w600));
        }

        engine.emit(const Connected());
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Tunnel: Connected'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      // Kill-switch blocking alert with the crimson unblock action.
      final blockingEngine = FakeVpnEngine();
      addTearDown(blockingEngine.dispose);

      await pumpConnectionApp(
        tester,
        _themedApp(
          themeMode: ThemeMode.dark,
          home: Padding(
            padding: const EdgeInsets.all(BrickSpacing.md),
            child: Center(
              child: ProviderScope(
                overrides: [
                  killSwitchProvider.overrideWith(
                    _BlockingKillSwitchNotifier.new,
                  ),
                ],
                child: const SessionInfoPanel(),
              ),
            ),
          ),
        ),
        engine: blockingEngine,
      );

      expect(
        find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
        findsOneWidget,
      );
      expect(find.text('Kill Switch Active — Traffic Blocked'), findsOneWidget);

      final unblockFinder = find.byKey(
        const ValueKey<String>('kill_switch_unblock_button'),
      );
      expect(unblockFinder, findsOneWidget);

      final button = tester.widget<FilledButton>(unblockFinder);
      final resolvedForeground = button.style?.foregroundColor?.resolve(
        <WidgetState>{},
      );
      expect(
        resolvedForeground,
        BrickSemanticColors.dark.onAccent,
        reason: 'Unblock action must use colors.onAccent, never Colors.white',
      );
      expect(resolvedForeground, isNot(Colors.white));

      final buttonSize = tester.getSize(unblockFinder);
      expect(buttonSize.width, greaterThanOrEqualTo(48.0));
      expect(buttonSize.height, greaterThanOrEqualTo(48.0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Test 4: Combined dashboard stack renders at 360x640 and 412x915 in '
    'Dark & Light with zero exceptions and zero raw localization keys',
    (tester) async {
      for (final size in const [Size(360, 640), Size(412, 915)]) {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        for (final themeMode in const [ThemeMode.dark, ThemeMode.light]) {
          final engine = FakeVpnEngine();
          addTearDown(engine.dispose);

          await pumpConnectionApp(
            tester,
            _themedApp(
              themeMode: themeMode,
              home: const SingleChildScrollView(
                padding: EdgeInsets.all(BrickSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: ConnectionStateBadge()),
                    SizedBox(height: BrickSpacing.md),
                    ThroughputReadout(),
                    SizedBox(height: BrickSpacing.md),
                    SessionInfoPanel(),
                  ],
                ),
              ),
            ),
            engine: engine,
          );

          engine.emit(const Connected());
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.byType(ConnectionStateBadge), findsOneWidget);
          expect(find.byType(ThroughputReadout), findsOneWidget);
          expect(find.byType(SessionInfoPanel), findsOneWidget);
          expect(tester.takeException(), isNull);

          for (final text in tester.widgetList<Text>(find.byType(Text))) {
            final data = text.data;
            if (data == null) continue;
            expect(
              data.startsWith('connection.'),
              isFalse,
              reason: 'Raw localization key leaked into the UI: $data',
            );
          }
        }
      }
    },
  );
}
