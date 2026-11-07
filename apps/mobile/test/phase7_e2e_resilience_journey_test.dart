// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Disconnected,
        Error,
        PlatformError,
        ServerProfile,
        TrafficStats;
import 'package:core_vpn_engine/core_vpn_engine.dart'
    show VpnCommandAccepted, VpnCommandRejectedBusy;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
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

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeVpnEngine engine,
  required FakeServerProfileDataSource dataSource,
  required FakeConnectivitySource fakeConnectivity,
  required AppPreferencesRepository fakePrefs,
  required FakeKillSwitchPlatformBridge fakeBridge,
}) async {
  await tester.pumpWidget(
    localizedApp(
      overrides: [
        initialConnectionStateProvider.overrideWithValue(engine.lastState),
        vpnEngineProvider.overrideWithValue(engine),
        serverProfileRepositoryProvider.overrideWith(
          (ref) async => buildRepository(dataSource),
        ),
        connectivitySourceProvider.overrideWithValue(fakeConnectivity),
        appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
        killSwitchPlatformBridgeProvider.overrideWithValue(fakeBridge),
      ],
      child: localizedMaterialApp(home: const HomeScreen()),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  // Frame-0 check: zero "Disconnected" flash when engine was Connected
  if (engine.lastState is Connected) {
    expect(find.text('Disconnected'), findsNothing);
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestLocalization);

  late Directory testTempDir;

  setUp(() async {
    testTempDir = await Directory.systemTemp.createTemp(
      'phase7_resilience_journey_',
    );
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

  group('P7-T7 Phase 7 Combined Resilience Stress Journey', () {
    testWidgets('Stages A through E: Full end-to-end multi-stage real-world '
        'resilience stress test', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dataSource = FakeServerProfileDataSource();
      final tokyoProfile = await _seedServer(
        dataSource,
        'vless://11111111-2222-3333-4444-555555555555@tokyo.example.com:443'
        '?sni=tokyo.example.com#Tokyo%20Node',
      );
      final osakaProfile = await _seedServer(
        dataSource,
        'vless://22222222-3333-4444-5555-666666666666@osaka.example.com:443'
        '?sni=osaka.example.com#Osaka%20Node',
      );

      final engine = FakeVpnEngine();
      final fakeConnectivity = FakeConnectivitySource();
      final fakePrefs = FakeAppPreferencesRepository(
        initialKillSwitchEnabled: true,
      );
      final fakeBridge = FakeKillSwitchPlatformBridge();

      // ---------------------------------------------------------------------
      // STAGE A: Initial Connect to Tokyo Node (Domain Endpoint & SNI)
      // ---------------------------------------------------------------------
      await _pumpApp(
        tester,
        engine: engine,
        dataSource: dataSource,
        fakeConnectivity: fakeConnectivity,
        fakePrefs: fakePrefs,
        fakeBridge: fakeBridge,
      );

      var container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      var controller = container.read(connectionControllerProvider.notifier);

      // Verify clean initial baseline
      expect(
        container.read(connectionStateProvider).value,
        isA<Disconnected>(),
      );
      expect(container.read(killSwitchProvider), isA<KillSwitchInactive>());
      expect(fakeBridge.isCurrentlyBlocking, isFalse);
      expect(container.read(autoReconnectProvider), isA<AutoReconnectIdle>());

      // Connect to Tokyo Node
      await container
          .read(activeServerIdProvider.notifier)
          .selectServer(tokyoProfile.id);
      final connectRes = await controller.connect(tokyoProfile);
      expect(connectRes, isA<VpnCommandAccepted>());
      engine.emit(const Connected());
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(connectionStateProvider).value, isA<Connected>());
      expect(container.read(killSwitchProvider), isA<KillSwitchArmed>());
      expect(fakeBridge.isCurrentlyBlocking, isFalse);
      expect(
        container.read(autoReconnectProvider.notifier).isUserSessionActive,
        isTrue,
      );
      expect(find.textContaining('Tokyo Node'), findsWidgets);

      // Verify session duration ticking
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Duration: 00:00:02'), findsOneWidget);

      // Verify traffic stats flowing
      engine.emitStats(
        TrafficStats(txBytes: 1024, rxBytes: 2048, timestamp: DateTime.now()),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1.0 KiB up / 2.0 KiB down'), findsOneWidget);

      // Verify live logs captured
      engine.emitLog(
        '2026-11-06 12:00:00 INFO Initial tunnel handshake verified',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container
            .read(structuredLogEntriesProvider)
            .any((l) => l.raw.contains('Initial tunnel handshake verified')),
        isTrue,
      );

      // ---------------------------------------------------------------------
      // STAGE B: Wi-Fi to Cellular Handoff (Auto-Reconnect Recovery)
      // ---------------------------------------------------------------------
      fakeConnectivity.emit(const [ConnectivityResult.mobile]);
      // Advance past 350ms debounce
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      // Engine was cleanly stopped for reconnection
      expect(engine.stopCalls, equals(1));
      // Engine transitions through drop
      engine.emit(const Disconnected());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Native lockdown blocking engaged immediately
      expect(fakeBridge.isCurrentlyBlocking, isTrue);
      expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
      expect(
        find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
        findsOneWidget,
      );
      expect(
        container.read(autoReconnectProvider),
        isA<AutoReconnectBackoff>(),
      );
      expect(
        (container.read(autoReconnectProvider) as AutoReconnectBackoff).attempt,
        equals(1),
      );

      // Advance 1s backoff timer -> auto-reconnect initiates engine.start
      await tester.pump(const Duration(seconds: 1));
      expect(engine.startCalls, contains(tokyoProfile));

      // Tunnel re-establishes
      engine.emit(const Connected());
      await tester.pumpAndSettle();

      expect(container.read(connectionStateProvider).value, isA<Connected>());
      expect(container.read(killSwitchProvider), isA<KillSwitchArmed>());
      expect(fakeBridge.isCurrentlyBlocking, isFalse);
      expect(
        find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
        findsNothing,
      );
      expect(container.read(autoReconnectProvider), isA<AutoReconnectIdle>());

      // ---------------------------------------------------------------------
      // STAGE C: Airplane Mode Outage Hold & Recovery
      // ---------------------------------------------------------------------
      fakeConnectivity.emit(const [ConnectivityResult.none]);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      engine.emit(const Error(PlatformError('Network dropped offline')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        container.read(autoReconnectProvider),
        isA<AutoReconnectWaitingForNetwork>(),
      );
      expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
      expect(fakeBridge.isCurrentlyBlocking, isTrue);

      // Outage hold: advance 5 seconds while offline -> ZERO futile start
      // calls
      final startCallsBeforeOutage = engine.startCalls.length;
      await tester.pump(const Duration(seconds: 5));
      expect(engine.startCalls.length, equals(startCallsBeforeOutage));

      // Restore Wi-Fi connectivity
      fakeConnectivity.emit(const [ConnectivityResult.wifi]);
      // Wait 350ms debounce -> transitions to AutoReconnectBackoff
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        container.read(autoReconnectProvider),
        isA<AutoReconnectBackoff>(),
      );

      // Advance 1s backoff -> triggers engine.start
      await tester.pump(const Duration(seconds: 1));
      expect(engine.startCalls.length, equals(startCallsBeforeOutage + 1));

      // Reconnect succeeds
      engine.emit(const Connected());
      await tester.pumpAndSettle();

      expect(container.read(connectionStateProvider).value, isA<Connected>());
      expect(container.read(killSwitchProvider), isA<KillSwitchArmed>());
      expect(fakeBridge.isCurrentlyBlocking, isFalse);
      expect(container.read(autoReconnectProvider), isA<AutoReconnectIdle>());

      // ---------------------------------------------------------------------
      // STAGE D: Mid-Session UI Process Kill & Relaunch
      // ---------------------------------------------------------------------
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Native engine remains connected in background service
      expect(engine.lastState, isA<Connected>());

      // Relaunch UI (Session 2) against running engine
      await _pumpApp(
        tester,
        engine: engine,
        dataSource: dataSource,
        fakeConnectivity: fakeConnectivity,
        fakePrefs: fakePrefs,
        fakeBridge: fakeBridge,
      );

      container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      controller = container.read(connectionControllerProvider.notifier);

      // Zero "Disconnected" flash: authoritative state is Connected
      // immediately
      expect(find.text('Disconnected'), findsNothing);
      expect(container.read(connectionStateProvider).value, isA<Connected>());
      expect(find.textContaining('Tokyo Node'), findsWidgets);
      expect(container.read(killSwitchProvider), isA<KillSwitchArmed>());
      expect(
        container.read(autoReconnectProvider.notifier).isUserSessionActive,
        isTrue,
      );

      // Verify session duration resumes ticking in relaunched process
      await tester.pump(const Duration(seconds: 2));
      expect(
        container.read(sessionDurationProvider).inSeconds,
        greaterThanOrEqualTo(2),
      );
      expect(find.textContaining('Duration:'), findsOneWidget);

      // Verify traffic stats resume streaming in relaunched process
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

      // Verify live logs resume capturing in relaunched process
      engine.emitLog('2026-11-06 12:00:00 INFO Resumed log line in Stage D');
      await tester.pump(const Duration(milliseconds: 100));
      final stageDLogs = container.read(structuredLogEntriesProvider);
      expect(
        stageDLogs.any((l) => l.raw.contains('Resumed log line in Stage D')),
        isTrue,
      );

      // Duplicate start prevention: connect(tokyoProfile) returns
      // rejectedBusy
      final dupRes = await controller.connect(tokyoProfile);
      expect(dupRes, isA<VpnCommandRejectedBusy>());

      // Clean server switch to Osaka Node
      await container
          .read(activeServerIdProvider.notifier)
          .selectServer(osakaProfile.id);
      await tester.pumpAndSettle();

      final switchRes = await controller.connect(osakaProfile);
      expect(switchRes, isA<VpnCommandAccepted>());
      expect(engine.startCalls, contains(osakaProfile));

      engine.emit(const Connected());
      await tester.pumpAndSettle();

      expect(container.read(activeServerProvider)?.id, equals(osakaProfile.id));
      expect(find.textContaining('Osaka Node'), findsWidgets);

      // ---------------------------------------------------------------------
      // STAGE E: 5-Attempt Retry Exhaustion on Osaka Node & Clean Unblock
      // ---------------------------------------------------------------------
      // Attempt 1: Drop induces AutoReconnectBackoff (attempt: 1, delay: 1s)
      engine.emit(const Error(PlatformError('Drop 1')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        (container.read(autoReconnectProvider) as AutoReconnectBackoff).attempt,
        equals(1),
      );
      expect(fakeBridge.isCurrentlyBlocking, isTrue);

      await tester.pump(const Duration(seconds: 1));
      engine.emit(const Error(PlatformError('Start 1 failed')));
      await tester.pump(const Duration(milliseconds: 100));

      // Attempt 2: delay 2s
      expect(
        (container.read(autoReconnectProvider) as AutoReconnectBackoff).attempt,
        equals(2),
      );
      await tester.pump(const Duration(seconds: 2));
      engine.emit(const Error(PlatformError('Start 2 failed')));
      await tester.pump(const Duration(milliseconds: 100));

      // Attempt 3: delay 4s
      expect(
        (container.read(autoReconnectProvider) as AutoReconnectBackoff).attempt,
        equals(3),
      );
      await tester.pump(const Duration(seconds: 4));
      engine.emit(const Error(PlatformError('Start 3 failed')));
      await tester.pump(const Duration(milliseconds: 100));

      // Attempt 4: delay 8s
      expect(
        (container.read(autoReconnectProvider) as AutoReconnectBackoff).attempt,
        equals(4),
      );
      await tester.pump(const Duration(seconds: 8));
      engine.emit(const Error(PlatformError('Start 4 failed')));
      await tester.pump(const Duration(milliseconds: 100));

      // Attempt 5: delay 16s
      expect(
        (container.read(autoReconnectProvider) as AutoReconnectBackoff).attempt,
        equals(5),
      );
      await tester.pump(const Duration(seconds: 16));
      engine.emit(const Error(PlatformError('Start 5 failed')));
      await tester.pump(const Duration(milliseconds: 100));

      // Ceiling reached: AutoReconnectExhausted(totalAttempts: 5)
      expect(
        container.read(autoReconnectProvider),
        isA<AutoReconnectExhausted>(),
      );
      expect(
        (container.read(
          autoReconnectProvider,
        ) as AutoReconnectExhausted).totalAttempts,
        equals(5),
      );
      // Fail-closed lockdown remains engaged
      expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
      expect(fakeBridge.isCurrentlyBlocking, isTrue);
      expect(
        find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
        findsOneWidget,
      );

      // Tap unblock button to disengage lockdown and reset to clean baseline
      await tester.tap(
        find.byKey(const ValueKey<String>('kill_switch_unblock_button')),
      );
      engine.emit(const Disconnected());
      await tester.pumpAndSettle();

      expect(
        container.read(connectionStateProvider).value,
        isA<Disconnected>(),
      );
      expect(container.read(killSwitchProvider), isA<KillSwitchInactive>());
      expect(fakeBridge.isCurrentlyBlocking, isFalse);
      expect(container.read(autoReconnectProvider), isA<AutoReconnectIdle>());
      expect(
        find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
        findsNothing,
      );
    });
  });
}
