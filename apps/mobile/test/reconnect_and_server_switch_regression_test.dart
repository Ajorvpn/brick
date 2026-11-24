// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Disconnecting,
        ServerProfile,
        TrafficStats;
import 'package:core_vpn_engine/core_vpn_engine.dart'
    show
        VpnCommandAccepted,
        VpnCommandRejectedBusy,
        VpnCommandRejectedInvalidConfig,
        VpnCommandResult,
        VpnEngine;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/connection/presentation/widgets/session_info_panel.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

const String _uriA =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443#Node%20A';
const String _uriB =
    'vless://22222222-3333-4444-5555-666666666666@example.com:443#Node%20B';
const String _uriC =
    'vless://33333333-4444-5555-6666-777777777777@example.com:443#Node%20C';

Future<ServerProfile> _seedOne(FakeServerProfileDataSource ds) async {
  final repo = buildRepository(ds);
  await repo.addServer(_uriA);
  final servers = await repo.getAll();
  return servers.first;
}

/// A real-async engine that models the on-device teardown window: `stop()`
/// publishes `Disconnecting` immediately and `Disconnected` ~80 ms later, and
/// `start()` is REJECTED as busy while a teardown is still in flight (the exact
/// behaviour of `VpnStateMachine.start()` for `VpnState.Stopping`).
///
/// Deliberately uses a synchronous broadcast controller so a state published
/// inside `stop()` is visible to the provider pipeline before `stop()`'s future
/// completes - i.e. the test does not depend on microtask ordering luck.
class _TeardownRacingEngine implements VpnEngine {
  final StreamController<ConnectionState> _states =
      StreamController<ConnectionState>.broadcast(sync: true);

  final List<ServerProfile> startCalls = <ServerProfile>[];
  int stopCalls = 0;
  int startWhileStoppingRejections = 0;

  ConnectionState _current = const Disconnected();

  @override
  Stream<ConnectionState> get connectionState => _states.stream;

  @override
  Stream<TrafficStats> get trafficStats => const Stream<TrafficStats>.empty();

  @override
  Stream<String> get logEvents => const Stream<String>.empty();

  void _set(ConnectionState state) {
    _current = state;
    _states.add(state);
  }

  @override
  Future<VpnCommandResult> start(ServerProfile profile) async {
    if (_current is Disconnecting) {
      startWhileStoppingRejections++;
      return const VpnCommandRejectedBusy();
    }
    startCalls.add(profile);
    _set(const Connecting());
    _set(const Connected());
    return const VpnCommandAccepted();
  }

  @override
  Future<VpnCommandResult> stop() async {
    stopCalls++;
    _set(const Disconnecting());
    Timer(const Duration(milliseconds: 80), () => _set(const Disconnected()));
    return const VpnCommandAccepted();
  }

  @override
  Future<VpnCommandResult> prepare() async => const VpnCommandAccepted();

  @override
  Future<ConnectionState> getStatus() async => _current;
}

/// Engine whose `start()` result and completion are scripted, so the failure
/// and overlap paths of a live switch can be exercised deterministically.
///
/// `stop()` models the fake-engine contract used across this suite: it reports
/// the call but publishes no transition, leaving the authoritative state alone.
class _ScriptedEngine implements VpnEngine {
  final StreamController<ConnectionState> _states =
      StreamController<ConnectionState>.broadcast(sync: true);

  final List<ServerProfile> startCalls = <ServerProfile>[];
  int stopCalls = 0;

  /// Result handed back by `start()` unless [startGate] is set.
  VpnCommandResult startResult = const VpnCommandAccepted();

  /// When set, `start()` waits on it (models an in-flight dispatch).
  Completer<VpnCommandResult>? startGate;

  ConnectionState _current = const Disconnected();

  @override
  Stream<ConnectionState> get connectionState => _states.stream;

  @override
  Stream<TrafficStats> get trafficStats => const Stream<TrafficStats>.empty();

