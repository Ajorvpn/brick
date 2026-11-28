// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart' as domain;
// `intl` (re-exported by easy_localization) also defines a `TextDirection`
// whose constants are `LTR`/`RTL`; hide it so this file resolves Flutter's
// `dart:ui` `TextDirection` (with `.ltr`/`.rtl`) instead.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/connection/domain/entities/connection_location_target.dart';
import 'package:mobile/features/connection/domain/formatters/traffic_formatter.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/providers/session_duration_provider.dart';
import 'package:mobile/features/servers/domain/models/server_location_group.dart';
import 'package:ui_theme/ui_theme.dart';

/// Glanceable connection session info panel sitting alongside traffic stats
/// on `HomeScreen`.
///
/// Displays:
/// - Active server name and protocol type
/// - Engine state from the authoritative [connectionStateProvider]
/// - Live elapsed connection session duration
/// - Auto-reconnect progress and the Signal Crimson kill-switch alert
///
/// Rebuild isolation: each row is encapsulated in a dedicated [ConsumerWidget]
/// leaf so that 1 Hz duration timer ticks do NOT trigger rebuilds of the entire
/// panel, server info, or home screen.
class SessionInfoPanel extends StatelessWidget {
  const SessionInfoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const BrickGlassCard(
      key: ValueKey<String>('session_info_panel'),
      padding: EdgeInsets.all(BrickSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActiveServerText(),
          SizedBox(height: BrickSpacing.xs),
          Row(
            children: [
              Expanded(child: _SessionStatusText()),
              SizedBox(width: BrickSpacing.xs),
              // Flexible + scale-down keeps the duration readable instead of
              // overflowing the row at 1.5x / 2.0x system font sizes.
              Flexible(child: _SessionDurationText()),
            ],
          ),
          _SessionAutoReconnectText(),
          _KillSwitchBlockingBanner(),
        ],
      ),
    );
  }
}

class _ActiveServerText extends ConsumerWidget {
  const _ActiveServerText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.brickColors;
    final activeServer = ref.watch(activeServerProvider);
    final locationTarget = ref.watch(resolvedLocationTargetProvider);

    final String text;
    if (activeServer == null) {
      text = 'connection.session_location_none'.tr();
    } else {
      switch (locationTarget) {
        case SmartAutoTarget():
          text = 'connection.session_location'.tr(
            namedArgs: {'location': 'servers.smart_auto_title'.tr()},
          );
        case CountryTarget(:final countryCode):
          final countryName =
              countryCode == ServerLocationParser.unknownCountryCode
              ? 'servers.other_locations'.tr()
              : ServerLocationParser.countryNameForCode(countryCode);
          text = 'connection.session_location'.tr(
            namedArgs: {'location': countryName},
          );
      }
    }

