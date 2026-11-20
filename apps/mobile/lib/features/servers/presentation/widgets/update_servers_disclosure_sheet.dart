// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:ui_theme/ui_theme.dart';

/// Modal bottom sheet presenting a Google Play-compliant privacy disclosure
/// before fetching remote server directory updates.
class UpdateServersDisclosureSheet extends StatelessWidget {
  /// Creates an update servers disclosure sheet.
  const UpdateServersDisclosureSheet({super.key});

  /// Displays the disclosure sheet as a modal bottom sheet, returning true
  /// when the user accepts or false/null when cancelled.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UpdateServersDisclosureSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.brickColors;

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: BrickSpacing.maxReadableWidth,
        ),
        child: Container(
          key: const ValueKey<String>('update_servers_disclosure_sheet'),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(BrickRadius.sheet),
            ),
            border: Border(top: BorderSide(color: colors.glassBorder)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BrickSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Drag Handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: BrickSpacing.lg),
                      decoration: BoxDecoration(
                        color: colors.glassBorder,
                        borderRadius: BorderRadius.circular(BrickRadius.pill),
                      ),
                    ),
                  ),

                  // Header Emblem & Titles
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: colors.brandBrickSoft,
                          borderRadius: BorderRadius.circular(BrickRadius.card),
                          border: Border.all(
                            color: colors.brandBrick.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Center(
                          child: BrickEmblemPlaceholder(size: 36),
                        ),
                      ),
                      const SizedBox(width: BrickSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'servers.disclosure_title'.tr(),
                              style: TextStyle(
                                fontFamily: BrickTypography.primaryFontFamily,
                                fontSize: BrickTypography.sizeTitle,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: BrickSpacing.xxs),
                            Text(
                              'servers.disclosure_body'.tr(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: BrickSpacing.lg),

                  // 3 Trust-Pillar Rows
                  BrickGlassCard(
                    child: Column(
                      children: [
                        _TrustPointRow(
                          icon: Icons.lock_outline_rounded,
                          iconColor: colors.stateConnected,
                          text: 'servers.disclosure_point_encrypted'.tr(),
                        ),
                        const SizedBox(height: BrickSpacing.sm),
                        _TrustPointRow(
                          icon: Icons.visibility_off_outlined,
                          iconColor: colors.brandBrick,
                          text: 'servers.disclosure_point_zero_telemetry'.tr(),
                        ),
                        const SizedBox(height: BrickSpacing.sm),
                        _TrustPointRow(
                          icon: Icons.enhanced_encryption_outlined,
                          iconColor: colors.brandBrick,
                          text: 'servers.disclosure_point_local_storage'.tr(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: BrickSpacing.xl),

                  // Action Buttons
                  FilledButton(
                    key: const ValueKey<String>(
                      'update_servers_disclosure_accept',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: colors.brandBrick,
                      foregroundColor: colors.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BrickRadius.md),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      'servers.disclosure_accept'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: BrickSpacing.xs),
                  OutlinedButton(
                    key: const ValueKey<String>(
                      'update_servers_disclosure_cancel',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      side: BorderSide(color: colors.glassBorder),
                      foregroundColor: colors.textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BrickRadius.md),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('servers.disclosure_cancel'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustPointRow extends StatelessWidget {
  const _TrustPointRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.brickColors;

    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: BrickSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: BrickTypography.primaryFontFamily,
              fontSize: BrickTypography.sizeBody,
              color: colors.textPrimary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
