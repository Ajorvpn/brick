// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:go_router/go_router.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// The app's [GoRouter] instance.
///
/// This is the single place where the route table is declared. Screens are
/// mapped to paths here and nowhere else, so adding a feature means adding
/// one entry to this list rather than threading navigation state through the
/// widget tree.
///
/// `keepAlive: true` is deliberate and load-bearing (same reasoning as
/// `vpnEngineProvider`): a bare `@riverpod` generates an auto-dispose
/// provider, and a [GoRouter] that were disposed whenever the last watcher
/// unmounted would lose its navigation state. The router must live exactly
/// as long as the app.
///
/// API note: `go_router` 18.x offers both the `GoRouter(routes: ...)`
/// constructor and the newer `GoRouter.routingConfig(routingConfig: ...)`
/// factory. Both are current and neither is deprecated; the constructor is
/// used here because it is the simplest form for a static route table, and
/// `routingConfig` is the right upgrade path if dynamic route lists are
/// needed later (verified against go_router 18.0.1 in the pub cache, not
/// assumed from training data).
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
