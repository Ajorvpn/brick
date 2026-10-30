// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Root shell widget providing the Material 3 [NavigationBar] and hosting
/// stateful tab branches via [StatefulNavigationShell].
class AppShell extends StatelessWidget {
  /// Creates the app shell wrapping [navigationShell].
  const AppShell({required this.navigationShell, super.key});

  /// The navigation shell provided by [StatefulShellRoute.indexedStack].
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home),
            label: 'navigation.home'.tr(),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: 'navigation.settings'.tr(),
          ),
        ],
      ),
    );
  }
}
