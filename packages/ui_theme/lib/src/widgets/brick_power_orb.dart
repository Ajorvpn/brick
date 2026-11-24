// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brick_colors.dart';
import '../brick_tokens.dart';
import '../brick_typography.dart';
import 'brick_status_dot.dart';

/// Visual connection state rendered by [BrickPowerOrb].
///
/// Deliberately defined here (not imported from `core_domain`) so
/// `packages/ui_theme` stays pure Flutter/Material UI.
enum BrickOrbState {
  /// Tunnel is down and idle.
  disconnected,

  /// Tunnel is being established.
  connecting,

  /// Tunnel is up and carrying traffic.
  connected,

  /// Tunnel dropped and auto-reconnect is retrying.
  reconnecting,

  /// Tunnel is being torn down.
  disconnecting,

  /// The engine reported an error.
  error,

  /// Kill switch is blocking traffic after an unexpected drop.
  killSwitch,
}

/// Signature "Obsidian Glass" power orb: the primary connect/disconnect
/// control and state readout for the connection screen.
///
/// Layered architecture (fixed `size x size` bounding box so nothing jitters):
/// 1. Ambient accent glow halo (breathes only in peak safety states).
/// 2. Precision vector ring ([CustomPainter]) with a rotating sweep arc.
/// 3. Sculpted obsidian glass core with a visible circular ink ripple.
///
/// WCAG 2.1 SC 2.3.3: under reduced motion ([MediaQueryData.disableAnimations])
/// neither the rotation ticker nor the breathing ticker ever runs. Transitional
/// states fall back to a crisp, static 240-degree arc and the status dot to a
/// static dot, so the state stays unambiguous without any motion.
class BrickPowerOrb extends StatefulWidget {
  /// Creates a power orb.
  const BrickPowerOrb({
    required this.state,
    required this.statusLabel,
    this.actionHint,
    this.onTap,
    this.size = BrickSpacing.orbDiameter,
    this.semanticLabel,
    super.key,
  });

  /// The current visual state.
  final BrickOrbState state;

  /// Label rendered below the orb (e.g. `Connected`).
  final String statusLabel;

  /// Optional compact hint inside the core (e.g. `Tap to connect`).
  final String? actionHint;

  /// Invoked when the orb is tapped. `null` disables the control.
  final VoidCallback? onTap;

  /// Outer diameter of the orb in logical pixels.
  final double size;

  /// Optional accessibility label override.
  final String? semanticLabel;

  @override
  State<BrickPowerOrb> createState() => _BrickPowerOrbState();
}

