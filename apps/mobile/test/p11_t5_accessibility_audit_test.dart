// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:core_domain/core_domain.dart' show Connected;
// `intl` (re-exported by easy_localization) also defines a `TextDirection`
// whose constants are `LTR`/`RTL`; hide it so this file resolves Flutter's
// `dart:ui` `TextDirection` (with `.ltr`/`.rtl`) instead.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/presentation/widgets/app_shell.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/presentation/providers/camera_permission_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:mobile/features/settings/presentation/screens/live_logs_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile/main.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

const String _uuid = '11111111-2222-3333-4444-555555555555';

const ValueKey<String> _dockKey = ValueKey<String>('brick_bottom_dock');
const ValueKey<String> _surfaceLayerKey = ValueKey<String>(
  'brick_dock_surface_layer',
);
const ValueKey<String> _sheenLayerKey = ValueKey<String>(
  'brick_dock_sheen_layer',
);
const ValueKey<String> _homeTabKey = ValueKey<String>('nav_tab_home');
const ValueKey<String> _serversTabKey = ValueKey<String>('nav_tab_servers');
const ValueKey<String> _settingsTabKey = ValueKey<String>('nav_tab_settings');
const ValueKey<String> _nextKey = ValueKey<String>('onboarding_next_button');

String _vlessUri(String remark) =>
    'vless://$_uuid@example.com:443?security=none#'
    '${Uri.encodeComponent(remark)}';

void _seedServer(
  FakeServerProfileDataSource dataSource, {
  required String id,
  required String remark,
}) {
  dataSource.records.add(
    SavedServerRecord(
      id: id,
      sourceUri: _vlessUri(remark),
      addedAt: DateTime.utc(2026, 11, 22),
    ),
  );
}

FakeServerProfileDataSource _seedHierarchy() {
  final dataSource = FakeServerProfileDataSource();
  _seedServer(
    dataSource,
    id: 'de-frankfurt',
    remark: '🇩🇪 Germany · Frankfurt',
  );
  _seedServer(dataSource, id: 'de-berlin', remark: '🇩🇪 Germany · Berlin');
  _seedServer(
    dataSource,
    id: 'us-nyc',
    remark: '🇺🇸 United States · New York',
  );
  dataSource.records.add(
    SavedServerRecord(
      id: 'unreadable',
      sourceUri: 'definitely-not-a-server-uri',
      addedAt: DateTime.utc(2026, 11, 22),
    ),
  );
  return dataSource;
}

/// Applies an explicit [TextScaler] to everything below [home].
Widget _scaledApp({
  required Widget home,
  required ThemeMode themeMode,
  required double textScale,
}) {
  return Builder(
    builder: (context) => MaterialApp(
      theme: BrickTheme.light(),
      darkTheme: BrickTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
    ),
  );
}