    return Row(
      children: [
        Icon(Icons.public_rounded, size: 16, color: colors.brandBrick),
        const SizedBox(width: BrickSpacing.xs),
        Expanded(
          child: Text(
            text,
            key: const ValueKey<String>('session_server_text'),
            style: TextStyle(
              fontFamily: BrickTypography.primaryFontFamily,
              fontSize: BrickTypography.sizeBody,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SessionStatusText extends ConsumerWidget {
  const _SessionStatusText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.brickColors;
    final connStateAsync = ref.watch(connectionStateProvider);
    final prewarmed = ref.watch(initialConnectionStateProvider);
    final connState = connStateAsync.value ?? prewarmed;

    final String statusLabel;
    final Color statusColor;
    final bool isConnected;
    final bool isError;

    if (connStateAsync.isLoading && connState == null) {
      statusLabel = 'connection.state_checking'.tr();
      statusColor = colors.stateDisconnected;
      isConnected = false;
      isError = false;
    } else if (connState is domain.Connected) {
      statusLabel = 'connection.state_connected'.tr();
      statusColor = colors.stateConnected;
      isConnected = true;
      isError = false;
    } else if (connState is domain.Connecting) {
      statusLabel = 'connection.state_connecting'.tr();
      statusColor = colors.stateConnecting;
      isConnected = false;
      isError = false;
    } else if (connState is domain.Disconnecting) {
      statusLabel = 'connection.state_disconnecting'.tr();
      statusColor = colors.stateDisconnecting;
      isConnected = false;
      isError = false;
    } else if (connState is domain.Error) {
      statusLabel = 'connection.state_error'.tr();
      statusColor = colors.stateError;
      isConnected = false;
      isError = true;
    } else {
      statusLabel = 'connection.state_disconnected'.tr();
      statusColor = colors.stateDisconnected;
      isConnected = false;
      isError = false;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Non-pulsing by default: the dashboard never runs a ticker.
        BrickStatusDot(
          color: statusColor,
          size: 7,
          glow: isConnected || isError,
        ),
        const SizedBox(width: BrickSpacing.xs),
        Flexible(
          child: Text(
            'connection.session_status'.tr(namedArgs: {'status': statusLabel}),
            key: const ValueKey<String>('session_status_text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: BrickTypography.primaryFontFamily,
              fontSize: BrickTypography.sizeLabel,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionDurationText extends ConsumerWidget {
  const _SessionDurationText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.brickColors;
    final formattedDuration = ref.watch(
      sessionDurationProvider.select(TrafficFormatter.formatDuration),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(BrickRadius.xs),
        border: Border.all(color: colors.glassBorder),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        // Directional so the readout hugs the start edge in both LTR and RTL.
        alignment: AlignmentDirectional.centerStart,
        // `00:00:00` is technical data: LTR island under Persian RTL.
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            'connection.session_duration'.tr(
              namedArgs: {'duration': formattedDuration},
            ),
            key: const ValueKey<String>('session_duration_text'),
            maxLines: 1,
            style: BrickTypography.monoLog(color: colors.textPrimary)
                .copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _SessionAutoReconnectText extends ConsumerWidget {
  const _SessionAutoReconnectText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoReconnect = ref.watch(autoReconnectProvider);
    if (!autoReconnect.isReconnecting &&
        autoReconnect is! AutoReconnectExhausted) {
      return const SizedBox.shrink();
    }

    final colors = context.brickColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExhausted = autoReconnect is AutoReconnectExhausted;
    final accent = isExhausted ? colors.stateError : colors.stateConnecting;
    final icon = isExhausted
        ? Icons.error_outline_rounded
        : Icons.autorenew_rounded;

    final message = switch (autoReconnect) {
      AutoReconnectBackoff(:final attempt, :final maxAttempts, :final delay) =>
        'connection.reconnecting_backoff'.tr(
          namedArgs: {
            'attempt': attempt.toString(),
            'max': maxAttempts.toString(),
            'seconds': delay.inSeconds.toString(),
          },
        ),
      AutoReconnectWaitingForNetwork() =>
        'connection.reconnecting_waiting_network'.tr(),
      AutoReconnectInFlight(:final attempt, :final maxAttempts) =>
        'connection.reconnecting_in_flight'.tr(
          namedArgs: {
            'attempt': attempt.toString(),
            'max': maxAttempts.toString(),
          },
        ),
      AutoReconnectExhausted(:final totalAttempts) =>
        'connection.reconnecting_exhausted'.tr(
          namedArgs: {'max': totalAttempts.toString()},
        ),
      _ => 'connection.state_reconnecting'.tr(),
    };

    return Padding(
      padding: const EdgeInsets.only(top: BrickSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BrickSpacing.xs,
          vertical: BrickSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(BrickRadius.sm),
          border: Border.all(color: accent.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: BrickSpacing.xs),
            Expanded(
              child: KeyedSubtree(
                key: const ValueKey<String>('session_reconnecting_text'),
                child: Text(
                  message,
                  key: const ValueKey<String>('session_auto_reconnect_text'),
                  style: TextStyle(
                    fontFamily: BrickTypography.primaryFontFamily,
                    fontSize: BrickTypography.sizeLabel,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KillSwitchBlockingBanner extends ConsumerWidget {
  const _KillSwitchBlockingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final killSwitch = ref.watch(killSwitchProvider);
    if (killSwitch is! KillSwitchBlocking) {
      return const SizedBox.shrink();
    }

    final colors = context.brickColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: const ValueKey<String>('kill_switch_blocking_banner'),
      margin: const EdgeInsets.only(top: BrickSpacing.xs),
      padding: const EdgeInsets.all(BrickSpacing.sm),
      decoration: BoxDecoration(
        color: colors.killSwitchActive.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(BrickRadius.md),
        border: Border.all(
          color: colors.killSwitchActive.withValues(alpha: 0.55),
          width: 1.25,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.gpp_bad_rounded,
                size: 20,
                color: colors.killSwitchActive,
              ),
              const SizedBox(width: BrickSpacing.xs),
              Expanded(
                child: Text(
                  'connection.kill_switch_blocking_title'.tr(),
                  style: TextStyle(
                    fontFamily: BrickTypography.primaryFontFamily,
                    fontSize: BrickTypography.sizeBody,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: BrickSpacing.xxs),
          Text(
            'connection.kill_switch_blocking_body'.tr(),
            style: TextStyle(
              fontFamily: BrickTypography.primaryFontFamily,
              fontSize: BrickTypography.sizeLabel,
              fontWeight: FontWeight.w400,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: BrickSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              key: const ValueKey<String>('kill_switch_unblock_button'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.killSwitchActive,
                foregroundColor: colors.onAccent,
                minimumSize: const Size(
                  BrickSpacing.minTouchTarget,
                  BrickSpacing.minTouchTarget,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: BrickSpacing.md,
                ),
                textStyle: const TextStyle(
                  fontFamily: BrickTypography.primaryFontFamily,
                  fontSize: BrickTypography.sizeLabel,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text('connection.kill_switch_unblock'.tr()),
              onPressed: () {
                unawaited(
                  ref.read(connectionControllerProvider.notifier).disconnect(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
