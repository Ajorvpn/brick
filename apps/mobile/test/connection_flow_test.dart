// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        Disconnected,
        Disconnecting,
        ServerProfile,
        TrafficStats;
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';
import 'package:ui_theme/ui_theme.dart' show BrickPowerOrb;

import 'localization_test_harness.dart';

/// Flushes pending frames without waiting for the [BrickPowerOrb]'s repeating
/// state animations to settle — connecting, connected, reconnecting,
/// disconnecting and kill-switch states never stop scheduling frames, so a
/// `pumpAndSettle()` there would time out.
Future<void> pumpBounded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The label currently shown in the connection state badge.
///
/// Reads the descendant [Text]'s `data` rather than casting `Chip.label`,
/// because `Chip.label` is a `Widget`, not a `String`.
String badgeText(WidgetTester tester) {
  final label = tester.widget<Chip>(find.byKey(badgeKey)).label;
  return (label as Text).data!;
}

/// The key on the connection state badge's [Chip].
const Key badgeKey = ValueKey<String>('connection_state_badge');

/// A [VpnEngine] fake whose [prepare] is rejected (permission denied),
/// used to verify [ConnectionController.connect] aborts without starting.
class _PermissionDeniedVpnEngine extends FakeVpnEngine {
  @override
  Future<VpnCommandResult> prepare() async {
    prepareCalls++;
    return const VpnCommandRejectedPermissionDenied();
  }
}

/// A [VpnEngine] fake whose [start] is rejected with invalid config.
class _InvalidConfigVpnEngine extends FakeVpnEngine {
  @override
  Future<VpnCommandResult> start(ServerProfile profile) async {
    return const VpnCommandRejectedInvalidConfig();
  }
}

