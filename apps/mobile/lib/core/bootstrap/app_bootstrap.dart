// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:core_domain/core_domain.dart'
    show ConnectionState, Disconnected;
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/repositories/server_profile_repository.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
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
  ///    **Concurrency (Product Alignment #2):** steps 2, 3 and 4 are
  ///    independent I/O domains, so they are dispatched together and awaited
  ///    once via [Future.wait] instead of one-after-another. Cold-start
  ///    pre-frame cost therefore drops from `localization + preferences +
  ///    getStatus()` to `max(...)`.
  ///
  /// 4. **Riverpod Provider Container Assembly (`ProviderContainer`)**
  ///    Assembles the root container with all production overrides
  ///    ([appPreferencesRepositoryProvider] and [vpnEngineProvider]).
  ///
  /// 5. **Cold-Boot VPN Resync & Theme Warm-up**
  ///    Eagerly evaluates [themeModeProvider], [connectionControllerProvider]
  ///    and *starts* [connectionStateProvider] without awaiting it. Per P4-T1
  ///    the stream probes the native `VpnEngine.getStatus()` truth on startup,
  ///    and [initialConnectionStateProvider] already carries the same probe's
  ///    result so Frame 0 renders the true state.
  ///
  ///    **No pre-frame blocking (Product Alignment #2):** neither
  ///    `connectionStateProvider` nor `savedServersProvider` is awaited before
  ///    `runApp()`. Awaiting `connectionStateProvider.future` never resolves
  ///    from the pre-warmed emission, so it burned its entire 500 ms timeout on
  ///    every cold start while contributing nothing the first frame could
  ///    display. Awaiting `savedServersProvider.future` blocked the first frame
  ///    on disk reads plus Android Keystore decryption for the same reason.
  ///    Both providers are *started* (read into the container cascade) and
  ///    allowed to resolve after `runApp()`: `initialConnectionStateProvider`
  ///    already carries the probe's result so Frame 0 shows the true tunnel
  ///    state, and HomeScreen renders `BrickSkeletonBox` placeholders until the
  ///    decrypted server list lands.
  ///
  /// 6. **Container Return**
  ///    Returns the fully warmed [ProviderContainer] to the caller for
  ///    mounting into [UncontrolledProviderScope].
  static Future<ProviderContainer> init({
    Future<SharedPreferences> Function()? preferencesLoader,
    AppPreferencesRepository? preferencesRepositoryOverride,
    ServerProfileRepository? serverProfileRepositoryOverride,
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
    // Engine handle resolution is synchronous and side-effect free, so it is
    // hoisted here: the native status probe can then join the parallel cohort
    // below instead of queueing behind localization and disk reads.
    // -------------------------------------------------------------------------
    final engine =
        vpnEngineOverride ?? (Platform.isAndroid ? AndroidVpnEngine() : null);

    AppPreferencesRepository? preferencesRepo;
    ConnectionState initialStatus = const Disconnected();

    // -------------------------------------------------------------------------
    // Steps 2, 3 and 4 are independent, so they are STARTED together and only
    // awaited once (Product Alignment #2 — parallel cold-start bootstrap).
    // Serialising them added their latencies together; awaiting the same set
    // concurrently costs only the slowest leg.
    //
    // Step 2: localization — persisted locale must be ready before widgets.
    // Step 3: preferences — needed before theme + container assembly, with
    //         graceful degradation to an in-memory repository on any failure
    //         (disk corruption, missing channel, permission denied).
    // Step 4: native VPN status — bounded by a strict short timeout so a slow
    //         platform channel can never hold the first frame hostage; the
    //         result pre-warms `initialConnectionStateProvider` so Frame 0
    //         already renders the true state (no "Disconnected" flash).
    // -------------------------------------------------------------------------
    final localizationFuture = ensureLocalization
        ? EasyLocalization.ensureInitialized()
        : Future<void>.value();

    final preferencesFuture = () async {
      if (preferencesRepositoryOverride != null) {
        preferencesRepo = preferencesRepositoryOverride;
        return;
      }
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
    }();

    final statusFuture = () async {
      if (engine == null) {
        return;
      }
      try {
        initialStatus = await engine.getStatus().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => const Disconnected(),
        );
      } on Object {
        initialStatus = const Disconnected();
      }
    }();

    await Future.wait<void>([
      localizationFuture,
      preferencesFuture,
      statusFuture,
    ]);

    final resolvedPreferencesRepo =
        preferencesRepo ?? FakeAppPreferencesRepository();

    // -------------------------------------------------------------------------
    // Step 5: Assemble root Riverpod ProviderContainer.
    // Overrides default repository stubs with concrete implementations.
    //
    // Step 6: Cold-boot VPN state resync and theme warm-up.
    // Queries native engine status (P4-T1) and loads persisted theme mode
    // before the navigation shell mounts, preventing visual flickers or desync.
    //
    // Step 7: Return container for UncontrolledProviderScope in main().
    // -------------------------------------------------------------------------
    final container =
        ProviderContainer(
            overrides: [
              appPreferencesRepositoryProvider.overrideWithValue(
                resolvedPreferencesRepo,
              ),
              initialConnectionStateProvider.overrideWithValue(initialStatus),
              if (serverProfileRepositoryOverride != null)
                serverProfileRepositoryProvider.overrideWith(
                  (ref) => serverProfileRepositoryOverride,
                ),
              if (engine != null) vpnEngineProvider.overrideWithValue(engine),
            ],
          )
          ..read(themeModeProvider)
          ..read(connectionControllerProvider)
          // Start the state stream now so the native probe and lifecycle
          // observer are live before the shell mounts; do NOT await it.
          ..read(connectionStateProvider)
          // Kick off the disk/Keystore-backed server list eagerly too, but
          // never await it: HomeScreen paints `BrickSkeletonBox` placeholders
          // until the decrypted list lands, so blocking here would only add
          // pre-frame latency for a frame that is designed to show skeletons.
          ..read(savedServersProvider);

    return container;
  }
}
