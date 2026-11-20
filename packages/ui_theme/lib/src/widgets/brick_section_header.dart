// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../brick_colors.dart';
import '../brick_tokens.dart';
import '../brick_typography.dart';

/// Refined micro-section header for country lists, settings groups, and telemetry bands.
class BrickSectionHeader extends StatelessWidget {
  const BrickSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.countLabel,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final String? countLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.brickColors;

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14.0, color: colors.textMuted),
          const SizedBox(width: BrickSpacing.xs),
        ],
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontFamily: BrickTypography.primaryFontFamily,
            fontSize: BrickTypography.sizeLabel,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.8,
            color: colors.textMuted,
          ),
        ),
        if (countLabel != null) ...[
          const SizedBox(width: BrickSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(BrickRadius.xs),
              border: Border.all(color: colors.glassBorder, width: 1.0),
            ),
            child: Text(
              countLabel!,
              style: BrickTypography.monoLog(color: colors.textMuted)
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}
