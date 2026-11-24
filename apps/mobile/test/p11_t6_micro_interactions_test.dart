// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:core_domain/core_domain.dart'
    show Connected, Connecting, TrafficStats;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/repositories/server_profile_repository.dart';
import 'package:mobile/features/connection/presentation/providers/camera_permission_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:mobile/main.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

const String _uuid = '11111111-2222-3333-4444-555555555555';

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

/// Four countries, which is one more than the automatic "expand everything"
/// threshold, so every accordion starts collapsed and a tap is meaningful.
FakeServerProfileDataSource _seedFourCountries() {
  final dataSource = FakeServerProfileDataSource();
  _seedServer(
    dataSource,
    id: 'de-frankfurt',
    remark: '🇩🇪 Germany · Frankfurt',
  );
  _seedServer(dataSource, id: 'fr-paris', remark: '🇫🇷 France · Paris');
  _seedServer(
    dataSource,
    id: 'nl-amsterdam',
    remark: '🇳🇱 Netherlands · Amsterdam',
  );
  _seedServer(
    dataSource,
    id: 'us-nyc',
    remark: '🇺🇸 United States · New York',
  );
  return dataSource;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required FakeVpnEngine engine,
  required FakeServerProfileDataSource dataSource,
  ThemeMode themeMode = ThemeMode.dark,
}) async {
  final connectivity = FakeConnectivitySource();
  addTearDown(connectivity.dispose);

  await pumpLocalizedApp(
    tester,
    Builder(
      builder: (context) => MaterialApp(
        theme: BrickTheme.light(),
        darkTheme: BrickTheme.dark(),
        themeMode: themeMode,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        home: screen,
      ),
    ),
    overrides: <Object>[
      vpnEngineProvider.overrideWithValue(engine),
      ...repositoryOverride(dataSource),
      appPreferencesRepositoryProvider.overrideWithValue(
        FakeAppPreferencesRepository(),
      ),
    ],
  );
}

