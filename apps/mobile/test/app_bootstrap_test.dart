// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show Connected, ConnectionState, Disconnected;
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mobile/core/bootstrap/app_bootstrap.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

/// Engine whose native status probe takes a deterministic amount of time.
class _DelayedStatusVpnEngine extends FakeVpnEngine {
  _DelayedStatusVpnEngine(this.delay) {
    lastState = const Connected();
  }

  final Duration delay;

  @override
  Future<ConnectionState> getStatus() async {
    await Future<void>.delayed(delay);
    return lastState;
  }
}

/// Engine whose native status probe always fails, to prove the concurrent
/// cohort cannot leak an error into the first frame.
class _ThrowingStatusVpnEngine extends FakeVpnEngine {
  @override
  Future<ConnectionState> getStatus() async {
    throw StateError('Simulated native channel failure');
  }
}

/// Repository whose storage read (the disk + Keystore decryption path in
/// production) takes a deterministic amount of time.
class _SlowLoadRepository extends FakeServerProfileRepository {
  _SlowLoadRepository(super.dataSource, this.delay);

  final Duration delay;

  @override
  Future<List<SavedServer>> loadServers() async {
    await Future<void>.delayed(delay);
    return await super.loadServers();
  }
}

/// Captures logs emitted by [Logger] to verify bootstrap error reporting.
class _CapturingOutput extends LogOutput {
  final List<String> lines = [];

  @override
  void output(OutputEvent event) {
    lines.add(event.lines.join('\n'));
  }
}

