// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_engine_android/vpn_engine_android.dart';

/// Handles the explicit, deterministic application startup sequence.
///
/// Refactored in P4-T7 to replace implicit/ad-hoc initialization with a
/// linear, documented startup sequence and graceful degradation under
/// storage or platform failures.
class AppBootstrap {
  AppBootstrap._();

  /// Executes the deterministic startup sequence and returns the configured
  /// [ProviderContainer].
  ///
  /// The startup sequence follows a strict, reasoned ordering:
  ///
  /// 1. **Flutter Bindings (`WidgetsFlutterBinding.ensureInitialized`)**
  ///    Must be called before any platform channels, native plugins, or
  ///    asynchronous framework features are invoked.
  ///
  /// 2. **Localization Engine (`EasyLocalization.ensureInitialized`)**
  ///    Loads translations and device locale from storage before any UI widgets
  ///    or providers that depend on localized strings are initialized.
  ///
  /// 3. **Non-Secret Preferences (`SharedPreferences.getInstance`)**
  ///    Preferences (e.g. theme mode, language selection) must be loaded before
  ///    the theme provider and dependency injection container are assembled.
  ///    **Graceful Degradation:** Wrapped in a try-catch block; if storage
  ///    fails (disk corruption, missing channel, permission denied), an error
  ///    is logged via [AppLogger] and the app falls back to an in-memory
  ///    [FakeAppPreferencesRepository] with safe defaults rather than crashing
  ///    on boot.
  ///
  /// 4. **Riverpod Provider Container Assembly (`ProviderContainer`)**
  ///    Assembles the root container with all production overrides
  ///    ([appPreferencesRepositoryProvider] and [vpnEngineProvider]).
  ///
  /// 5. **Cold-Boot VPN Resync & Theme Warm-up**
  ///    Eagerly evaluates [themeModeProvider] and [connectionStateProvider].
  ///    Per P4-T1, reading [connectionStateProvider] queries the native
  ///    `VpnEngine.getStatus()` truth immediately on startup to prevent
  ///    background/cold-boot state desync before the navigation shell renders.
  ///
  /// 6. **Container Return**
  ///    Returns the fully warmed [ProviderContainer] to the caller for
  ///    mounting into [UncontrolledProviderScope].
  static Future<ProviderContainer> init({
    Future<SharedPreferences> Function()? preferencesLoader,
    VpnEngine? vpnEngineOverride,
    AppLogger? logger,
    bool ensureBinding = true,
    bool ensureLocalization = true,
  }) async {
    final appLogger = logger ?? AppLogger();

    // -------------------------------------------------------------------------
    // Step 1: Ensure Flutter bindings are initialized.
    // Required before any binary messenger / platform channel interactions.
    // -------------------------------------------------------------------------
    if (ensureBinding) {
      WidgetsFlutterBinding.ensureInitialized();
    }

    // -------------------------------------------------------------------------
    // Step 2: Initialize localization engine.
    // Loads persisted locale from disk before widgets or formatting are ready.
    // -------------------------------------------------------------------------
    if (ensureLocalization) {
      await EasyLocalization.ensureInitialized();
    }

    // -------------------------------------------------------------------------
    // Step 3: Initialize non-secret preferences with graceful degradation.
    // Preferences must be available before theme and container initialization.
    // Wrapped in try-catch: if persistent storage throws, degrade to safe
    // in-memory defaults instead of crashing on launch.
    // -------------------------------------------------------------------------
    AppPreferencesRepository preferencesRepo;
    try {
      final prefs = await (preferencesLoader != null
          ? preferencesLoader()
          : SharedPreferences.getInstance());
      preferencesRepo = SharedPreferencesAppPreferencesRepository(prefs);
    } on Object catch (error, stackTrace) {
      appLogger.e(
        'Failed to initialize SharedPreferences; degrading to in-memory fake',
        error,
        stackTrace,
      );
      preferencesRepo = FakeAppPreferencesRepository();
    }

    // -------------------------------------------------------------------------
    // Step 4: Assemble root Riverpod ProviderContainer.
    // Overrides default repository stubs with concrete implementations.
    //
    // Step 5: Cold-boot VPN state resync and theme warm-up.
    // Queries native engine status (P4-T1) and loads persisted theme mode
    // before the navigation shell mounts, preventing visual flickers or desync.
    //
    // Step 6: Return container for UncontrolledProviderScope in main().
    // -------------------------------------------------------------------------
    return ProviderContainer(
        overrides: [
          appPreferencesRepositoryProvider.overrideWithValue(preferencesRepo),
          if (vpnEngineOverride != null)
            vpnEngineProvider.overrideWithValue(vpnEngineOverride)
          else if (Platform.isAndroid)
            vpnEngineProvider.overrideWith((ref) => AndroidVpnEngine()),
        ],
      )
      ..read(themeModeProvider)
      ..read(connectionStateProvider);
  }
}