/// Pumps [screen] on an unresolved repository without `pumpAndSettle`, so a
/// live skeleton shimmer is allowed to keep ticking.
Future<void> _pumpLoadingScreen(
  WidgetTester tester,
  Widget screen, {
  required FakeVpnEngine engine,
  required Future<ServerProfileRepository> Function(Ref ref) repository,
  ThemeMode themeMode = ThemeMode.dark,
}) async {
  final connectivity = FakeConnectivitySource();
  addTearDown(connectivity.dispose);

  // Start from an empty tree so every pump gets a fresh ProviderScope: the
  // `keepAlive` saved-server provider cannot be driven back into a loading
  // state inside a scope that already resolved it.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    localizedApp(
      child: Builder(
        builder: (context) => MaterialApp(
          theme: BrickTheme.light(),
          darkTheme: BrickTheme.dark(),
          themeMode: themeMode,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          home: screen,
        ),
      ),
      overrides: <Object>[
        vpnEngineProvider.overrideWithValue(engine),
        serverProfileRepositoryProvider.overrideWith(repository),
        cameraPermissionServiceProvider.overrideWithValue(
          const FakeCameraPermissionService(),
        ),
        connectivitySourceProvider.overrideWithValue(connectivity),
        appPreferencesRepositoryProvider.overrideWithValue(
          FakeAppPreferencesRepository(),
        ),
      ],
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  // Bounded pump only: the shimmer repeats forever, so settling here would
  // hang by design.
  await tester.pump(const Duration(milliseconds: 300));
  // A second real event-loop turn lets a *resolved* repository future land
  // without any unbounded settling.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(initTestLocalization);

  late Directory testTempDir;

  setUp(() async {
    testTempDir = await Directory.systemTemp.createTemp('p11_t6_');
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

  /// Captures every `HapticFeedback.vibrate` dispatched while installed.
  List<String> recordHaptics(WidgetTester tester) {
    final haptics = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments as String? ?? '');
            }
            return null;
          });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return haptics;
  }

  group('P11-T6 micro-interactions', () {
    testWidgets(
      'Test 1: loading skeletons shimmer while animated and settle under '
      'reduced motion',
      (tester) async {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);
        final pending = Completer<ServerProfileRepository>();

        Future<void> pumpLoading(Widget screen) => _pumpLoadingScreen(
          tester,
          screen,
          engine: engine,
          repository: (ref) => pending.future,
        );

        // --- Animated shimmer (system animations left enabled) ---
        await pumpLoading(const HomeScreen());

        final homeSkeleton = find.byKey(
          const ValueKey<String>('home_server_loading_skeleton'),
        );
        expect(homeSkeleton, findsOneWidget);
        expect(
          find.descendant(
            of: homeSkeleton,
            matching: find.byType(BrickSkeletonBox),
          ),
          findsNWidgets(3),
        );
        // The raw spinner placeholder it replaced is gone.
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // Bounded frames prove the live shimmer renders without exceptions.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester.binding.transientCallbackCount,
          greaterThan(0),
          reason: 'The shimmer ticker must actually be running',
        );
        expect(tester.takeException(), isNull);

        await pumpLoading(const ServersScreen());

        final serversSkeleton = find.byKey(
          const ValueKey<String>('servers_loading_skeleton'),
        );
        expect(serversSkeleton, findsOneWidget);
        // One search bar placeholder plus a flag tile and two text bars per
        // country card.
        expect(
          find.descendant(
            of: serversSkeleton,
            matching: find.byType(BrickSkeletonBox),
          ),
          findsNWidgets(10),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);

        // --- Reduced motion (system animations disabled) ---
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        await pumpLoading(const ServersScreen());
        expect(
          find.byKey(const ValueKey<String>('servers_loading_skeleton')),
          findsOneWidget,
        );

        // No shimmer ticker may keep the tree spinning: it must settle.
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Test 2: atmosphere stays gradient-only, a tap never fakes Connected, '
      'and 1 Hz traffic ticks do not rebuild the orb',
      (tester) async {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);
        final dataSource = FakeServerProfileDataSource();
        _seedServer(
          dataSource,
          id: 'de-frankfurt',
          remark: '🇩🇪 Germany · Frankfurt',
        );

        await _pumpScreen(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        const glowKey = ValueKey<String>('home_atmosphere_glow');
        DecoratedBox glow() => tester.widget<DecoratedBox>(find.byKey(glowKey));

        final initialGlow = glow().decoration as BoxDecoration;
        expect(initialGlow.gradient, isNotNull);
        expect(initialGlow.color, isNull);

        const orbKey = ValueKey<String>('home_connect_toggle_button');
        BrickPowerOrb orb() => tester.widget<BrickPowerOrb>(find.byKey(orbKey));

        expect(orb().state, BrickOrbState.disconnected);

        // VpnEngine Invariant 1: a tap is a request, never a state claim.
        await tester.tap(find.byKey(orbKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(engine.startCalls, hasLength(1));
        expect(orb().state, BrickOrbState.disconnected);
        expect(find.text('Connected'), findsNothing);

        final glowBeforeTransition = glow().decoration as BoxDecoration;
        expect(glowBeforeTransition.color, isNull);
        expect(glowBeforeTransition.gradient, isNotNull);

        // Connecting: the authoritative stream — never the tap — drives this.
        engine.emit(const Connecting());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(orb().state, BrickOrbState.connecting);
        expect((glow().decoration as BoxDecoration).color, isNull);

        engine.emit(const Connected());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(orb().state, BrickOrbState.connected);
        expect((glow().decoration as BoxDecoration).color, isNull);

        // 1 Hz rebuild isolation, measured while actually Connected: the
        // telemetry leaves must render the live bytes, while the orb widget
        // instance stays identical (never rebuilt by traffic ticks).
        final orbBeforeTicks = orb();
        for (var i = 1; i <= 5; i++) {
          engine.emitStats(
            TrafficStats(
              txBytes: i * 1024,
              rxBytes: i * 2048,
              timestamp: DateTime.utc(2026, 11, 22, 0, 0, i),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
        }

        expect(
          find.textContaining('5.0 KiB'),
          findsOneWidget,
          reason: 'ThroughputReadout must render the live cumulative bytes',
        );
        expect(
          find.textContaining('10.0 KiB'),
          findsOneWidget,
          reason: 'ThroughputReadout must render the live cumulative bytes',
        );
        expect(identical(orbBeforeTicks, orb()), isTrue);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Test 3: accordion, dock and settings dispatch the right haptics',
      (tester) async {
        final haptics = recordHaptics(tester);

        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);
        final dataSource = _seedFourCountries();

        await _pumpScreen(
          tester,
          const ServersScreen(),
          engine: engine,
          dataSource: dataSource,
          themeMode: ThemeMode.light,
        );

        // Collapsed by default (4 countries > auto-expand threshold), and
        // every country card animates its body size instead of snapping.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('country_group_DE')),
            matching: find.byType(AnimatedSize),
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('country_header_DE')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(haptics, contains('HapticFeedbackType.selectionClick'));
        expect(tester.takeException(), isNull);

        // Unmount first: a new screen with a different override set needs a
        // fresh ProviderScope rather than an updated one.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        // The dock ticks on a real branch change, and stays silent when the
        // already-active tab is re-tapped.
        haptics.clear();
        await pumpLocalizedApp(
          tester,
          const MyApp(),
          overrides: repositoryOverride(dataSource),
        );

        await tester.tap(find.byKey(const ValueKey('nav_tab_servers')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(haptics, contains('HapticFeedbackType.selectionClick'));

        haptics.clear();
        await tester.tap(find.byKey(const ValueKey('nav_tab_servers')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(haptics, isEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        // A settings toggle ticks once and still persists the preference.
        haptics.clear();
        await _pumpScreen(
          tester,
          const SettingsScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        const killSwitchKey = ValueKey<String>('settings_kill_switch_tile');
        SwitchListTile killSwitch() =>
            tester.widget<SwitchListTile>(find.byKey(killSwitchKey));

        expect(killSwitch().value, isFalse);
        await tester.tap(find.byKey(killSwitchKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(haptics, contains('HapticFeedbackType.selectionClick'));
        expect(killSwitch().value, isTrue);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Test 4: skeletons and accordions survive 360x640 and 412x915 in both '
      'themes with zero overflow',
      (tester) async {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);
        final dataSource = _seedFourCountries();
        final pending = Completer<ServerProfileRepository>();

        for (final size in <Size>[const Size(360, 640), const Size(412, 915)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          // Registered per size so a failure can never leak viewport state.
          addTearDown(tester.view.reset);

          for (final mode in <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
            final reason = '$size / $mode';

            // Loading Home skeleton.
            await _pumpLoadingScreen(
              tester,
              const HomeScreen(),
              engine: engine,
              repository: (ref) => pending.future,
              themeMode: mode,
            );
            expect(
              find.byKey(
                const ValueKey<String>('home_server_loading_skeleton'),
              ),
              findsOneWidget,
              reason: reason,
            );
            expect(tester.takeException(), isNull, reason: reason);

            // Loading Servers skeleton.
            await _pumpLoadingScreen(
              tester,
              const ServersScreen(),
              engine: engine,
              repository: (ref) => pending.future,
              themeMode: mode,
            );
            expect(
              find.byKey(const ValueKey<String>('servers_loading_skeleton')),
              findsOneWidget,
              reason: reason,
            );
            expect(tester.takeException(), isNull, reason: reason);

            // Unmount before switching the repository from unresolved to
            // resolved, so the fresh scope cannot inherit loading state.
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();

            // Populated Servers with an expanded accordion.
            await _pumpLoadingScreen(
              tester,
              const ServersScreen(),
              engine: engine,
              repository: (ref) async =>
                  FakeServerProfileRepository(dataSource),
              themeMode: mode,
            );
            await tester.tap(
              find.byKey(const ValueKey<String>('country_header_DE')),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull, reason: reason);

            // Populated Home with the active-server card.
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await _pumpLoadingScreen(
              tester,
              const HomeScreen(),
              engine: engine,
              repository: (ref) async =>
                  FakeServerProfileRepository(dataSource),
              themeMode: mode,
            );
            expect(
              find.byKey(const ValueKey<String>('home_active_server_card')),
              findsOneWidget,
              reason: reason,
            );
            expect(tester.takeException(), isNull, reason: reason);
          }
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}