void main() {
  setUpAll(initTestLocalization);

  group('AppBootstrap.init startup sequencing', () {
    test(
      'completes startup sequence and injects SharedPreferences repository',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          SharedPreferencesAppPreferencesRepository.keyThemeMode: 'dark',
        });

        final container = await AppBootstrap.init();
        addTearDown(container.dispose);

        // 1. Verify preferences repository is backed by real SharedPreferences
        final repo = container.read(appPreferencesRepositoryProvider);
        expect(repo, isA<SharedPreferencesAppPreferencesRepository>());

        // 2. Verify theme mode was eagerly warmed up from storage
        final themeMode = container.read(themeModeProvider);
        expect(themeMode, ThemeMode.dark);

        // 3. Verify connectionStateProvider is active and querying status
        final connState = container.read(connectionStateProvider);
        expect(connState, isA<AsyncValue<ConnectionState>>());
      },
    );

    test('supports custom vpnEngineOverride', () async {
      final customEngine = MockVpnEngine(connectDelay: Duration.zero);
      final container = await AppBootstrap.init(
        vpnEngineOverride: customEngine,
      );
      addTearDown(container.dispose);

      final engine = container.read(vpnEngineProvider);
      expect(engine, same(customEngine));
    });
  });

  group('AppBootstrap parallel cold-start (Product Alignment #2)', () {
    test('runs preferences and native status probes concurrently', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      // Both independent legs cost 120ms. Serial waiting would need >240ms;
      // overlapping them costs roughly the slowest leg only.
      const legDelay = Duration(milliseconds: 120);
      final delayedEngine = _DelayedStatusVpnEngine(legDelay);

      final stopwatch = Stopwatch()..start();
      final container = await AppBootstrap.init(
        ensureBinding: false,
        ensureLocalization: false,
        vpnEngineOverride: delayedEngine,
        // In-memory storage so the measured window contains only the
        // parallel cohort, never a storage-timeout fallback.
        serverProfileRepositoryOverride: buildRepository(
          FakeServerProfileDataSource(),
        ),
        preferencesLoader: () async {
          await Future<void>.delayed(legDelay);
          final prefs = await SharedPreferences.getInstance();
          return prefs;
        },
      );
      stopwatch.stop();
      addTearDown(container.dispose);

      // Overlap proof: strictly below the 240ms serial sum.
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(210),
        reason:
            'Independent startup futures must overlap; elapsed was '
            '${stopwatch.elapsedMilliseconds}ms, which indicates serial '
            'awaiting of the 120ms legs',
      );

      // Preferences still resolved through the real storage path.
      expect(
        container.read(appPreferencesRepositoryProvider),
        isA<SharedPreferencesAppPreferencesRepository>(),
      );

      // Pre-warm invariant: the fetched native state is injected verbatim so
      // Frame 0 renders the truth without a "Disconnected" flash.
      expect(container.read(initialConnectionStateProvider), isA<Connected>());
    });

    test('does not block pre-frame bootstrap on slow savedServersProvider '
        'disk/Keystore I/O', () async {
      // Production reads the server list from an encrypted file (disk +
      // Android Keystore); 250 ms stands in for that work.
      const loadDelay = Duration(milliseconds: 250);
      final dataSource = FakeServerProfileDataSource();
      final repository = _SlowLoadRepository(dataSource, loadDelay);
      await repository.addServer(
        'vless://11111111-2222-3333-4444-555555555555@example.com:443'
        '#Tokyo%20Node',
      );

      final stopwatch = Stopwatch()..start();
      final container = await AppBootstrap.init(
        ensureBinding: false,
        ensureLocalization: false,
        preferencesRepositoryOverride: FakeAppPreferencesRepository(),
        serverProfileRepositoryOverride: repository,
        vpnEngineOverride: FakeVpnEngine(),
      );
      stopwatch.stop();
      addTearDown(container.dispose);

      // The 250 ms storage read must NOT be part of the pre-frame window.
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(120),
        reason:
            'AppBootstrap.init() must return without awaiting '
            'savedServersProvider; elapsed was '
            '${stopwatch.elapsedMilliseconds}ms',
      );

      // It was started eagerly (not awaited) and is still resolving.
      expect(container.read(savedServersProvider).isLoading, isTrue);

      // ...and it still lands cleanly afterwards.
      final servers = await container.read(savedServersProvider.future);
      final profiles = servers.whereType<SavedServerProfile>();
      expect(profiles, hasLength(1));
      expect(profiles.single.profile.name, equals('Tokyo Node'));
    });

    test(
      'concurrent status probe still degrades to Disconnected on failure',
      () async {
        final container = await AppBootstrap.init(
          ensureBinding: false,
          ensureLocalization: false,
          preferencesRepositoryOverride: FakeAppPreferencesRepository(),
          serverProfileRepositoryOverride: buildRepository(
            FakeServerProfileDataSource(),
          ),
          vpnEngineOverride: _ThrowingStatusVpnEngine(),
        );
        addTearDown(container.dispose);

        expect(
          container.read(initialConnectionStateProvider),
          isA<Disconnected>(),
        );
      },
    );
  });

  group('AppBootstrap graceful degradation (resilience)', () {
    test(
      'degrades gracefully to FakeAppPreferencesRepository on async error',
      () async {
        final capturingOutput = _CapturingOutput();
        final logger = AppLogger(
          log: Logger(level: Level.all, output: capturingOutput),
          isReleaseMode: false,
        );

        // Intentionally simulate a storage / disk I/O failure
        final container = await AppBootstrap.init(
          preferencesLoader: () => Future<SharedPreferences>.error(
            Exception('Simulated disk error'),
          ),
          logger: logger,
        );
        addTearDown(container.dispose);

        // App must NOT crash; it must provide safe in-memory fallback
        final repo = container.read(appPreferencesRepositoryProvider);
        expect(repo, isA<FakeAppPreferencesRepository>());

        // Safe defaults must be applied
        expect(container.read(themeModeProvider), ThemeMode.system);

        // Subsequent in-memory operations must continue working cleanly
        await container
            .read(themeModeProvider.notifier)
            .setThemeMode(ThemeMode.light);
        expect(container.read(themeModeProvider), ThemeMode.light);

        // The error must be logged for diagnostics
        expect(
          capturingOutput.lines.any(
            (line) => line.contains('Failed to initialize SharedPreferences'),
          ),
          isTrue,
        );
      },
    );

    test(
      'degrades gracefully to FakeAppPreferencesRepository on sync error',
      () async {
        final capturingOutput = _CapturingOutput();
        final logger = AppLogger(
          log: Logger(level: Level.all, output: capturingOutput),
          isReleaseMode: false,
        );

        // Intentionally simulate synchronous failure during initialization
        final container = await AppBootstrap.init(
          preferencesLoader: () => throw StateError('Synchronous crash'),
          logger: logger,
        );
        addTearDown(container.dispose);

        final repo = container.read(appPreferencesRepositoryProvider);
        expect(repo, isA<FakeAppPreferencesRepository>());
        expect(container.read(themeModeProvider), ThemeMode.system);

        expect(
          capturingOutput.lines.any(
            (line) => line.contains('Failed to initialize SharedPreferences'),
          ),
          isTrue,
        );
      },
    );
  });
}
