// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../brick_tokens.dart';

/// Live signal indicator used on floating bottom docks, server spotlights,
/// and telemetry headers.
///
/// Features a core glowing circle and an optional concentric outer ripple
/// animation contained in a jitter-free bounding box.
///
/// WCAG 2.1 SC 2.3.3: when the platform reports reduced motion
/// ([MediaQueryData.disableAnimations], driven by Android's "Remove
/// animations" setting) the ripple ticker never runs and the dot renders as a
/// crisp, fully static indicator.
class BrickStatusDot extends StatefulWidget {
  const BrickStatusDot({
    super.key,
    required this.color,
    this.size = 8.0,
    this.glow = true,
    this.pulsing = false,
    this.semanticLabel,
  });

  final Color color;
  final double size;
  final bool glow;
  final bool pulsing;
  final String? semanticLabel;

  @override
  State<BrickStatusDot> createState() => _BrickStatusDotState();
}

class _BrickStatusDotState extends State<BrickStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  /// Mirrors [MediaQueryData.disableAnimations] for this widget's context.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: BrickMotion.orbPulse,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 2.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacityAnimation = Tween<double>(
      begin: 0.45,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    // The ripple is started from [didChangeDependencies], which is the first
    // lifecycle hook where the platform's motion preference is readable.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncRipple();
  }

  /// Runs the ripple only when it was asked for AND motion is allowed.
  ///
  /// Returning early under reduced motion stops *and* resets the controller,
  /// so zero tickers stay registered and no partially-faded ring is left on
  /// screen.
  void _syncRipple() {
    if (widget.pulsing && !_reduceMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
      return;
    }
    _controller.stop();
    _controller.reset();
  }

  @override
  void didUpdateWidget(covariant BrickStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing != oldWidget.pulsing) {
      _syncRipple();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showRipple = widget.pulsing && !_reduceMotion;

    final coreDot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color,
        boxShadow: widget.glow
            ? [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.45),
                  blurRadius: widget.size * 1.1,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
    );

    Widget dotContent = SizedBox(
      width: widget.size * 2.2,
      height: widget.size * 2.2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showRipple)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withValues(
                        alpha: _opacityAnimation.value,
                      ),
                    ),
                  ),
                );
              },
            ),
          coreDot,
        ],
      ),
    );

    if (widget.semanticLabel != null) {
      dotContent = Semantics(label: widget.semanticLabel, child: dotContent);
    }

    return dotContent;
  }
}
