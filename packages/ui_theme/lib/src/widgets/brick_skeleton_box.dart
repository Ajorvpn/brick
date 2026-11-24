// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../brick_colors.dart';
import '../brick_tokens.dart';

/// Obsidian-glass shimmer placeholder used while async data loads.
///
/// A skeleton keeps the exact footprint of the content it stands in for, so
/// the layout does not jump when the real data arrives. The sheen sweeps a
/// soft gradient across a solid base surface — the base `color` and the sheen
/// `gradient` always live in **separate** `BoxDecoration`s, because Flutter
/// silently drops `color` when both are set on one decoration.
///
/// WCAG 2.1 SC 2.3.3: when [MediaQueryData.disableAnimations] is on, the
/// ticker is stopped *and reset*, so a reduced-motion build holds zero active
/// tickers and renders a clean static placeholder instead.
///
/// The box is purely decorative; it is wrapped in [ExcludeSemantics] so
/// TalkBack never announces empty shimmer rectangles as content.
class BrickSkeletonBox extends StatefulWidget {
  /// Creates a skeleton placeholder box.
  const BrickSkeletonBox({
    required this.height,
    this.width,
    this.borderRadius = BrickRadius.md,
    super.key,
  });

  /// Fixed width, or `null` to fill the parent's available width.
  final double? width;

  /// Fixed height of the placeholder.
  final double height;

  /// Corner radius of the placeholder.
  final double borderRadius;

  @override
  State<BrickSkeletonBox> createState() => _BrickSkeletonBoxState();
}

class _BrickSkeletonBoxState extends State<BrickSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Mirrors [MediaQueryData.disableAnimations] for this widget's context.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion != disableAnimations) {
      _reduceMotion = disableAnimations;
      if (_reduceMotion) {
        _controller.stop();
        _controller.reset();
      } else if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else if (!_reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.brickColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(widget.borderRadius);

    return ExcludeSemantics(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ClipRRect(
          borderRadius: radius,
          // Static base layer: solid surface + 1px glass border only.
          child: DecoratedBox(
            key: const ValueKey<String>('brick_skeleton_base'),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: radius,
              border: Border.all(color: colors.glassBorder, width: 1.0),
            ),
            child: _reduceMotion
                ? const SizedBox.expand()
                : AnimatedBuilder(
                    key: const ValueKey<String>('brick_skeleton_sheen'),
                    animation: _controller,
                    builder: (context, _) {
                      // The sheen travels from fully off-screen left to fully
                      // off-screen right, so the highlight never pops.
                      final slide = (_controller.value * 3.0) - 1.5;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(
                            begin: Alignment(slide - 0.6, -1),
                            end: Alignment(slide + 0.6, 1),
                            stops: const [0.0, 0.5, 1.0],
                            colors: [
                              Colors.transparent,
                              isDark
                                  ? const Color(0x14FFFFFF)
                                  : const Color(0x66FFFFFF),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