void main() {
  setUpAll(initTestLocalization);

  group('Add Server — direct save flow', () {
    testWidgets(
      'entering valid VLESS URI and saving persists and pops to Home',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        // Pumped through the REAL app shell (`MyApp` + the production
        // `GoRouter`), not a bare `MaterialApp`. Saving ends in
        // `context.pop()`, which needs a genuine navigation stack.
        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );

        // Nothing is persisted before Save.
        expect(dataSource.records, isEmpty);

        unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
        await tester.pumpAndSettle();
        expect(find.byType(AddServerScreen), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          validVlessUri,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        expect(dataSource.records, hasLength(1));
        expect(dataSource.records.single.sourceUri, validVlessUri);
        // `context.pop()` unwound the real stack back to Home.
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(AddServerScreen), findsNothing);
      },
    );

    testWidgets('entering valid Shadowsocks URI directly saves and persists', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );

      unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('add_server_uri_field')),
        validShadowsocksUri,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_save_button')),
      );
      await tester.pumpAndSettle();

      expect(dataSource.records, hasLength(1));
      expect(dataSource.records.single.sourceUri, validShadowsocksUri);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('an empty field shows error snackbar and stays on screen', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);

      await pumpConnectionMaterialApp(
        tester,
        const AddServerScreen(),
        engine: engine,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_save_button')),
      );
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.widgetWithText(SnackBar, 'Enter a server URI first'),
        findsOneWidget,
      );
    });

    testWidgets(
      'an invalid URI shows error snackbar and never echoes credentials',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        // Contains a plausible credential; it must not reach the error text.
        const secret = 'sup3rs3cr3t-p4ssw0rd';
        const badUri = 'not-a-uri://sup3rs3cr3t-p4ssw0rd';

        await pumpConnectionMaterialApp(
          tester,
          const AddServerScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          badUri,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pump();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(dataSource.records, isEmpty);

        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(text.data ?? '', isNot(contains(secret)));
        }
      },
    );

    testWidgets('an unsupported scheme shows error snackbar', (tester) async {
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);

      await pumpConnectionMaterialApp(
        tester,
        const AddServerScreen(),
        engine: engine,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('add_server_uri_field')),
        'gopher://example.com:70',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_save_button')),
      );
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(AddServerScreen), findsOneWidget);
    });
  });

  group('Home — renders saved servers', () {
    testWidgets('lists a saved server with its name, protocol and endpoint', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      // Simulates an app restart: this entry was written by a previous run.
      dataSource.records.add(
        SavedServerRecord(
          id: 'seed-1',
          sourceUri: validVlessUri,
          addedAt: DateTime.utc(2026),
        ),
      );

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      // The redesigned dashboard shows the saved server in its active-server
      // selector card; the duplicate ServerTile list was removed.
      expect(
        find.byKey(const ValueKey<String>('home_active_server_card')),
        findsOneWidget,
      );
      expect(find.text('Active: My Server'), findsOneWidget);
      final activeName = tester.widget<Text>(
        find.byKey(const ValueKey<String>('home_active_server_name')),
      );
      expect(activeName.data, 'Active: My Server');
      // Protocol and endpoint stay visible, addressed by their own keys.
      final activeEndpoint = tester.widget<Text>(
        find.byKey(const ValueKey<String>('home_active_server_endpoint')),
      );
      expect(activeEndpoint.data, contains('vless'));
      expect(activeEndpoint.data, contains('example.com:443'));
      expect(find.text('VLESS'), findsWidgets);
      // And it is connectable from the dashboard orb.
      expect(
        find.byKey(const ValueKey<String>('home_connect_toggle_button')),
        findsOneWidget,
      );
    });

    testWidgets('shows an empty message when nothing is saved', (tester) async {
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
      );

      expect(find.text('No saved servers yet'), findsOneWidget);
    });

    testWidgets('a stored URI that no longer parses renders as broken, is '
        'removable, and is not silently dropped', (tester) async {
      final engine = FakeVpnEngine();
      // A stored entry whose URI no longer parses — e.g. the parser rules
      // changed between app versions, or the blob was damaged.
      final dataSource = FakeServerProfileDataSource([
        SavedServerRecord(
          id: 'broken-1',
          sourceUri: 'totally-not-a-uri',
          addedAt: DateTime.utc(2026),
        ),
      ]);
      addTearDown(engine.dispose);

      // Broken records surface on the Servers tab, which owns the full list.
      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );
      await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
      await tester.pumpAndSettle();

      // A recognizable broken entry...
      expect(find.text('Unreadable server'), findsOneWidget);
      // ...with no connect affordance, so it can never reach the engine...
      expect(find.text('Connect'), findsNothing);
      // ...still stored rather than silently dropped...
      expect(dataSource.records, hasLength(1));
      // ...and removable.
      await tester.tap(
        find.byKey(const ValueKey<String>('server_delete_broken-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm_delete_confirm')),
      );
      await tester.pumpAndSettle();
      expect(dataSource.records, isEmpty);
      expect(find.text('Unreadable server'), findsNothing);
    });

    testWidgets('a broken entry never displays the stored URI', (tester) async {
      final engine = FakeVpnEngine();
      const secretUri = 'leaked://hunter2-secret@example.com';
      final dataSource = FakeServerProfileDataSource([
        SavedServerRecord(
          id: 'broken-2',
          sourceUri: secretUri,
          addedAt: DateTime.utc(2026),
        ),
      ]);
      addTearDown(engine.dispose);

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );
      await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
      await tester.pumpAndSettle();

      expect(find.text('Unreadable server'), findsOneWidget);
      expect(find.textContaining('hunter2-secret'), findsNothing);
      // No text inside the broken tile may carry the stored URI either.
      final brokenTexts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('server_broken_tile_broken-2')),
          matching: find.byType(Text),
        ),
      );
      for (final text in brokenTexts) {
        expect(text.data ?? '', isNot(contains('hunter2-secret')));
      }
    });
  });

  group('Home — connect dispatches exactly one command per tap', () {
    testWidgets('tapping Connect calls engine.start once, not per rebuild', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);
      await buildRepository(dataSource).addServer(validVlessUri);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      expect(engine.startCalls, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey<String>('home_connect_toggle_button')),
      );
      await pumpBounded(tester);

      expect(engine.startCalls, hasLength(1));
      expect(engine.startCalls.single.config.protocol.scheme, 'vless');

      // Rebuilds driven by stream events must NOT re-dispatch the command.
      engine.emit(const Connecting());
      await pumpBounded(tester);
      engine.emit(const Connected());
      await pumpBounded(tester);
      expect(badgeText(tester), 'Connected');

      expect(engine.startCalls, hasLength(1));
    });

    testWidgets('connect aborts when prepare() is rejected', (tester) async {
      final engine = _PermissionDeniedVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);
      await buildRepository(dataSource).addServer(validVlessUri);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      expect(engine.startCalls, isEmpty);
      expect(engine.prepareCalls, 0);

      await tester.tap(
        find.byKey(const ValueKey<String>('home_connect_toggle_button')),
      );
      await pumpBounded(tester);

      expect(engine.prepareCalls, 1);
      expect(engine.startCalls, isEmpty);
    });

    testWidgets('tapping Disconnect calls engine.stop once', (tester) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);
      await buildRepository(dataSource).addServer(validVlessUri);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      expect(engine.stopCalls, 0);

      // Disconnect is only offered while the tunnel is up.
      engine.emit(const Connected());
      await pumpBounded(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('home_connect_toggle_button')),
      );
      await pumpBounded(tester);

      expect(engine.stopCalls, 1);

      engine.emit(const Disconnecting());
      await pumpBounded(tester);
      expect(engine.stopCalls, 1);
    });
  });

  group('Home — state renders only from the stream', () {
    testWidgets('badge is Disconnected before the engine emits anything', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
      );

      expect(badgeText(tester), 'Disconnected');
    });

    testWidgets('badge follows Connecting -> Connected -> Disconnecting -> '
        'Disconnected from stream events alone', (tester) async {
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
      );

      engine.emit(const Connecting());
      await pumpBounded(tester);
      expect(badgeText(tester), 'Connecting');

      engine.emit(const Connected());
      await pumpBounded(tester);
      expect(badgeText(tester), 'Connected');

      engine.emit(const Disconnecting());
      await pumpBounded(tester);
      expect(badgeText(tester), 'Disconnecting');

      engine.emit(const Disconnected());
      await pumpBounded(tester);
      expect(badgeText(tester), 'Disconnected');
    });

    testWidgets('an accepted start() alone does NOT show Connected', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);
      await buildRepository(dataSource).addServer(validVlessUri);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('home_connect_toggle_button')),
      );
      await pumpBounded(tester);

      // The engine accepted the command but has emitted NO transition. This
      // is the regression guard for the legacy "Connected over a dead
      // tunnel" bug: the UI must still read Disconnected.
      expect(engine.startCalls, hasLength(1));
      expect(badgeText(tester), 'Disconnected');
      expect(find.text('Connected'), findsNothing);
    });

    testWidgets(
      'the controller holds no connection state a widget could read',
      (tester) async {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );

        // Emitting from the engine moves the streamed state...
        engine.emit(const Connecting());
        await pumpBounded(tester);
        expect(badgeText(tester), 'Connecting');

        // ...while the controller's own value stays a void placeholder, so no
        // widget can source connection status from it.
        expect(
          container.read(connectionControllerProvider),
          isA<AsyncValue<void>>(),
        );
        expect(
          await container.read(connectionStateProvider.future),
          isA<Connecting>(),
        );
      },
    );
  });

  group('Home — traffic stats', () {
    testWidgets('throughput readout renders bytes from the stats stream', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
      );

      engine.emitStats(
        TrafficStats(
          txBytes: 2048,
          rxBytes: 1048576,
          timestamp: DateTime.utc(2026),
        ),
      );
      await tester.pumpAndSettle();

      final readout = tester.widget<Text>(
        find.byKey(const ValueKey<String>('throughput_readout')),
      );
      expect(readout.data, contains('2.0 KiB'));
      expect(readout.data, contains('1.0 MiB'));
    });

    testWidgets(
      'a stats-stream failure does not disturb the connection badge',
      (tester) async {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
        );

        engine.emit(const Connected());
        await pumpBounded(tester);
        expect(badgeText(tester), 'Connected');

        // Invariant 2: independent failure domains. A stats-pipeline error
        // must degrade statistics WITHOUT moving the connection badge.
        engine.emitStatsError(StateError('stats pipeline down'));
        await pumpBounded(tester);

        expect(badgeText(tester), 'Connected');
        expect(find.text('Traffic data unavailable'), findsOneWidget);
      },
    );
  });

  group('P5-T8 Real Connect/Disconnect Flow', () {
    testWidgets('primary toggle connects active server and stamps lastUsedAt', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);
      await buildRepository(dataSource).addServer(validVlessUri);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      final toggleFinder = find.byKey(
        const ValueKey<String>('home_connect_toggle_button'),
      );
      expect(toggleFinder, findsOneWidget);
      expect(engine.startCalls, isEmpty);

      // Before connect, no profile in savedProfiles with lastUsedAt
      expect(dataSource.savedProfiles, isEmpty);

      await tester.tap(toggleFinder);
      await pumpBounded(tester);

      expect(engine.prepareCalls, 1);
      expect(engine.startCalls, hasLength(1));
      expect(engine.startCalls.single.config.protocol.scheme, 'vless');

      // Verify lastUsedAt was stamped into storage
      expect(dataSource.savedProfiles, hasLength(1));
      expect(dataSource.savedProfiles.single.lastUsedAt, isNotNull);

      // Transition engine to Connected
      engine.emit(const Connected());
      await pumpBounded(tester);

      // Tapping toggle now calls disconnect
      expect(engine.stopCalls, 0);
      await tester.tap(toggleFinder);
      await pumpBounded(tester);

      expect(engine.stopCalls, 1);
    });

    testWidgets(
      'command rejections surface distinct error messages in snackbar',
      (tester) async {
        final engine = _PermissionDeniedVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        await buildRepository(dataSource).addServer(validVlessUri);

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        final toggleFinder = find.byKey(
          const ValueKey<String>('home_connect_toggle_button'),
        );

        await tester.tap(toggleFinder);
        await tester.pump();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text('VPN permission was denied by the system'),
          findsOneWidget,
        );
      },
    );

    testWidgets('invalid config rejection surfaces invalid config message', (
      tester,
    ) async {
      final engine = _InvalidConfigVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);
      await buildRepository(dataSource).addServer(validVlessUri);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      final toggleFinder = find.byKey(
        const ValueKey<String>('home_connect_toggle_button'),
      );

      await tester.tap(toggleFinder);
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('The server configuration is invalid'), findsOneWidget);
    });

    testWidgets(
      'mid-connection switch cleanly stops active tunnel before starting new',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        final repo = buildRepository(dataSource);
        await repo.addServer(validVlessUri);
        await repo.addServer(validShadowsocksUri);

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        final servers = await repo.getAll();
        expect(servers, hasLength(2));
        final server1 = servers[0];
        final server2 = servers[1];

        // Connect first server
        final toggleFinder = find.byKey(
          const ValueKey<String>('home_connect_toggle_button'),
        );
        await tester.tap(toggleFinder);
        await pumpBounded(tester);

        expect(engine.startCalls, hasLength(1));
        expect(engine.startCalls.single.id, equals(server1.id));

        // Engine enters Connected state
        engine.emit(const Connected());
        await pumpBounded(tester);

        // Mid-connection switch: trigger connect to server 2 while connected
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final result = await container
            .read(connectionControllerProvider.notifier)
            .connect(server2);
        await pumpBounded(tester);

        expect(result, isA<VpnCommandAccepted>());
        // Engine stop was called for server 1, and server 2 was started
        expect(engine.stopCalls, 1);
        expect(engine.startCalls, hasLength(2));
        expect(engine.startCalls.last.id, equals(server2.id));
      },
    );

    testWidgets('disconnecting state disables toggle button', (tester) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);
      await buildRepository(dataSource).addServer(validVlessUri);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      final toggleFinder = find.byKey(
        const ValueKey<String>('home_connect_toggle_button'),
      );
      expect(toggleFinder, findsOneWidget);

      // Put engine in Disconnecting state
      engine.emit(const Disconnecting());
      await pumpBounded(tester);

      final orb = tester.widget<BrickPowerOrb>(toggleFinder);
      expect(orb.onTap, isNull);
    });

    testWidgets('empty state displays no active server card or toggle button', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      expect(
        find.byKey(const ValueKey<String>('home_active_server_card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('home_connect_toggle_button')),
        findsNothing,
      );
      expect(find.text('No saved servers yet'), findsOneWidget);
    });

    testWidgets(
      'selecting a server on ServersScreen connects that exact server from '
      'the Home orb',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        final repo = buildRepository(dataSource);
        await repo.addServer(validVlessUri);
        await repo.addServer(validShadowsocksUri);

        // Pumped through the real app shell so the Servers tab is reachable.
        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );

        final servers = await repo.getAll();
        expect(servers, hasLength(2));
        final server1 = servers[0];
        final server2 = servers[1];

        // Active server auto-falls back to server 1
        expect(find.text('Active: ${server1.name}'), findsOneWidget);

        // Select the second server on the Servers tab
        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();
        final secondTile = find.byKey(
          ValueKey<String>('server_tile_${server2.id}'),
        );
        expect(secondTile, findsOneWidget);
        await tester.tap(secondTile);
        await tester.pumpAndSettle();

        // Back on Home, the dashboard shows server 2 and connects it
        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_home')));
        await tester.pumpAndSettle();
        expect(find.text('Active: ${server2.name}'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('home_connect_toggle_button')),
        );
        await pumpBounded(tester);

        // Engine starts with server 2's profile
        expect(engine.startCalls, hasLength(1));
        expect(engine.startCalls.single.id, equals(server2.id));
      },
    );
  });
}
