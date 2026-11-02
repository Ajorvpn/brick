// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';

/// Presentation tile representing a valid saved server profile.
///
/// Modular and design-ready for Phase 11 styling and P5-T6 selection/actions.
class ServerProfileTile extends StatelessWidget {
  /// Creates a server profile tile.
  const ServerProfileTile({
    required this.server,
    required this.sourceLabel,
    required this.onDelete,
    this.onEdit,
    this.onDuplicate,
    this.isSelected = false,
    this.onSelect,
    super.key,
  });

  /// The parsed server profile model.
  final SavedServerProfile server;

  /// User-facing source label (e.g. 'Standalone' or parent subscription name).
  final String sourceLabel;

  /// Invoked when the user taps the remove button.
  final VoidCallback onDelete;

  /// Invoked when the user taps the edit button (null for subscription-sourced
  /// servers).
  final VoidCallback? onEdit;

  /// Invoked when the user taps the duplicate button.
  final VoidCallback? onDuplicate;

  /// Whether this server is the currently active/selected server.
  final bool isSelected;

  /// Invoked when the user taps the tile to select it as the active server.
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = server.profile;

    return Card(
      key: ValueKey<String>('server_tile_${profile.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        onTap: onSelect,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(
            server.protocolLabel.substring(0, 1).toUpperCase(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                server.name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                key: ValueKey<String>('server_selected_${profile.id}'),
                color: theme.colorScheme.primary,
                size: 20,
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  server.protocolLabel.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  server.endpoint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  sourceLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(
                key: ValueKey<String>('server_edit_${profile.id}'),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'servers.edit'.tr(),
                onPressed: onEdit,
              ),
            if (onDuplicate != null)
              IconButton(
                key: ValueKey<String>('server_duplicate_${profile.id}'),
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'servers.duplicate'.tr(),
                onPressed: onDuplicate,
              ),
            IconButton(
              key: ValueKey<String>('server_delete_${profile.id}'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'connection.remove'.tr(),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Presentation tile representing an unparseable or broken server entry.
class BrokenServerTile extends StatelessWidget {
  /// Creates a broken server tile.
  const BrokenServerTile({
    required this.server,
    required this.onDelete,
    super.key,
  });

  /// The broken server entity.
  final SavedServerBroken server;

  /// Invoked when the user taps the remove button.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: ValueKey<String>('server_broken_tile_${server.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.errorContainer,
          foregroundColor: theme.colorScheme.onErrorContainer,
          child: const Icon(Icons.warning_amber_rounded),
        ),
        title: Text(
          'connection.broken_title'.tr(),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        subtitle: Text(
          server.reason,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
        trailing: IconButton(
          key: ValueKey<String>('server_delete_${server.id}'),
          icon: const Icon(Icons.delete_outline),
          tooltip: 'connection.remove'.tr(),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
