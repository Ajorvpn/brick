// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/servers/presentation/providers/server_list_provider.dart';
import 'package:mobile/features/servers/presentation/widgets/server_profile_tile.dart';

/// Screen displaying the user's saved and subscription-sourced servers.
///
/// Features:
/// 1. Reactive Riverpod integration via [groupedServerListProvider].
/// 2. Structural & visual distinction between standalone and
///    subscription-sourced servers.
/// 3. Rich empty state with clear CTAs to add server or subscription.
/// 4. Direct add actions in AppBar.
/// 5. Safe broken-server handling without credential leakage.
class ServersScreen extends ConsumerWidget {
  /// Creates the servers screen.
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(groupedServerListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('servers.title'.tr()),
        actions: [
          IconButton(
            key: const ValueKey<String>('servers_add_server_action'),
            icon: const Icon(Icons.add),
            tooltip: 'connection.add_server'.tr(),
            onPressed: () => context.push('/add-server'),
          ),
          IconButton(
            key: const ValueKey<String>('servers_add_subscription_action'),
            icon: const Icon(Icons.rss_feed),
            tooltip: 'connection.add_subscription'.tr(),
            onPressed: () => context.push('/add-subscription'),
          ),
        ],
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('connection.load_failed'.tr())),
        data: (data) {
          if (data.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildPopulatedList(context, ref, data);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'servers.empty_title'.tr(),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'servers.empty_subtitle'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey<String>('servers_empty_add_server_button'),
              icon: const Icon(Icons.add),
              label: Text('connection.add_server'.tr()),
              onPressed: () => context.push('/add-server'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey<String>(
                'servers_empty_add_subscription_button',
              ),
              icon: const Icon(Icons.rss_feed),
              label: Text('connection.add_subscription'.tr()),
              onPressed: () => context.push('/add-subscription'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopulatedList(
    BuildContext context,
    WidgetRef ref,
    GroupedServerList data,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      children: [
        if (data.standalone.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            title: 'servers.standalone_section'.tr(),
            count: data.standalone.length,
            isSubscription: false,
          ),
          for (final server in data.standalone)
            ServerProfileTile(
              server: server,
              sourceLabel: 'servers.standalone_badge'.tr(),
              onDelete: () => ref
                  .read(savedServersProvider.notifier)
                  .removeServer(server.id),
            ),
          const SizedBox(height: 16),
        ],
        for (final entry in data.subscriptionGroups.entries) ...[
          _buildSectionHeader(
            context,
            title: entry.key.name,
            count: entry.value.length,
            isSubscription: true,
          ),
          for (final server in entry.value)
            ServerProfileTile(
              server: server,
              sourceLabel: entry.key.name,
              onDelete: () => ref
                  .read(savedServersProvider.notifier)
                  .removeServer(server.id),
            ),
          const SizedBox(height: 16),
        ],
        if (data.broken.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            title: 'connection.broken_title'.tr(),
            count: data.broken.length,
            isSubscription: false,
          ),
          for (final broken in data.broken)
            BrokenServerTile(
              server: broken,
              onDelete: () => ref
                  .read(savedServersProvider.notifier)
                  .removeServer(broken.id),
            ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required int count,
    required bool isSubscription,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            isSubscription ? Icons.rss_feed : Icons.dns,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(count.toString(), style: theme.textTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}