  @override
  Stream<String> get logEvents => const Stream<String>.empty();

  void emit(ConnectionState state) {
    _current = state;
    _states.add(state);
  }

  @override
  Future<VpnCommandResult> start(ServerProfile profile) async {
    startCalls.add(profile);
    final gate = startGate;
    if (gate != null) return gate.future;
    return startResult;
  }

  @override
  Future<VpnCommandResult> stop() async {
    stopCalls++;
    return const VpnCommandAccepted();
  }

  @override
  Future<VpnCommandResult> prepare() async => const VpnCommandAccepted();

  @override
  Future<ConnectionState> getStatus() async => _current;

  Future<void> dispose() => _states.close();
}

/// Advances animation time without requiring the tree to become idle: a
/// Connected session keeps the orb breathing, so `pumpAndSettle` never returns.
Future<void> _pumpBounded(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpSessionPanel(
  WidgetTester tester, {
  required VpnEngine engine,
  required FakeServerProfileDataSource dataSource,
  required FakeConnectivitySource connectivity,
  FakeAppPreferencesRepository? preferences,
}) async {
  await pumpConnectionMaterialApp(
    tester,
    const Scaffold(body: SessionInfoPanel()),
    engine: engine,
    dataSource: dataSource,
    connectivitySource: connectivity,
    preferencesRepository: preferences,
  );
}

void main() {
  setUpAll(initTestLocalization);

  group('T1-T3: connectivity events must never manufacture a handoff', () {
    testWidgets(
      'T1: tun0 coming up as ConnectivityResult.vpn is NOT an interface '
      'handoff (no stop, stays Connected)',
      (tester) async {
        final engine = FakeVpnEngine();
        final connectivity = FakeConnectivitySource();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        addTearDown(connectivity.dispose);

        final profile = await _seedOne(dataSource);
        await _pumpSessionPanel(
          tester,
          engine: engine,
          dataSource: dataSource,
          connectivity: connectivity,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();
        expect(engine.stopCalls, equals(0));

        // Our own tunnel appears: [wifi] -> [wifi, vpn].
        connectivity.emit(const [
          ConnectivityResult.wifi,
          ConnectivityResult.vpn,
        ]);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        expect(engine.stopCalls, equals(0));
        expect(container.read(autoReconnectProvider), isA<AutoReconnectIdle>());
        expect(find.text('Tunnel: Connected'), findsOneWidget);

        // And the tunnel disappearing ([wifi, vpn] -> [wifi]) is equally not a
        // handoff: no physical transport changed.
        connectivity.emit(const [ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        expect(engine.stopCalls, equals(0));
        expect(container.read(autoReconnectProvider), isA<AutoReconnectIdle>());
        expect(find.text('Tunnel: Connected'), findsOneWidget);
        expect(engine.startCalls, hasLength(1));
      },
    );

    testWidgets(
      'T2: a real Wi-Fi -> Cellular handoff while connected still restarts the '
      'tunnel exactly once',
      (tester) async {
        final engine = FakeVpnEngine();
        final connectivity = FakeConnectivitySource(
          initial: const [ConnectivityResult.wifi, ConnectivityResult.vpn],
        );
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        addTearDown(connectivity.dispose);

        final profile = await _seedOne(dataSource);
        await _pumpSessionPanel(
          tester,
          engine: engine,
          dataSource: dataSource,
          connectivity: connectivity,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();
        expect(engine.stopCalls, equals(0));

        // Physical bearer changes: [wifi, vpn] -> [mobile, vpn].
        connectivity.emit(const [
          ConnectivityResult.mobile,
          ConnectivityResult.vpn,
        ]);
        await tester.pump(const Duration(milliseconds: 500));

        expect(engine.stopCalls, equals(1));
      },
    );

    testWidgets(
      'T3: Auto-Reconnect disabled in Settings blocks the handoff restart',
      (tester) async {
        final engine = FakeVpnEngine();
        final connectivity = FakeConnectivitySource();
        final dataSource = FakeServerProfileDataSource();
        final preferences = FakeAppPreferencesRepository(
          initialAutoReconnectEnabled: false,
        );
        addTearDown(engine.dispose);
        addTearDown(connectivity.dispose);

        final profile = await _seedOne(dataSource);
        await _pumpSessionPanel(
          tester,
          engine: engine,
          dataSource: dataSource,
          connectivity: connectivity,
          preferences: preferences,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Genuine physical handoff, but the user disabled automatic restarts.
        connectivity.emit(const [ConnectivityResult.mobile]);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        expect(engine.stopCalls, equals(0));
        expect(find.text('Tunnel: Connected'), findsOneWidget);
      },
    );
  });

  group('T4: ConnectionController serializes stop -> start', () {
    test(
      'T4: switching to a different server waits for Disconnected and starts '
      'the new profile without a RejectedBusy bounce',
      () async {
        final engine = _TeardownRacingEngine();
        final dataSource = FakeServerProfileDataSource();
        final repo = buildRepository(dataSource);
        await repo.addServer(_uriA);
        await repo.addServer(_uriB);
        final seeded = await repo.getAll();
        final profileA = seeded[0];
        final profileB = seeded[1];

        final container = ProviderContainer(
          overrides: [
            vpnEngineProvider.overrideWithValue(engine),
            serverProfileRepositoryProvider.overrideWith((ref) async => repo),
            connectivitySourceProvider.overrideWithValue(
              FakeConnectivitySource(),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(
              FakeAppPreferencesRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen(connectionStateProvider, (_, _) {});
        addTearDown(sub.close);

        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        expect(await controller.connect(profileA), isA<VpnCommandAccepted>());
        expect(container.read(connectionStateProvider).value, isA<Connected>());
        expect(engine.startCalls.single.id, equals(profileA.id));

        final result = await controller.connect(profileB);

        expect(result, isA<VpnCommandAccepted>());
        expect(engine.stopCalls, equals(1));
        expect(
          engine.startWhileStoppingRejections,
          equals(0),
          reason: 'start() must not be dispatched while native is Stopping',
        );
        expect(engine.startCalls.last.id, equals(profileB.id));
        expect(container.read(connectionStateProvider).value, isA<Connected>());
      },
    );
  });

  group('T5: ServersScreen performs a live, one-tap switch', () {
    testWidgets(
      'T5a: tapping a different server while Connected switches the live '
      'tunnel and persists the selection',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        final repo = buildRepository(dataSource);
        await repo.addServer(_uriA);
        await repo.addServer(_uriB);
        final seeded = await repo.getAll();
        final serverB = seeded[1];

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );

        // A live session exists (re-attached from native truth).
        engine.emit(const Connected());
        await _pumpBounded(tester);

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await _pumpBounded(tester);

        final tile = find.byKey(ValueKey<String>('server_tile_${serverB.id}'));
        expect(tile, findsOneWidget);
        await tester.tap(tile);
        await _pumpBounded(tester);

        expect(container.read(activeServerIdProvider), equals(serverB.id));
        expect(engine.stopCalls, equals(1));
        expect(engine.startCalls.last.id, equals(serverB.id));
      },
    );

    testWidgets(
      'T5b: tapping a server while Disconnected only selects it (never '
      'auto-connects)',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        final repo = buildRepository(dataSource);
        await repo.addServer(_uriA);
        await repo.addServer(_uriB);
        final seeded = await repo.getAll();
        final serverB = seeded[1];

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        final tile = find.byKey(ValueKey<String>('server_tile_${serverB.id}'));
        expect(tile, findsOneWidget);
        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(container.read(activeServerIdProvider), equals(serverB.id));
        expect(engine.startCalls, isEmpty);
        expect(engine.stopCalls, equals(0));
      },
    );
  });

  group('T6: J1 physical-bearer memory across an intermediate [vpn]', () {
    testWidgets(
      'T6: a Wi-Fi drop reported as [vpn] alone is offline, keeps the last '
      'bearer, and the following Cellular handoff still restarts the tunnel',
      (tester) async {
        final engine = FakeVpnEngine();
        final connectivity = FakeConnectivitySource();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        addTearDown(connectivity.dispose);

        final profile = await _seedOne(dataSource);
        await _pumpSessionPanel(
          tester,
          engine: engine,
          dataSource: dataSource,
          connectivity: connectivity,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Tunnel up: [wifi] -> [wifi, vpn]. Remembers {wifi}.
        connectivity.emit(const [
          ConnectivityResult.wifi,
          ConnectivityResult.vpn,
        ]);
        await tester.pump(const Duration(milliseconds: 500));
        expect(engine.stopCalls, equals(0));

        // Wi-Fi drops while tun0 still exists: Android reports vpn only.
        connectivity.emit(const [ConnectivityResult.vpn]);
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectWaitingForNetwork>(),
          reason: 'zero physical bearers means offline, not online',
        );

        // Cellular returns. The remembered {wifi} makes this a real handoff.
        connectivity.emit(const [
          ConnectivityResult.mobile,
          ConnectivityResult.vpn,
        ]);
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          engine.stopCalls,
          equals(1),
          reason: 'a wiped bearer memory would miss the Wi-Fi -> Cellular '
              'handoff entirely',
        );
      },
    );
  });

  group('T7: J2 a rejected or overlapping live switch never desyncs the UI', () {
    testWidgets(
      'T7a: a rejected start leaves the active selection on the old server '
      'and surfaces an error',
      (tester) async {
        final engine = _ScriptedEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        final repo = buildRepository(dataSource);
        await repo.addServer(_uriA);
        await repo.addServer(_uriB);
        final seeded = await repo.getAll();
        final serverA = seeded[0];
        final serverB = seeded[1];

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );

        engine.emit(const Connected());
        await _pumpBounded(tester);

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await _pumpBounded(tester);

        engine.startResult = const VpnCommandRejectedInvalidConfig();
        await tester.tap(
          find.byKey(ValueKey<String>('server_tile_${serverB.id}')),
        );
        await _pumpBounded(tester);

        expect(
          container.read(activeServerIdProvider),
          equals(serverA.id),
          reason: 'a rejected switch must not claim the new server is active',
        );
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets(
      'T7b: a tap that lands while a switch is still in flight is ignored, so '
      'the selection stays with the server that actually starts',
      (tester) async {
        final engine = _ScriptedEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);
        final repo = buildRepository(dataSource);
        await repo.addServer(_uriA);
        await repo.addServer(_uriB);
        await repo.addServer(_uriC);
        final seeded = await repo.getAll();
        final serverB = seeded[1];
        final serverC = seeded[2];

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );

        engine.emit(const Connected());
        await _pumpBounded(tester);

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await _pumpBounded(tester);

        // First tap: the switch to B stays in flight until the gate opens.
        engine.startGate = Completer<VpnCommandResult>();
        await tester.tap(
          find.byKey(ValueKey<String>('server_tile_${serverB.id}')),
        );
        await tester.pump();
        await tester.pump();

        // Second tap lands while `connect()` is still busy: it must be dropped.
        await tester.tap(
          find.byKey(ValueKey<String>('server_tile_${serverC.id}')),
        );
        await tester.pump();

        engine.startGate!.complete(const VpnCommandAccepted());
        engine.startGate = null;
        await _pumpBounded(tester);

        expect(
          container.read(activeServerIdProvider),
          equals(serverB.id),
          reason: 'the dropped overlap must not rewrite the selection to C',
        );
        expect(engine.startCalls.single.id, equals(serverB.id));
      },
    );
  });
}
