// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../brick_colors.dart';
import '../brick_tokens.dart';
import '../brick_typography.dart';
import 'brick_glass_card.dart';

/// Compact monospace telemetry readout card for metrics such as throughput,
/// session duration, and ping.
///
/// Values always use tabular figures so 1 Hz updates never shift horizontally,
/// and are wrapped in [FittedBox] so long strings (`128.45 MB/s`, `99:59:59`)
/// cannot overflow narrow 360dp phones.
class BrickTelemetryCard extends StatelessWidget {
  /// Creates a telemetry card.
  const BrickTelemetryCard({
    required this.label,
    required this.value,
    this.icon,
    this.accentColor,
    this.sublabel,
    this.prominent = false,
    super.key,
  });

  /// Uppercase tracked caption (e.g. `Download`).
  final String label;

  /// Monospace telemetry value (e.g. `128.45 MB/s`).
  final String value;

  /// Optional leading metric icon.
  final IconData? icon;

  /// Optional accent override; defaults to the brand brick hue.
  final Color? accentColor;

  /// Optional secondary monospace detail.
  final String? sublabel;

  /// Renders [value] with the larger `monoMetricLarge` style.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colors = context.brickColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveAccent = accentColor ?? colors.brandBrick;

    return BrickGlassCard(
      padding: const EdgeInsets.all(BrickSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: effectiveAccent.withValues(
                      alpha: isDark ? 0.14 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(BrickRadius.sm),
                  ),
                  child: Center(
                    child: Icon(icon, size: 16, color: effectiveAccent),
                  ),
                ),
                const SizedBox(width: BrickSpacing.xs),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: BrickTypography.uiStyle(
                    fontSize: BrickTypography.sizeLabel,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.8,
                    color: colors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: BrickSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: prominent
                  ? BrickTypography.monoMetricLarge(color: colors.textPrimary)
                  : BrickTypography.monoMetric(color: colors.textPrimary),
            ),
          ),
          if (sublabel != null) ...[
            const SizedBox(height: 4),
            Text(
              sublabel!,
              style: BrickTypography.monoLog(color: colors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
