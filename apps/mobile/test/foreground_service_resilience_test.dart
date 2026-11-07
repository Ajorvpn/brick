// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show Connected, Disconnected, ServerProfile;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/platform/battery_optimization_service.dart';
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

  group('P7-T4 BatteryOptimizationService unit tests', () {
    const channelName = 'dev.brickvpn.harness/battery_optimization';
    late MethodChannelBatteryOptimizationService service;

    setUp(() {
      service = const MethodChannelBatteryOptimizationService();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), null);
    });

    test(
      'isIgnoringBatteryOptimizations returns true when channel responds true',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName), (
              MethodCall call,
            ) async {
              if (call.method == 'isIgnoringBatteryOptimizations') {
                return true;
              }
              return null;
            });

        final result = await service.isIgnoringBatteryOptimizations();
        expect(result, isTrue);
      },
    );

    test('isIgnoringBatteryOptimizations gracefully falls back to false on '
        'MissingPluginException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), (
            MethodCall call,
          ) async {
            throw MissingPluginException();
          });

      final result = await service.isIgnoringBatteryOptimizations();
      expect(result, isFalse);
    });

    test(
      'requestIgnoreBatteryOptimizations returns true when channel succeeds',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName), (
              MethodCall call,
            ) async {
              if (call.method == 'requestIgnoreBatteryOptimizations') {
                return true;
              }
              return false;
            });

        final result = await service.requestIgnoreBatteryOptimizations();
        expect(result, isTrue);
      },
    );

    test('requestIgnoreBatteryOptimizations gracefully falls back to false on '
        'PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), (
            MethodCall call,
          ) async {
            throw PlatformException(code: 'ERROR');
          });

      final result = await service.requestIgnoreBatteryOptimizations();
      expect(result, isFalse);
    });

    test('FakeBatteryOptimizationService tracks check and request calls and '
        'transitions to true', () async {
      final fake = FakeBatteryOptimizationService();
      expect(fake.checkCalls, equals(0));
      expect(fake.requestCalls, equals(0));

      final initial = await fake.isIgnoringBatteryOptimizations();
      expect(initial, isFalse);
      expect(fake.checkCalls, equals(1));

      final requested = await fake.requestIgnoreBatteryOptimizations();
      expect(requested, isTrue);
      expect(fake.requestCalls, equals(1));
      expect(fake.isIgnoring, isTrue);

      final after = await fake.isIgnoringBatteryOptimizations();
      expect(after, isTrue);
      expect(fake.checkCalls, equals(2));
    });
  });

  group('P7-T4 Foreground Service Resilience & Settings Integration', () {
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
      'Test 2: SettingsScreen displays settings_battery_optimization_tile '
      'with "Optimized — tap to exclude from battery limits" when '
      'isIgnoring == false, and tapping it calls '
      'requestIgnoreBatteryOptimizations() and updates the UI to '
      '"Unrestricted (recommended for stable VPN)"',
      (tester) async {
        final fakePrefs = FakeAppPreferencesRepository();
        final fakeBatteryService = FakeBatteryOptimizationService();

        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const SettingsScreen()),
          overrides: [
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
            batteryOptimizationServiceProvider.overrideWithValue(
              fakeBatteryService,
            ),
          ],
        );

        expect(find.text('Battery Optimization'), findsOneWidget);
        final tileFinder = find.byKey(
          const ValueKey<String>('settings_battery_optimization_tile'),
        );
        expect(tileFinder, findsOneWidget);

        // Before tap: optimized subtitle
        expect(
          find.text('Optimized — tap to exclude from battery limits'),
          findsOneWidget,
        );
        expect(fakeBatteryService.requestCalls, equals(0));

        // Tap tile to request exclusion
        await tester.tap(tileFinder);
        await tester.pumpAndSettle();

        expect(fakeBatteryService.requestCalls, equals(1));
        expect(fakeBatteryService.isIgnoring, isTrue);

        // After tap: unrestricted subtitle
        expect(
          find.text('Unrestricted (recommended for stable VPN)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Defect D1 regression: AppLifecycleState.resumed automatically refreshes '
      'batteryOptimizationIgnoredProvider when user returns from system dialog',
      (tester) async {
        final fakePrefs = FakeAppPreferencesRepository();
        final fakeBatteryService = FakeBatteryOptimizationService(
          autoGrantOnRequest: false,
        );

        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const SettingsScreen()),
          overrides: [
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
            batteryOptimizationServiceProvider.overrideWithValue(
              fakeBatteryService,
            ),
          ],
        );

        final tileFinder = find.byKey(
          const ValueKey<String>('settings_battery_optimization_tile'),
        );
        expect(tileFinder, findsOneWidget);

        // Before tap: optimized subtitle
        expect(
          find.text('Optimized — tap to exclude from battery limits'),
          findsOneWidget,
        );

        // Tap tile: requests exemption, but system dialog is still on screen
        await tester.tap(tileFinder);
        await tester.pumpAndSettle();

        expect(fakeBatteryService.requestCalls, equals(1));
        // Subtitle remains optimized because user has not approved in system
        // dialog yet
        expect(
          find.text('Optimized — tap to exclude from battery limits'),
          findsOneWidget,
        );

        // User approves in system settings and returns to the app
        fakeBatteryService.isIgnoring = true;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        // Subtitle automatically updates to unrestricted on resume!
        expect(
          find.text('Unrestricted (recommended for stable VPN)'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Test 3: Cold start after OS service kill never displays stale '
        '"Connected" state (SessionInfoPanel shows Disconnected and '
        '00:00:00)', (tester) async {
      final fakePrefs = FakeAppPreferencesRepository();
      // Native engine status is Disconnected (OS terminated background service)
      engine.lastState = const Disconnected();

      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const Scaffold(body: SessionInfoPanel())),
        overrides: [
          vpnEngineProvider.overrideWithValue(engine),
          serverProfileRepositoryProvider.overrideWith(
            (ref) => buildRepository(dataSource),
          ),
          connectivitySourceProvider.overrideWithValue(fakeConnectivity),
          appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
        ],
      );

      expect(find.text('Tunnel: Disconnected'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);
    });

    testWidgets('Test 4: OS service kill while backgrounded — app resumes '
        '(AppLifecycleState.resumed), reconciles Connected -> Disconnected '
        'immediately, and resets timer to 00:00:00', (tester) async {
      final profile = await _seedServer(dataSource);
      final fakePrefs = FakeAppPreferencesRepository();

      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const Scaffold(body: SessionInfoPanel())),
        overrides: [
          vpnEngineProvider.overrideWithValue(engine),
          serverProfileRepositoryProvider.overrideWith(
            (ref) => buildRepository(dataSource),
          ),
          connectivitySourceProvider.overrideWithValue(fakeConnectivity),
          appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
        ],
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionInfoPanel)),
      );

      // 1. Initial connect
      await container
          .read(connectionControllerProvider.notifier)
          .connect(profile);
      engine.emit(const Connected());
      await tester.pumpAndSettle();

      // Advance 3 seconds: duration timer ticks
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Tunnel: Connected'), findsOneWidget);
      expect(find.text('Duration: 00:00:03'), findsOneWidget);

      // 2. App backgrounded (resumed -> inactive -> hidden -> paused)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // 3. OS forcibly terminates the native VPN service while backgrounded
      engine.lastState = const Disconnected();

      // 4. User resumes app into foreground
      // (paused -> hidden -> inactive -> resumed)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // 5. Verification: State reconciled immediately to Disconnected,
      // duration reset
      expect(find.text('Tunnel: Disconnected'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);

      // Defect D3 assertions: verify auto-reconnect and kill-switch states
      expect(
        container.read(autoReconnectProvider),
        isA<AutoReconnectBackoff>(),
      );
      expect(
        container.read(killSwitchProvider),
        equals(const KillSwitchInactive()),
      );
    });

    testWidgets(
      'Defect D3 regression: OS service kill with autoReconnect disabled '
      'settles deterministically in AutoReconnectIdle on resume',
      (tester) async {
        final profile = await _seedServer(dataSource);
        final fakePrefs = FakeAppPreferencesRepository();
        await fakePrefs.setAutoReconnectEnabled(enabled: false);

        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const Scaffold(body: SessionInfoPanel())),
          overrides: [
            vpnEngineProvider.overrideWithValue(engine),
            serverProfileRepositoryProvider.overrideWith(
              (ref) => buildRepository(dataSource),
            ),
            connectivitySourceProvider.overrideWithValue(fakeConnectivity),
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
          ],
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );

        await container
            .read(connectionControllerProvider.notifier)
            .connect(profile);
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Background app and kill service
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        engine.lastState = const Disconnected();

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(find.text('Tunnel: Disconnected'), findsOneWidget);
        expect(find.text('Duration: 00:00:00'), findsOneWidget);
        expect(
          container.read(autoReconnectProvider),
          equals(const AutoReconnectIdle()),
        );
        expect(
          container.read(killSwitchProvider),
          equals(const KillSwitchInactive()),
        );
      },
    );
  });
}
