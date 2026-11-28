// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        Disconnected,
        Disconnecting,
        Error,
        PlatformError;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

const String _uuid = '11111111-2222-3333-4444-555555555555';

String _vlessUri(String remark) =>
    'vless://$_uuid@example.com:443?security=none#'
    '${Uri.encodeComponent(remark)}';

void _seedServer(FakeServerProfileDataSource dataSource) {
  dataSource.records.add(
    SavedServerRecord(
      id: 'de-frankfurt',
      sourceUri: _vlessUri('🇩🇪 Germany · Frankfurt #1'),
      addedAt: DateTime.utc(2026, 11, 21),
    ),
  );
}

/// Kill switch notifier whose state the test drives directly, so the orb's
/// safety priority can be asserted without a real engine session.
class _StubKillSwitchNotifier extends KillSwitchNotifier {
  @override
  KillSwitchState build() => const KillSwitchInactive();

  void block() => state = const KillSwitchBlocking(reason: 'test_block');

  void clear() => state = const KillSwitchInactive();
}

/// Auto-reconnect notifier whose state the test drives directly, so the
/// reconnecting branch can be asserted deterministically.
class _StubAutoReconnectNotifier extends AutoReconnectNotifier {
  @override
  AutoReconnectState build() => const AutoReconnectIdle();

  void startReconnecting() =>
      state = const AutoReconnectInFlight(attempt: 1, maxAttempts: 5);

  void reset() => state = const AutoReconnectIdle();
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/servers',
        builder: (context, state) => const ServersScreen(),
      ),
    ],
  );
}

