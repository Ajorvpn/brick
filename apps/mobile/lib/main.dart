// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/core/router/app_router.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:vpn_engine_android/vpn_engine_android.dart';

Future<void> main() async {
  // Required before any plugin (including the localization asset loader and
  // secure storage) is used, and before `runApp`.
  WidgetsFlutterBinding.ensureInitialized();

  // Loads the saved locale from device storage so the app starts in the
  // user's chosen language rather than always the fallback.
  await EasyLocalization.ensureInitialized();

  // `ProviderScope` is the root of the Riverpod container: every provider
  // in the app (`lib/core/`, and each feature's `presentation/providers/`)
  // is resolved from this scope. Keeping it here — and nowhere else — means
  // a test can replace the whole container by pumping its own
  // `ProviderScope` with `overrides:` (see CODING_STANDARDS.md Section 4).
  //
  // `EasyLocalization` must sit ABOVE `ProviderScope` so that the whole
  // subtree — including any provider that reads a localized string — shares
  // one locale. It is also the seam a widget test reproduces: see
  // `test/localization_test_harness.dart`.
  runApp(
    EasyLocalization(
      supportedLocales: const <Locale>[Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: ProviderScope(
        overrides: [
          if (Platform.isAndroid)
            vpnEngineProvider.overrideWith((ref) => AndroidVpnEngine()),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

/// Application root.
///
/// [ConsumerWidget] because it reads exactly one provider — the router —
/// and nothing else. Per CODING_STANDARDS.md Section 4, widgets should
/// watch only the specific providers they need; keeping this list at one
/// entry means unrelated state changes never rebuild the root.
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly listen to connectionStateProvider so the lifecycle observer
    // and native status reconciliation are active from app root without
    // causing unnecessary rebuilds of MaterialApp.
    ref.listen(connectionStateProvider, (_, _) {});

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      routerConfig: router,
      // `EasyLocalization` does not insert its delegate automatically: the
      // app must register it on `MaterialApp` or `.tr()` silently falls back
      // to returning the raw key.
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      // Localized: no hardcoded user-facing string (CODING_STANDARDS.md).
      onGenerateTitle: (context) => 'app_title'.tr(),
    );
  }
}
