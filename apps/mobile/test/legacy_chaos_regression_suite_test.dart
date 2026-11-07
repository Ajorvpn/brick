// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        Disconnected,
        Disconnecting,
        Error,
        PlatformError,
        ServerProfile,
        TrafficStats,
        VlessOutbound;
import 'package:core_vpn_engine/core_vpn_engine.dart'
    show
        MockVpnEngine,
        VpnCommandAccepted,
        VpnCommandFailed,
        VpnCommandRejectedBusy,
        VpnCommandResult;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/providers/session_duration_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/connection/presentation/widgets/throughput_readout.dart';

import 'localization_test_harness.dart';

const String _testVlessUri =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443#Tokyo%20Node';

Future<ServerProfile> _seedServer(FakeServerProfileDataSource ds) async {
  final repo = buildRepository(ds);
  await repo.addServer(_testVlessUri);
  final servers = await repo.loadServers();
  return (servers.first as SavedServerProfile).profile;
}

class _IpcFaultVpnEngine extends FakeVpnEngine {
  bool shouldFailCommand = false;
  bool shouldThrowPlatformException = false;

  @override
  Future<VpnCommandResult> start(ServerProfile profile) {
    if (shouldThrowPlatformException) {
      throw PlatformException(
        code: 'UNAVAILABLE',
        message: 'Service onBind returned null / IPC binding failure',
      );
    }
    if (shouldFailCommand) {
      return Future.value(const VpnCommandFailed());
    }
    return super.start(profile);
  }
}

