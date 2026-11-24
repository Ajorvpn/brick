// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:core_domain/core_domain.dart'
    show Connected, Connecting, Disconnecting, Error;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/servers/presentation/providers/built_in_directory_sync_provider.dart';
import 'package:ui_theme/ui_theme.dart';

/// Root shell widget hosting the 3-tab "Obsidian Glass Floating Dock"
/// and stateful navigation branches via [StatefulNavigationShell].
///
/// Entering the shell is also the app's single trigger point for the built-in
/// server-directory sync. It runs **post-frame**, never inside
/// `AppBootstrap.init()`, so cold start stays network-free and the first frame
/// renders from the encrypted local cache.
class AppShell extends ConsumerStatefulWidget {
  /// Creates the app shell wrapping [navigationShell].
  const AppShell({required this.navigationShell, super.key});

  /// The navigation shell provided by [StatefulShellRoute.indexedStack].
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame: the UI is already interactive and the
    // cached directory is already on screen before any request starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(builtInDirectorySyncControllerProvider).syncIfNeeded(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not read) so the controller outlives individual screens and a
    // completed background sync can never notify a disposed object.
    ref.watch(builtInDirectorySyncControllerProvider);

    return Scaffold(
      // Let scrolled content flow behind the floating dock so
      // `BackdropFilter` blurs real page content instead of an opaque canvas.
      extendBody: true,
      body: widget.navigationShell,
      bottomNavigationBar: _ObsidianGlassDock(
        navigationShell: widget.navigationShell,
      ),
    );
  }
}

