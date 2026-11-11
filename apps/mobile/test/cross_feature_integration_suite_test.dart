// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Disconnected,
        ServerProfile,
        ShadowsocksOutbound,
        TrafficStats;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/subscription_fetcher_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/core/security/sensitive_field_cipher.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/camera_permission_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/connection/presentation/providers/session_traffic_metrics_provider.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/add_subscription_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/servers/data/repositories/file_server_profile_repository.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:mobile/features/servers/presentation/providers/server_management_controller.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

class _FakeSubscriptionTransport implements SubscriptionTransport {
  _FakeSubscriptionTransport({required this.bodyProvider});

  final String Function() bodyProvider;

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) async {
    return TransportResponse(
      statusCode: HttpStatus.ok,
      headers: const {},
      body: Stream.value(utf8.encode(bodyProvider())),
    );
  }

  @override
  void close() {}
}

void _dismissAnySnackBar(WidgetTester tester) {
  final scaffoldMessengers = tester.stateList<ScaffoldMessengerState>(
    find.byType(ScaffoldMessenger),
  );
  for (final state in scaffoldMessengers) {
    state.removeCurrentSnackBar();
  }
}

late Directory globalTestLogDir;

void main() {
  setUpAll(initTestLocalization);

  setUp(() {
    globalTestLogDir = Directory.systemTemp.createTempSync('p9t2_logs_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getTemporaryDirectory') {
              return globalTestLogDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (globalTestLogDir.existsSync()) {
      globalTestLogDir.deleteSync(recursive: true);
    }
  });

  group('P9-T2 Cross-Feature Integration Suite: Cross-Feature Journeys', () {
    testWidgets(
      'Journey 1: Subscription Lifecycle (Import -> Connect -> Refresh '
      'Replacement -> Cascade Delete) <-> Active Server & Redaction Sync',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final dataSource = FakeServerProfileDataSource();
        const standaloneId = 'standalone-node-1';
        const standaloneSecret = 'standaloneSecretKey123';
        final standaloneProfile = ServerProfile(
          id: standaloneId,
          name: 'Standalone Node',
          config: const ShadowsocksOutbound(
            server: 'standalone.example.com',
            serverPort: 8388,
            method: 'aes-256-gcm',
            password: standaloneSecret,
          ),
          addedAt: DateTime.now().toUtc(),
        );
        dataSource.savedProfiles.add(standaloneProfile);

        const subUuidAlpha = '11111111-aaaa-bbbb-cccc-111111111111';
        const subUuidBeta = '22222222-aaaa-bbbb-cccc-222222222222';
        const subUuidGamma = '33333333-aaaa-bbbb-cccc-333333333333';
        const subTokenSecret = 'secretSubTokenXYZ999';

        const subUri1 =
            'vless://$subUuidAlpha@sub-a.example.com:443?security=none'
            '#Sub%20Node%20Alpha';
        const subUri2 =
            'vless://$subUuidBeta@sub-b.example.com:443?security=none'
            '#Sub%20Node%20Beta';
        const subUriGamma =
            'vless://$subUuidGamma@sub-g.example.com:443?security=none'
            '#Sub%20Node%20Gamma';

        var currentSubPayload = '$subUri1\n$subUri2';
        final fetcher = SubscriptionFetcher(
          transport: _FakeSubscriptionTransport(
            bodyProvider: () => currentSubPayload,
          ),
        );

        final fakeEngine = FakeVpnEngine();
        addTearDown(fakeEngine.dispose);
        final fakePrefs = FakeAppPreferencesRepository();
        final fakeBridge = FakeKillSwitchPlatformBridge();
        final fakeConnectivity = FakeConnectivitySource();
        addTearDown(fakeConnectivity.dispose);

        await tester.pumpWidget(
          localizedApp(
            overrides: [
              vpnEngineProvider.overrideWithValue(fakeEngine),
              serverProfileRepositoryProvider.overrideWith(
                (ref) async => buildRepository(dataSource),
              ),
              subscriptionFetcherProvider.overrideWithValue(fetcher),
              appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
              killSwitchPlatformBridgeProvider.overrideWithValue(fakeBridge),
              connectivitySourceProvider.overrideWithValue(fakeConnectivity),
              cameraPermissionServiceProvider.overrideWithValue(
                const FakeCameraPermissionService(),
              ),
            ],
            child: const MyApp(),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        // 1. Verify Standalone Node exists on HomeScreen
        expect(find.textContaining('Standalone Node'), findsWidgets);

        // 2. Import Subscription via AddSubscriptionScreen (/add-subscription)
        final homeContext = tester.element(find.byType(HomeScreen));
        unawaited(GoRouter.of(homeContext).push('/add-subscription'));
        await tester.pumpAndSettle();
        expect(find.byType(AddSubscriptionScreen), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_name_field')),
          'Alpha Subscription',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_url_field')),
          'https://sub.example.com/feed?token=$subTokenSecret',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_subscription_import_button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        _dismissAnySnackBar(tester);
        await tester.pumpAndSettle();

        // Verify popped back to HomeScreen
        expect(find.byType(HomeScreen), findsOneWidget);

        // Switch to ServersScreen to verify imported nodes and select
        // Alpha node
        await tester.tap(find.byIcon(Icons.dns).first);
        await tester.pumpAndSettle();

        expect(
          find.text('Alpha Subscription - sub-a.example.com:443'),
          findsOneWidget,
        );
        expect(
          find.text('Alpha Subscription - sub-b.example.com:443'),
          findsOneWidget,
        );

        // Select Alpha node
        await tester.tap(
          find.text('Alpha Subscription - sub-a.example.com:443'),
        );
        await tester.pumpAndSettle();

        // Switch back to HomeScreen
        await tester.tap(find.byIcon(Icons.home).first);
        await tester.pumpAndSettle();

        // 3. Connect to Sub Node Alpha
        final toggleBtn = find.byKey(
          const ValueKey<String>('home_connect_toggle_button'),
        );
        expect(toggleBtn, findsOneWidget);
        await tester.tap(toggleBtn);
        await tester.pump();

        fakeEngine.emit(const Connected());
        await tester.pump(const Duration(milliseconds: 100));

        // Verify SessionInfoPanel and ThroughputReadout
        expect(
          find.byKey(const ValueKey<String>('session_info_panel')),
          findsOneWidget,
        );
        expect(find.textContaining('sub-a.example.com'), findsWidgets);
        expect(
          find.byKey(const ValueKey<String>('throughput_readout')),
          findsOneWidget,
        );

        fakeEngine.emitStats(
          TrafficStats(
            txBytes: 1024,
            rxBytes: 2048,
            timestamp: DateTime.now().toUtc(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // 4. Trigger subscription refresh (Sub Node Beta replaced with
        // Sub Node Gamma)
        currentSubPayload = '$subUri1\n$subUriGamma';
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        final repo = await container.read(
          serverProfileRepositoryProvider.future,
        );
        final subs = await repo.getAllSubscriptions();
        final alphaSub = subs.first;
        await container
            .read(serverManagementControllerProvider.notifier)
            .refreshSubscription(alphaSub);
        await tester.pump(const Duration(milliseconds: 100));

        // Verify active server remains Sub Node Alpha (tunnel continuity)
        expect(fakeEngine.lastState, const Connected());
        expect(find.textContaining('sub-a.example.com'), findsWidgets);

        // Verify old Sub Node Beta purged, Sub Node Gamma added in repository
        final currentProfiles = await repo.getAll();
        expect(
          currentProfiles.any((p) => p.config.server == 'sub-b.example.com'),
          isFalse,
        );
        expect(
          currentProfiles.any((p) => p.config.server == 'sub-g.example.com'),
          isTrue,
        );

        // Verify on-disk encrypted persistence via FileServerProfileRepository
        final j1StorageDir = Directory.systemTemp.createTempSync(
          'p9t2_j1_storage_',
        );
        addTearDown(() {
          if (j1StorageDir.existsSync()) {
            j1StorageDir.deleteSync(recursive: true);
          }
        });
        final j1StorageFile = File('${j1StorageDir.path}/server_profiles.json');
        await tester.runAsync(() async {
          final j1Repo = FileServerProfileRepository(
            storageFile: j1StorageFile,
            cipher: InMemorySensitiveFieldCipher(),
          );
          await j1Repo.init();
          await j1Repo.saveSubscription(alphaSub);
          for (final p in currentProfiles) {
            await j1Repo.save(p);
          }
          expect(j1StorageFile.existsSync(), isTrue);
          final diskJson = await j1StorageFile.readAsString();
          expect(diskJson.contains('enc:v1:'), isTrue);
          expect(diskJson.contains(subTokenSecret), isFalse);
          expect(diskJson.contains(subUuidAlpha), isFalse);
          expect(diskJson.contains(subUuidGamma), isFalse);
        });

        // 5. Delete parent subscription -> assert cascade deletion of child
        // nodes
        await container
            .read(serverManagementControllerProvider.notifier)
            .deleteSubscription(alphaSub.id);
        await tester.pump(const Duration(milliseconds: 100));

        // Verify child nodes removed and active profile resets safely
        final remainingProfiles = await repo.getAll();
        expect(remainingProfiles.any((p) => p.subscriptionId != null), isFalse);
        expect(remainingProfiles.length, equals(1));
        expect(remainingProfiles.first.name, equals('Standalone Node'));

        // Disconnect engine safely
        container
            .read(autoReconnectProvider.notifier)
            .onUserInitiatedDisconnect();
        fakeEngine.emit(const Disconnected());
        await tester.pump(const Duration(milliseconds: 100));
        _dismissAnySnackBar(tester);
        await tester.pump(const Duration(milliseconds: 100));

        // 6. Verify LogManager scrubbed subscription URLs & tokens
        final logManager = container.read(logManagerProvider.notifier);
        fakeEngine.emitLog(
          'Diagnostic log: fetching from https://sub.example.com/feed?token=$subTokenSecret',
        );
        await tester.pump(const Duration(milliseconds: 100));

        final entries = logManager.structuredEntries;
        expect(entries.any((l) => l.raw.contains(subTokenSecret)), isFalse);
        expect(entries.any((l) => l.raw.contains('[REDACTED]')), isTrue);
      },
    );

    testWidgets('Journey 2: Mid-Session Settings Mutations <-> Live Tunnel '
        'Continuity & Fail-Closed Drop', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dataSource = FakeServerProfileDataSource();
      final fakeEngine = FakeVpnEngine();
      addTearDown(fakeEngine.dispose);
      final fakePrefs = FakeAppPreferencesRepository();
      final fakeBridge = FakeKillSwitchPlatformBridge();
      final fakeConnectivity = FakeConnectivitySource();
      addTearDown(fakeConnectivity.dispose);

      const resServerId = 'resilience-node-1';
      final resProfile = ServerProfile(
        id: resServerId,
        name: 'Resilience Server',
        config: const ShadowsocksOutbound(
          server: 'resilience.example.com',
          serverPort: 8388,
          method: 'aes-256-gcm',
          password: 'resilienceSecretKey456',
        ),
        addedAt: DateTime.now().toUtc(),
      );
      dataSource.savedProfiles.add(resProfile);

      await tester.pumpWidget(
        localizedApp(
          overrides: [
            vpnEngineProvider.overrideWithValue(fakeEngine),
            serverProfileRepositoryProvider.overrideWith(
              (ref) async => buildRepository(dataSource),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
            killSwitchPlatformBridgeProvider.overrideWithValue(fakeBridge),
            connectivitySourceProvider.overrideWithValue(fakeConnectivity),
            cameraPermissionServiceProvider.overrideWithValue(
              const FakeCameraPermissionService(),
            ),
          ],
          child: const MyApp(),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      // 1. Connect to Resilience Server
      expect(find.textContaining('Resilience Server'), findsWidgets);

      final toggleBtn = find.byKey(
        const ValueKey<String>('home_connect_toggle_button'),
      );
      await tester.tap(toggleBtn);
      await tester.pump();

      fakeEngine.emit(const Connected());
      await tester.pump(const Duration(milliseconds: 100));

      fakeEngine.emitStats(
        TrafficStats(
          txBytes: 5000,
          rxBytes: 10000,
          timestamp: DateTime.now().toUtc(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final homeContext = tester.element(find.byType(HomeScreen));
      final container = ProviderScope.containerOf(homeContext);

      // 2. Mid-Session Settings Mutations: ThemeMode and Locale
      await container
          .read(themeModeProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeEngine.lastState, const Connected());

      await container
          .read(localeProvider.notifier)
          .setLocale(const Locale('de'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeEngine.lastState, const Connected());

      // Verify metrics preserved through mutations
      final metrics = container.read(sessionTrafficMetricsProvider);
      expect(metrics.txBytes, equals(5000));
      expect(metrics.rxBytes, equals(10000));

      // 3. Toggle Auto-Reconnect OFF and KillSwitch ON mid-session
      await container
          .read(autoReconnectEnabledProvider.notifier)
          .setEnabled(enabled: false);
      await container
          .read(killSwitchEnabledProvider.notifier)
          .setEnabled(enabled: true);
      await tester.pump(const Duration(milliseconds: 100));

      final initialStartCalls = fakeEngine.startCalls.length;

      // 4. Induce connection drop
      fakeEngine.emit(const Disconnected());
      await tester.pump(const Duration(milliseconds: 100));

      // Verify KillSwitch triggers fail-closed blocking
      expect(fakeBridge.isCurrentlyBlocking, isTrue);
      expect(
        find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
        findsOneWidget,
      );

      // Auto-reconnect does NOT trigger reconnection loop
      await tester.pump(const Duration(seconds: 2));
      expect(fakeEngine.startCalls.length, equals(initialStartCalls));
      expect(fakeEngine.lastState, const Disconnected());

      // Tap unblock button to unblock kill switch
      await tester.tap(
        find.byKey(const ValueKey<String>('kill_switch_unblock_button')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeBridge.isCurrentlyBlocking, isFalse);
      expect(
        find.byKey(const ValueKey<String>('kill_switch_blocking_banner')),
        findsNothing,
      );

      // 5. User manually triggers Reconnect
      await tester.tap(toggleBtn);
      await tester.pump();

      fakeEngine.emit(const Connected());
      await tester.pump(const Duration(milliseconds: 100));

      // Verify KillSwitch safely unblocks
      expect(fakeBridge.isCurrentlyBlocking, isFalse);
      expect(fakeEngine.lastState, const Connected());

      // Disconnect cleanly
      container
          .read(autoReconnectProvider.notifier)
          .onUserInitiatedDisconnect();
      fakeEngine.emit(const Disconnected());
      await tester.pump(const Duration(milliseconds: 100));
      _dismissAnySnackBar(tester);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('Journey 3: Server Management & Mid-Session Handoff <-> '
        'Multi-Profile 3-Surface Redaction', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dataSource = FakeServerProfileDataSource();
      final fakeEngine = FakeVpnEngine();
      addTearDown(fakeEngine.dispose);
      final fakePrefs = FakeAppPreferencesRepository();
      final fakeConnectivity = FakeConnectivitySource();
      addTearDown(fakeConnectivity.dispose);

      await tester.pumpWidget(
        localizedApp(
          overrides: [
            vpnEngineProvider.overrideWithValue(fakeEngine),
            serverProfileRepositoryProvider.overrideWith(
              (ref) async => buildRepository(dataSource),
            ),
            appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
            connectivitySourceProvider.overrideWithValue(fakeConnectivity),
            cameraPermissionServiceProvider.overrideWithValue(
              const FakeCameraPermissionService(),
            ),
          ],
          child: const MyApp(),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      // 1. Add server via manual URI paste ("Server Original")
      final homeContext = tester.element(find.byType(HomeScreen));
      unawaited(GoRouter.of(homeContext).push('/add-server'));
      await tester.pumpAndSettle();
      expect(find.byType(AddServerScreen), findsOneWidget);

      const origUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      const origUri =
          'vless://$origUuid@orig.example.com:443?security=none#Server%20Original';

      await tester.enterText(
        find.byKey(const ValueKey<String>('add_server_uri_field')),
        origUri,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_save_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      _dismissAnySnackBar(tester);
      await tester.pumpAndSettle();

      // Verify "Server Original" appears on HomeScreen
      expect(find.textContaining('Server Original'), findsWidgets);

      // 2. Connect to "Server Original"
      final toggleBtn = find.byKey(
        const ValueKey<String>('home_connect_toggle_button'),
      );
      await tester.tap(toggleBtn);
      await tester.pump();

      fakeEngine.emit(const Connected());
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeEngine.lastState, const Connected());

      // 3. Rename "Server Original" -> "Server Renamed" while connected
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      final repo = await container.read(serverProfileRepositoryProvider.future);
      final origProfile = (await repo.getAll()).firstWhere(
        (p) => p.name == 'Server Original',
      );
      final renamedProfile = origProfile.copyWith(name: 'Server Renamed');
      await repo.save(renamedProfile);
      container.invalidate(savedServersProvider);
      await tester.pump(const Duration(milliseconds: 100));

      // Verify active session reflects updated remark without disconnection
      expect(fakeEngine.lastState, const Connected());
      expect(find.textContaining('Server Renamed'), findsWidgets);

      // 4. Duplicate "Server Renamed" -> creates "Server Renamed (Copy)"
      await container
          .read(serverManagementControllerProvider.notifier)
          .duplicateServer(renamedProfile);
      await tester.pump(const Duration(milliseconds: 100));

      final allProfiles = await repo.getAll();
      expect(allProfiles.any((p) => p.name.contains('(Copy)')), isTrue);
      final copyProfile = allProfiles.firstWhere(
        (p) => p.name.contains('(Copy)'),
      );

      // 5. Trigger seamless server switch (switch to Servers tab,
      // select copy, return to Home, connect)
      await tester.tap(find.byIcon(Icons.dns).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(copyProfile.name), findsOneWidget);
      await tester.tap(find.text(copyProfile.name));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byIcon(Icons.home).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining(copyProfile.name), findsWidgets);

      // Disconnect previous profile first, then connect the newly selected
      // copyProfile
      await tester.tap(toggleBtn);
      await tester.pump();
      fakeEngine.emit(const Disconnected());
      await tester.pump(const Duration(milliseconds: 100));

      // Now tap Connect to start copyProfile and verify engine received it
      await tester.tap(toggleBtn);
      await tester.pump();
      fakeEngine.emit(const Connected());
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeEngine.lastState, const Connected());
      expect(fakeEngine.startCalls.map((p) => p.id), contains(copyProfile.id));

      // Disconnect cleanly
      container
          .read(autoReconnectProvider.notifier)
          .onUserInitiatedDisconnect();
      fakeEngine.emit(const Disconnected());
      await tester.pump(const Duration(milliseconds: 100));
      _dismissAnySnackBar(tester);
      await tester.pump(const Duration(milliseconds: 100));

      // 6. Verify 3 surfaces of LogManager redact sensitive credentials
      // automatically. Initialize LogManager inside tester.runAsync so
      // _initSink() opens brick_vpn_live.log on disk and savedServersProvider
      // listener registers origUuid & orig.example.com automatically!
      late final LogManager logManager;
      await tester.runAsync(() async {
        logManager = container.read(logManagerProvider.notifier);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await logManager.flushFile();
      });
      await tester.pump();

      fakeEngine.emitLog(
        'Diagnostic connection test: $origUuid at orig.example.com',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        await logManager.flushFile();
      });

      // Surface 1: Live structured entries
      final entries = logManager.structuredEntries;
      expect(entries, isNotEmpty);
      expect(entries.any((l) => l.raw.contains(origUuid)), isFalse);
      expect(entries.any((l) => l.raw.contains('orig.example.com')), isFalse);
      expect(entries.any((l) => l.raw.contains('[REDACTED')), isTrue);

      // Surface 2: In-memory raw queue
      final inMemory = container.read(logManagerProvider);
      expect(inMemory.any((l) => l.contains(origUuid)), isFalse);
      expect(inMemory.any((l) => l.contains('orig.example.com')), isFalse);
      expect(inMemory.any((l) => l.contains('[REDACTED')), isTrue);

      // Surface 3: Real On-Disk Log File written by LogManager's IOSink
      // (ZERO test-side writeAsStringSync!)
      final logFile = File(
        '${globalTestLogDir.path}/${LogManager.logFileName}',
      );
      await tester.runAsync(() async {
        expect(logFile.existsSync(), isTrue);
        final content = await logFile.readAsString();
        expect(content, isNotEmpty);
        expect(content.contains(origUuid), isFalse);
        expect(content.contains('orig.example.com'), isFalse);
        expect(content.contains('[REDACTED'), isTrue);
      });
    });

    testWidgets(
      'Journey 4: Encrypted Schema v1 -> v2 Migration <-> Process-Restart '
      'Re-Attachment <-> Offline Outage Hold & Auto-Reconnect Recovery',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final tempDir = Directory.systemTemp.createTempSync('p9t2_j4_repo_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final storageFile = File('${tempDir.path}/server_profiles.json');
        const v1PlaintextSecret = 'v1PlaintextPassword123';
        const v1ServerId = 'v1-migrated-server-1';

        final v1Profile = ServerProfile(
          id: v1ServerId,
          name: 'Migrated v1 Server',
          config: const ShadowsocksOutbound(
            server: 'migrated.example.com',
            serverPort: 8388,
            method: 'aes-256-gcm',
            password: v1PlaintextSecret,
          ),
          addedAt: DateTime.now().toUtc(),
        );

        const subMetadata = SubscriptionMetadata(
          id: 'sub-migrated-1',
          url: 'https://sub.example.com/feed?token=secretMigratedToken999',
          name: 'Migrated Subscription',
        );

        final v1JsonMap = <String, dynamic>{
          'schema_version': 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'server_profiles': [v1Profile.toJson()],
          'subscriptions': [subMetadata.toJson()],
          'broken_servers': <String, dynamic>{},
        };
        storageFile.writeAsStringSync(jsonEncode(v1JsonMap));

        // 1. Verify Schema v1 -> v2 migration executed atomically at rest
        final cipher = InMemorySensitiveFieldCipher();
        late final FileServerProfileRepository fileRepo;
        late final List<ServerProfile> migratedProfiles;
        await tester.runAsync(() async {
          fileRepo = FileServerProfileRepository(
            storageFile: storageFile,
            cipher: cipher,
          );
          await fileRepo.init();
          migratedProfiles = await fileRepo.getAll();
        });

        final migratedJson = storageFile.readAsStringSync();
        expect(migratedJson.contains(v1PlaintextSecret), isFalse);
        expect(migratedJson.contains('secretMigratedToken999'), isFalse);
        expect(migratedJson.contains('enc:v1:'), isTrue);
        expect(migratedJson.contains('"schema_version": 2'), isTrue);

        // 2. Process-restart re-attachment
        final dataSource = FakeServerProfileDataSource();
        dataSource.savedProfiles.addAll(migratedProfiles);

        final fakeEngine = FakeVpnEngine();
        addTearDown(fakeEngine.dispose);
        final fakePrefs = FakeAppPreferencesRepository();
        final fakeConnectivity = FakeConnectivitySource();
        addTearDown(fakeConnectivity.dispose);

        final fakeBridge = FakeKillSwitchPlatformBridge();

        // Session 1: User launches and connects to Migrated v1 Server
        await tester.pumpWidget(
          localizedApp(
            overrides: [
              vpnEngineProvider.overrideWithValue(fakeEngine),
              serverProfileRepositoryProvider.overrideWith(
                (ref) async => buildRepository(dataSource),
              ),
              appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
              killSwitchPlatformBridgeProvider.overrideWithValue(fakeBridge),
              connectivitySourceProvider.overrideWithValue(fakeConnectivity),
              cameraPermissionServiceProvider.overrideWithValue(
                const FakeCameraPermissionService(),
              ),
            ],
            child: const MyApp(),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(find.textContaining('Migrated v1 Server'), findsWidgets);

        final toggleBtn = find.byKey(
          const ValueKey<String>('home_connect_toggle_button'),
        );
        await tester.tap(toggleBtn);
        await tester.pump();

        fakeEngine.emit(const Connected());
        await tester.pump(const Duration(milliseconds: 100));

        final homeContext = tester.element(find.byType(HomeScreen));
        final container = ProviderScope.containerOf(homeContext);

        expect(container.read(connectionStateProvider).value, isA<Connected>());
        expect(container.read(activeServerProvider)?.id, equals(v1ServerId));
        expect(
          container.read(autoReconnectProvider.notifier).isUserSessionActive,
          isTrue,
        );

        // Simulate UI process kill: unmount & dispose old container
        await fakePrefs.setActiveServerId(v1ServerId);
        await fakePrefs.setActiveSessionStartedAt(DateTime.now().toUtc());

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));

        // Background service remains connected
        expect(fakeEngine.lastState, const Connected());

        // Session 2: Relaunch UI (process restart re-attachment)
        await tester.pumpWidget(
          localizedApp(
            overrides: [
              vpnEngineProvider.overrideWithValue(fakeEngine),
              serverProfileRepositoryProvider.overrideWith(
                (ref) async => buildRepository(dataSource),
              ),
              appPreferencesRepositoryProvider.overrideWithValue(fakePrefs),
              killSwitchPlatformBridgeProvider.overrideWithValue(fakeBridge),
              connectivitySourceProvider.overrideWithValue(fakeConnectivity),
              cameraPermissionServiceProvider.overrideWithValue(
                const FakeCameraPermissionService(),
              ),
            ],
            child: const MyApp(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        final reattachedContext = tester.element(find.byType(HomeScreen));
        final reattachedContainer = ProviderScope.containerOf(
          reattachedContext,
        );

        // Authoritative connection state is Connected immediately upon settling
        expect(
          reattachedContainer.read(connectionStateProvider).value,
          isA<Connected>(),
        );
        expect(
          reattachedContainer.read(activeServerProvider)?.id,
          equals(v1ServerId),
        );
        expect(find.textContaining('Migrated v1 Server'), findsWidgets);
        expect(
          reattachedContainer
              .read(autoReconnectProvider.notifier)
              .isUserSessionActive,
          isTrue,
        );

        // 3. Induce offline outage (Airplane mode)
        fakeConnectivity.emit([ConnectivityResult.none]);
        await tester.pump(const Duration(milliseconds: 350));

        // Tunnel drops unexpectedly
        fakeEngine.emit(const Disconnected());
        await tester.pump(const Duration(milliseconds: 100));

        // Auto-reconnect enters offline hold; does not start futile
        // reconnection attempts
        final attemptsBefore = fakeEngine.startCalls.length;
        await tester.pump(const Duration(seconds: 2));
        expect(fakeEngine.startCalls.length, equals(attemptsBefore));

        // 4. Physical network restored (Wi-Fi connected)
        fakeConnectivity.emit([ConnectivityResult.wifi]);
        await tester.pump(const Duration(milliseconds: 350)); // debounce
        await tester.pump(const Duration(seconds: 1)); // backoff

        // Auto-reconnect triggers reconnection
        expect(fakeEngine.startCalls.length, greaterThan(attemptsBefore));

        // Reconnection succeeds
        fakeEngine.emit(const Connected());
        await tester.pump(const Duration(milliseconds: 100));
        expect(fakeEngine.lastState, const Connected());

        // 5. Clean user disconnect
        reattachedContainer
            .read(autoReconnectProvider.notifier)
            .onUserInitiatedDisconnect();
        fakeEngine.emit(const Disconnected());
        await tester.pump(const Duration(milliseconds: 100));
        _dismissAnySnackBar(tester);
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });
}
