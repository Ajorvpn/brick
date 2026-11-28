// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart'
    show Connected, Connecting, ConnectionState, Disconnecting;
import 'package:core_domain/core_domain.dart' as domain show Error;
import 'package:core_vpn_engine/core_vpn_engine.dart' show VpnCommandAccepted;
// `intl` (re-exported by easy_localization) also defines a `TextDirection`
// whose constants are `LTR`/`RTL`; hide it so this file resolves Flutter's
// `dart:ui` `TextDirection` (with `.ltr`/`.rtl`) instead.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/features/connection/domain/entities/connection_location_target.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/connection/presentation/widgets/connection_state_badge.dart';
import 'package:mobile/features/connection/presentation/widgets/session_info_panel.dart';
import 'package:mobile/features/connection/presentation/widgets/throughput_readout.dart';
import 'package:mobile/features/servers/domain/models/server_location_group.dart';
import 'package:ui_theme/ui_theme.dart';

/// Home screen for the `connection` feature — the app's primary connection
/// dashboard ("Obsidian Glass & Brick Ember").
///
/// Layout: a compact brand bar (emblem, title, live state badge) over a
/// scrollable body holding the [BrickPowerOrb] hero control, the active-server
/// selector card, and the isolated telemetry/session cards.
///
/// ### The connection-state invariant
///
/// Every orb state, label and action is derived **only** from authoritative
/// streams (`connectionStateProvider`, `initialConnectionStateProvider`,
/// `autoReconnectProvider`, `killSwitchProvider`). Tapping the orb dispatches
/// an engine command, whose returned `Future` is deliberately never written
/// back into local state: a completed command means "accepted", not
/// "connected" (`VpnEngine` Invariant 1). Nothing here infers status from a
/// tap, which is the exact failure `connection/presentation/README.md`
/// forbids and which the legacy prototype shipped.
///
/// ### Rebuild isolation
///
/// This screen does not watch `sessionDurationProvider` or
/// `sessionTrafficMetricsProvider`; those live inside the `const`
/// `SessionInfoPanel()` and `const` `ThroughputReadout()` leaves. The saved
/// server list is watched through a narrow `.select` for loading/error status
/// only.
///
/// Every user-facing string comes from `assets/translations/en.json` via
/// `.tr()`; hardcoded strings are forbidden (CODING_STANDARDS.md).
///
/// Layering: `presentation/`. Depends on `domain/` and `presentation/`
/// siblings only — never on `data/` (CODING_STANDARDS.md Section 3.2).
class HomeScreen extends ConsumerWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<ConnectionState>>(connectionStateProvider, (
      previous,
      next,
    ) {
      next.when(
        data: (state) {
          final errorMessage = ErrorMapper.mapConnectionState(state);
          if (errorMessage != null) {
            AppFeedback.showError(context, errorMessage);
          }
        },
        error: (error, _) {
          final errorMessage = ErrorMapper.mapToUserMessage(error);
          AppFeedback.showError(context, errorMessage);
        },
        loading: () {},
      );
    });

    final locationTarget = ref.watch(resolvedLocationTargetProvider);
    final serversStatus = ref.watch(
      savedServersProvider.select((servers) {
        final list = servers.asData?.value;
        final int serverCount;
        if (list == null) {
          serverCount = 0;
        } else {
          serverCount = switch (locationTarget) {
            SmartAutoTarget() => list.whereType<SavedServerProfile>().length,
            CountryTarget(:final countryCode) =>
              list
                  .whereType<SavedServerProfile>()
                  .where(
                    (server) =>
                        ServerLocationParser.parse(server.name).countryCode ==
                        countryCode,
                  )
                  .length,
          };
        }
        return (
          isLoading: servers.isLoading,
          hasError: servers.hasError,
          serverCount: serverCount,
        );
      }),
    );
    final activeServer = ref.watch(activeServerProvider);
    final connStateAsync = ref.watch(connectionStateProvider);
    final prewarmed = ref.watch(initialConnectionStateProvider);
    ref.watch(connectionControllerProvider);
    final connectionState = connStateAsync.value ?? prewarmed;
    final isChecking = connStateAsync.isLoading && connectionState == null;
    final autoReconnect = ref.watch(autoReconnectProvider);
    final killSwitch = ref.watch(killSwitchProvider);

    final theme = Theme.of(context);
    final colors = context.brickColors;
    final isDark = theme.brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final isConnected = connectionState is Connected;
    final isConnectedOrConnecting =
        isConnected ||
        connectionState is Connecting ||
        autoReconnect.isReconnecting;

    final orbViewModel = _resolveOrbViewModel(
      connectionState: connectionState,
      isChecking: isChecking,
      autoReconnect: autoReconnect,
      killSwitch: killSwitch,
      hasActiveServer: activeServer != null,
      colors: colors,
    );

    final VoidCallback? orbOnTap;
    if (orbViewModel.isDisabled) {
      orbOnTap = null;
    } else if (killSwitch is KillSwitchBlocking || isConnectedOrConnecting) {
      orbOnTap = () => unawaited(_disconnect(context, ref));
    } else if (activeServer != null) {
      orbOnTap = () => unawaited(_connect(context, ref, locationTarget));
    } else {
      orbOnTap = () => context.go('/servers');
    }

    final orbKey =
        activeServer != null ||
            killSwitch is KillSwitchBlocking ||
            isConnectedOrConnecting
        ? const ValueKey<String>('home_connect_toggle_button')
        : const ValueKey<String>('home_connect_orb_idle');

    final orbSemanticLabel = killSwitch is KillSwitchBlocking
        ? 'connection.kill_switch_unblock'.tr()
        : activeServer != null
        ? (isConnectedOrConnecting
              ? 'connection.disconnect'.tr()
              : 'connection.connect'.tr())
        : 'home.browse_servers'.tr();

    return Scaffold(
      body: Stack(
        children: [
          // Layer 0 — ambient radial atmosphere. Gradient only: a single
          // `BoxDecoration` must never carry both `color` and `gradient`.
          // Only the accent color is tweened, and it is read from the orb view
          // model alone, so 1 Hz traffic/duration ticks never rebuild it.
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: orbViewModel.atmosphereColor),
                duration: reduceMotion
                    ? Duration.zero
                    : BrickMotion.stateTransition,
                curve: BrickMotion.curveStandard,
                builder: (context, atmosphereColor, _) {
                  return DecoratedBox(
                    key: const ValueKey<String>('home_atmosphere_glow'),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.35),
                        radius: 0.95,
                        colors: [
                          (atmosphereColor ?? orbViewModel.atmosphereColor)
                              .withValues(alpha: isDark ? 0.13 : 0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: BrickSpacing.maxReadableWidth,
                ),
                child: Column(
                  children: [
                    _buildBrandBar(
                      context,
                      theme: theme,
                      isConnected: isConnected,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        // `extendBody` floats the dock over this scrollable,
                        // so the bottom inset carries dock + gesture area.
                        padding: EdgeInsets.fromLTRB(
                          BrickSpacing.md,
                          BrickSpacing.lg,
                          BrickSpacing.md,
                          MediaQuery.paddingOf(context).bottom +
                              BrickSpacing.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: BrickPowerOrb(
                                key: orbKey,
                                state: orbViewModel.state,
                                statusLabel: orbViewModel.statusLabel,
                                actionHint: orbViewModel.actionHint,
                                semanticLabel: orbSemanticLabel,
                                onTap: orbOnTap,
                              ),
                            ),
                            const SizedBox(height: BrickSpacing.xl),
                            _buildServerCard(
                              context,
                              status: serversStatus,
                              activeServer: activeServer,
                              locationTarget: locationTarget,
                              isConnected: isConnected,
                            ),
                            const SizedBox(height: BrickSpacing.sm),
                            const ThroughputReadout(),
                            const SizedBox(height: BrickSpacing.sm),
                            const SessionInfoPanel(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact top brand bar: emblem, product title and live state badge.
  Widget _buildBrandBar(
    BuildContext context, {
    required ThemeData theme,
    required bool isConnected,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BrickSpacing.md,
        BrickSpacing.md,
        BrickSpacing.md,
        BrickSpacing.xs,
      ),
      child: Row(
        children: [
          BrickEmblemPlaceholder(size: 26, isConnected: isConnected),
          const SizedBox(width: BrickSpacing.sm),
          Expanded(
            child: Text(
              'home.title'.tr(),
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: BrickSpacing.xs),
          // Flexible + scale-down keeps the badge inside the bar when the
          // system font is enlarged (1.5x / 2.0x).
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              // Directional so the badge hugs the end edge in both LTR and RTL.
              alignment: AlignmentDirectional.centerEnd,
              child: ConnectionStateBadge(),
            ),
          ),
        ],
      ),
    );
  }

  /// Thumb-zone location selector: loading, error, active location
  /// (`Smart Auto` or selected country), or empty state routing to Servers.
  Widget _buildServerCard(
    BuildContext context, {
    required ({bool isLoading, bool hasError, int serverCount}) status,
    required SavedServerProfile? activeServer,
    required ConnectionLocationTarget locationTarget,
    required bool isConnected,
  }) {
    final theme = Theme.of(context);
    final colors = context.brickColors;

    if (status.isLoading && activeServer == null) {
      // Skeleton mirrors the active-location card's exact footprint (42dp
      // icon tile + title/subtitle bars) so nothing shifts when data lands.
      return const BrickGlassCard(
        key: ValueKey<String>('home_server_loading_skeleton'),
        elevated: true,
        child: Row(
          children: [
            BrickSkeletonBox(width: 42, height: 42),
            SizedBox(width: BrickSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrickSkeletonBox(height: 14),
                  SizedBox(height: BrickSpacing.xs),
                  FractionallySizedBox(
                    widthFactor: 0.6,
                    alignment: AlignmentDirectional.centerStart,
                    child: BrickSkeletonBox(height: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (status.hasError && activeServer == null) {
      return BrickGlassCard(
        isSelected: true,
        accentColor: colors.stateError,
        child: Text('connection.load_failed'.tr()),
      );
    }

    final server = activeServer;
    if (server != null) {
      final String leadingGlyph;
      final String title;
      final String subtitle;
      switch (locationTarget) {
        case SmartAutoTarget():
          leadingGlyph = '⚡';
          title = 'servers.smart_auto_title'.tr();
          subtitle = 'home.location_best_available'.tr();
        case CountryTarget(:final countryCode):
          leadingGlyph = ServerLocationParser.emojiForCountryCode(countryCode);
          title = countryCode == ServerLocationParser.unknownCountryCode
              ? 'servers.other_locations'.tr()
              : ServerLocationParser.countryNameForCode(countryCode);
          subtitle = status.serverCount == 1
              ? 'home.location_auto_selected_one'.tr()
              : 'home.location_auto_selected'.tr(
                  namedArgs: {'count': '${status.serverCount}'},
                );
      }

      return BrickGlassCard(
        key: const ValueKey<String>('home_active_server_card'),
        isSelected: isConnected,
        elevated: true,
        accentColor: isConnected ? colors.stateConnected : colors.brandBrick,
        onTap: () => context.go('/servers'),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(BrickRadius.md),
                border: Border.all(color: colors.glassBorder),
              ),
              child: Center(
                child: Text(leadingGlyph, style: const TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: BrickSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    key: const ValueKey<String>('home_active_server_name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: BrickTypography.primaryFontFamily,
                      fontSize: BrickTypography.sizeBody,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    key: const ValueKey<String>('home_active_server_subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: BrickTypography.primaryFontFamily,
                      fontSize: BrickTypography.sizeLabel,
                      fontWeight: FontWeight.w400,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: BrickSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colors.textMuted,
            ),
          ],
        ),
      );
    }

    return BrickGlassCard(
      key: const ValueKey<String>('home_empty_server_card'),
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.public_rounded, size: 20, color: colors.brandBrick),
              const SizedBox(width: BrickSpacing.xs),
              Expanded(
                child: Text(
                  'connection.no_servers'.tr(),
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
            'home.choose_server_subtitle'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: BrickSpacing.md),
          FilledButton.icon(
            key: const ValueKey<String>('home_browse_servers_button'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.brandBrick,
              foregroundColor: colors.onAccent,
              minimumSize: const Size.fromHeight(BrickSpacing.minTouchTarget),
            ),
            onPressed: () => context.go('/servers'),
            icon: const Icon(Icons.public_rounded, size: 18),
            label: Text('home.browse_servers'.tr()),
          ),
        ],
      ),
    );
  }
}

/// Immutable view model describing exactly how the orb should render.
@immutable
final class _OrbViewModel {
  const _OrbViewModel({
    required this.state,
    required this.statusLabel,
    required this.atmosphereColor,
    this.actionHint,
    this.isDisabled = false,
  });

  final BrickOrbState state;
  final String statusLabel;
  final String? actionHint;
  final Color atmosphereColor;
  final bool isDisabled;
}

/// Maps authoritative engine/safety state to the orb view model.
///
/// Priority order mirrors the peripheral beacon in `app_shell.dart`: the
/// kill switch (fail-closed leak protection) outranks everything, then
/// auto-reconnect, then the engine's own state.
_OrbViewModel _resolveOrbViewModel({
  required ConnectionState? connectionState,
  required bool isChecking,
  required AutoReconnectState autoReconnect,
  required KillSwitchState killSwitch,
  required bool hasActiveServer,
  required BrickSemanticColors colors,
}) {
  final connectHint = hasActiveServer
      ? 'home.tap_to_connect'.tr()
      : 'home.select_server_hint'.tr();

  if (killSwitch is KillSwitchBlocking) {
    return _OrbViewModel(
      state: BrickOrbState.killSwitch,
      statusLabel: 'home.orb_status_kill_switch'.tr(),
      actionHint: 'home.tap_to_unblock'.tr(),
      atmosphereColor: colors.killSwitchActive,
    );
  }

  if (autoReconnect.isReconnecting) {
    return _OrbViewModel(
      state: BrickOrbState.reconnecting,
      statusLabel: 'connection.state_reconnecting'.tr(),
      actionHint: 'home.tap_to_cancel'.tr(),
      atmosphereColor: colors.stateConnecting,
    );
  }

  if (isChecking) {
    return _OrbViewModel(
      state: BrickOrbState.connecting,
      statusLabel: 'connection.state_checking'.tr(),
      atmosphereColor: colors.stateConnecting,
      isDisabled: true,
    );
  }

  if (connectionState is Connected) {
    return _OrbViewModel(
      state: BrickOrbState.connected,
      statusLabel: 'connection.state_connected'.tr(),
      actionHint: 'home.tap_to_disconnect'.tr(),
      atmosphereColor: colors.stateConnected,
    );
  }

  if (connectionState is Connecting) {
    return _OrbViewModel(
      state: BrickOrbState.connecting,
      statusLabel: 'connection.state_connecting'.tr(),
      actionHint: 'home.tap_to_cancel'.tr(),
      atmosphereColor: colors.stateConnecting,
    );
  }

  if (connectionState is Disconnecting) {
    return _OrbViewModel(
      state: BrickOrbState.disconnecting,
      statusLabel: 'connection.state_disconnecting'.tr(),
      atmosphereColor: colors.stateDisconnecting,
      isDisabled: true,
    );
  }

  if (connectionState is domain.Error) {
    return _OrbViewModel(
      state: BrickOrbState.error,
      statusLabel: 'connection.state_error'.tr(),
      actionHint: connectHint,
      atmosphereColor: colors.stateError,
    );
  }

  return _OrbViewModel(
    state: BrickOrbState.disconnected,
    statusLabel: 'connection.state_disconnected'.tr(),
    actionHint: connectHint,
    atmosphereColor: colors.brandBrick,
  );
}

/// Dispatches a connect command and surfaces diagnostics on rejection.
///
/// The accepted result is intentionally discarded: acceptance is not
/// connection (`VpnEngine` Invariant 1).
Future<void> _connect(
  BuildContext context,
  WidgetRef ref,
  ConnectionLocationTarget locationTarget,
) async {
  final result = await ref
      .read(connectionControllerProvider.notifier)
      .connectForTarget(locationTarget);
  if (context.mounted && result is! VpnCommandAccepted) {
    AppFeedback.showError(context, ErrorMapper.mapToUserMessage(result));
  }
}

/// Dispatches a disconnect command (which also cancels reconnect and unblocks
/// kill-switch lockdown) and surfaces diagnostics on rejection.
Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
  final result = await ref
      .read(connectionControllerProvider.notifier)
      .disconnect();
  if (context.mounted && result is! VpnCommandAccepted) {
    AppFeedback.showError(context, ErrorMapper.mapToUserMessage(result));
  }
}
