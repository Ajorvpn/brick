// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:core_domain/core_domain.dart'
    as core_domain
    show Connected, Connecting, Disconnected, Error, Unknown;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/presentation/widgets/app_shell.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/router/app_router.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:mobile/features/settings/presentation/screens/live_logs_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

class _TestKillSwitchNotifier extends KillSwitchNotifier {
  _TestKillSwitchNotifier(this._state);

  final KillSwitchState _state;

  @override
  KillSwitchState build() => _state;
}

/// Helper that mounts the app and pumps bounded frames without calling
/// `pumpAndSettle()`. Used for tests mounting repeating animations.
Future<void> _pumpAppWithoutSettle(
  WidgetTester tester,
  Widget app, {
  List<Object>? overrides,
}) async {
  await tester.pumpWidget(localizedApp(child: app, overrides: overrides));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(initTestLocalization);

  late Directory testTempDir;

  setUp(() async {
    testTempDir = await Directory.systemTemp.createTemp('app_shell_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getTemporaryDirectory') {
              return testTempDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (testTempDir.existsSync()) {
      await testTempDir.delete(recursive: true);
    }
  });

  group('AppShell 3-tab Obsidian Glass Dock layout (Chunk 2B)', () {
    testWidgets(
      'renders dock with 3 tabs and does not render legacy logs tab',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: repositoryOverride(),
        );

        // Dock container exists with expected key
        expect(find.byKey(const ValueKey('brick_bottom_dock')), findsOneWidget);

        // 3 tabs exist
        expect(find.byKey(const ValueKey('nav_tab_home')), findsOneWidget);
        expect(find.byKey(const ValueKey('nav_tab_servers')), findsOneWidget);
        expect(find.byKey(const ValueKey('nav_tab_settings')), findsOneWidget);

        // Legacy tab & old icon do not exist in dock
        expect(find.byKey(const ValueKey('nav_tab_logs')), findsNothing);
        expect(find.byIcon(Icons.article_outlined), findsNothing);
      },
    );

    testWidgets(
      'splits surface color and specular sheen into distinct layers (D1 fix)',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: repositoryOverride(),
        );

        final surfaceFinder = find.byKey(
          const ValueKey<String>('brick_dock_surface_layer'),
        );
        final sheenFinder = find.byKey(
          const ValueKey<String>('brick_dock_sheen_layer'),
        );

        expect(surfaceFinder, findsOneWidget);
        expect(sheenFinder, findsOneWidget);

        final surfaceBox = tester.widget<DecoratedBox>(surfaceFinder);
        final surfaceDeco = surfaceBox.decoration as BoxDecoration;
        expect(surfaceDeco.color, isNotNull);
        expect(surfaceDeco.gradient, isNull);

        final sheenBox = tester.widget<DecoratedBox>(sheenFinder);
        final sheenDeco = sheenBox.decoration as BoxDecoration;
        expect(sheenDeco.gradient, isNotNull);
        expect(sheenDeco.color, isNull);
      },
    );

    testWidgets(
      'enforces zero ghost opacity widgets and internal Material for InkWell (D2/D3)',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: repositoryOverride(),
        );

        // Zero Opacity ghost widgets inside AppShell
        expect(
          find.descendant(
            of: find.byType(AppShell),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );

        // Verify InkWell inside nav_tab_home has a Material ancestor inside
        // brick_bottom_dock.
        final homeTabFinder = find.byKey(const ValueKey('nav_tab_home'));
        final inkWellFinder = find.descendant(
          of: homeTabFinder,
          matching: find.byType(InkWell),
        );
        expect(inkWellFinder, findsOneWidget);

        final dockFinder = find.byKey(const ValueKey('brick_bottom_dock'));
        final materialFinder = find.descendant(
          of: dockFinder,
          matching: find.byType(Material),
        );
        expect(materialFinder, findsWidgets);

        final inkWellElement = tester.element(inkWellFinder);
        final materialAncestor = inkWellElement
            .findAncestorWidgetOfExactType<Material>();
        expect(materialAncestor, isNotNull);
        expect(materialAncestor!.type, equals(MaterialType.transparency));
      },
    );
  });

  group('AppShell 3-tab switching and nested navigation', () {
    testWidgets(
      'switches between Home, Servers, Settings and preserves state',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: repositoryOverride(),
        );

        // 1. Initial location renders AppShell and HomeScreen.
        expect(find.byType(AppShell), findsOneWidget);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(ServersScreen), findsNothing);
        expect(find.byType(SettingsScreen), findsNothing);

        // 2. Switch to Servers tab.
        await tester.tap(find.byKey(const ValueKey('nav_tab_servers')));
        await tester.pumpAndSettle();

        expect(find.byType(ServersScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Servers'), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);

        // 3. Switch to Settings tab.
        await tester.tap(find.byKey(const ValueKey('nav_tab_settings')));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.byType(ServersScreen), findsNothing);

        // 4. Navigate into nested Live Logs screen under Settings.
        await tester.tap(find.widgetWithText(ListTile, 'Live Logs'));
        await tester.pumpAndSettle();

        expect(find.byType(LiveLogsScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Live Logs'), findsOneWidget);
        expect(find.byType(SettingsScreen), findsNothing);

        // 5. Switch to Servers tab.
        await tester.tap(find.byKey(const ValueKey('nav_tab_servers')));
        await tester.pumpAndSettle();

        expect(find.byType(ServersScreen), findsOneWidget);
        expect(find.byType(LiveLogsScreen), findsNothing);

        // 6. Switch back to Settings tab - nested state preserved.
        await tester.tap(find.byKey(const ValueKey('nav_tab_settings')));
        await tester.pumpAndSettle();

        expect(find.byType(LiveLogsScreen), findsOneWidget);

        // 7. Re-tapping active Settings tab resets branch to root
        // (SettingsScreen).
        await tester.tap(find.byKey(const ValueKey('nav_tab_settings')));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.byType(LiveLogsScreen), findsNothing);
      },
    );

    testWidgets(
      'tapping currently active Home tab does not crash or change branch',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: repositoryOverride(),
        );

        expect(find.byType(HomeScreen), findsOneWidget);

        // Tapping Home while already on Home does not crash or navigate away.
        await tester.tap(find.byKey(const ValueKey('nav_tab_home')));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  });

  GoRouter buildBeaconTestRouter() => GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) =>
                    const Scaffold(body: SizedBox.expand()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/servers',
                builder: (context, state) =>
                    const Scaffold(body: SizedBox.expand()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
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

  group('AppShell peripheral tunnel status beacon', () {
    testWidgets('renders emerald solid beacon when tunnel is Connected', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        const MyApp(),
        overrides: [
          ...repositoryOverride(),
          appRouterProvider.overrideWithValue(buildBeaconTestRouter()),
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(const core_domain.Connected()),
          ),
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('nav_home_beacon_connected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('nav_home_beacon_connecting')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('nav_home_beacon_killswitch')),
        findsNothing,
      );
    });

    testWidgets('renders amber pulsing beacon when tunnel is Connecting', (
      tester,
    ) async {
      await _pumpAppWithoutSettle(
        tester,
        const MyApp(),
        overrides: [
          ...repositoryOverride(),
          appRouterProvider.overrideWithValue(buildBeaconTestRouter()),
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(const core_domain.Connecting()),
          ),
        ],
      );

      // Note: Connecting beacon pulses indefinitely; use bounded pump,
      // NEVER pumpAndSettle!
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const ValueKey('nav_home_beacon_connecting')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('nav_home_beacon_connected')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('nav_home_beacon_killswitch')),
        findsNothing,
      );

      // Clean unmount to tear down repeating ticker
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets(
      'renders crimson pulsing beacon when KillSwitch is KillSwitchBlocking',
      (tester) async {
        await _pumpAppWithoutSettle(
          tester,
          const MyApp(),
          overrides: [
            ...repositoryOverride(),
            appRouterProvider.overrideWithValue(buildBeaconTestRouter()),
            killSwitchProvider.overrideWith(
              () => _TestKillSwitchNotifier(
                const KillSwitchBlocking(reason: 'test_blocking'),
              ),
            ),
          ],
        );

        // Note: Kill switch beacon pulses indefinitely; use bounded pump,
        // NEVER pumpAndSettle!
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.byKey(const ValueKey('nav_home_beacon_killswitch')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('nav_home_beacon_connected')),
          findsNothing,
        );

        // Clean unmount to tear down repeating ticker
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 50));
      },
    );

    testWidgets('renders no beacon dot when Disconnected', (tester) async {
      await pumpLocalizedApp(
        tester,
        const MyApp(),
        overrides: [
          ...repositoryOverride(),
          appRouterProvider.overrideWithValue(buildBeaconTestRouter()),
          connectionStateProvider.overrideWith(
            (ref) => Stream.value(const core_domain.Disconnected()),
          ),
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('nav_home_beacon_connected')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('nav_home_beacon_connecting')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('nav_home_beacon_killswitch')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('nav_home_beacon_error')), findsNothing);
    });

    testWidgets('renders crimson solid beacon when tunnel is in Error state', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        const MyApp(),
        overrides: [
          ...repositoryOverride(),
          appRouterProvider.overrideWithValue(buildBeaconTestRouter()),
          connectionStateProvider.overrideWith(
            (ref) =>
                Stream.value(const core_domain.Error(core_domain.Unknown())),
          ),
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('nav_home_beacon_error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('nav_home_beacon_connected')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('nav_home_beacon_connecting')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('nav_home_beacon_killswitch')),
        findsNothing,
      );
    });
  });

  group('AppShell responsive dock layout & touch target verification', () {
    for (final themeMode in [ThemeMode.dark, ThemeMode.light]) {
      for (final size in const [Size(360, 640), Size(412, 915)]) {
        testWidgets('dock tabs maintain >= 48.0dp touch targets at '
            '${size.width.toInt()}x${size.height.toInt()} in $themeMode', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          final testRouter = GoRouter(
            initialLocation: '/',
            routes: [
              StatefulShellRoute.indexedStack(
                builder: (context, state, navigationShell) =>
                    AppShell(navigationShell: navigationShell),
                branches: [
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: '/',
                        builder: (context, state) =>
                            const Scaffold(body: SizedBox.expand()),
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: '/servers',
                        builder: (context, state) =>
                            const Scaffold(body: SizedBox.expand()),
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    routes: [
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

          await pumpLocalizedApp(
            tester,
            const MyApp(),
            overrides: [
              ...repositoryOverride(),
              appRouterProvider.overrideWithValue(testRouter),
              appPreferencesRepositoryProvider.overrideWithValue(
                FakeAppPreferencesRepository(initialThemeMode: themeMode),
              ),
            ],
          );
          await tester.pumpAndSettle();

          final homeSize = tester.getSize(
            find.byKey(const ValueKey('nav_tab_home')),
          );
          final serversSize = tester.getSize(
            find.byKey(const ValueKey('nav_tab_servers')),
          );
          final settingsSize = tester.getSize(
            find.byKey(const ValueKey('nav_tab_settings')),
          );

          expect(homeSize.height, greaterThanOrEqualTo(48.0));
          expect(serversSize.height, greaterThanOrEqualTo(48.0));
          expect(settingsSize.height, greaterThanOrEqualTo(48.0));
        });
      }
    }
  });
}
