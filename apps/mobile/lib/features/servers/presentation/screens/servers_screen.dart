// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart' show ServerProfile;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:mobile/features/servers/presentation/providers/server_list_provider.dart';
import 'package:mobile/features/servers/presentation/providers/server_management_controller.dart';
import 'package:mobile/features/servers/presentation/widgets/server_profile_tile.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

/// Screen displaying the user's saved and subscription-sourced servers.
///
/// Features:
/// 1. Reactive Riverpod integration via [groupedServerListProvider].
/// 2. Structural & visual distinction between standalone and
///    subscription-sourced servers.
/// 3. Rich empty state with clear CTAs to add server or subscription.
/// 4. Direct add actions in AppBar.
/// 5. Safe broken-server handling without credential leakage.
/// 6. Server actions: Edit (standalone only), Duplicate (to standalone), and
///    Delete with confirmation dialog.
/// 7. Subscription actions: Refresh with Full-Replace diffing policy and Delete
///    with cascade confirmation dialog.
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
          _buildStandaloneSectionHeader(
            context,
            title: 'servers.standalone_section'.tr(),
            count: data.standalone.length,
          ),
          for (final server in data.standalone)
            ServerProfileTile(
              server: server,
              sourceLabel: 'servers.standalone_badge'.tr(),
              onEdit: () => _showEditDialog(context, ref, server.profile),
              onDuplicate: () => _handleDuplicate(context, ref, server.profile),
              onDelete: () => _showConfirmDeleteDialog(
                context,
                title: 'servers.delete_server_title'.tr(),
                message: 'servers.delete_server_message'.tr(),
                onConfirm: () => _handleDeleteServer(context, ref, server.id),
              ),
            ),
          const SizedBox(height: 16),
        ],
        for (final entry in data.subscriptionGroups.entries) ...[
          _buildSubscriptionSectionHeader(
            context,
            ref,
            subscription: entry.key,
            count: entry.value.length,
          ),
          for (final server in entry.value)
            ServerProfileTile(
              server: server,
              sourceLabel: entry.key.name,
              onDuplicate: () => _handleDuplicate(context, ref, server.profile),
              onDelete: () => _showConfirmDeleteDialog(
                context,
                title: 'servers.delete_server_title'.tr(),
                message: 'servers.delete_server_message'.tr(),
                onConfirm: () => _handleDeleteServer(context, ref, server.id),
              ),
            ),
          const SizedBox(height: 16),
        ],
        if (data.broken.isNotEmpty) ...[
          _buildStandaloneSectionHeader(
            context,
            title: 'connection.broken_title'.tr(),
            count: data.broken.length,
          ),
          for (final broken in data.broken)
            BrokenServerTile(
              server: broken,
              onDelete: () => _showConfirmDeleteDialog(
                context,
                title: 'servers.delete_server_title'.tr(),
                message: 'servers.delete_server_message'.tr(),
                onConfirm: () => _handleDeleteServer(context, ref, broken.id),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildStandaloneSectionHeader(
    BuildContext context, {
    required String title,
    required int count,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.dns, size: 20, color: theme.colorScheme.primary),
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

  Widget _buildSubscriptionSectionHeader(
    BuildContext context,
    WidgetRef ref, {
    required SubscriptionMetadata subscription,
    required int count,
  }) {
    final theme = Theme.of(context);
    final isRefreshing =
        ref
            .watch(serverManagementControllerProvider)
            .value
            ?.contains(subscription.id) ??
        false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(Icons.rss_feed, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subscription.name,
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
          if (isRefreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              key: ValueKey<String>('subscription_refresh_${subscription.id}'),
              icon: const Icon(Icons.refresh),
              tooltip: 'servers.refresh_subscription'.tr(),
              onPressed: () =>
                  _handleRefreshSubscription(context, ref, subscription),
            ),
          IconButton(
            key: ValueKey<String>('subscription_delete_${subscription.id}'),
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'servers.delete_subscription'.tr(),
            onPressed: () => _showConfirmDeleteDialog(
              context,
              title: 'servers.delete_subscription_title'.tr(),
              message: 'servers.delete_subscription_message'.tr(),
              onConfirm: () =>
                  _handleDeleteSubscription(context, ref, subscription.id),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRefreshSubscription(
    BuildContext context,
    WidgetRef ref,
    SubscriptionMetadata subscription,
  ) async {
    final result = await ref
        .read(serverManagementControllerProvider.notifier)
        .refreshSubscription(subscription);

    if (!context.mounted) return;

    switch (result) {
      case Ok(:final value):
        if (value.skippedCount > 0) {
          AppFeedback.showSuccess(
            context,
            'add_subscription.partial_success_message'.tr(
              namedArgs: {
                'count': value.importedCount.toString(),
                'skipped': value.skippedCount.toString(),
              },
            ),
          );
        } else {
          AppFeedback.showSuccess(
            context,
            'add_subscription.success_message'.tr(
              namedArgs: {'count': value.importedCount.toString()},
            ),
          );
        }
      case Err(:final error):
        AppFeedback.showError(context, ErrorMapper.mapToUserMessage(error));
    }
  }

  Future<void> _handleDeleteSubscription(
    BuildContext context,
    WidgetRef ref,
    String subscriptionId,
  ) async {
    final result = await ref
        .read(serverManagementControllerProvider.notifier)
        .deleteSubscription(subscriptionId);

    if (!context.mounted) return;

    if (result case Err(:final error)) {
      AppFeedback.showError(context, ErrorMapper.mapToUserMessage(error));
    }
  }

  Future<void> _handleDeleteServer(
    BuildContext context,
    WidgetRef ref,
    String serverId,
  ) async {
    final result = await ref
        .read(serverManagementControllerProvider.notifier)
        .deleteServer(serverId);

    if (!context.mounted) return;

    if (result case Err(:final error)) {
      AppFeedback.showError(context, ErrorMapper.mapToUserMessage(error));
    }
  }

  Future<void> _handleDuplicate(
    BuildContext context,
    WidgetRef ref,
    ServerProfile profile,
  ) async {
    final result = await ref
        .read(serverManagementControllerProvider.notifier)
        .duplicateServer(profile);

    if (!context.mounted) return;

    if (result case Err(:final error)) {
      AppFeedback.showError(context, ErrorMapper.mapToUserMessage(error));
    }
  }

  Future<void> _showConfirmDeleteDialog(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey<String>('confirm_delete_dialog'),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            key: const ValueKey<String>('confirm_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('servers.cancel'.tr()),
          ),
          FilledButton(
            key: const ValueKey<String>('confirm_delete_confirm'),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await onConfirm();
            },
            child: Text('servers.confirm_delete'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    ServerProfile profile,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _EditServerDialog(profile: profile),
    );
  }
}

class _EditServerDialog extends ConsumerStatefulWidget {
  const _EditServerDialog({required this.profile});

  final ServerProfile profile;

  @override
  ConsumerState<_EditServerDialog> createState() => _EditServerDialogState();
}

class _EditServerDialogState extends ConsumerState<_EditServerDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _uriController;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _uriController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      final msg = 'servers.name_required'.tr();
      setState(() => _errorMessage = msg);
      AppFeedback.showError(context, msg);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final newUri = _uriController.text.trim();
    final result = await ref
        .read(serverManagementControllerProvider.notifier)
        .editServer(
          existing: widget.profile,
          newName: newName,
          newRawUri: newUri.isNotEmpty ? newUri : null,
        );

    if (!mounted) return;

    setState(() => _isLoading = false);

    switch (result) {
      case Ok():
        Navigator.of(context).pop();
      case Err(:final error):
        final msg = ErrorMapper.mapToUserMessage(error);
        setState(() => _errorMessage = msg);
        AppFeedback.showError(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('edit_server_dialog'),
      title: Text('servers.edit_server_title'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey<String>('edit_server_name_field'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'servers.server_name'.tr(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey<String>('edit_server_uri_field'),
              controller: _uriController,
              decoration: InputDecoration(
                labelText: 'servers.replacement_uri'.tr(),
                hintText: 'servers.replacement_uri_hint'.tr(),
              ),
              enabled: !_isLoading,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('edit_server_cancel'),
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text('servers.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey<String>('edit_server_save'),
          onPressed: _isLoading ? null : _handleSave,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('servers.save'.tr()),
        ),
      ],
    );
  }
}
