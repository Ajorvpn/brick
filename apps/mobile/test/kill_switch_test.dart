// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        Disconnected,
        Disconnecting,
        Error,
        PlatformError,
        ServerProfile;
import 'package:core_vpn_engine/core_vpn_engine.dart'
    show VpnCommandRejectedInvalidConfig, VpnCommandResult;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/widgets/session_info_panel.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';

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

  group('KillSwitchState unit tests', () {
    test('State value equality and hashCode', () {
      const inactive1 = KillSwitchInactive();
      const inactive2 = KillSwitchInactive();
      expect(inactive1, equals(inactive2));
      expect(inactive1.hashCode, equals(inactive2.hashCode));

      const armed1 = KillSwitchArmed();
      const armed2 = KillSwitchArmed();
      expect(armed1, equals(armed2));
      expect(armed1.hashCode, equals(armed2.hashCode));
      expect(inactive1, isNot(equals(armed1)));

      const blocking1 = KillSwitchBlocking(reason: 'drop');
      const blocking2 = KillSwitchBlocking(reason: 'drop');
      const blockingDiff = KillSwitchBlocking(reason: 'other');
      expect(blocking1, equals(blocking2));
      expect(blocking1.hashCode, equals(blocking2.hashCode));
      expect(blocking1, isNot(equals(blockingDiff)));
      expect(blocking1, isNot(equals(armed1)));
    });
  });

  group('P7-T2 Kill Switch Lifecycle & Invariants', () {
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
      'Test 1: Default preference is false; toggling switch in SettingsScreen '
      'persists and updates killSwitchEnabledProvider',
      (tester) async {
        final fakePrefs = FakeAppPreferencesRepository();

        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const SettingsScreen()),
          overrides: [
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
          ],
        );

        expect(find.text('Kill Switch'), findsOneWidget);
        final killSwitchTile = find.byKey(
          const ValueKey<String>('settings_kill_switch_tile'),
        );
        expect(killSwitchTile, findsOneWidget);
        final switchFinder = find.descendant(
          of: killSwitchTile,
          matching: find.byType(Switch),
        );
        expect(switchFinder, findsOneWidget);
        expect(fakePrefs.isKillSwitchEnabled(), isFalse);

        // Toggle on
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(fakePrefs.isKillSwitchEnabled(), isTrue);

        // Toggle off
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(fakePrefs.isKillSwitchEnabled(), isFalse);
      },
    );

    testWidgets(
      'Test 2: With Kill Switch enabled, connecting enters KillSwitchArmed; '
      'unexpected connection drop / auto-reconnect window / exhaustion '
      'transitions to KillSwitchBlocking and renders banner',
      (tester) async {
        final profile = await _seedServer(dataSource);
        final fakePrefs = FakeAppPreferencesRepository(
          initialKillSwitchEnabled: true,
        );

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

        // 1. Initial boot: inactive before connect
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsNothing,
        );

        // 2. Connect
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connecting());
        await tester.pump();
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Kill switch is armed and protecting traffic
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchArmed()),
        );
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsNothing,
        );

        // 3. Unexpected connection drop mid-session
        engine.emit(const Error(PlatformError('Tunnel crashed')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Kill switch actively blocks traffic across auto-reconnect window
        expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsOneWidget,
        );
        expect(
          find.text('Kill Switch Active — Traffic Blocked'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('kill_switch_unblock_button')),
          findsOneWidget,
        );

        // 4. Exhaust retries to verify post-retry exhaustion risk window
        for (var i = 1; i <= 5; i++) {
          await tester.pump(Duration(seconds: 1 << (i - 1)));
          await tester.pump(const Duration(milliseconds: 100));
          engine.emit(Error(PlatformError('Fail $i')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          container.read(autoReconnectProvider),
          isA<AutoReconnectExhausted>(),
        );
        // Kill switch stays in blocking state after retry exhaustion!
        expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Test 3: With Kill Switch disabled, unexpected drop leaves Kill Switch '
      'in KillSwitchInactive and does NOT render banner',
      (tester) async {
        final profile = await _seedServer(dataSource);
        final fakePrefs = FakeAppPreferencesRepository();

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

        // Connect
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );

        // Unexpected drop
        engine.emit(const Error(PlatformError('Tunnel died')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Stays inactive, NO blocking banner rendered
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Test 4: Normal user-initiated connect -> connected -> disconnect flow '
      'transitions cleanly KillSwitchArmed -> KillSwitchInactive and NEVER '
      'falsely enters KillSwitchBlocking',
      (tester) async {
        final profile = await _seedServer(dataSource);
        final fakePrefs = FakeAppPreferencesRepository(
          initialKillSwitchEnabled: true,
        );

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

        // 1. Connect
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchArmed()),
        );

        // 2. Normal user disconnect
        await container
            .read(connectionControllerProvider.notifier)
            .disconnect();
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );

        engine.emit(const Disconnecting());
        await tester.pump();
        engine.emit(const Disconnected());
        await tester.pumpAndSettle();

        // Crucial safety invariant: Must remain inactive, NEVER blocked
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Test 5: While in KillSwitchBlocking, tapping kill_switch_unblock_button '
      '(or toggling kill switch off) immediately disengages to '
      'KillSwitchInactive and cancels auto-reconnect',
      (tester) async {
        final profile = await _seedServer(dataSource);
        final fakePrefs = FakeAppPreferencesRepository(
          initialKillSwitchEnabled: true,
        );

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

        // Connect then drop to enter blocking
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        engine.emit(const Error(PlatformError('Tunnel dropped')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsOneWidget,
        );

        // Tap unblock button
        await tester.tap(
          find.byKey(const ValueKey<String>('kill_switch_unblock_button')),
        );
        await tester.pumpAndSettle();

        // Disengaged cleanly
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );
        expect(
          container.read(autoReconnectProvider),
          equals(const AutoReconnectIdle()),
        );
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsNothing,
        );

        // Subtest: toggling kill switch preference off while blocking also
        // disengages
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        engine.emit(const Error(PlatformError('Tunnel dropped again')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());

        // Toggle preference off
        await container
            .read(killSwitchEnabledProvider.notifier)
            .setEnabled(enabled: false);
        await tester.pumpAndSettle();

        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Test 6: When auto-reconnect succeeds (Connected), KillSwitchBlocking '
      'transitions back to KillSwitchArmed and hides blocking banner',
      (tester) async {
        final profile = await _seedServer(dataSource);
        final fakePrefs = FakeAppPreferencesRepository(
          initialKillSwitchEnabled: true,
        );

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

        // Connect then drop
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        engine.emit(const Error(PlatformError('Drop')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsOneWidget,
        );

        // Wait backoff delay (1s for attempt 1)
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 100));

        // Reconnect attempt accepted and emits Connected
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Restored to Armed
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchArmed()),
        );
        expect(
          find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Defect D1 regression: FakeKillSwitchPlatformBridge isCurrentlyBlocking '
      'transitions false -> true on KillSwitchBlocking and false on unblock',
      (tester) async {
        final profile = await _seedServer(dataSource);
        final fakePrefs = FakeAppPreferencesRepository(
          initialKillSwitchEnabled: true,
        );
        final fakeBridge = FakeKillSwitchPlatformBridge();

        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const Scaffold(body: SessionInfoPanel())),
          overrides: [
            vpnEngineProvider.overrideWithValue(engine),
            serverProfileRepositoryProvider.overrideWith(
              (ref) async => buildRepository(dataSource),
            ),
            connectivitySourceProvider.overrideWithValue(fakeConnectivity),
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
            killSwitchPlatformBridgeProvider.overrideWithValue(fakeBridge),
          ],
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );

        expect(fakeBridge.isCurrentlyBlocking, isFalse);

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        expect(fakeBridge.isCurrentlyBlocking, isFalse);

        // Tunnel drops unexpectedly
        engine.emit(const Error(PlatformError('Tunnel dropped')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
        expect(fakeBridge.isCurrentlyBlocking, isTrue);

        // Tap unblock button
        await tester.tap(
          find.byKey(const ValueKey<String>('kill_switch_unblock_button')),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );
        expect(fakeBridge.isCurrentlyBlocking, isFalse);
        expect(fakeBridge.blockingHistory, equals([true, false]));
      },
    );

    testWidgets(
      'Defects D3 & D4 regression: mid-connection server switch and rejected '
      'engine.start() never enter KillSwitchBlocking or leave KillSwitchArmed '
      'stranded',
      (tester) async {
        final repo = buildRepository(dataSource);
        await repo.addServer(_testVlessUri);
        const server2Uri =
            'vless://22222222-3333-4444-5555-666666666666@example.org:443#Osaka';
        await repo.addServer(server2Uri);
        final servers = await repo.loadServers();
        final profile1 = (servers[0] as SavedServerProfile).profile;
        final profile2 = (servers[1] as SavedServerProfile).profile;

        final fakePrefs = FakeAppPreferencesRepository(
          initialKillSwitchEnabled: true,
        );
        final fakeBridge = FakeKillSwitchPlatformBridge();

        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const Scaffold(body: SessionInfoPanel())),
          overrides: [
            vpnEngineProvider.overrideWithValue(engine),
            serverProfileRepositoryProvider.overrideWith(
              (ref) async => buildRepository(dataSource),
            ),
            connectivitySourceProvider.overrideWithValue(fakeConnectivity),
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
            killSwitchPlatformBridgeProvider.overrideWithValue(fakeBridge),
          ],
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

        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchArmed()),
        );
        expect(fakeBridge.isCurrentlyBlocking, isFalse);

        // Switch mid-connection to server 2 (D3)
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile2);

        // During the switch, kill switch was cleanly disarmed and re-armed;
        // it must never have entered KillSwitchBlocking!
        expect(fakeBridge.isCurrentlyBlocking, isFalse);
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchArmed()),
        );

        // Subtest D4: Rejected engine.start() cleanly disarms session
        final rejectingEngine = _RejectingStartFakeVpnEngine(
          const VpnCommandRejectedInvalidConfig(),
        );
        final fakeBridge2 = FakeKillSwitchPlatformBridge();
        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const Scaffold(body: SessionInfoPanel())),
          overrides: [
            vpnEngineProvider.overrideWithValue(rejectingEngine),
            serverProfileRepositoryProvider.overrideWith(
              (ref) async => buildRepository(dataSource),
            ),
            connectivitySourceProvider.overrideWithValue(fakeConnectivity),
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
            killSwitchPlatformBridgeProvider.overrideWithValue(fakeBridge2),
          ],
        );
        final container2 = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );

        final result = await container2
            .read(connectionControllerProvider.notifier)
            .connect(profile1);
        expect(result, isA<VpnCommandRejectedInvalidConfig>());

        expect(
          container2.read(killSwitchProvider.notifier).isUserSessionActive,
          isFalse,
        );
        expect(
          container2.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );
        expect(fakeBridge2.isCurrentlyBlocking, isFalse);

        await rejectingEngine.dispose();
      },
    );

    testWidgets(
      'Defect D5 regression: Toggling killSwitchEnabledProvider to true while '
      'already Connected immediately transitions to KillSwitchArmed',
      (tester) async {
        final profile = await _seedServer(dataSource);
        final fakePrefs = FakeAppPreferencesRepository();
        final fakeBridge = FakeKillSwitchPlatformBridge();

        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const Scaffold(body: SessionInfoPanel())),
          overrides: [
            vpnEngineProvider.overrideWithValue(engine),
            serverProfileRepositoryProvider.overrideWith(
              (ref) async => buildRepository(dataSource),
            ),
            connectivitySourceProvider.overrideWithValue(fakeConnectivity),
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
            killSwitchPlatformBridgeProvider.overrideWithValue(fakeBridge),
          ],
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );

        // Connect with kill switch disabled
        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );

        // Enable kill switch in settings while connected
        await container
            .read(killSwitchEnabledProvider.notifier)
            .setEnabled(enabled: true);
        await tester.pumpAndSettle();

        // Immediately transitions to KillSwitchArmed
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchArmed()),
        );
        expect(
          container.read(killSwitchProvider.notifier).isUserSessionActive,
          isTrue,
        );
        expect(fakeBridge.isCurrentlyBlocking, isFalse);

        // Subtest: Drop occurs, then toggle disabled and re-enabled during drop
        engine.emit(const Error(PlatformError('Tunnel dropped')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(container.read(killSwitchProvider), isA<KillSwitchBlocking>());
        expect(fakeBridge.isCurrentlyBlocking, isTrue);

        await container
            .read(killSwitchEnabledProvider.notifier)
            .setEnabled(enabled: false);
        await tester.pumpAndSettle();

        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );
        expect(fakeBridge.isCurrentlyBlocking, isFalse);

        // Re-enable while drop/reconnect is active -> immediately enters
        // KillSwitchBlocking and engages native blocking
        await container
            .read(killSwitchEnabledProvider.notifier)
            .setEnabled(enabled: true);
        await tester.pumpAndSettle();

        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchBlocking(reason: 'enabled_during_drop')),
        );
        expect(fakeBridge.isCurrentlyBlocking, isTrue);
      },
    );
  });
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