void main() {
  setUpAll(initTestLocalization);

  group('P7-T5 Chaos Test Suite: Legacy Failure Mode Regression Set', () {
    late FakeVpnEngine engine;
    late FakeServerProfileDataSource dataSource;
    late FakeConnectivitySource fakeConnectivity;

    setUp(() {
      engine = FakeVpnEngine();
      dataSource = FakeServerProfileDataSource();
      fakeConnectivity = FakeConnectivitySource();
    });

    tearDown(() async {
      await fakeConnectivity.dispose();
      await engine.dispose();
    });

    testWidgets(
      'Failure Mode 1: Swallowed stats error / Always-0 bytes — verifies '
      'Invariant 2 independent failure domains & error UI presentation',
      (tester) async {
        await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // 1. Valid stats reflect in throughput readout
        final t0 = DateTime.now();
        engine.emitStats(
          TrafficStats(txBytes: 1024, rxBytes: 2048, timestamp: t0),
        );
        await tester.pump();

        expect(find.byType(ThroughputReadout), findsOneWidget);
        expect(find.text('Traffic data unavailable'), findsNothing);

        // 2. Inject stats error: Invariant 2 requires connectionState untouched
        engine.emitStatsError(Exception('stats connection socket closed'));
        await tester.pump();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        expect(container.read(connectionStateProvider).value, isA<Connected>());
        expect(find.text('Traffic data unavailable'), findsOneWidget);

        // 3. Stats resume: UI recovers seamlessly
        final t1 = t0.add(const Duration(seconds: 1));
        engine.emitStats(
          TrafficStats(txBytes: 2048, rxBytes: 4096, timestamp: t1),
        );
        await tester.pump();
        expect(find.text('Traffic data unavailable'), findsNothing);
      },
    );

    testWidgets(
      'Failure Mode 2: False "Connected" State — verifies Invariant 1 '
      'stream-truth & no optimistic UI transitions on connect command',
      (tester) async {
        final profile = await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        expect(find.text('Connected'), findsNothing);

        // Tap connect button
        final connectBtn = find.widgetWithText(TextButton, 'Connect');
        expect(connectBtn, findsOneWidget);
        await tester.tap(connectBtn);
        await tester.pump();

        // engine.start() returned VpnCommandAccepted, but stream has not
        // emitted Connected yet
        expect(engine.startCalls, contains(profile));
        // Invariant 1: UI must NEVER jump to Connected from command acceptance
        expect(find.text('Connected'), findsNothing);

        // Only stream emission transitions to Connected
        engine.emit(const Connected());
        await tester.pumpAndSettle();
        expect(find.text('Connected'), findsWidgets);
      },
    );

    testWidgets(
      'Failure Mode 3: DNS / Rule-Set bootstrap hang prevention & timeout abort',
      (tester) async {
        // Part A: Outbound config contains 0 remote rule_sets
        const vlessOutbound = VlessOutbound(
          server: 'vpn.example.com',
          serverPort: 443,
          uuid: '11111111-2222-3333-4444-555555555555',
        );
        final serialized = buildSingBoxOutbound(vlessOutbound);
        expect(serialized.containsKey('rule_set'), isFalse);

        // Part B: Stalled engine startup transitions cleanly to PlatformError
        await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        engine.emit(
          const Error(
            PlatformError(
              'start failed: TimeoutCancellationException: 15000 ms',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets(
      'Failure Mode 4: Non-blocking disconnect call & 5000ms watchdog '
      'resilience',
      (tester) async {
        final profile = await _seedServer(dataSource);
        final mockEngine = MockVpnEngine(
          connectDelay: Duration.zero,
          disconnectDelay: const Duration(hours: 1),
        );
        addTearDown(mockEngine.dispose);

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: mockEngine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        // Connect
        final connectRes = await controller.connect(profile);
        expect(connectRes, isA<VpnCommandAccepted>());
        await tester.pumpAndSettle();
        expect(container.read(connectionStateProvider).value, isA<Connected>());

        // Disconnect returns asynchronously without blocking the UI thread
        final disconnectFuture = controller.disconnect();
        expect(disconnectFuture, completes);
        final result = await disconnectFuture;
        expect(result, isA<VpnCommandAccepted>());

        // Disconnect is stalled at 1 hour; at 4900ms engine is still
        // Disconnecting
        await tester.pump(const Duration(milliseconds: 4900));
        expect(
          container.read(connectionStateProvider).value,
          isA<Disconnecting>(),
        );

        // At 5000ms (100ms later), the 5000ms stopWatchdogTimeout fires
        // and forces Disconnected
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          container.read(connectionStateProvider).value,
          isA<Disconnected>(),
        );
      },
    );

    testWidgets(
      'Failure Mode 5: Asynchronous startup errors are surfaced directly to '
      'user via UI feedback, never swallowed into a daemon thread black hole',
      (tester) async {
        await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        engine.emit(
          const Error(
            PlatformError('Fatal core startup failure: TUN permission denied'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets(
      'Failure Mode 6: Repeated connection cycles verify no spent one-shot '
      'initialization guards across close() cycles',
      (tester) async {
        final profile = await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        for (var i = 1; i <= 3; i++) {
          final connectRes = await controller.connect(profile);
          expect(connectRes, isA<VpnCommandAccepted>());
          engine.emit(const Connected());
          await tester.pumpAndSettle();
          expect(
            container.read(connectionStateProvider).value,
            isA<Connected>(),
          );

          engine.emitLog('Cycle $i active');
          await tester.pump();

          final t0 = DateTime.now();
          engine.emitStats(
            TrafficStats(
              txBytes: i * 100000,
              rxBytes: i * 200000,
              timestamp: t0,
            ),
          );
          await tester.pump(const Duration(seconds: 1));

          engine.emitStats(
            TrafficStats(
              txBytes: i * 100000 + 50000,
              rxBytes: i * 200000 + 100000,
              timestamp: t0.add(const Duration(seconds: 1)),
            ),
          );
          await tester.pump(const Duration(seconds: 1));

          expect(
            container.read(sessionDurationProvider).inSeconds,
            greaterThanOrEqualTo(2),
          );

          final disconnectRes = await controller.disconnect();
          expect(disconnectRes, isA<VpnCommandAccepted>());
          engine.emit(const Disconnected());
          await tester.pumpAndSettle();
          expect(
            container.read(connectionStateProvider).value,
            isA<Disconnected>(),
          );
          expect(
            container.read(sessionDurationProvider),
            equals(Duration.zero),
          );
        }

        expect(engine.startCalls.length, equals(3));
        expect(engine.stopCalls, equals(3));
      },
    );

    testWidgets(
      'Failure Mode 7: IPC binding failure recovery without app crash or '
      'permanent controller lockup',
      (tester) async {
        final faultEngine = _IpcFaultVpnEngine();
        final profile = await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: faultEngine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        // 1. Simulate PlatformException on IPC call: controller catches
        // Object, returns VpnCommandFailed
        faultEngine.shouldThrowPlatformException = true;
        final excRes = await controller.connect(profile);
        expect(excRes, isA<VpnCommandFailed>());
        expect(controller.isBusy, isFalse);
        expect(container.read(autoReconnectProvider).isReconnecting, isFalse);
        expect(container.read(killSwitchProvider), isA<KillSwitchInactive>());

        // 2. Simulate VpnCommandFailed on IPC binding loss
        faultEngine
          ..shouldThrowPlatformException = false
          ..shouldFailCommand = true;
        final failRes = await controller.connect(profile);
        expect(failRes, isA<VpnCommandFailed>());
        expect(controller.isBusy, isFalse);
        expect(container.read(autoReconnectProvider).isReconnecting, isFalse);
        expect(container.read(killSwitchProvider), isA<KillSwitchInactive>());

        // 3. Restore binding and succeed
        faultEngine.shouldFailCommand = false;
        final okRes = await controller.connect(profile);
        expect(okRes, isA<VpnCommandAccepted>());
        expect(faultEngine.startCalls, contains(profile));

        await faultEngine.dispose();
      },
    );

    testWidgets(
      'Failure Mode 8: User-initiated stop vs unexpected drop kill-switch '
      'coordination (ACTION_STOP vs crash leak prevention)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final profile = await _seedServer(dataSource);
        final fakePrefs = FakeAppPreferencesRepository(
          initialKillSwitchEnabled: true,
        );
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        // 1. User connect -> Armed
        await controller.connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();
        expect(container.read(killSwitchProvider), isA<KillSwitchArmed>());

        // 2. Deliberate user disconnect -> Inactive (clean unblock)
        await controller.disconnect();
        engine.emit(const Disconnected());
        await tester.pumpAndSettle();
        expect(container.read(killSwitchProvider), isA<KillSwitchInactive>());
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsNothing,
        );

        // 3. User reconnect -> Armed
        await controller.connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();
        expect(container.read(killSwitchProvider), isA<KillSwitchArmed>());

        // 4. Unexpected drop -> Blocking (fail-closed protection)
        engine.emit(const Disconnected());
        await tester.pumpAndSettle();
        expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Failure Mode 9: Late traffic stats and rapid taps cannot overwrite '
      'Disconnecting state',
      (tester) async {
        await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Begin disconnect
        engine.emit(const Disconnecting());
        await tester.pump();

        // Emit late traffic stats during disconnect
        engine.emitStats(
          TrafficStats(txBytes: 9999, rxBytes: 9999, timestamp: DateTime.now()),
        );
        await tester.pump();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        expect(
          container.read(connectionStateProvider).value,
          isA<Disconnecting>(),
        );

        // Connect button disabled during disconnecting
        final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey<String>('home_connect_toggle_button')),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets(
      'Failure Mode 10: Session timers and coroutines reset cleanly across '
      'sessions with zero leakage',
      (tester) async {
        final profile = await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        // Session 1: Connect and run for 3 seconds
        await controller.connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        expect(container.read(sessionDurationProvider).inSeconds, equals(3));

        // Simulate unexpected drop to arm AutoReconnectBackoff timer
        engine.emit(const Disconnected());
        await tester.pump();
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectBackoff>(),
        );

        // User disconnects deliberately -> cancels backoff timer and
        // rests in idle
        await controller.disconnect();
        await tester.pumpAndSettle();
        expect(container.read(autoReconnectProvider), isA<AutoReconnectIdle>());
        expect(container.read(sessionDurationProvider), equals(Duration.zero));

        // Session 2: Connect fresh session
        await controller.connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();
        expect(container.read(sessionDurationProvider), equals(Duration.zero));

        // Advance 5 seconds (well past Session 1's backoff timer)
        await tester.pump(const Duration(seconds: 5));
        // Verify Session 1's cancelled backoff timer never fired or
        // perturbed Session 2
        expect(container.read(autoReconnectProvider), isA<AutoReconnectIdle>());
        expect(container.read(connectionStateProvider).value, isA<Connected>());
        expect(container.read(sessionDurationProvider).inSeconds, equals(5));

        // Disconnect Session 2 cleanly
        await controller.disconnect();
        engine.emit(const Disconnected());
        await tester.pumpAndSettle();
        expect(container.read(sessionDurationProvider), equals(Duration.zero));
      },
    );

    testWidgets(
      'Failure Mode 11: Re-entrant concurrent commands handled via busy '
      'guard without deadlock',
      (tester) async {
        final profile = await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        // 20 rapid interleaved calls
        final futures = <Future<VpnCommandResult>>[];
        for (var i = 0; i < 20; i++) {
          if (i.isEven) {
            futures.add(controller.connect(profile));
          } else {
            futures.add(controller.disconnect());
          }
        }

        final results = await Future.wait(futures);
        expect(results.length, equals(20));
        final busyCount = results.whereType<VpnCommandRejectedBusy>().length;
        expect(busyCount, greaterThan(0));
        expect(controller.isBusy, isFalse);
      },
    );

    testWidgets(
      'Failure Mode 12: Rapid start-then-stop during Connecting cancels '
      'cleanly without TUN descriptor or session leak',
      (tester) async {
        final profile = await _seedServer(dataSource);
        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        // Start connect and wait for engine command dispatch to complete
        await controller.connect(profile);
        // Engine is in Connecting state (stream has not emitted Connected yet)
        engine.emit(const Connecting());
        await tester.pump();

        // Immediate disconnect while still in Connecting
        final disconnectRes = await controller.disconnect();
        expect(disconnectRes, isA<VpnCommandAccepted>());
        expect(engine.stopCalls, equals(1));

        engine.emit(const Disconnected());
        await tester.pumpAndSettle();

        expect(
          container.read(connectionStateProvider).value,
          isA<Disconnected>(),
        );
        expect(controller.activeConnectingServerId, isNull);
      },
    );
  });
}
