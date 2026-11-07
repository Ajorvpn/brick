// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        Disconnected,
        Disconnecting,
        Error,
        InvalidConfig,
        PermissionDenied,
        PlatformError,
        ServerProfile,
        TrafficStats;
import 'package:core_vpn_engine/core_vpn_engine.dart'
    show VpnCommandAccepted, VpnCommandRejectedInvalidConfig, VpnCommandResult;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/session_duration_provider.dart';
import 'package:mobile/features/connection/presentation/providers/session_traffic_metrics_provider.dart';
import 'package:mobile/features/connection/presentation/widgets/session_info_panel.dart';

import 'localization_test_harness.dart';

const String _testVlessUri =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443#Tokyo%20Node';

Future<ServerProfile> _seedServer(FakeServerProfileDataSource ds) async {
  final repo = buildRepository(ds);
  await repo.addServer(_testVlessUri);
  final servers = await repo.loadServers();
  return (servers.first as SavedServerProfile).profile;
}

void main() {
  setUpAll(initTestLocalization);

  group('AutoReconnectState & Policy unit tests', () {
    test('State value equality and isReconnecting getter', () {
      const idle1 = AutoReconnectIdle();
      const idle2 = AutoReconnectIdle();
      expect(idle1, equals(idle2));
      expect(idle1.isReconnecting, isFalse);

      const waiting1 = AutoReconnectWaitingForNetwork(attempt: 1);
      const waiting2 = AutoReconnectWaitingForNetwork(attempt: 1);
      const waitingDiff = AutoReconnectWaitingForNetwork(attempt: 2);
      expect(waiting1, equals(waiting2));
      expect(waiting1, isNot(equals(waitingDiff)));
      expect(waiting1.isReconnecting, isTrue);

      const backoff1 = AutoReconnectBackoff(
        attempt: 1,
        maxAttempts: 5,
        delay: Duration(seconds: 1),
      );
      const backoff2 = AutoReconnectBackoff(
        attempt: 1,
        maxAttempts: 5,
        delay: Duration(seconds: 1),
      );
      expect(backoff1, equals(backoff2));
      expect(backoff1.isReconnecting, isTrue);

      const inFlight1 = AutoReconnectInFlight(attempt: 1, maxAttempts: 5);
      const inFlight2 = AutoReconnectInFlight(attempt: 1, maxAttempts: 5);
      expect(inFlight1, equals(inFlight2));
      expect(inFlight1.isReconnecting, isTrue);

      const exhausted1 = AutoReconnectExhausted(totalAttempts: 5);
      const exhausted2 = AutoReconnectExhausted(totalAttempts: 5);
      expect(exhausted1, equals(exhausted2));
      expect(exhausted1.isReconnecting, isFalse);
    });

    test(
      'AutoReconnectPolicy calculates exponential backoff with ceiling cap',
      () {
        const policy = AutoReconnectPolicy();

        expect(policy.backoffForAttempt(1), equals(const Duration(seconds: 1)));
        expect(policy.backoffForAttempt(2), equals(const Duration(seconds: 2)));
        expect(policy.backoffForAttempt(3), equals(const Duration(seconds: 4)));
        expect(policy.backoffForAttempt(4), equals(const Duration(seconds: 8)));
        expect(
          policy.backoffForAttempt(5),
          equals(const Duration(seconds: 16)),
        );
        // Beyond 5 attempts capped at maxBackoff (30s)
        expect(
          policy.backoffForAttempt(6),
          equals(const Duration(seconds: 30)),
        );
      },
    );
  });

  group('AutoReconnect on Network Change & Drop Recovery', () {
    late FakeVpnEngine engine;
    late FakeConnectivitySource fakeConnectivity;
    late FakeAppPreferencesRepository fakePrefs;
    late FakeServerProfileDataSource dataSource;

    setUp(() {
      engine = FakeVpnEngine();
      fakeConnectivity = FakeConnectivitySource();
      fakePrefs = FakeAppPreferencesRepository();
      dataSource = FakeServerProfileDataSource();
    });

    tearDown(() async {
      await fakeConnectivity.dispose();
      await engine.dispose();
    });

    testWidgets('Invariant 1: User-intent respect — manual disconnect prevents '
        'auto-reconnect on network flap', (tester) async {
      final profile = await _seedServer(dataSource);

      await pumpConnectionMaterialApp(
        tester,
        const Scaffold(body: SessionInfoPanel()),
        engine: engine,
        dataSource: dataSource,
        connectivitySource: fakeConnectivity,
        preferencesRepository: fakePrefs,
      );

      // 1. User connects
      final controller = tester.element(find.byType(SessionInfoPanel));
      final container = ProviderScope.containerOf(controller);
      await container
          .read(connectionControllerProvider.notifier)
          .connect(profile);
      engine.emit(const Connecting());
      await tester.pump();
      engine.emit(const Connected());
      await tester.pumpAndSettle();

      expect(
        container.read(autoReconnectProvider.notifier).isUserSessionActive,
        isTrue,
      );

      // 2. User manually disconnects
      await container.read(connectionControllerProvider.notifier).disconnect();
      engine.emit(const Disconnecting());
      await tester.pump();
      engine.emit(const Disconnected());
      await tester.pumpAndSettle();

      expect(
        container.read(autoReconnectProvider.notifier).isUserSessionActive,
        isFalse,
      );
      expect(
        container.read(autoReconnectProvider),
        equals(const AutoReconnectIdle()),
      );

      // 3. Network flaps offline then online
      fakeConnectivity.emit(const [ConnectivityResult.none]);
      await tester.pump(const Duration(milliseconds: 350));

      fakeConnectivity.emit(const [ConnectivityResult.wifi]);
      await tester.pump(const Duration(milliseconds: 350));

      // Auto-reconnect MUST NOT fire
      expect(engine.startCalls.length, equals(1)); // Only the initial connect
      expect(
        container.read(autoReconnectProvider),
        equals(const AutoReconnectIdle()),
      );
      expect(
        container.read(connectionStateProvider).value,
        isA<Disconnected>(),
      );
    });

    testWidgets(
      'Invariant 2: Never connected — app boots disconnected, network changes '
      'do NOT trigger connect',
      (tester) async {
        await buildRepository(dataSource).addServer(_testVlessUri);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );
        final metricsSub = container.listen(
          sessionTrafficMetricsProvider,
          (previous, next) {},
        );
        addTearDown(metricsSub.close);

        expect(
          container.read(autoReconnectProvider.notifier).isUserSessionActive,
          isFalse,
        );
        expect(engine.startCalls.length, equals(0));

        // Network flaps
        fakeConnectivity.emit(const [ConnectivityResult.mobile]);
        await tester.pump(const Duration(milliseconds: 350));

        fakeConnectivity.emit(const [ConnectivityResult.none]);
        await tester.pump(const Duration(milliseconds: 350));

        fakeConnectivity.emit(const [ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 350));

        expect(engine.startCalls.length, equals(0));
        expect(
          container.read(autoReconnectProvider),
          equals(const AutoReconnectIdle()),
        );
      },
    );

    testWidgets('Happy Path: Network interface handoff (Wi-Fi to Mobile) while '
        'Connected restarts tunnel', (tester) async {
      final profile = await _seedServer(dataSource);

      await pumpConnectionMaterialApp(
        tester,
        const Scaffold(body: SessionInfoPanel()),
        engine: engine,
        dataSource: dataSource,
        connectivitySource: fakeConnectivity,
        preferencesRepository: fakePrefs,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionInfoPanel)),
      );
      final metricsSub = container.listen(
        sessionTrafficMetricsProvider,
        (previous, next) {},
      );
      addTearDown(metricsSub.close);

      // 1. Connect on Wi-Fi
      await container
          .read(connectionControllerProvider.notifier)
          .connect(profile);
      engine.emit(const Connected());
      await tester.pumpAndSettle();

      expect(find.text('Tunnel: Connected'), findsOneWidget);
      expect(engine.startCalls.length, equals(1));
      expect(engine.stopCalls, equals(0));

      // 2. Network switches to Cellular (interface handoff)
      fakeConnectivity.emit(const [ConnectivityResult.mobile]);
      // Debounce fires
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      // Coordinator detects handoff and invokes engine.stop()
      expect(engine.stopCalls, equals(1));

      // Engine transitions through drop
      engine.emit(const Disconnected());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Coordinator is now in AutoReconnectBackoff (attempt 1)
      expect(
        container.read(autoReconnectProvider),
        isA<AutoReconnectBackoff>(),
      );
      expect(
        find.byKey(const ValueKey<String>('session_reconnecting_text')),
        findsOneWidget,
      );

      // Advance 1s backoff timer
      await tester.pump(const Duration(seconds: 1));
      expect(engine.startCalls.length, equals(2)); // Reconnected!

      // Complete reconnect
      engine.emit(const Connected());
      await tester.pumpAndSettle();

      expect(find.text('Tunnel: Connected'), findsOneWidget);
      expect(
        container.read(autoReconnectProvider),
        equals(const AutoReconnectIdle()),
      );
      expect(
        find.byKey(const ValueKey<String>('session_reconnecting_text')),
        findsNothing,
      );
    });

    testWidgets(
      'Drop recovery: Unexpected disconnect triggers backoff and successful '
      'reconnect',
      (tester) async {
        final profile = await _seedServer(dataSource);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );
        final metricsSub = container.listen(
          sessionTrafficMetricsProvider,
          (previous, next) {},
        );
        addTearDown(metricsSub.close);

        // Connect
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Simulate unexpected engine error
        engine.emit(const Error(PlatformError('Underlying socket closed')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Tunnel: Connection error'), findsOneWidget);
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectBackoff>(),
        );
        expect(
          find.byKey(const ValueKey<String>('session_reconnecting_text')),
          findsOneWidget,
        );

        // Advance 1s backoff
        await tester.pump(const Duration(seconds: 1));
        expect(engine.startCalls.length, equals(2));

        engine.emit(const Connected());
        await tester.pumpAndSettle();

        expect(find.text('Tunnel: Connected'), findsOneWidget);
        expect(
          container.read(autoReconnectProvider),
          equals(const AutoReconnectIdle()),
        );
      },
    );

    testWidgets(
      'Offline handling: Tunnel drops while offline pauses reconnect until '
      'network returns online',
      (tester) async {
        final profile = await _seedServer(dataSource);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );
        final metricsSub = container.listen(
          sessionTrafficMetricsProvider,
          (previous, next) {},
        );
        addTearDown(metricsSub.close);

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Device goes offline (Airplane mode)
        fakeConnectivity.emit(const [ConnectivityResult.none]);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 100));

        // Engine drops
        engine.emit(const Error(PlatformError('Network unreachable')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Coordinator must wait for network without attempting connect
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectWaitingForNetwork>(),
        );
        expect(
          find.text('Waiting for network connectivity...'),
          findsOneWidget,
        );
        expect(
          engine.startCalls.length,
          equals(1),
        ); // No futile connect attempt!

        // Advance time: still waiting, no connects
        await tester.pump(const Duration(seconds: 5));
        expect(engine.startCalls.length, equals(1));

        // Network returns online (Airplane mode off)
        fakeConnectivity.emit(const [ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 100));

        // Now backoff begins
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectBackoff>(),
        );

        await tester.pump(const Duration(seconds: 1));
        expect(engine.startCalls.length, equals(2));

        engine.emit(const Connected());
        await tester.pumpAndSettle();
        expect(find.text('Tunnel: Connected'), findsOneWidget);
      },
    );

    testWidgets(
      'User cancellation: Disconnect button cancels reconnect mid-backoff',
      (tester) async {
        final profile = await _seedServer(dataSource);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );
        final metricsSub = container.listen(
          sessionTrafficMetricsProvider,
          (previous, next) {},
        );
        addTearDown(metricsSub.close);

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Engine unexpected drop
        engine.emit(const Error(PlatformError('Server died')));
        await tester.pump();

        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectBackoff>(),
        );

        // User cancels / disconnects mid-backoff
        await container
            .read(connectionControllerProvider.notifier)
            .disconnect();
        await tester.pump();

        expect(
          container.read(autoReconnectProvider),
          equals(const AutoReconnectIdle()),
        );
        expect(
          container.read(autoReconnectProvider.notifier).isUserSessionActive,
          isFalse,
        );

        // Advance timer past the backoff window
        await tester.pump(const Duration(seconds: 5));
        // No second start occurred
        expect(engine.startCalls.length, equals(1));
      },
    );

    testWidgets(
      'Retry exhaustion: Fails up to maxRetries (5) and stops cleanly',
      (tester) async {
        final profile = await _seedServer(dataSource);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );
        final metricsSub = container.listen(
          sessionTrafficMetricsProvider,
          (previous, next) {},
        );
        addTearDown(metricsSub.close);

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // 1. Initial drop
        engine.emit(const Error(PlatformError('Drop 0')));
        await tester.pump();

        // Attempt 1 (1s backoff)
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectBackoff>(),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(engine.startCalls.length, equals(2));
        engine.emit(const Error(PlatformError('Fail 1')));
        await tester.pump();

        // Attempt 2 (2s backoff)
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectBackoff>(),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(engine.startCalls.length, equals(3));
        engine.emit(const Error(PlatformError('Fail 2')));
        await tester.pump();

        // Attempt 3 (4s backoff)
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectBackoff>(),
        );
        await tester.pump(const Duration(seconds: 4));
        expect(engine.startCalls.length, equals(4));
        engine.emit(const Error(PlatformError('Fail 3')));
        await tester.pump();

        // Attempt 4 (8s backoff)
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectBackoff>(),
        );
        await tester.pump(const Duration(seconds: 8));
        expect(engine.startCalls.length, equals(5));
        engine.emit(const Error(PlatformError('Fail 4')));
        await tester.pump();

        // Attempt 5 (16s backoff)
        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectBackoff>(),
        );
        await tester.pump(const Duration(seconds: 16));
        expect(engine.startCalls.length, equals(6));
        engine.emit(const Error(PlatformError('Fail 5')));
        await tester.pump();

        // Retries exhausted!
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          container.read(autoReconnectProvider),
          equals(const AutoReconnectExhausted(totalAttempts: 5)),
        );
        expect(
          container.read(autoReconnectProvider.notifier).isUserSessionActive,
          isFalse,
        );
        expect(
          find.byKey(const ValueKey<String>('session_auto_reconnect_text')),
          findsOneWidget,
        );
        expect(
          find.text('Auto-reconnect failed after 5 attempts'),
          findsOneWidget,
        );

        // Advance further time: no more start calls
        await tester.pump(const Duration(seconds: 60));
        expect(engine.startCalls.length, equals(6));
      },
    );

    testWidgets(
      'Non-recoverable errors: InvalidConfig or PermissionDenied aborts '
      'session without retries',
      (tester) async {
        final profile = await _seedServer(dataSource);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );
        final metricsSub = container.listen(
          sessionTrafficMetricsProvider,
          (previous, next) {},
        );
        addTearDown(metricsSub.close);

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        expect(
          container.read(autoReconnectProvider.notifier).isUserSessionActive,
          isTrue,
        );

        // Emit non-recoverable InvalidConfig error
        engine.emit(const Error(InvalidConfig()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // AutoReconnect should be Idle and user session cancelled
        expect(
          container.read(autoReconnectProvider),
          equals(const AutoReconnectIdle()),
        );
        expect(
          container.read(autoReconnectProvider.notifier).isUserSessionActive,
          isFalse,
        );

        // Advance 5 seconds: no reconnect attempt dispatched
        await tester.pump(const Duration(seconds: 5));
        expect(engine.startCalls.length, equals(1));

        // Reconnect and verify PermissionDenied also cancels session
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        expect(
          container.read(autoReconnectProvider.notifier).isUserSessionActive,
          isTrue,
        );

        engine.emit(const Error(PermissionDenied()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          container.read(autoReconnectProvider),
          equals(const AutoReconnectIdle()),
        );
        expect(
          container.read(autoReconnectProvider.notifier).isUserSessionActive,
          isFalse,
        );
      },
    );

    testWidgets(
      'Rapid network flapping resilience: 10 rapid transitions coalesce '
      'cleanly',
      (tester) async {
        final profile = await _seedServer(dataSource);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );
        final metricsSub = container.listen(
          sessionTrafficMetricsProvider,
          (previous, next) {},
        );
        addTearDown(metricsSub.close);

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Emit 10 rapid transitions within 200ms ending on a different
        // interface.
        for (var i = 0; i < 10; i++) {
          final res = i.isEven
              ? ConnectivityResult.wifi
              : ConnectivityResult.mobile;
          fakeConnectivity.emit([res]);
          await tester.pump(const Duration(milliseconds: 20));
        }

        // Wait for debounce (300ms) to settle
        await tester.pump(const Duration(milliseconds: 350));

        // Old tunnel stopped exactly once
        expect(engine.stopCalls, equals(1));

        engine.emit(const Disconnected());
        await tester.pump();

        // Reconnect backoff runs cleanly
        await tester.pump(const Duration(seconds: 1));
        expect(engine.startCalls.length, equals(2));

        engine.emit(const Connected());
        await tester.pumpAndSettle();
        expect(find.text('Tunnel: Connected'), findsOneWidget);
      },
    );

    testWidgets(
      'User preference disabled: Setting auto_reconnect_enabled to false '
      'prevents reconnect',
      (tester) async {
        final profile = await _seedServer(dataSource);
        await fakePrefs.setAutoReconnectEnabled(enabled: false);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );
        final metricsSub = container.listen(
          sessionTrafficMetricsProvider,
          (previous, next) {},
        );
        addTearDown(metricsSub.close);

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Engine drop
        engine.emit(const Error(PlatformError('Unexpected drop')));
        await tester.pump();

        // Does NOT reconnect
        expect(
          container.read(autoReconnectProvider),
          equals(const AutoReconnectIdle()),
        );
        await tester.pump(const Duration(seconds: 5));
        expect(engine.startCalls.length, equals(1));
      },
    );

    testWidgets(
      'Phase 6 integration: SessionDuration and TrafficMetrics reset cleanly '
      'across auto-reconnect',
      (tester) async {
        final profile = await _seedServer(dataSource);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: engine,
          dataSource: dataSource,
          connectivitySource: fakeConnectivity,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );
        final metricsSub = container.listen(
          sessionTrafficMetricsProvider,
          (previous, next) {},
        );
        addTearDown(metricsSub.close);

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Advance 3s duration
        await tester.pump(const Duration(seconds: 3));
        expect(
          container.read(sessionDurationProvider),
          equals(const Duration(seconds: 3)),
        );

        // Emit traffic stats
        final t0 = DateTime.utc(2026, 11, 5, 12);
        engine.emitStats(
          TrafficStats(txBytes: 1024, rxBytes: 2048, timestamp: t0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final t1 = t0.add(const Duration(seconds: 1));
        engine.emitStats(
          TrafficStats(txBytes: 2048, rxBytes: 4096, timestamp: t1),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          container.read(sessionTrafficMetricsProvider).txBytesPerSec,
          greaterThan(0),
        );

        // Sudden drop
        engine.emit(const Error(PlatformError('Drop')));
        await tester.pump();

        // Verified: Duration and Traffic metrics are reset immediately
        expect(container.read(sessionDurationProvider), equals(Duration.zero));
        expect(
          container.read(sessionTrafficMetricsProvider).txBytesPerSec,
          equals(0),
        );
        expect(
          container.read(sessionTrafficMetricsProvider).rxBytesPerSec,
          equals(0),
        );

        // Advance backoff and reconnect
        await tester.pump(const Duration(seconds: 1));
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Duration timer starts fresh from 0
        expect(container.read(sessionDurationProvider), equals(Duration.zero));
        await tester.pump(const Duration(seconds: 2));
        expect(
          container.read(sessionDurationProvider),
          equals(const Duration(seconds: 2)),
        );
      },
    );

    testWidgets('Defect D2 regression: engine.stop() emitting Disconnecting -> '
        'Disconnected during _executeReconnect() increments currentAttempt '
        'by 1, not 2', (tester) async {
      final profile = await _seedServer(dataSource);
      final emittingEngine = _EmittingStopFakeVpnEngine();

      await pumpConnectionMaterialApp(
        tester,
        const Scaffold(body: SessionInfoPanel()),
        engine: emittingEngine,
        dataSource: dataSource,
        connectivitySource: fakeConnectivity,
        preferencesRepository: fakePrefs,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionInfoPanel)),
      );

      // Initial connect
      await container
          .read(connectionControllerProvider.notifier)
          .connect(profile);
      emittingEngine.emit(const Connected());
      await tester.pumpAndSettle();

      // Unexpected drop triggers attempt 1
      emittingEngine.emit(const Error(PlatformError('Tunnel dropped')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final reconnect = container.read(autoReconnectProvider);
      expect(reconnect, isA<AutoReconnectBackoff>());
      expect((reconnect as AutoReconnectBackoff).attempt, equals(1));

      // Advance 1s backoff timer to fire _executeReconnect()
      // During _executeReconnect(), emittingEngine.stop() emits
      // Disconnecting -> Disconnected.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));

      final notifier = container.read(autoReconnectProvider.notifier);
      // Attempt count must remain 1, not 2
      expect(notifier.currentAttempt, equals(1));
      expect(
        container.read(autoReconnectProvider),
        isA<AutoReconnectInFlight>(),
      );

      // Tunnel comes back up
      emittingEngine.emit(const Connected());
      await tester.pumpAndSettle();

      expect(
        container.read(autoReconnectProvider),
        equals(const AutoReconnectIdle()),
      );
      expect(notifier.currentAttempt, equals(0));

      await emittingEngine.dispose();
    });

    testWidgets('Defects D3 & D4 regression: mid-connection server switch and '
        'rejected engine.start() do not trigger false auto-reconnect', (
      tester,
    ) async {
      final repo = buildRepository(dataSource);
      await repo.addServer(_testVlessUri);
      const server2Uri =
          'vless://22222222-3333-4444-5555-666666666666@example.org:443#Osaka';
      await repo.addServer(server2Uri);
      final servers = await repo.loadServers();
      final profile1 = (servers[0] as SavedServerProfile).profile;
      final profile2 = (servers[1] as SavedServerProfile).profile;

      await pumpConnectionMaterialApp(
        tester,
        const Scaffold(body: SessionInfoPanel()),
        engine: engine,
        dataSource: dataSource,
        connectivitySource: fakeConnectivity,
        preferencesRepository: fakePrefs,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionInfoPanel)),
      );

      // Connect to server 1
      await container
          .read(connectionControllerProvider.notifier)
          .connect(profile1);
      engine.emit(const Connected());
      await tester.pumpAndSettle();

      // Mid-connection switch to server 2 (D3)
      await container
          .read(connectionControllerProvider.notifier)
          .connect(profile2);
      // During switch, engine.stop() was called; auto-reconnect must NOT be
      // triggered
      expect(
        container.read(autoReconnectProvider),
        equals(const AutoReconnectIdle()),
      );

      // Subtest D4: Rejected engine.start() cleanly disarms session
      final rejectingEngine = _RejectingStartFakeVpnEngine(
        const VpnCommandRejectedInvalidConfig(),
      );
      await pumpConnectionMaterialApp(
        tester,
        const Scaffold(body: SessionInfoPanel()),
        engine: rejectingEngine,
        dataSource: dataSource,
        connectivitySource: fakeConnectivity,
        preferencesRepository: fakePrefs,
      );
      final container2 = ProviderScope.containerOf(
        tester.element(find.byType(SessionInfoPanel)),
      );

      final result = await container2
          .read(connectionControllerProvider.notifier)
          .connect(profile1);
      expect(result, isA<VpnCommandRejectedInvalidConfig>());

      // Coordinator is cleanly disarmed
      expect(
        container2.read(autoReconnectProvider.notifier).isUserSessionActive,
        isFalse,
      );
      expect(
        container2.read(autoReconnectProvider),
        equals(const AutoReconnectIdle()),
      );

      await rejectingEngine.dispose();
    });
  });
}

class _EmittingStopFakeVpnEngine extends FakeVpnEngine {
  @override
  Future<VpnCommandResult> stop() async {
    stopCalls++;
    emit(const Disconnecting());
    emit(const Disconnected());
    return const VpnCommandAccepted();
  }
}

class _RejectingStartFakeVpnEngine extends FakeVpnEngine {
  _RejectingStartFakeVpnEngine(this.rejection);

  final VpnCommandResult rejection;

  @override
  Future<VpnCommandResult> start(ServerProfile profile) async {
    startCalls.add(profile);
    return rejection;
  }
}
