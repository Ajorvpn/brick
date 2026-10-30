// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:go_router/go_router.dart';
import 'package:mobile/core/presentation/widgets/app_shell.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/settings/presentation/screens/live_logs_screen.dart';
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
/// In Phase 4 (P4-T16), top-level tabs (Home and Settings) are hosted within
/// a [StatefulShellRoute.indexedStack] so that each tab preserves its own
/// navigation stack and scroll state.
///
/// `keepAlive: true` is deliberate and load-bearing (same reasoning as
/// `vpnEngineProvider`): a bare `@riverpod` generates an auto-dispose
/// provider, and a [GoRouter] that were disposed whenever the last watcher
/// unmounted would lose its navigation state. The router must live exactly
/// as long as the app.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'logs',
                    name: 'settings-logs',
                    builder: (context, state) => const LiveLogsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/add-server',
        name: 'add-server',
        builder: (context, state) => const AddServerScreen(),
      ),
    ],
  );
}