class _BrickPowerOrbState extends State<BrickPowerOrb>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _breathController;
  bool _isPressed = false;

  /// Mirrors [MediaQueryData.disableAnimations] for this widget's context.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: BrickMotion.orbPulse,
    );
    _breathController = AnimationController(
      vsync: this,
      duration: BrickMotion.orbPulse,
    );
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant BrickPowerOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncAnimations();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion != disableAnimations) {
      _reduceMotion = disableAnimations;
      _syncAnimations();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  /// Runs only the animations the current state actually needs, and stops the
  /// rest so no ticker keeps the app awake or leaks on unmount.
  void _syncAnimations() {
    // Reduced motion wins over every state: stop AND reset both controllers so
    // no ticker survives and no mid-rotation frame is frozen on screen.
    if (_reduceMotion) {
      _rotationController.stop();
      _rotationController.reset();
      _breathController.stop();
      _breathController.reset();
      return;
    }

    if (_isRotating(widget.state)) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      _rotationController.stop();
      _rotationController.reset();
    }

    if (_isBreathing(widget.state)) {
      if (!_breathController.isAnimating) {
        _breathController.repeat(reverse: true);
      }
    } else {
      _breathController.stop();
      _breathController.reset();
    }
  }

  static bool _isRotating(BrickOrbState state) =>
      state == BrickOrbState.connecting ||
      state == BrickOrbState.reconnecting ||
      state == BrickOrbState.disconnecting;

  static bool _isBreathing(BrickOrbState state) =>
      state == BrickOrbState.connected || state == BrickOrbState.killSwitch;

  static bool _isPulsingDot(BrickOrbState state) =>
      state == BrickOrbState.connecting ||
      state == BrickOrbState.reconnecting ||
      state == BrickOrbState.killSwitch;

  static Color _accentFor(BrickOrbState state, BrickSemanticColors colors) {
    return switch (state) {
      BrickOrbState.disconnected => colors.brandBrick,
      BrickOrbState.connecting ||
      BrickOrbState.reconnecting => colors.stateConnecting,
      BrickOrbState.connected => colors.stateConnected,
      BrickOrbState.disconnecting => colors.stateDisconnecting,
      BrickOrbState.error => colors.stateError,
      BrickOrbState.killSwitch => colors.killSwitchActive,
    };
  }

  static IconData _iconFor(BrickOrbState state) {
    return switch (state) {
      BrickOrbState.disconnected ||
      BrickOrbState.disconnecting => Icons.power_settings_new_rounded,
      BrickOrbState.connecting ||
      BrickOrbState.reconnecting => Icons.sync_rounded,
      BrickOrbState.connected => Icons.shield_rounded,
      BrickOrbState.error => Icons.error_outline_rounded,
      BrickOrbState.killSwitch => Icons.gpp_bad_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.brickColors;
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentFor(widget.state, colors);
    final isBreathing = !_reduceMotion && _isBreathing(widget.state);
    final isBusy = !_reduceMotion && _isRotating(widget.state);
    final coreSize = widget.size * 0.78;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Layer 1 — Ambient state glow halo.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _breathController,
                    builder: (context, child) {
                      final breath = isBreathing
                          ? _breathController.value
                          : 0.0;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(
                                alpha: isBreathing
                                    ? 0.18 + (0.16 * breath)
                                    : 0.12,
                              ),
                              blurRadius:
                                  widget.size * (isBreathing ? 0.14 : 0.10),
                              spreadRadius: widget.size * 0.02,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Layer 2 — Precision vector state ring.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _rotationController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _BrickOrbRingPainter(
                          accent: accent,
                          trackColor: colors.glassBorder,
                          rotation: _rotationController.value,
                          isBusy: isBusy,
                          isConnected: widget.state == BrickOrbState.connected,
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),

              // Layer 3 — Sculpted obsidian glass core.
              Semantics(
                button: widget.onTap != null,
                enabled: widget.onTap != null,
                label: widget.semanticLabel ?? widget.statusLabel,
                child: AnimatedScale(
                  scale: _isPressed ? 0.96 : 1.0,
                  duration: _reduceMotion ? Duration.zero : BrickMotion.fast,
                  curve: BrickMotion.curveStandard,
                  child: SizedBox(
                    width: coreSize,
                    height: coreSize,
                    // The glass ring border and drop shadow lerp between state
                    // accents instead of snapping; under reduced motion the
                    // transition collapses to a single frame.
                    child: AnimatedContainer(
                      duration: _reduceMotion
                          ? Duration.zero
                          : BrickMotion.stateTransition,
                      curve: BrickMotion.curveStandard,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.surfaceElevated,
                        border: Border.all(
                          color: accent.withValues(alpha: isDark ? 0.50 : 0.40),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.tintedShadow,
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        // The visible fill is the animated container above; this
                        // keyed layer stays explicitly gradient-free so `color`
                        // and `gradient` never share one BoxDecoration.
                        child: DecoratedBox(
                          key: const ValueKey<String>('brick_orb_core_surface'),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.transparent,
                          ),
                          // Sheen is a separate DecoratedBox so the solid
                          // surface color and the gradient never share one
                          // BoxDecoration (Flutter silently drops `color`).
                          child: DecoratedBox(
                            key: const ValueKey<String>('brick_orb_core_sheen'),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.45],
                                colors: [
                                  isDark
                                      ? const Color(0x16FFFFFF)
                                      : const Color(0x80FFFFFF),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                splashColor: accent.withValues(alpha: 0.16),
                                highlightColor: accent.withValues(alpha: 0.08),
                                onHighlightChanged: (highlighted) {
                                  setState(() {
                                    _isPressed = highlighted;
                                  });
                                },
                                onTap: widget.onTap == null
                                    ? null
                                    : () {
                                        unawaited(
                                          HapticFeedback.mediumImpact(),
                                        );
                                        widget.onTap!();
                                      },
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedSwitcher(
                                        duration: _reduceMotion
                                            ? Duration.zero
                                            : BrickMotion.stateTransition,
                                        child: Icon(
                                          _iconFor(widget.state),
                                          key: ValueKey<BrickOrbState>(
                                            widget.state,
                                          ),
                                          size: 40,
                                          color: accent,
                                        ),
                                      ),
                                      if (widget.actionHint != null) ...[
                                        const SizedBox(
                                          height: BrickSpacing.xxs,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: BrickSpacing.xs,
                                          ),
                                          child: Text(
                                            widget.actionHint!,
                                            style: BrickTypography.uiStyle(
                                              fontSize:
                                                  BrickTypography.sizeLabel,
                                              fontWeight: FontWeight.w500,
                                              color: colors.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
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
              ),
            ],
          ),
        ),
        const SizedBox(height: BrickSpacing.md),

        // Status label with live state dot.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrickStatusDot(
              color: accent,
              pulsing: !_reduceMotion && _isPulsingDot(widget.state),
            ),
            const SizedBox(width: BrickSpacing.xs),
            Flexible(
              child: Text(
                widget.statusLabel,
                style: BrickTypography.uiStyle(
                  fontSize: BrickTypography.sizeTitle,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Paints the precision track ring and the state arc of [BrickPowerOrb].
class _BrickOrbRingPainter extends CustomPainter {
  const _BrickOrbRingPainter({
    required this.accent,
    required this.trackColor,
    required this.rotation,
    required this.isBusy,
    required this.isConnected,
  });

  final Color accent;
  final Color trackColor;
  final double rotation;
  final bool isBusy;
  final bool isConnected;

  static const double _sweepDegrees = 240.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide / 2) - 2.0;
    if (radius <= 0) return;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = trackColor
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius, trackPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);

    if (isBusy) {
      final sweep = _sweepDegrees * math.pi / 180.0;
      final start = (rotation * 2 * math.pi) - (math.pi / 2);
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true
        ..shader = SweepGradient(
          colors: [
            accent.withValues(alpha: 0.0),
            accent,
            accent.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.7, 1.0],
          transform: GradientRotation(start),
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep, false, arcPaint);
      return;
    }

    if (isConnected) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0
        ..color = accent.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..isAntiAlias = true;
      canvas.drawCircle(center, radius, glowPaint);

      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..color = accent
        ..isAntiAlias = true;
      canvas.drawCircle(center, radius, ringPaint);
      return;
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = accent
      ..isAntiAlias = true;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      _sweepDegrees * math.pi / 180.0,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BrickOrbRingPainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.rotation != rotation ||
        oldDelegate.isBusy != isBusy ||
        oldDelegate.isConnected != isConnected;
  }
}
