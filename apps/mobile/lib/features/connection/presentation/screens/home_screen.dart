// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/connection/presentation/widgets/connection_state_badge.dart';
import 'package:mobile/features/connection/presentation/widgets/server_tile.dart';
import 'package:mobile/features/connection/presentation/widgets/throughput_readout.dart';

/// Home screen for the `connection` feature.
///
/// Renders the saved-server list, a connect/disconnect affordance per
/// server, the live state badge, and live throughput.
///
/// ### The connection-state invariant
///
/// This screen renders connection state **only** through
/// [ConnectionStateBadge], which reads the engine's `connectionState`
/// stream. Tapping Connect calls `ConnectionController.connect`, whose
/// returned `Future` is deliberately **not** awaited into any state change:
/// a completed command means "accepted", not "connected"
/// (`VpnEngine` Invariant 1). Nothing here infers status from a button
/// press, which is the exact failure `connection/presentation/README.md`
/// forbids and which the legacy prototype shipped.
///
/// Every user-facing string comes from `assets/translations/en.json` via
/// `.tr()`; hardcoded strings are forbidden (CODING_STANDARDS.md).
///
/// Layering: `presentation/`. Depends on `domain/` and `presentation/`
/// siblings only — never on `data/` (CODING_STANDARDS.md Section 3.2).
class HomeScreen extends ConsumerWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(savedServersProvider);

    return Scaffold(
      appBar: AppBar(title: Text('home.title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ConnectionStateBadge(),
                const SizedBox(height: 8),
                const ThroughputReadout(),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.push('/add-server'),
                  child: Text('connection.add_server'.tr()),
                ),
              ],
            ),
          ),
          Expanded(child: _buildList(context, ref, servers)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton(
              // `context.push` keeps the route on the navigation stack so the
              // Settings screen can pop back here.
              onPressed: () => context.push('/settings'),
              child: Text('home.go_to_settings'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the saved-server list, or its loading/error/empty states.
  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SavedServer>> servers,
  ) {
    return servers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('connection.load_failed'.tr())),
      data: (entries) {
        if (entries.isEmpty) {
          return Center(child: Text('connection.no_servers'.tr()));
        }
        return ListView(
          children: [
            for (final entry in entries)
              ServerTile(
                server: entry,
                // `connect`/`disconnect` return a Future that is
                // deliberately NOT awaited here: a completed command means
                // "accepted", not "connected" (VpnEngine Invariant 1). The
                // badge updates only when the state stream emits.
                onConnect: (profile) {
                  unawaited(
                    ref
                        .read(connectionControllerProvider.notifier)
                        .connect(profile),
                  );
                },
                onDisconnect: () {
                  unawaited(
                    ref
                        .read(connectionControllerProvider.notifier)
                        .disconnect(),
                  );
                },
                onRemove: () {
                  unawaited(
                    ref
                        .read(savedServersProvider.notifier)
                        .removeServer(entry.id),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
