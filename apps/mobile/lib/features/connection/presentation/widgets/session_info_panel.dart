// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart' as domain;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/connection/domain/formatters/traffic_formatter.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/session_duration_provider.dart';

/// Glanceable connection session info panel sitting alongside traffic stats
/// on `HomeScreen`.
///
/// Displays:
/// - Active server name and protocol type
/// - Engine state from the authoritative [connectionStateProvider]
/// - Live elapsed connection session duration
///
/// Rebuild isolation: each row is encapsulated in a dedicated [ConsumerWidget]
/// leaf so that 1 Hz duration timer ticks do NOT trigger rebuilds of the entire
/// panel, server info, or home screen.
class SessionInfoPanel extends StatelessWidget {
  const SessionInfoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      key: const ValueKey<String>('session_info_panel'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActiveServerText(),
            SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [_SessionStatusText(), _SessionDurationText()],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveServerText extends ConsumerWidget {
  const _ActiveServerText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeServer = ref.watch(activeServerProvider);
    final theme = Theme.of(context);

    final text = activeServer != null
        ? 'connection.session_server'.tr(
            namedArgs: {
              'name': activeServer.name,
              'protocol': activeServer.protocolLabel,
            },
          )
        : 'connection.session_server_none'.tr();

    return Text(
      text,
      key: const ValueKey<String>('session_server_text'),
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SessionStatusText extends ConsumerWidget {
  const _SessionStatusText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionStateProvider.select((s) => s.value));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final String statusLabel;
    final Color statusColor;

    if (connState is domain.Connected) {
      statusLabel = 'connection.state_connected'.tr();
      statusColor = scheme.primary;
    } else if (connState is domain.Connecting) {
      statusLabel = 'connection.state_connecting'.tr();
      statusColor = Colors.orange.shade800;
    } else if (connState is domain.Disconnecting) {
      statusLabel = 'connection.state_disconnecting'.tr();
      statusColor = Colors.orange.shade800;
    } else if (connState is domain.Error) {
      statusLabel = 'connection.state_error'.tr();
      statusColor = scheme.error;
    } else {
      statusLabel = 'connection.state_disconnected'.tr();
      statusColor = scheme.outline;
    }

    return Text(
      'connection.session_status'.tr(namedArgs: {'status': statusLabel}),
      key: const ValueKey<String>('session_status_text'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: statusColor,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _SessionDurationText extends ConsumerWidget {
  const _SessionDurationText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formattedDuration = ref.watch(
      sessionDurationProvider.select(TrafficFormatter.formatDuration),
    );
    final theme = Theme.of(context);

    return Text(
      'connection.session_duration'.tr(
        namedArgs: {'duration': formattedDuration},
      ),
      key: const ValueKey<String>('session_duration_text'),
      style: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
