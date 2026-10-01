// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';

/// Shows cumulative up/down throughput.
///
/// Reads only `trafficStatsProvider`. Because that provider is backed by a
/// stream independent of the connection-state stream (`VpnEngine` Invariant
/// 2), a stats failure surfaces here as an error without ever disturbing the
/// connection badge next to it.
class ThroughputReadout extends ConsumerWidget {
  /// Creates the readout.
  const ThroughputReadout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(trafficStatsProvider);

    return stats.when(
      loading: () => Text(
        'connection.traffic_none'.tr(),
        key: const ValueKey<String>('throughput_readout'),
      ),
      error: (error, stackTrace) => Text(
        'connection.traffic_unavailable'.tr(),
        key: const ValueKey<String>('throughput_readout'),
      ),
      data: (value) => Text(
        // Byte counts only — never the remote host or any config detail.
        'connection.traffic'
            .tr()
            .replaceAll('{tx}', _formatBytes(value.txBytes))
            .replaceAll('{rx}', _formatBytes(value.rxBytes)),
        key: const ValueKey<String>('throughput_readout'),
      ),
    );
  }

  /// Formats [bytes] with a binary unit suffix.
  ///
  /// A plain `num`/unit formatter rather than pulling in an intl dependency
  /// for two numbers; the exact wording of "1.2 MB" is not load-bearing.
  String _formatBytes(int bytes) {
    const units = <String>['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final rendered = unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$rendered ${units[unit]}';
  }
}
