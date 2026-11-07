// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        ConnectionState,
        Disconnected,
        Error,
        PlatformError,
        ServerProfile,
        TrafficStats;
import 'package:core_vpn_engine/core_vpn_engine.dart'
    show VpnCommandAccepted, VpnCommandRejectedBusy;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/bootstrap/app_bootstrap.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/connection/presentation/providers/session_duration_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';

import 'localization_test_harness.dart';

Future<ServerProfile> _seedServer(
  FakeServerProfileDataSource ds,
  String uri,
) async {
  final repo = buildRepository(ds);
  await repo.addServer(uri);
  final lastRecord = ds.records.last;
  final servers = await repo.loadServers();
  return servers
      .whereType<SavedServerProfile>()
      .firstWhere((s) => s.id == lastRecord.id)
      .profile;
}

class _DelayedStatusVpnEngine extends FakeVpnEngine {
  _DelayedStatusVpnEngine() {
    lastState = const Connected();
  }

  static const Duration statusDelay = Duration(milliseconds: 200);

  @override
  Future<ConnectionState> getStatus() async {
    await Future<void>.delayed(statusDelay);
    return lastState;
  }
}

void main() {
  setUpAll(initTestLocalization);

  group('P7-T6 VPN State Persistence Across App Process Restart', () {
    testWidgets('Test 1: Full UI process kill and relaunch re-attaches to '
        'active VPN session', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dataSource = FakeServerProfileDataSource();
      final profile = await _seedServer(
        dataSource,
        'vless://11111111-2222-3333-4444-555555555555@example.com:443#Tokyo%20Node',
      );
      final fakePrefs = FakeAppPreferencesRepository(
        initialKillSwitchEnabled: true,
      );
      final engine = FakeVpnEngine();

      // 1. Initial Launch (Session 1)
      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
        preferencesRepository: fakePrefs,
      );

      var container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      final controller = container.read(connectionControllerProvider.notifier);

      // Connect
      final res = await controller.connect(profile);
      expect(res, isA<VpnCommandAccepted>());
      engine.emit(const Connected());
      await tester.pumpAndSettle();

      expect(container.read(connectionStateProvider).value, isA<Connected>());
      expect(container.read(activeServerProvider)?.id, equals(profile.id));
      expect(container.read(killSwitchProvider), isA<KillSwitchArmed>());
      expect(
        container.read(autoReconnectProvider.notifier).isUserSessionActive,
        isTrue,
      );

      // Emit stats and advance duration
      final t0 = DateTime.now();
      engine.emitStats(
        TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        container.read(sessionDurationProvider).inSeconds,
        greaterThanOrEqualTo(2),
      );

      // 2. Simulate UI process kill: unmount & dispose old container
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Background service remains connected
      expect(engine.lastState, isA<Connected>());

      // In fakeAsync, wall-clock DateTime.now() does not advance when pumping.
      // Adjust the persisted session start timestamp by 2 seconds to simulate
      // the real-world time elapsed during Session 1.
      final startedAt = fakePrefs.getActiveSessionStartedAt();
      if (startedAt != null) {
        await fakePrefs.setActiveSessionStartedAt(
          startedAt.subtract(const Duration(seconds: 2)),
        );
      }

      // 3. Relaunch UI (Session 2) with persistent engine & storage
      await pumpConnectionMaterialApp(
        tester,
        const HomeScreen(),
        engine: engine,
        dataSource: dataSource,
        preferencesRepository: fakePrefs,
      );

      container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );

      // Authoritative connection state is Connected immediately upon settling
      expect(container.read(connectionStateProvider).value, isA<Connected>());
      expect(container.read(activeServerProvider)?.id, equals(profile.id));
      expect(find.textContaining('Tokyo Node'), findsWidgets);

      // Coordinators re-arm
      expect(container.read(killSwitchProvider), isA<KillSwitchArmed>());
      expect(
        container.read(autoReconnectProvider.notifier).isUserSessionActive,
        isTrue,
      );

      // Duration timer resumes ticking for re-attached session,
      // preserving elapsed time
      await tester.pump(const Duration(seconds: 3));
      expect(
        container.read(sessionDurationProvider).inSeconds,
        greaterThanOrEqualTo(5),
      );
      expect(find.text('Duration: 00:00:05'), findsOneWidget);

      // Two TrafficStats snapshots continue flowing into active session
      final now = DateTime.now();
      engine.emitStats(
        TrafficStats(txBytes: 1024, rxBytes: 2048, timestamp: now),
      );
      await tester.pump(const Duration(seconds: 1));
      engine.emitStats(
        TrafficStats(
          txBytes: 3072,
          rxBytes: 6144,
          timestamp: now.add(const Duration(seconds: 1)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('3.0 KiB up / 6.0 KiB down'), findsOneWidget);
      expect(find.text('Speed: ↑ 2.0 KiB/s · ↓ 4.0 KiB/s'), findsOneWidget);

      // Live log capture via structuredLogEntriesProvider
      engine.emitLog('2026-11-06 12:00:00 INFO Post-restart log line');
      await tester.pump(const Duration(milliseconds: 100));
      final logs = container.read(structuredLogEntriesProvider);
      expect(logs.any((l) => l.raw.contains('Post-restart log line')), isTrue);

      // Post-relaunch unexpected drop engages KillSwitchBlocking and
      // AutoReconnectBackoff
      engine.emit(const Error(PlatformError('Post-relaunch drop')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
      expect(
        container.read(autoReconnectProvider),
        isA<AutoReconnectBackoff>(),
      );
      expect(
        find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
        findsOneWidget,
      );

      // Advance 1s backoff -> auto reconnect dispatches engine.start
      await tester.pump(const Duration(seconds: 1));
      expect(engine.startCalls, contains(profile));
      engine.emit(const Connected());
      await tester.pumpAndSettle();
      expect(container.read(connectionStateProvider).value, isA<Connected>());
      expect(container.read(killSwitchProvider), isA<KillSwitchArmed>());
      expect(container.read(autoReconnectProvider), isA<AutoReconnectIdle>());

      // Server switching connects cleanly to a second profile
      final profile2 = await _seedServer(
        dataSource,
        'vless://22222222-3333-4444-5555-666666666666@example.com:443#Osaka%20Node',
      );
      container.invalidate(savedServersProvider);
      await tester.pumpAndSettle();
      final switchRes = await container
          .read(connectionControllerProvider.notifier)
          .connect(profile2);
      expect(switchRes, isA<VpnCommandAccepted>());
      await container
          .read(activeServerIdProvider.notifier)
          .selectServer(profile2.id);
      expect(engine.stopCalls, equals(2));
      expect(engine.startCalls, contains(profile2));
      engine.emit(const Connected());
      await tester.pumpAndSettle();
      expect(container.read(activeServerProvider)?.id, equals(profile2.id));
      expect(find.textContaining('Osaka Node'), findsWidgets);

      // Clean disconnect works in relaunched process
      final discRes = await container
          .read(connectionControllerProvider.notifier)
          .disconnect();
      expect(discRes, isA<VpnCommandAccepted>());
      engine.emit(const Disconnected());
      await tester.pumpAndSettle();
      expect(
        container.read(connectionStateProvider).value,
        isA<Disconnected>(),
      );
      expect(container.read(killSwitchProvider), isA<KillSwitchInactive>());
    });

    testWidgets(
      'Test 2: Zero "Disconnected" flash during async getStatus() and '
      'instant Connected with pre-warm',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final delayedEngine = _DelayedStatusVpnEngine();

        // Case A: Launch without pre-warm, while getStatus() is in-flight
        await tester.pumpWidget(
          localizedApp(
            overrides: [vpnEngineProvider.overrideWithValue(delayedEngine)],
            child: localizedMaterialApp(home: const HomeScreen()),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();

        // On initial frame before 200ms delay elapses:
        // ConnectionStateBadge shows "Checking...", NOT "Disconnected"
        final badgeChip = tester.widget<Chip>(
          find.byKey(const ValueKey<String>('connection_state_badge')),
        );
        expect((badgeChip.label as Text).data, equals('Checking...'));
        expect(find.text('Disconnected'), findsNothing);

        // Also check SessionInfoPanel renders "Checking..."
        expect(
          find.byKey(const ValueKey<String>('session_status_text')),
          findsOneWidget,
        );
        expect(find.text('Tunnel: Checking...'), findsOneWidget);
        expect(find.textContaining('Disconnected'), findsNothing);

        // Advance past the 200ms delay so getStatus() completes
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();

        // State settles on Connected
        expect(find.text('Connected'), findsWidgets);

        // Case B: Launch with AppBootstrap.init pre-warming
        final dataSource = FakeServerProfileDataSource();
        final profile = await _seedServer(
          dataSource,
          'vless://11111111-2222-3333-4444-555555555555@example.com:443#Tokyo%20Node',
        );
        final repo = buildRepository(dataSource);
        final fakePrefs = FakeAppPreferencesRepository(
          initialActiveServerId: profile.id,
        );

        final prewarmedContainer = await tester.runAsync(
          () => AppBootstrap.init(
            vpnEngineOverride: delayedEngine,
            serverProfileRepositoryOverride: repo,
            preferencesRepositoryOverride: fakePrefs,
            ensureBinding: false,
            ensureLocalization: false,
          ),
        );
        expect(prewarmedContainer, isNotNull);
        addTearDown(prewarmedContainer!.dispose);

        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const <Locale>[Locale('en'), Locale('de')],
            path: 'assets/translations',
            startLocale: const Locale('en'),
            fallbackLocale: const Locale('en'),
            saveLocale: false,
            assetLoader: TestAssetLoader(),
            child: UncontrolledProviderScope(
              container: prewarmedContainer,
              child: localizedMaterialApp(home: const HomeScreen()),
            ),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();

        // On frame 0, pre-warmed state is already Connected
        final prewarmedBadge = tester.widget<Chip>(
          find.byKey(const ValueKey<String>('connection_state_badge')),
        );
        expect((prewarmedBadge.label as Text).data, equals('Connected'));
        expect(find.text('Checking...'), findsNothing);
        expect(find.text('Disconnected'), findsNothing);

        // Frame-0 assertions: SessionInfoPanel already displays Tunnel & Server
        expect(find.text('Tunnel: Connected'), findsOneWidget);
        expect(find.text('Server: Tokyo Node (vless)'), findsOneWidget);

        // Frame-0 assertion: HomeScreen connect button already shows Disconnect
        expect(find.widgetWithText(FilledButton, 'Disconnect'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        prewarmedContainer.dispose();
      },
    );

    testWidgets(
      'Test 3: Duplicate session start prevention rejects busy for active '
      'server and cleanly switches for new server',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final dataSource = FakeServerProfileDataSource();
        final profile1 = await _seedServer(
          dataSource,
          'vless://11111111-2222-3333-4444-555555555555@example.com:443#Server%201',
        );
        final profile2 = await _seedServer(
          dataSource,
          'vless://22222222-3333-4444-5555-666666666666@example.com:443#Server%202',
        );
        final engine = FakeVpnEngine()..emit(const Connected());

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        expect(container.read(connectionStateProvider).value, isA<Connected>());
        // Active server defaults to most recently used server (Server 1)
        expect(container.read(activeServerProvider)?.id, equals(profile1.id));

        // 1. Calling connect(profile1) for active server is rejected as busy
        final dupRes = await controller.connect(profile1);
        expect(dupRes, isA<VpnCommandRejectedBusy>());
        // No redundant start or stop calls dispatched to engine
        expect(engine.startCalls, isEmpty);
        expect(engine.stopCalls, equals(0));

        // 2. Calling connect(profile2) for different server switches cleanly
        final switchRes = await controller.connect(profile2);
        expect(switchRes, isA<VpnCommandAccepted>());
        expect(engine.stopCalls, equals(1));
        expect(engine.startCalls, contains(profile2));
      },
    );

    testWidgets(
      'Test 4: Stale activeSessionStartedAt timestamp from a dead prior '
      'session is wiped on Disconnected cold boot and never pollutes a new '
      'connection',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final dataSource = FakeServerProfileDataSource();
        final profile = await _seedServer(
          dataSource,
          'vless://11111111-2222-3333-4444-555555555555@example.com:443#Stale%20Node',
        );

        // Simulate a stale session started 5 hours ago before OS killed both
        // UI and native VPN service
        final staleTimestamp = DateTime.now().toUtc().subtract(
          const Duration(hours: 5),
        );
        final fakePrefs = FakeAppPreferencesRepository(
          initialActiveSessionStartedAt: staleTimestamp,
        );
        final engine = FakeVpnEngine()..lastState = const Disconnected();

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
          preferencesRepository: fakePrefs,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        // 1. Initial state is Disconnected and stale timestamp was cleaned up
        expect(
          container.read(connectionStateProvider).value,
          isA<Disconnected>(),
        );
        expect(fakePrefs.getActiveSessionStartedAt(), isNull);
        expect(container.read(sessionDurationProvider), equals(Duration.zero));
        expect(find.text('Duration: 00:00:00'), findsOneWidget);

        // 2. User initiates new connection (Connecting -> Connected)
        final res = await controller.connect(profile);
        expect(res, isA<VpnCommandAccepted>());
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // 3. New session duration starts at 00:00:00 (NOT 05:00:00)
        expect(container.read(sessionDurationProvider), equals(Duration.zero));
        expect(find.text('Duration: 00:00:00'), findsOneWidget);
        expect(find.textContaining('05:00:'), findsNothing);

        // 4. Pump 2 seconds -> verify sessionDurationProvider is 2s
        // (Duration: 00:00:02), NOT 5 hours!
        await tester.pump(const Duration(seconds: 2));
        expect(container.read(sessionDurationProvider).inSeconds, equals(2));
        expect(find.text('Duration: 00:00:02'), findsOneWidget);
        expect(find.textContaining('05:00:'), findsNothing);

        // Clean up UI tree and fake timer
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  });
}
