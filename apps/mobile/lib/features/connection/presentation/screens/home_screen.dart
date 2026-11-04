// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart'
    show Connected, Connecting, ConnectionState, Disconnecting;
import 'package:core_vpn_engine/core_vpn_engine.dart' show VpnCommandAccepted;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
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
    ref.listen<AsyncValue<ConnectionState>>(connectionStateProvider, (
      previous,
      next,
    ) {
      next.when(
        data: (state) {
          final errorMessage = ErrorMapper.mapConnectionState(state);
          if (errorMessage != null) {
            AppFeedback.showError(context, errorMessage);
          }
        },
        error: (error, _) {
          final errorMessage = ErrorMapper.mapToUserMessage(error);
          AppFeedback.showError(context, errorMessage);
        },
        loading: () {},
      );
    });

    final servers = ref.watch(savedServersProvider);
    final activeServer = ref.watch(activeServerProvider);
    final connectionState = ref.watch(connectionStateProvider).value;

    final isConnecting = connectionState is Connecting;
    final isConnected = connectionState is Connected;
    final isDisconnecting = connectionState is Disconnecting;
    final isConnectedOrConnecting = isConnected || isConnecting;

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
                if (activeServer != null) ...[
                  Card(
                    key: const ValueKey<String>('home_active_server_card'),
                    child: ListTile(
                      leading: Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        'home.active_server_prefix'.tr(
                          namedArgs: {'name': activeServer.name},
                        ),
                        key: const ValueKey<String>('home_active_server_name'),
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${activeServer.protocolLabel} · '
                        '${activeServer.endpoint}',
                        key: const ValueKey<String>(
                          'home_active_server_endpoint',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: FilledButton(
                        key: const ValueKey<String>(
                          'home_connect_toggle_button',
                        ),
                        onPressed: isDisconnecting
                            ? null
                            : () async {
                                if (isConnectedOrConnecting) {
                                  final result = await ref
                                      .read(
                                        connectionControllerProvider.notifier,
                                      )
                                      .disconnect();
                                  if (context.mounted &&
                                      result is! VpnCommandAccepted) {
                                    AppFeedback.showError(
                                      context,
                                      ErrorMapper.mapToUserMessage(result),
                                    );
                                  }
                                } else {
                                  final result = await ref
                                      .read(
                                        connectionControllerProvider.notifier,
                                      )
                                      .connect(activeServer.profile);
                                  if (context.mounted &&
                                      result is! VpnCommandAccepted) {
                                    AppFeedback.showError(
                                      context,
                                      ErrorMapper.mapToUserMessage(result),
                                    );
                                  }
                                }
                              },
                        child: Text(
                          isConnectedOrConnecting
                              ? 'connection.disconnect'.tr()
                              : isDisconnecting
                              ? 'connection.state_disconnecting'.tr()
                              : 'connection.connect'.tr(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  key: const ValueKey<String>('home_add_server_button'),
                  onPressed: () => context.push('/add-server'),
                  child: Text('connection.add_server'.tr()),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey<String>('home_add_subscription_button'),
                  onPressed: () => context.push('/add-subscription'),
                  child: Text('connection.add_subscription'.tr()),
                ),
              ],
            ),
          ),
          Expanded(child: _buildList(context, ref, servers)),
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
                onConnect: (profile) async {
                  unawaited(
                    ref
                        .read(activeServerIdProvider.notifier)
                        .selectServer(profile.id),
                  );
                  final result = await ref
                      .read(connectionControllerProvider.notifier)
                      .connect(profile);
                  if (context.mounted && result is! VpnCommandAccepted) {
                    AppFeedback.showError(
                      context,
                      ErrorMapper.mapToUserMessage(result),
                    );
                  }
                },
                onDisconnect: () async {
                  final result = await ref
                      .read(connectionControllerProvider.notifier)
                      .disconnect();
                  if (context.mounted && result is! VpnCommandAccepted) {
                    AppFeedback.showError(
                      context,
                      ErrorMapper.mapToUserMessage(result),
                    );
                  }
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
