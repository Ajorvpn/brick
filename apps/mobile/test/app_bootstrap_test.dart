// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart' show ConnectionState;
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
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'localization_test_harness.dart';

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
