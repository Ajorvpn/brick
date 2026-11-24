// SPDX-License-Identifier: GPL-3.0-or-later

// Flutter's own `ConnectionState` (from `package:flutter/src/widgets/async.dart`)
// collides by name with the domain type; hide Flutter's so the exhaustive
// switch below stays exhaustive over `core_domain`'s five variants.
import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Disconnecting,
        Error;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:ui_theme/ui_theme.dart';

/// Shows the current tunnel state as an Obsidian Glass status pill.
///
/// **This widget is the enforcement point for `VpnEngine` Invariant 1.** Its
/// only input is `connectionStateProvider`, i.e. the engine's authoritative
/// `connectionState` stream. It never reads the result of a `start()`/`stop()`
/// command and never infers state from a button press. Before the engine
/// emits anything the badge reads "Checking...", which is the honest default:
/// an un-emitted stream means no transition has been reported yet.
///
/// `Error` is deliberately rendered as one generic badge rather than
/// branching on `ConnectionErrorReason`. The reason enum exists so callers
/// *can* branch exhaustively; at this stage the app has no recovery action to
/// offer per reason, so surfacing raw native detail would be noise.
///
/// The pill keeps the [Chip] shell (existing tests read `Chip.label` through
/// the `connection_state_badge` key) but is restyled into a calm
/// `surfaceElevated` stadium with a state-tinted border and a non-pulsing
/// [BrickStatusDot] avatar so the dashboard never runs a repeating ticker.
class ConnectionStateBadge extends ConsumerWidget {
  /// Creates the badge.
  const ConnectionStateBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionStateProvider);
    final colors = context.brickColors;

    return state.when(
      // Probing engine status on startup: render pre-warmed state if present,
      // or neutral checking state if async probing is in flight.
      loading: () {
        final prewarmed = ref.watch(initialConnectionStateProvider);
        if (prewarmed != null) {
          return _Badge.fromVisual(_visualFor(prewarmed, colors));
        }
        return _Badge(
          label: 'connection.state_checking'.tr(),
          accentColor: colors.stateDisconnected,
          glow: false,
        );
      },
      error: (error, stackTrace) => _Badge(
        label: 'connection.state_error'.tr(),
        accentColor: colors.stateError,
        glow: true,
      ),
      data: (value) => _Badge.fromVisual(_visualFor(value, colors)),
    );
  }

  /// Maps a sealed [ConnectionState] to its localized label, state accent and
  /// glow weight.
  ///
  /// Exhaustive over the sealed hierarchy, so adding a variant upstream
  /// becomes a compile-time error here rather than a silent blank badge.
  _BadgeVisual _visualFor(ConnectionState value, BrickSemanticColors colors) {
    return switch (value) {
      Connected() => _BadgeVisual(
        label: 'connection.state_connected'.tr(),
        accentColor: colors.stateConnected,
        glow: true,
      ),
      Connecting() => _BadgeVisual(
        label: 'connection.state_connecting'.tr(),
        accentColor: colors.stateConnecting,
        glow: true,
      ),
      Disconnecting() => _BadgeVisual(
        label: 'connection.state_disconnecting'.tr(),
        accentColor: colors.stateDisconnecting,
        glow: false,
      ),
      Error() => _BadgeVisual(
        label: 'connection.state_error'.tr(),
        accentColor: colors.stateError,
        glow: true,
      ),
      Disconnected() => _BadgeVisual(
        label: 'connection.state_disconnected'.tr(),
        accentColor: colors.stateDisconnected,
        glow: false,
      ),
    };
  }
}

/// Resolved visual inputs for one badge render.
class _BadgeVisual {
  const _BadgeVisual({
    required this.label,
    required this.accentColor,
    required this.glow,
  });

  final String label;
  final Color accentColor;
  final bool glow;
}

/// The badge's visual chrome, kept private so the public widget surface stays
/// one class.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.accentColor,
    required this.glow,
  });

  factory _Badge.fromVisual(_BadgeVisual visual) => _Badge(
    label: visual.label,
    accentColor: visual.accentColor,
    glow: visual.glow,
  );

  final String label;
  final Color accentColor;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final colors = context.brickColors;

    return Chip(
      // The key lets widget tests assert which state is shown without
      // depending on the localized copy.
      key: const ValueKey<String>('connection_state_badge'),
      // `BrickStatusDot` defaults to `pulsing: false`; the dashboard must
      // never own a repeating ticker (the orb and beacon already animate).
      avatar: BrickStatusDot(color: accentColor, size: 7, glow: glow),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: BrickTypography.primaryFontFamily,
          fontSize: BrickTypography.sizeLabel,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      labelPadding: const EdgeInsets.only(
        left: BrickSpacing.xxs,
        right: BrickSpacing.xs,
      ),
      padding: const EdgeInsets.symmetric(horizontal: BrickSpacing.xxs),
      backgroundColor: colors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      side: BorderSide(
        color: glow ? accentColor.withValues(alpha: 0.40) : colors.glassBorder,
      ),
      shape: const StadiumBorder(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