Widget _app({required GoRouter router, required ThemeMode themeMode}) {
  return Builder(
    builder: (context) => MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      theme: BrickTheme.light(),
      darkTheme: BrickTheme.dark(),
      themeMode: themeMode,
    ),
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required FakeVpnEngine engine,
  required FakeServerProfileDataSource dataSource,
  ThemeMode themeMode = ThemeMode.dark,
}) async {
  final connectivity = FakeConnectivitySource();
  addTearDown(connectivity.dispose);

  await pumpLocalizedApp(
    tester,
    _app(router: _buildRouter(), themeMode: themeMode),
    overrides: <Object>[
      vpnEngineProvider.overrideWithValue(engine),
      serverProfileRepositoryProvider.overrideWith(
        (ref) async => FakeServerProfileRepository(dataSource),
      ),
      connectivitySourceProvider.overrideWithValue(connectivity),
      killSwitchProvider.overrideWith(_StubKillSwitchNotifier.new),
      autoReconnectProvider.overrideWith(_StubAutoReconnectNotifier.new),
    ],
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

_StubKillSwitchNotifier _killSwitch(WidgetTester tester) =>
    _container(tester).read(killSwitchProvider.notifier)
        as _StubKillSwitchNotifier;

_StubAutoReconnectNotifier _autoReconnect(WidgetTester tester) =>
    _container(tester).read(autoReconnectProvider.notifier)
        as _StubAutoReconnectNotifier;

const ValueKey<String> _toggleKey = ValueKey<String>(
  'home_connect_toggle_button',
);

BrickPowerOrb _orb(WidgetTester tester, [ValueKey<String> key = _toggleKey]) =>
    tester.widget<BrickPowerOrb>(find.byKey(key));

void main() {
  setUpAll(initTestLocalization);

  testWidgets(
    'Test 1: empty state guides to the Servers tab with no manual add '
    'affordances and the idle orb key',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);

      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);

      await _pumpHome(
        tester,
        engine: engine,
        dataSource: FakeServerProfileDataSource(),
      );

      expect(
        find.byKey(const ValueKey<String>('home_empty_server_card')),
        findsOneWidget,
      );
      expect(find.text('No saved servers yet'), findsOneWidget);
      expect(find.text('Browse Servers'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('home_connect_orb_idle')),
        findsOneWidget,
      );
      expect(find.byKey(_toggleKey), findsNothing);

      // Manual add affordances were removed from the primary dashboard.
      expect(
        find.byKey(const ValueKey<String>('home_add_server_button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('home_add_subscription_button')),
        findsNothing,
      );
      expect(find.byType(ServersScreen), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('home_browse_servers_button')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ServersScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Test 2: every authoritative state drives the orb state and label '
    '(stream truth, Invariant 1)',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);

      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);
      final dataSource = FakeServerProfileDataSource();
      _seedServer(dataSource);

      await _pumpHome(tester, engine: engine, dataSource: dataSource);

      expect(
        find.byKey(const ValueKey<String>('home_active_server_card')),
        findsOneWidget,
      );
      expect(find.byKey(_toggleKey), findsOneWidget);

      // Disconnected (initial pre-warmed state).
      expect(_orb(tester).state, BrickOrbState.disconnected);
      expect(_orb(tester).statusLabel, 'Disconnected');

      engine.emit(const Connecting());
      await tester.pump(const Duration(milliseconds: 200));
      expect(_orb(tester).state, BrickOrbState.connecting);
      expect(_orb(tester).statusLabel, 'Connecting');
      expect(_orb(tester).actionHint, 'Cancel');

      engine.emit(const Connected());
      await tester.pump(const Duration(milliseconds: 200));
      expect(_orb(tester).state, BrickOrbState.connected);
      expect(_orb(tester).statusLabel, 'Connected');
      expect(_orb(tester).actionHint, 'Disconnect');

      _autoReconnect(tester).startReconnecting();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_orb(tester).state, BrickOrbState.reconnecting);
      expect(_orb(tester).statusLabel, 'Reconnecting');
      expect(_orb(tester).actionHint, 'Cancel');

      _autoReconnect(tester).reset();
      engine.emit(const Disconnecting());
      await tester.pump(const Duration(milliseconds: 200));
      expect(_orb(tester).state, BrickOrbState.disconnecting);
      expect(_orb(tester).statusLabel, 'Disconnecting');
      expect(_orb(tester).onTap, isNull);

      engine.emit(const Error(PlatformError('bad')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_orb(tester).state, BrickOrbState.error);
      expect(_orb(tester).statusLabel, 'Connection error');
      expect(_orb(tester).onTap, isNotNull);

      _killSwitch(tester).block();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_orb(tester).state, BrickOrbState.killSwitch);
      expect(_orb(tester).statusLabel, 'Traffic Blocked');
      expect(_orb(tester).actionHint, 'Unblock');
      expect(_orb(tester).onTap, isNotNull);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Test 3: orb taps dispatch connect, disconnect and kill-switch unblock '
    'exactly once with accurate hit testing',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);

      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);
      final dataSource = FakeServerProfileDataSource();
      _seedServer(dataSource);

      await _pumpHome(tester, engine: engine, dataSource: dataSource);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pump(const Duration(milliseconds: 200));
      expect(engine.startCalls.length, 1);

      engine.emit(const Connected());
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(_toggleKey));
      await tester.pump(const Duration(milliseconds: 200));
      expect(engine.stopCalls, 1);

      engine.emit(const Disconnected());
      _killSwitch(tester).block();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_orb(tester).state, BrickOrbState.killSwitch);

      await tester.tap(find.byKey(_toggleKey));
      await tester.pump(const Duration(milliseconds: 200));
      expect(engine.stopCalls, 2);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Test 4: atmosphere glow uses a gradient only, typography stays '
      'w600-free, the browse action uses onAccent, and the active server card '
      'routes to /servers', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    final emptyEngine = FakeVpnEngine();
    addTearDown(emptyEngine.dispose);

    await _pumpHome(
      tester,
      engine: emptyEngine,
      dataSource: FakeServerProfileDataSource(),
    );

    final glow = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('home_atmosphere_glow')),
    );
    final glowDecoration = glow.decoration as BoxDecoration;
    expect(glowDecoration.gradient, isNotNull);
    expect(glowDecoration.color, isNull);

    final browseButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('home_browse_servers_button')),
    );
    expect(
      browseButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      BrickSemanticColors.dark.brandBrick,
    );
    expect(
      browseButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      BrickSemanticColors.dark.onAccent,
    );
    expect(
      browseButton.style?.foregroundColor?.resolve(<WidgetState>{}),
      isNot(Colors.white),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('home_browse_servers_button')),
          )
          .height,
      greaterThanOrEqualTo(48.0),
    );

    for (final text in tester.widgetList<Text>(
      find.descendant(of: find.byType(HomeScreen), matching: find.byType(Text)),
    )) {
      expect(
        text.style?.fontWeight,
        isNot(FontWeight.w600),
        reason: 'Disallowed FontWeight.w600 in Text("${text.data}")',
      );
      expect(
        text.style?.fontSize,
        isNot(13),
        reason: 'Disallowed fontSize 13 in Text("${text.data}")',
      );
    }

    // Fresh tree for the seeded run: re-pumping an identical root reuses
    // the provider scope and its already-resolved server list.
    await tester.pumpWidget(const SizedBox.shrink());

    final seededEngine = FakeVpnEngine();
    addTearDown(seededEngine.dispose);
    final dataSource = FakeServerProfileDataSource();
    _seedServer(dataSource);

    await _pumpHome(tester, engine: seededEngine, dataSource: dataSource);

    expect(
      find.byKey(const ValueKey<String>('home_active_server_card')),
      findsOneWidget,
    );
    expect(find.text('Smart Auto'), findsOneWidget);
    expect(find.text('Best available server'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('home_active_server_endpoint')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('home_active_server_card')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ServersScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Test 5: responsive dark and light stack at 360x640 and 412x915 with '
    'zero overflow in connected and kill-switch worst cases',
    (tester) async {
      for (final size in const <Size>[Size(360, 640), Size(412, 915)]) {
        for (final themeMode in const <ThemeMode>[
          ThemeMode.dark,
          ThemeMode.light,
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());

          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);

          final engine = FakeVpnEngine();
          addTearDown(engine.dispose);
          final dataSource = FakeServerProfileDataSource();
          _seedServer(dataSource);

          await _pumpHome(
            tester,
            engine: engine,
            dataSource: dataSource,
            themeMode: themeMode,
          );

          engine.emit(const Connected());
          await tester.pump(const Duration(milliseconds: 300));

          expect(
            tester.takeException(),
            isNull,
            reason:
                'Render exception at ${size.width.toInt()}x'
                '${size.height.toInt()} in $themeMode',
          );
          expect(_orb(tester).state, BrickOrbState.connected);

          _killSwitch(tester).block();
          await tester.pump(const Duration(milliseconds: 300));

          expect(
            tester.takeException(),
            isNull,
            reason:
                'Kill-switch render exception at ${size.width.toInt()}x'
                '${size.height.toInt()} in $themeMode',
          );
          expect(_orb(tester).state, BrickOrbState.killSwitch);

          for (final text in tester.widgetList<Text>(find.byType(Text))) {
            final data = text.data;
            if (data == null) continue;
            expect(
              data.startsWith('home.') || data.startsWith('connection.'),
              isFalse,
              reason: 'Raw localization key leaked into the UI: $data',
            );
          }
        }
      }

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