/// Router host for [HomeScreen] so its `go` calls resolve in tests.
Widget _scaledRouterApp({
  required ThemeMode themeMode,
  required double textScale,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/servers',
        builder: (context, state) => const ServersScreen(),
      ),
    ],
  );
  return Builder(
    builder: (context) => MaterialApp.router(
      routerConfig: router,
      theme: BrickTheme.light(),
      darkTheme: BrickTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

/// Bare [AppShell] host used to measure dock tabs at large text scales.
Widget _scaledShellApp({required double textScale}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (context, state) =>
                    const Scaffold(body: SizedBox.expand()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/servers',
                builder: (context, state) =>
                    const Scaffold(body: SizedBox.expand()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (context, state) =>
                    const Scaffold(body: SizedBox.expand()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  return Builder(
    builder: (context) => MaterialApp.router(
      routerConfig: router,
      theme: BrickTheme.light(),
      darkTheme: BrickTheme.dark(),
      themeMode: ThemeMode.dark,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

List<Object> _preferenceOverrides() => <Object>[
  appPreferencesRepositoryProvider.overrideWithValue(
    FakeAppPreferencesRepository(),
  ),
];

List<Object> _serversOverrides(
  FakeVpnEngine engine,
  FakeServerProfileDataSource dataSource,
) {
  final connectivity = FakeConnectivitySource();
  // Every connectivity source created here is torn down with its test.
  addTearDown(connectivity.dispose);
  return <Object>[
    vpnEngineProvider.overrideWithValue(engine),
    serverProfileRepositoryProvider.overrideWith(
      (ref) async => FakeServerProfileRepository(dataSource),
    ),
    cameraPermissionServiceProvider.overrideWithValue(
      const FakeCameraPermissionService(),
    ),
    connectivitySourceProvider.overrideWithValue(connectivity),
  ];
}

void _setSurface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

double _channel(double component) => component <= 0.04045
    ? component / 12.92
    : math.pow((component + 0.055) / 1.055, 2.4).toDouble();

double _relativeLuminance(Color color) =>
    0.2126 * _channel(color.r) +
    0.7152 * _channel(color.g) +
    0.0722 * _channel(color.b);

/// WCAG 2.1 contrast ratio between two fully opaque colors.
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Fails with [reason] if the last frame produced any render/semantics error.
void _expectNoException(WidgetTester tester, String reason) {
  expect(tester.takeException(), isNull, reason: reason);
}

void main() {
  setUpAll(initTestLocalization);

  testWidgets(
    'Test 1: AppShell floats a real frosted dock (extendBody, no opaque '
    'backdrop) with >= 48dp tabs at 1.5x and 2.0x text scale',
    (tester) async {
      _setSurface(tester, const Size(360, 640));

      await pumpLocalizedApp(
        tester,
        const MyApp(),
        overrides: <Object>[...repositoryOverride(), ..._preferenceOverrides()],
      );

      final scaffoldFinder = find.descendant(
        of: find.byType(AppShell),
        matching: find.byType(Scaffold),
      );
      final scaffold = tester.widget<Scaffold>(scaffoldFinder.first);
      expect(
        scaffold.extendBody,
        isTrue,
        reason: 'Scrolled content must flow behind the floating dock',
      );

      // No opaque `colors.background` DecoratedBox may wrap the dock, or the
      // BackdropFilter would blur a solid canvas instead of page content.
      final opaqueAncestors = <String>[];
      tester.element(find.byKey(_dockKey)).visitAncestorElements((element) {
        final widget = element.widget;
        if (widget is DecoratedBox) {
          final decoration = widget.decoration;
          if (decoration is BoxDecoration) {
            final color = decoration.color;
            if (color != null &&
                (color == BrickSemanticColors.dark.background ||
                    color == BrickSemanticColors.light.background)) {
              opaqueAncestors.add(color.toString());
            }
          }
        }
        return true;
      });
      expect(
        opaqueAncestors,
        isEmpty,
        reason: 'An opaque background wrapper defeats the frosted blur',
      );

      expect(find.byKey(_surfaceLayerKey), findsOneWidget);
      expect(find.byKey(_sheenLayerKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppShell),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AppShell),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );

      for (final scale in const <double>[1.5, 2]) {
        await tester.pumpWidget(const SizedBox.shrink());

        await pumpLocalizedApp(
          tester,
          _scaledShellApp(textScale: scale),
          overrides: <Object>[
            ...repositoryOverride(),
            ..._preferenceOverrides(),
          ],
        );

        for (final key in const <ValueKey<String>>[
          _homeTabKey,
          _serversTabKey,
          _settingsTabKey,
        ]) {
          final size = tester.getSize(find.byKey(key));
          expect(
            size.width,
            greaterThanOrEqualTo(48.0),
            reason: '$key must stay >= 48dp wide at ${scale}x',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(48.0),
            reason: '$key must stay >= 48dp tall at ${scale}x',
          );
        }

        expect(
          tester.takeException(),
          isNull,
          reason: 'Dock overflowed at ${scale}x text scale',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Test 2: HomeScreen and OnboardingScreen never overflow at 1.5x / 2.0x '
    'text scale on 360x640 in dark and light',
    (tester) async {
      _setSurface(tester, const Size(360, 640));

      for (final themeMode in const <ThemeMode>[
        ThemeMode.dark,
        ThemeMode.light,
      ]) {
        for (final scale in const <double>[1.5, 2]) {
          final engine = FakeVpnEngine();
          addTearDown(engine.dispose);
          final dataSource = FakeServerProfileDataSource();
          _seedServer(
            dataSource,
            id: 'de-frankfurt',
            remark: '🇩🇪 Germany · Frankfurt',
          );

          await pumpLocalizedApp(
            tester,
            _scaledRouterApp(themeMode: themeMode, textScale: scale),
            overrides: _serversOverrides(engine, dataSource),
          );
          await tester.pump(const Duration(milliseconds: 300));

          _expectNoException(
            tester,
            'HomeScreen (disconnected) overflowed at ${scale}x in $themeMode',
          );

          engine.emit(const Connected());
          await tester.pump(const Duration(milliseconds: 300));

          _expectNoException(
            tester,
            'HomeScreen (connected) overflowed at ${scale}x in $themeMode',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 50));

          await pumpLocalizedApp(
            tester,
            _scaledApp(
              home: const OnboardingScreen(),
              themeMode: themeMode,
              textScale: scale,
            ),
            overrides: _preferenceOverrides(),
          );

          for (var step = 0; step < 3; step++) {
            _expectNoException(
              tester,
              'Onboarding step ${step + 1} overflowed at ${scale}x in '
              '$themeMode',
            );
            if (step < 2) {
              await tester.tap(find.byKey(_nextKey));
              await tester.pumpAndSettle();
            }
          }

          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  testWidgets('Test 3: ServersScreen, SettingsScreen and a populated '
      'LiveLogsScreen never overflow at 1.5x / 2.0x text scale on '
      '360x640 in dark and light', (tester) async {
    _setSurface(tester, const Size(360, 640));

    for (final themeMode in const <ThemeMode>[
      ThemeMode.dark,
      ThemeMode.light,
    ]) {
      for (final scale in const <double>[1.5, 2]) {
        final serversEngine = FakeVpnEngine();
        addTearDown(serversEngine.dispose);
        await pumpLocalizedApp(
          tester,
          _scaledApp(
            home: const ServersScreen(),
            themeMode: themeMode,
            textScale: scale,
          ),
          overrides: _serversOverrides(serversEngine, _seedHierarchy()),
        );
        _expectNoException(
          tester,
          'ServersScreen overflowed at ${scale}x in $themeMode',
        );

        await tester.pumpWidget(const SizedBox.shrink());

        await pumpLocalizedApp(
          tester,
          _scaledApp(
            home: const SettingsScreen(),
            themeMode: themeMode,
            textScale: scale,
          ),
          overrides: _preferenceOverrides(),
        );
        _expectNoException(
          tester,
          'SettingsScreen overflowed at ${scale}x in $themeMode',
        );

        await tester.pumpWidget(const SizedBox.shrink());

        final logsEngine = FakeVpnEngine();
        addTearDown(logsEngine.dispose);
        await pumpLocalizedApp(
          tester,
          _scaledApp(
            home: const LiveLogsScreen(),
            themeMode: themeMode,
            textScale: scale,
          ),
          overrides: <Object>[vpnEngineProvider.overrideWithValue(logsEngine)],
        );
        logsEngine
          ..emitLog('2026-11-22 10:00:00 INFO [tun] Tunnel started')
          ..emitLog('2026-11-22 10:00:01 WARN [dns] High latency detected')
          ..emitLog('2026-11-22 10:00:02 ERROR [router] Handshake failed')
          ..emitLog('2026-11-22 10:00:03 DEBUG [cache] Entry evicted');
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('log_entry_tile_3')),
          findsOneWidget,
          reason: 'Populated log rows must render for the audit',
        );
        _expectNoException(
          tester,
          'LiveLogsScreen overflowed at ${scale}x in $themeMode',
        );

        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets(
    'Test 4: TalkBack semantics audit covers the dock tabs, orb, server '
    'refresh, settings toggles, log actions and onboarding controls',
    (tester) async {
      // Disposed explicitly: the binding verifies active handles at the end
      // of the test body, before `addTearDown` callbacks run.
      final handle = tester.ensureSemantics();

      _setSurface(tester, const Size(360, 640));

      // --- AppShell dock tabs ---
      await pumpLocalizedApp(
        tester,
        const MyApp(),
        overrides: <Object>[...repositoryOverride(), ..._preferenceOverrides()],
      );

      void expectTab(
        ValueKey<String> key,
        String label, {
        required bool selected,
      }) {
        final node = tester.getSemantics(find.byKey(key));
        expect(
          node.label,
          contains(label),
          reason: 'Dock tab $key has no meaningful label',
        );
        expect(
          node,
          isSemantics(
            isButton: true,
            hasSelectedState: true,
            isSelected: selected,
            hasTapAction: true,
          ),
          reason: 'Dock tab $key must announce itself as a button',
        );
      }

      expectTab(_homeTabKey, 'Home', selected: true);
      expectTab(_serversTabKey, 'Servers', selected: false);
      expectTab(_settingsTabKey, 'Settings', selected: false);

      // --- /settings/logs renders under the floating dock --------------------
      await tester.tap(find.byKey(_settingsTabKey));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.widgetWithText(ListTile, 'Live Logs')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Live Logs'));
      await tester.pumpAndSettle();

      expect(find.byType(LiveLogsScreen), findsOneWidget);
      _expectNoException(
        tester,
        'LiveLogsScreen must render without overflow above the dock',
      );

      // Back to Home for the orb audit.
      await tester.tap(find.byKey(_homeTabKey));
      await tester.pumpAndSettle();

      // --- HomeScreen power orb ----------------------------------------------
      final orbNode = tester.getSemantics(
        find
            .descendant(
              of: find.byType(BrickPowerOrb),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(
        orbNode.label,
        contains('Browse Servers'),
        reason: 'Empty-state orb must speak its Browse Servers action',
      );
      expect(orbNode, isSemantics(isButton: true, hasTapAction: true));

      await tester.pumpWidget(const SizedBox.shrink());

      // --- ServersScreen refresh ---------------------------------------------
      final serversEngine = FakeVpnEngine();
      addTearDown(serversEngine.dispose);
      await pumpLocalizedApp(
        tester,
        _scaledApp(
          home: const ServersScreen(),
          themeMode: ThemeMode.dark,
          textScale: 1,
        ),
        overrides: _serversOverrides(serversEngine, _seedHierarchy()),
      );
      expect(
        find.bySemanticsLabel(RegExp('Update Servers')),
        findsWidgets,
        reason: 'The refresh control must expose its action name',
      );

      await tester.pumpWidget(const SizedBox.shrink());

      // --- SettingsScreen toggles --------------------------------------------
      await pumpLocalizedApp(
        tester,
        _scaledApp(
          home: const SettingsScreen(),
          themeMode: ThemeMode.dark,
          textScale: 1,
        ),
        overrides: _preferenceOverrides(),
      );
      expect(find.bySemanticsLabel(RegExp('Auto-Reconnect')), findsWidgets);
      final killSwitchNode = tester.getSemantics(
        find.byKey(const ValueKey<String>('settings_kill_switch_tile')),
      );
      expect(
        killSwitchNode,
        isSemantics(hasToggledState: true),
        reason: 'Kill Switch must announce its on/off state',
      );
      expect(find.bySemanticsLabel(RegExp('Live Logs')), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());

      // --- LiveLogsScreen AppBar actions -------------------------------------
      final logsEngine = FakeVpnEngine();
      addTearDown(logsEngine.dispose);
      await pumpLocalizedApp(
        tester,
        _scaledApp(
          home: const LiveLogsScreen(),
          themeMode: ThemeMode.dark,
          textScale: 1,
        ),
        overrides: <Object>[vpnEngineProvider.overrideWithValue(logsEngine)],
      );
      // A log entry enables the copy action (it is disabled while empty).
      logsEngine.emitLog('2026-11-22 10:00:00 INFO [tun] Tunnel started');
      await tester.pumpAndSettle();

      // `IconButton.tooltip` surfaces as a semantics tooltip, not a label.
      for (final entry in <String, String>{
        'logs_copy_button': 'Copy logs',
        'logs_clear_button': 'Clear logs',
      }.entries) {
        final iconButton = tester.widget<IconButton>(
          find.byKey(ValueKey<String>(entry.key)),
        );
        expect(
          iconButton.tooltip,
          entry.value,
          reason: '${entry.key} lost its tooltip',
        );
        expect(
          tester.getSemantics(find.byKey(ValueKey<String>(entry.key))),
          isSemantics(tooltip: entry.value, hasTapAction: true),
          reason: '${entry.key} does not announce its action',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());

      // --- OnboardingScreen controls -----------------------------------------
      await pumpLocalizedApp(
        tester,
        _scaledApp(
          home: const OnboardingScreen(),
          themeMode: ThemeMode.dark,
          textScale: 1,
        ),
        overrides: _preferenceOverrides(),
      );
      expect(find.bySemanticsLabel(RegExp('Skip')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Next')), findsWidgets);

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Back')), findsWidgets);

      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Get Started')), findsWidgets);

      expect(tester.takeException(), isNull);
      handle.dispose();
    },
  );

  testWidgets(
    'Test 5: every log level pill meets WCAG AA 4.5:1 in dark and light',
    (tester) async {
      _setSurface(tester, const Size(360, 640));

      for (final themeMode in const <ThemeMode>[
        ThemeMode.dark,
        ThemeMode.light,
      ]) {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpLocalizedApp(
          tester,
          _scaledApp(
            home: const LiveLogsScreen(),
            themeMode: themeMode,
            textScale: 1,
          ),
          overrides: <Object>[vpnEngineProvider.overrideWithValue(engine)],
        );

        engine
          ..emitLog('2026-11-22 10:00:00 INFO [tun] Tunnel started')
          ..emitLog('2026-11-22 10:00:01 WARN [dns] High latency detected')
          ..emitLog('2026-11-22 10:00:02 ERROR [router] Handshake failed')
          ..emitLog('2026-11-22 10:00:03 DEBUG [cache] Entry evicted');
        await tester.pumpAndSettle();

        final colors = themeMode == ThemeMode.dark
            ? BrickSemanticColors.dark
            : BrickSemanticColors.light;
        const levels = <String>['info', 'warning', 'error', 'debug'];

        for (var index = 0; index < levels.length; index++) {
          final badgeKey = ValueKey<String>(
            'log_level_badge_${levels[index]}_$index',
          );
          final badge = tester.widget<Container>(find.byKey(badgeKey));
          final decoration = badge.decoration! as BoxDecoration;
          final text = tester.widget<Text>(
            find.descendant(
              of: find.byKey(badgeKey),
              matching: find.byType(Text),
            ),
          );

          final pillColor = Color.alphaBlend(
            decoration.color!,
            colors.background,
          );
          final textColor = text.style!.color!;

          final ratio = _contrastRatio(textColor, pillColor);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'Level "${levels[index]}" is only '
                '${ratio.toStringAsFixed(2)}:1 in $themeMode',
          );
        }

        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'Test 6: Persian renders RTL without overflow at 360x640 in dark and '
    'light, while technical log rows stay LTR islands',
    (tester) async {
      final direct = File('assets/translations/fa.json');
      final fa = jsonDecode(
        (direct.existsSync()
                ? direct
                : File('apps/mobile/assets/translations/fa.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final faLoader = TestAssetLoader(
        translations: {'en': testEnglishTranslations(), 'fa': fa},
      );

      _setSurface(tester, const Size(360, 640));

      String? rawKeyLeak() {
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          final data = text.data;
          if (data == null) continue;
          if (data.startsWith('home.') ||
              data.startsWith('servers.') ||
              data.startsWith('settings.') ||
              data.startsWith('logs.') ||
              data.startsWith('onboarding.') ||
              data.startsWith('connection.')) {
            return data;
          }
        }
        return null;
      }

      for (final themeMode in const <ThemeMode>[
        ThemeMode.dark,
        ThemeMode.light,
      ]) {
        // --- OnboardingScreen ---------------------------------------------
        await pumpLocalizedApp(
          tester,
          _scaledApp(
            home: const OnboardingScreen(),
            themeMode: themeMode,
            textScale: 1.5,
          ),
          assetLoader: faLoader,
          overrides: _preferenceOverrides(),
          startLocale: const Locale('fa'),
        );
        expect(
          Directionality.of(tester.element(find.byType(OnboardingScreen))),
          TextDirection.rtl,
          reason: 'Persian onboarding must render right-to-left',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'OnboardingScreen overflowed in fa/$themeMode',
        );
        expect(rawKeyLeak(), isNull, reason: 'Raw key leaked in fa onboarding');
        await tester.pumpWidget(const SizedBox.shrink());

        // --- HomeScreen ----------------------------------------------------
        final homeEngine = FakeVpnEngine();
        addTearDown(homeEngine.dispose);
        await pumpLocalizedApp(
          tester,
          _scaledApp(
            home: const HomeScreen(),
            themeMode: themeMode,
            textScale: 1.5,
          ),
          assetLoader: faLoader,
          overrides: _serversOverrides(homeEngine, _seedHierarchy()),
          startLocale: const Locale('fa'),
        );
        expect(
          Directionality.of(tester.element(find.byType(HomeScreen))),
          TextDirection.rtl,
          reason: 'Persian home must render right-to-left',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'HomeScreen overflowed in fa/$themeMode',
        );
        expect(rawKeyLeak(), isNull, reason: 'Raw key leaked in fa home');
        await tester.pumpWidget(const SizedBox.shrink());

        // --- ServersScreen -------------------------------------------------
        final serversEngine = FakeVpnEngine();
        addTearDown(serversEngine.dispose);
        await pumpLocalizedApp(
          tester,
          _scaledApp(
            home: const ServersScreen(),
            themeMode: themeMode,
            textScale: 1.5,
          ),
          assetLoader: faLoader,
          overrides: _serversOverrides(serversEngine, _seedHierarchy()),
          startLocale: const Locale('fa'),
        );
        expect(
          Directionality.of(tester.element(find.byType(ServersScreen))),
          TextDirection.rtl,
          reason: 'Persian server list must render right-to-left',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'ServersScreen overflowed in fa/$themeMode',
        );
        expect(rawKeyLeak(), isNull, reason: 'Raw key leaked in fa servers');
        await tester.pumpWidget(const SizedBox.shrink());

        // --- SettingsScreen ------------------------------------------------
        await pumpLocalizedApp(
          tester,
          _scaledApp(
            home: const SettingsScreen(),
            themeMode: themeMode,
            textScale: 1.5,
          ),
          assetLoader: faLoader,
          overrides: _preferenceOverrides(),
          startLocale: const Locale('fa'),
        );
        expect(
          Directionality.of(tester.element(find.byType(SettingsScreen))),
          TextDirection.rtl,
          reason: 'Persian settings must render right-to-left',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'SettingsScreen overflowed in fa/$themeMode',
        );
        expect(rawKeyLeak(), isNull, reason: 'Raw key leaked in fa settings');
        await tester.pumpWidget(const SizedBox.shrink());

        // --- LiveLogsScreen + LTR log islands ------------------------------
        final logsEngine = FakeVpnEngine();
        addTearDown(logsEngine.dispose);
        await pumpLocalizedApp(
          tester,
          _scaledApp(
            home: const LiveLogsScreen(),
            themeMode: themeMode,
            textScale: 1.5,
          ),
          assetLoader: faLoader,
          overrides: <Object>[vpnEngineProvider.overrideWithValue(logsEngine)],
          startLocale: const Locale('fa'),
        );
        logsEngine.emitLog('2026-11-22 10:00:00 INFO [tun] Tunnel started');
        await tester.pumpAndSettle();

        expect(
          Directionality.of(tester.element(find.byType(LiveLogsScreen))),
          TextDirection.rtl,
          reason: 'Persian log screen chrome must render right-to-left',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'LiveLogsScreen overflowed in fa/$themeMode',
        );
        expect(rawKeyLeak(), isNull, reason: 'Raw key leaked in fa logs');

        // A log row (timestamp + level pill + redacted endpoint) is technical
        // data and must be pinned to LTR inside the RTL page.
        final entryTile = find.byKey(
          const ValueKey<String>('log_entry_tile_0'),
        );
        expect(entryTile, findsOneWidget);
        expect(
          Directionality.of(tester.element(entryTile)),
          TextDirection.ltr,
          reason: 'Log entry rows must be LTR islands under Persian RTL',
        );

        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
