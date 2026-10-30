// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/bootstrap/app_bootstrap.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/router/app_router.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';

Future<void> main() async {
  // Execute the explicit, ordered startup sequence:
  // 1. Flutter Bindings -> 2. Localization -> 3. Preferences (fallback)
  // -> 4. ProviderContainer -> 5. VPN Resync -> 6. Container Return.
  final container = await AppBootstrap.init();

  // `UncontrolledProviderScope` passes the bootstrap-initialized container
  // to the widget tree so all providers share the warmed-up state.
  //
  // `EasyLocalization` must sit ABOVE `UncontrolledProviderScope` so that
  // the whole subtree — including any provider that reads a localized
  // string — shares one locale.
  runApp(
    EasyLocalization(
      supportedLocales: const <Locale>[Locale('en'), Locale('de')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: UncontrolledProviderScope(
        container: container,
        child: const MyApp(),
      ),
    ),
  );
}

/// Application root.
///
/// [ConsumerWidget] because it reads the router and themeMode providers.
/// Per CODING_STANDARDS.md Section 4, widgets should watch only the specific
/// providers they need; keeping this list focused means unrelated state
/// changes never rebuild the root.
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly listen to connectionStateProvider so the lifecycle observer
    // and native status reconciliation are active from app root without
    // causing unnecessary rebuilds of MaterialApp.
    ref.listen(connectionStateProvider, (_, _) {});

    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      routerConfig: router,
      themeMode: themeMode,
      darkTheme: ThemeData.dark(),
      // `EasyLocalization` does not insert its delegate automatically: the
      // app must register it on `MaterialApp` or `.tr()` silently falls back
      // to returning the raw key.
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      // Localized: no hardcoded user-facing string (CODING_STANDARDS.md).
      onGenerateTitle: (context) => 'app_title'.tr(),
    );
  }
}
