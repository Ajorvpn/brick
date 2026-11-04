// SPDX-License-Identifier: GPL-3.0-or-later

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
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

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

        await tester.tap(find.text('Add Server'));
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

      await tester.tap(find.text('Add Server'));
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

      expect(find.text('My Server'), findsOneWidget);
      // Addressed by its own key, never by position: the tile also renders
      // Connect/Disconnect `Text` buttons, so a `.last` descendant finder
      // lands on 'Disconnect' the moment the trailing row is reordered.
      final tileSubtitle = tester.widget<Text>(
        find.byKey(const ValueKey<String>('server_tile_subtitle_seed-1')),
      );
      expect(tileSubtitle.data, contains('vless'));
      expect(tileSubtitle.data, contains('example.com:443'));
      expect(find.text('Connect'), findsNWidgets(2));
      expect(find.text('Disconnect'), findsOneWidget);
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

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      // A recognizable broken entry...
      expect(find.text('Unreadable server'), findsOneWidget);
      // ...with no connect affordance, so it can never reach the engine...
      expect(find.text('Connect'), findsNothing);
      // ...still stored rather than silently dropped...
      expect(dataSource.records, hasLength(1));
      // ...and removable.
      await tester.tap(find.text('Remove'));
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

      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
      );

      expect(find.text('Unreadable server'), findsOneWidget);
      expect(find.textContaining('hunter2-secret'), findsNothing);
      // The reason shown must not carry the stored URI either.
      final reason = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('server_tile_broken_broken-2'),
              ),
              matching: find.byType(Text),
            )
            .last,
      );
      expect(reason.data ?? '', isNot(contains('hunter2-secret')));
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

      await tester.tap(find.text('Connect').first);
      await tester.pumpAndSettle();

      expect(engine.startCalls, hasLength(1));
      expect(engine.startCalls.single.config.protocol.scheme, 'vless');

      // Rebuilds driven by stream events must NOT re-dispatch the command.
      engine.emit(const Connecting());
      await tester.pumpAndSettle();
      engine.emit(const Connected());
      await tester.pumpAndSettle();
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

      await tester.tap(find.text('Connect').first);
      await tester.pumpAndSettle();

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

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(engine.stopCalls, 1);

      engine.emit(const Disconnecting());
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(badgeText(tester), 'Connecting');

      engine.emit(const Connected());
      await tester.pumpAndSettle();
      expect(badgeText(tester), 'Connected');

      engine.emit(const Disconnecting());
      await tester.pumpAndSettle();
      expect(badgeText(tester), 'Disconnecting');

      engine.emit(const Disconnected());
      await tester.pumpAndSettle();
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

      await tester.tap(find.text('Connect').first);
      await tester.pumpAndSettle();

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
        await tester.pumpAndSettle();
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
        await tester.pumpAndSettle();
        expect(badgeText(tester), 'Connected');

        // Invariant 2: independent failure domains. A stats-pipeline error
        // must degrade statistics WITHOUT moving the connection badge.
        engine.emitStatsError(StateError('stats pipeline down'));
        await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      expect(engine.prepareCalls, 1);
      expect(engine.startCalls, hasLength(1));
      expect(engine.startCalls.single.config.protocol.scheme, 'vless');

      // Verify lastUsedAt was stamped into storage
      expect(dataSource.savedProfiles, hasLength(1));
      expect(dataSource.savedProfiles.single.lastUsedAt, isNotNull);

      // Transition engine to Connected
      engine.emit(const Connected());
      await tester.pumpAndSettle();

      // Tapping toggle now calls disconnect
      expect(engine.stopCalls, 0);
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

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
        await tester.pumpAndSettle();

        expect(engine.startCalls, hasLength(1));
        expect(engine.startCalls.single.id, equals(server1.id));

        // Engine enters Connected state
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Mid-connection switch: trigger connect to server 2 while connected
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final result = await container
            .read(connectionControllerProvider.notifier)
            .connect(server2);
        await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(toggleFinder);
      expect(button.onPressed, isNull);
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
      'tapping Connect on ServerTile connects to that specific server and '
      'updates active selection',
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

        // Active server auto-falls back to server 1
        expect(find.text('Active: ${server1.name}'), findsOneWidget);

        // Find the second server's tile and tap its Connect button specifically
        final secondTile = find.byKey(
          ValueKey<String>('server_tile_${server2.id}'),
        );
        expect(secondTile, findsOneWidget);
        final connectButton = find.descendant(
          of: secondTile,
          matching: find.text('Connect'),
        );
        expect(connectButton, findsOneWidget);

        await tester.tap(connectButton);
        await tester.pumpAndSettle();

        // Engine starts with server 2's profile
        expect(engine.startCalls, hasLength(1));
        expect(engine.startCalls.single.id, equals(server2.id));

        // Active server selection switched to server 2
        expect(find.text('Active: ${server2.name}'), findsOneWidget);
      },
    );
  });
}
