// SPDX-License-Identifier: GPL-3.0-or-later

// `intl` (re-exported by easy_localization) also defines a `TextDirection`
// whose constants are `LTR`/`RTL`; hide it so this file resolves Flutter's
// `dart:ui` `TextDirection` (with `.ltr`/`.rtl`) instead.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:ui_theme/ui_theme.dart';

/// Presentation tile representing a valid saved server profile.
///
/// Sculpted with Obsidian Glass styling, an interactive selection ring,
/// protocol pill, and compact action buttons.
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

  /// Invoked when the user taps the edit button (null for subscription
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
    final colors = context.brickColors;
    final profile = server.profile;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BrickSpacing.xxs),
      child: BrickGlassCard(
        key: ValueKey<String>('server_tile_${profile.id}'),
        isSelected: isSelected,
        accentColor: colors.brandBrick,
        padding: const EdgeInsets.symmetric(
          horizontal: BrickSpacing.md,
          vertical: BrickSpacing.sm,
        ),
        onTap: onSelect,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1 (Identity)
            Row(
              children: [
                // Leading Selection Ring (22 x 22 dp)
                AnimatedContainer(
                  duration: BrickMotion.standard,
                  curve: BrickMotion.curveStandard,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? colors.brandBrickSoft
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? colors.brandBrick
                          : colors.glassBorder,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: BrickStatusDot(
                            key: ValueKey<String>(
                              'server_selected_${profile.id}',
                            ),
                            color: colors.brandBrick,
                            size: 7,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    server.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                BrickProtocolPill(label: server.protocolLabel, compact: true),
              ],
            ),
            const SizedBox(height: 6),
            // Row 2 (Metadata Left + 48x48dp Actions Right)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // `host:port` is technical data: LTR island so Persian
                      // RTL never reorders the endpoint.
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          server.endpoint,
                          style: BrickTypography.monoLog(
                            color: colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceElevated,
                          borderRadius: BorderRadius.circular(BrickRadius.xs),
                          border: Border.all(
                            color: colors.glassBorder,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          sourceLabel,
                          style: TextStyle(
                            fontFamily: BrickTypography.primaryFontFamily,
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      IconButton(
                        key: ValueKey<String>('server_edit_${profile.id}'),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'servers.edit'.tr(),
                        onPressed: onEdit,
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        color: colors.textMuted,
                        constraints: const BoxConstraints(
                          minWidth: BrickSpacing.minTouchTarget,
                          minHeight: BrickSpacing.minTouchTarget,
                        ),
                      ),
                    if (onDuplicate != null)
                      IconButton(
                        key: ValueKey<String>('server_duplicate_${profile.id}'),
                        icon: const Icon(Icons.copy_outlined),
                        tooltip: 'servers.duplicate'.tr(),
                        onPressed: onDuplicate,
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        color: colors.textMuted,
                        constraints: const BoxConstraints(
                          minWidth: BrickSpacing.minTouchTarget,
                          minHeight: BrickSpacing.minTouchTarget,
                        ),
                      ),
                    IconButton(
                      key: ValueKey<String>('server_delete_${profile.id}'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'connection.remove'.tr(),
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      color: colors.textMuted,
                      constraints: const BoxConstraints(
                        minWidth: BrickSpacing.minTouchTarget,
                        minHeight: BrickSpacing.minTouchTarget,
                      ),
                    ),
                  ],
                ),
              ],
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
    final colors = context.brickColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BrickSpacing.xxs),
      child: BrickGlassCard(
        key: ValueKey<String>('server_broken_tile_${server.id}'),
        isSelected: true,
        accentColor: colors.stateError,
        padding: const EdgeInsets.symmetric(
          horizontal: BrickSpacing.md,
          vertical: BrickSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.stateError.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(BrickRadius.sm),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: colors.stateError,
                size: 20,
              ),
            ),
            const SizedBox(width: BrickSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'connection.broken_title'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.stateError,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    server.reason,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey<String>('server_delete_${server.id}'),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: colors.stateError,
              tooltip: 'connection.remove'.tr(),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: BrickSpacing.minTouchTarget,
                minHeight: BrickSpacing.minTouchTarget,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