/// Iconic floating bottom dock crafted from translucent obsidian glass,
/// specular edge highlights, and an animated selection capsule.
class _ObsidianGlassDock extends StatelessWidget {
  const _ObsidianGlassDock({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final colors = context.brickColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // No opaque `colors.background` wrapper: the dock floats over the body.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          BrickSpacing.md,
          BrickSpacing.xs,
          BrickSpacing.md,
          BrickSpacing.sm,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: BrickSpacing.maxReadableWidth,
            ),
            child: DecoratedBox(
              key: const ValueKey<String>('brick_bottom_dock'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(BrickRadius.sheet),
                border: Border.all(color: colors.glassBorder),
                boxShadow: [
                  BoxShadow(
                    color: colors.tintedShadow,
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BrickRadius.sheet),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: DecoratedBox(
                    key: const ValueKey<String>('brick_dock_surface_layer'),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(
                        alpha: isDark ? 0.86 : 0.94,
                      ),
                    ),
                    child: DecoratedBox(
                      key: const ValueKey<String>('brick_dock_sheen_layer'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.35],
                          colors: [
                            if (isDark)
                              const Color(0x14FFFFFF)
                            else
                              const Color(0x66FFFFFF),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            Expanded(
                              child: _DockDestinationItem(
                                key: const ValueKey<String>('nav_tab_home'),
                                index: 0,
                                selectedIndex: navigationShell.currentIndex,
                                label: 'navigation.home'.tr(),
                                icon: Icons.shield_outlined,
                                selectedIcon: Icons.shield_rounded,
                                onTap: () => _onTabTapped(0),
                                iconBadge: const _HomeBeaconIcon(),
                              ),
                            ),
                            Expanded(
                              child: _DockDestinationItem(
                                key: const ValueKey<String>('nav_tab_servers'),
                                index: 1,
                                selectedIndex: navigationShell.currentIndex,
                                label: 'navigation.servers'.tr(),
                                icon: Icons.public_outlined,
                                selectedIcon: Icons.public_rounded,
                                onTap: () => _onTabTapped(1),
                              ),
                            ),
                            Expanded(
                              child: _DockDestinationItem(
                                key: const ValueKey<String>('nav_tab_settings'),
                                index: 2,
                                selectedIndex: navigationShell.currentIndex,
                                label: 'navigation.settings'.tr(),
                                icon: Icons.tune_outlined,
                                selectedIcon: Icons.tune_rounded,
                                onTap: () => _onTabTapped(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTabTapped(int index) {
    // A tactile tick confirms a genuine branch change; re-tapping the already
    // active tab is a no-op and must stay silent.
    if (index != navigationShell.currentIndex) {
      unawaited(HapticFeedback.selectionClick());
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

/// An individual destination item within the floating obsidian dock.
class _DockDestinationItem extends StatelessWidget {
  const _DockDestinationItem({
    super.key,
    required this.index,
    required this.selectedIndex,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.onTap,
    this.iconBadge,
  });

  final int index;
  final int selectedIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final VoidCallback onTap;
  final Widget? iconBadge;

  @override
  Widget build(BuildContext context) {
    final isSelected = index == selectedIndex;
    final colors = context.brickColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final capsuleDuration = reduceMotion ? Duration.zero : BrickMotion.standard;

    final itemColor = isSelected ? colors.brandBrick : colors.textMuted;
    final capsuleRadius = BorderRadius.circular(BrickRadius.cardLarge - 2);

    return Semantics(
      selected: isSelected,
      button: true,
      label: label,
      child: AnimatedContainer(
        duration: capsuleDuration,
        curve: BrickMotion.curveStandard,
        decoration: BoxDecoration(
          color: isSelected ? colors.brandBrickSoft : Colors.transparent,
          borderRadius: capsuleRadius,
          border: Border.all(
            color: isSelected
                ? colors.brandBrick.withValues(alpha: isDark ? 0.30 : 0.24)
                : Colors.transparent,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: capsuleRadius,
            splashColor: colors.brandBrick.withValues(alpha: 0.14),
            highlightColor: colors.brandBrick.withValues(alpha: 0.06),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          isSelected ? selectedIcon : icon,
                          size: 22,
                          color: itemColor,
                        ),
                        ?iconBadge,
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: BrickTypography.primaryFontFamily,
                        fontSize: BrickTypography.sizeLabel,
                        fontWeight: FontWeight.w500,
                        color: itemColor,
                      ),
                    ),
                    AnimatedContainer(
                      duration: capsuleDuration,
                      curve: BrickMotion.curveStandard,
                      margin: const EdgeInsets.only(top: 3),
                      height: 2.5,
                      width: isSelected ? 18.0 : 0.0,
                      decoration: BoxDecoration(
                        color: colors.brandBrick,
                        borderRadius: BorderRadius.circular(BrickRadius.pill),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Peripheral tunnel status beacon anchored to the Home shield icon.
///
/// Watches ONLY [connectionStateProvider] and [killSwitchProvider] to eliminate
/// redundant dock rebuilds on unrelated global state mutations.
class _HomeBeaconIcon extends ConsumerWidget {
  const _HomeBeaconIcon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.brickColors;

    // Check Kill Switch lockdown blocking state first (highest safety priority)
    final killSwitch = ref.watch(killSwitchProvider);
    if (killSwitch is KillSwitchBlocking) {
      return Positioned(
        top: -2,
        right: -4,
        child: BrickStatusDot(
          key: const ValueKey<String>('nav_home_beacon_killswitch'),
          color: colors.killSwitchActive,
          size: 6.5,
          pulsing: true,
        ),
      );
    }

    final connectionAsync = ref.watch(connectionStateProvider);
    final state = connectionAsync.value;

    if (state is Connected) {
      return Positioned(
        top: -2,
        right: -4,
        child: BrickStatusDot(
          key: const ValueKey<String>('nav_home_beacon_connected'),
          color: colors.stateConnected,
          size: 6.5,
        ),
      );
    }

    if (state is Connecting || state is Disconnecting) {
      return Positioned(
        top: -2,
        right: -4,
        child: BrickStatusDot(
          key: const ValueKey<String>('nav_home_beacon_connecting'),
          color: colors.stateConnecting,
          size: 6.5,
          pulsing: true,
        ),
      );
    }

    if (state is Error) {
      return Positioned(
        top: -2,
        right: -4,
        child: BrickStatusDot(
          key: const ValueKey<String>('nav_home_beacon_error'),
          color: colors.stateError,
          size: 6.5,
        ),
      );
    }

    // Disconnected or null -> no dot rendered (calm, distraction-free idle)
    return const SizedBox.shrink();
  }
}
