// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/connection/domain/formatters/traffic_formatter.dart';
import 'package:mobile/features/connection/presentation/providers/session_traffic_metrics_provider.dart';

/// Shows cumulative up/down throughput and real-time instantaneous speed.
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
    final hasStatsError = ref.watch(
      sessionTrafficMetricsProvider.select((m) => m.hasError),
    );

    if (hasStatsError) {
      return Text(
        'connection.traffic_unavailable'.tr(),
        key: const ValueKey<String>('throughput_readout'),
      );
    }

    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CumulativeTotalsText(),
        SizedBox(height: 2),
        _InstantaneousSpeedText(),
      ],
    );
  }
}

class _CumulativeTotalsText extends ConsumerWidget {
  const _CumulativeTotalsText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(
      sessionTrafficMetricsProvider.select(
        (m) => (
          TrafficFormatter.formatBytes(m.txBytes),
          TrafficFormatter.formatBytes(m.rxBytes),
        ),
      ),
    );

    return Text(
      'connection.traffic'.tr(namedArgs: {'tx': totals.$1, 'rx': totals.$2}),
      key: const ValueKey<String>('throughput_readout'),
    );
  }
}

class _InstantaneousSpeedText extends ConsumerWidget {
  const _InstantaneousSpeedText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speeds = ref.watch(
      sessionTrafficMetricsProvider.select(
        (m) => (
          TrafficFormatter.formatSpeed(m.txBytesPerSec),
          TrafficFormatter.formatSpeed(m.rxBytesPerSec),
        ),
      ),
    );

    return Text(
      'connection.traffic_speed'.tr(
        namedArgs: {'tx_speed': speeds.$1, 'rx_speed': speeds.$2},
      ),
      key: const ValueKey<String>('throughput_speed_readout'),
    );
  }
}
