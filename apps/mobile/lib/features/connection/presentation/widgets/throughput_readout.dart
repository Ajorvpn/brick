// SPDX-License-Identifier: GPL-3.0-or-later

// `intl` (re-exported by easy_localization) also defines a `TextDirection`
// whose constants are `LTR`/`RTL`; hide it so this file resolves Flutter's
// `dart:ui` `TextDirection` (with `.ltr`/`.rtl`) instead.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/connection/domain/formatters/traffic_formatter.dart';
import 'package:mobile/features/connection/presentation/providers/session_traffic_metrics_provider.dart';
import 'package:ui_theme/ui_theme.dart';

/// Shows cumulative up/down throughput and real-time instantaneous speed in an
/// Obsidian Glass telemetry card.
///
/// Designed with fine-grained Riverpod `.select(...)` rebuild isolation
/// (`ROADMAP.md` P6-T2 Acceptance Criterion 4):
/// - Neither `HomeScreen` nor the parent [ThroughputReadout] rebuilds on
///   continuous traffic ticks.
/// - `_CumulativeTotalsText` selects only formatted cumulative byte strings.
/// - `_InstantaneousSpeedText` selects only formatted speed strings.
/// - When stats error occurs on [sessionTrafficMetricsProvider], surfaces
///   `connection.traffic_unavailable` without disturbing the connection badge
///   (VpnEngine Invariant 2).
class ThroughputReadout extends ConsumerWidget {
  /// Creates the readout.
  const ThroughputReadout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.brickColors;
    final hasStatsError = ref.watch(
      sessionTrafficMetricsProvider.select((m) => m.hasError),
    );

    return BrickGlassCard(
      // Compact vertical rhythm: `HomeScreen`'s header is a fixed-height
      // Column (frozen for this micro-chunk), so the telemetry card must fit
      // the same footprint as the two plain text rows it replaced.
      padding: const EdgeInsets.symmetric(
        horizontal: BrickSpacing.md,
        vertical: BrickSpacing.xxs,
      ),
      child: hasStatsError
          ? Row(
              children: [
                Icon(
                  Icons.signal_cellular_nodata_rounded,
                  size: 16,
                  color: colors.textMuted,
                ),
                const SizedBox(width: BrickSpacing.xs),
                Expanded(
                  child: Text(
                    'connection.traffic_unavailable'.tr(),
                    key: const ValueKey<String>('throughput_readout'),
                    style: BrickTypography.monoLog(color: colors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InstantaneousSpeedText(),
                Divider(height: 1),
                _CumulativeTotalsText(),
              ],
            ),
    );
  }
}

/// 24dp tinted squircle used as a metric glyph holder.
class _MetricGlyph extends StatelessWidget {
  const _MetricGlyph({
    required this.icon,
    required this.background,
    required this.color,
  });

  final IconData icon;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(BrickRadius.sm),
      ),
      child: Center(child: Icon(icon, size: 14, color: color)),
    );
  }
}

class _InstantaneousSpeedText extends ConsumerWidget {
  const _InstantaneousSpeedText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.brickColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final speeds = ref.watch(
      sessionTrafficMetricsProvider.select(
        (m) => (
          TrafficFormatter.formatSpeed(m.txBytesPerSec),
          TrafficFormatter.formatSpeed(m.rxBytesPerSec),
        ),
      ),
    );

    return Row(
      children: [
        _MetricGlyph(
          icon: Icons.speed_rounded,
          background: colors.stateConnected.withValues(
            alpha: isDark ? 0.14 : 0.10,
          ),
          color: colors.stateConnected,
        ),
        const SizedBox(width: BrickSpacing.xs),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            // Directional so the label hugs the start edge in both LTR and RTL.
            alignment: AlignmentDirectional.centerStart,
            // `MiB/s` and `KiB` rates are technical data: LTR island under
            // Persian RTL.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                'connection.traffic_speed'.tr(
                  namedArgs: {'tx_speed': speeds.$1, 'rx_speed': speeds.$2},
                ),
                key: const ValueKey<String>('throughput_speed_readout'),
                maxLines: 1,
                style: BrickTypography.monoMetric(color: colors.textPrimary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CumulativeTotalsText extends ConsumerWidget {
  const _CumulativeTotalsText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.brickColors;
    final totals = ref.watch(
      sessionTrafficMetricsProvider.select(
        (m) => (
          TrafficFormatter.formatBytes(m.txBytes),
          TrafficFormatter.formatBytes(m.rxBytes),
        ),
      ),
    );

    return Row(
      children: [
        _MetricGlyph(
          icon: Icons.swap_vert_rounded,
          background: colors.brandBrickSoft,
          color: colors.brandBrick,
        ),
        const SizedBox(width: BrickSpacing.xs),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            // Directional so the label hugs the start edge in both LTR and RTL.
            alignment: AlignmentDirectional.centerStart,
            // Byte totals are technical data: LTR island under Persian RTL.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                'connection.traffic'.tr(
                  namedArgs: {'tx': totals.$1, 'rx': totals.$2},
                ),
                key: const ValueKey<String>('throughput_readout'),
                maxLines: 1,
                style: BrickTypography.monoLog(color: colors.textSecondary)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
